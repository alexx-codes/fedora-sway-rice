#!/usr/bin/env bash
# cheatsheet.sh — show the keybind cheatsheet ($mod+Shift+/).
# Primary: Quickshell popup. Fallback: fuzzel list. Both read
# ~/.config/rice/keybinds.tsv — the same single source of truth that
# generates KEYBINDS.md, so the popup can never drift from the docs.
set -u

if command -v qs >/dev/null 2>&1 && qs -c rice ipc call cheatsheet toggle >/dev/null 2>&1; then
    exit 0
fi

awk -F'\t' '
    /^[[:space:]]*(#|$)/ { next }
    $3 !~ /hide/ {
        cat = $1
        if (cat != last) { printf "── %s ──\n", cat; last = cat }
        printf "%-28s %s\n", $2, $5
    }' "$HOME/.config/rice/keybinds.tsv" \
    | fuzzel --dmenu --prompt "  keys ❯ " --width 80 --lines 24 >/dev/null || true
