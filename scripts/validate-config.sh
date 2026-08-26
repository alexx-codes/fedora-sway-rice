#!/usr/bin/env bash
# validate-config.sh — validate the sway config INCLUDING its includes.
#
# Why this exists: `sway --validate` only reports errors from the top-level
# config file. An error inside an included file — and this rice keeps
# keybinds.conf, workspaces.conf, windowrules.conf, the theme colors and the
# Settings app's overrides in includes — exits 0 and is silently missed.
# Verified directly: a bogus directive in the main config exits 1, the same
# bogus directive in an included file exits 0.
#
# So: flatten our own includes into one file, then validate that. System
# includes (/etc/sway/config.d/*) are left alone — they are not ours to check
# and are absent in a test environment anyway.
#
#   ./scripts/validate-config.sh [path-to-sway-config]
set -u

cfg="${1:-$HOME/.config/sway/config}"
[ -f "$cfg" ] || { echo "no such config: $cfg" >&2; exit 2; }

flat=$(mktemp) || exit 1
trap 'rm -f "$flat"' EXIT

flatten() { # flatten <file> <depth>
    local f="$1" depth="${2:-0}" line target
    if [ "$depth" -gt 10 ]; then
        echo "# include depth exceeded at $f" >> "$flat"; return
    fi
    while IFS= read -r line; do
        case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" in
            include\ /etc/*)
                # system drop-ins: keep as-is, not ours to validate
                printf '%s\n' "$line" >> "$flat" ;;
            include\ *)
                target=$(printf '%s' "$line" | sed 's/^[[:space:]]*include[[:space:]]*//')
                target="${target/#\~/$HOME}"
                target="${target/#\$HOME/$HOME}"
                if [ -f "$target" ]; then
                    printf '\n# ---- inlined: %s ----\n' "$target" >> "$flat"
                    flatten "$target" $((depth + 1))
                else
                    printf '# MISSING INCLUDE: %s\n' "$target" >> "$flat"
                    echo "warning: include not found: $target" >&2
                fi ;;
            *) printf '%s\n' "$line" >> "$flat" ;;
        esac
    done < "$f"
}

flatten "$cfg" 0

out=$(XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}" \
      WLR_BACKENDS="${WLR_BACKENDS:-headless}" \
      WLR_RENDERER="${WLR_RENDERER:-pixman}" \
      sway --validate --config "$flat" 2>&1)
rc=$?

# sway logs backend/renderer noise in a headless test env; only config errors
# matter here.
errs=$(printf '%s\n' "$out" | grep -E '\[sway/config\.c|Error' || true)

if [ -n "$errs" ] || [ "$rc" -ne 0 ]; then
    echo "config INVALID (including includes):" >&2
    printf '%s\n' "$errs" | sed 's|'"$flat"'|<flattened>|g' >&2
    exit 1
fi

echo "config valid: $cfg and all $(grep -c '^# ---- inlined:' "$flat") included files"
