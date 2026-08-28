#!/usr/bin/env bash
# lib-notify.sh — shared failure reporting for keybind-driven scripts.
#
# Why this exists: sway's `bindsym exec` discards stdout AND stderr, so a
# script that fails because a binary is missing or a permission is denied
# looks exactly like a key that was never bound — nothing happens, no clue.
# That is precisely how the volume keys (missing wpctl) and brightness keys
# (missing `video` group) both failed invisibly on first login.
#
# Source this from any script bound to a key:
#     . "$(dirname "$0")/lib-notify.sh"
#     require_cmd wpctl wireplumber

# notify_fail <title> <body> — visible, and logged to the journal so
# `journalctl --user -t rice-key` has a trail even if notifications are down.
notify_fail() {
    local title="$1" body="${2:-}"
    notify-send -u critical -a "rice" "$title" "$body" 2>/dev/null || true
    command -v systemd-cat >/dev/null 2>&1 \
        && printf '%s: %s\n' "$title" "$body" | systemd-cat -t rice-key -p err \
        || printf 'rice-key: %s: %s\n' "$title" "$body" >&2
}

# require_cmd <binary> [package] [install-hint] — abort with a visible,
# actionable message naming how to install it, rather than dying silently.
#
# The default hint assumes dnf, which is right for everything in
# packages.tsv's base/deps/hardware/integration tiers — but wrong for a tool
# like matugen that packages.tsv itself marks as cargo-only (optional tier,
# not in the Fedora repos). Pass a 3rd argument to override the hint verbatim
# for those cases instead of pointing the user at a dnf install that fails.
require_cmd() {
    local bin="$1" pkg="${2:-$1}" hint="${3:-}"
    if ! command -v "$bin" >/dev/null 2>&1; then
        notify_fail "Key action failed: $bin not installed" \
            "${hint:-Install it with: sudo dnf install $pkg  (or run ./verify.sh --fix)}"
        exit 127
    fi
}

# run_or_report <description> <command...> — run a command and, if it fails,
# say so visibly with the exit status and the command that failed.
run_or_report() {
    local what="$1"; shift
    local err rc
    err=$("$@" 2>&1); rc=$?
    if [ $rc -ne 0 ]; then
        notify_fail "$what failed" "${err:-exit status $rc} — command: $*"
        return $rc
    fi
    return 0
}
