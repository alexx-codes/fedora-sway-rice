#!/usr/bin/env bash
# launch-or-focus.sh <workspace-number> <app_id-regex> <command> [args...]
# Jump to the app's home workspace; if no window matching the regex exists
# anywhere, launch the command. Used by the $mod+Shift+c/w/v app binds.
set -u

ws="$1"; pattern="$2"; shift 2

# Deliberately do NOT switch workspace first: if the window exists somewhere
# else, focusing it moves us there anyway, and jumping first made that a
# visible double-jump. Only switch when we are about to launch.
if swaymsg -t get_tree | jq -e --arg re "$pattern" '
        [.. | objects
         | select((.app_id? // .window_properties?.class? // "") | test($re))]
        | length > 0' >/dev/null 2>&1; then
    # Window exists; focus it (it may live on another workspace after a manual move)
    swaymsg "[app_id=\"$pattern\"] focus" >/dev/null 2>&1 \
        || swaymsg "[class=\"$pattern\"] focus" >/dev/null 2>&1 || true
else
    swaymsg "workspace number $ws" >/dev/null
    swaymsg exec -- "$(printf '%q ' "$@")" >/dev/null
fi
