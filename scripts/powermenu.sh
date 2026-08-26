#!/usr/bin/env bash
# powermenu.sh — toggle the Quickshell power menu; if quickshell is not
# running, fall back to an equivalent rofi menu so power actions always work.
set -u

if command -v qs >/dev/null 2>&1 && qs -c rice ipc call powermenu toggle >/dev/null 2>&1; then
    exit 0
fi

choice=$(printf '%s\n' \
    "  Lock" \
    "󰍃  Logout" \
    "󰤄  Suspend" \
    "  Theme toggle" \
    "󰜉  Reboot" \
    "󰐥  Shutdown" \
    | rofi -dmenu -i -p "power" -l 6) || exit 0

case "$choice" in
    *Lock)     swaylock -f ;;
    *Logout)   swaymsg exit ;;
    *Suspend)  systemctl suspend ;;
    *Theme*)   "$HOME/.config/rice/scripts/theme-toggle.sh" ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
esac
