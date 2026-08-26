#!/usr/bin/env bash
# clipboard-pick.sh — cliphist history through rofi; picked entry goes to
# the clipboard.
set -u
sel=$(cliphist list | rofi -dmenu -i -p "clip" -theme-str 'entry { placeholder: "search clipboard"; }') || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
