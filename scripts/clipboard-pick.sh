#!/usr/bin/env bash
# clipboard-pick.sh — cliphist history through fuzzel; picked entry goes to
# the clipboard.
set -u
sel=$(cliphist list | fuzzel --dmenu --prompt " 󰅍 clip ❯ " --width 60) || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
