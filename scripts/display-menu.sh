#!/usr/bin/env bash
# display-menu.sh — F7 / XF86Display. The projector key: pick how outputs are
# arranged. Reads the live output list from sway rather than assuming names,
# so it works with whatever is plugged into the dock.
set -u
. "$(dirname "$0")/lib-notify.sh"

require_cmd swaymsg sway
require_cmd jq jq

internal=$(swaymsg -t get_outputs | jq -r '[.[] | select(.name | test("^eDP"))][0].name // empty')
externals=$(swaymsg -t get_outputs | jq -r '.[] | select(.name | test("^eDP") | not) | .name')

if [ -z "$internal" ]; then
    notify_fail "No internal panel found" "sway reports no eDP output."
    exit 1
fi

if [ -z "$externals" ]; then
    notify-send -a display -t 2000 "󰍹  Only the internal display" \
        "Nothing else is connected." 2>/dev/null || true
    exit 0
fi

choice=$(printf '%s\n' \
    "󰌢  Internal only" \
    "󰍹  External only" \
    "󰡆  Extend (both)" \
    | rofi -dmenu -p "  display " -l 3) || exit 0

case "$choice" in
    *"Internal only")
        swaymsg output "$internal" enable >/dev/null
        for o in $externals; do swaymsg output "$o" disable >/dev/null; done
        ;;
    *"External only")
        for o in $externals; do swaymsg output "$o" enable >/dev/null; done
        swaymsg output "$internal" disable >/dev/null
        ;;
    *"Extend"*)
        swaymsg output "$internal" enable >/dev/null
        for o in $externals; do swaymsg output "$o" enable >/dev/null; done
        ;;
    *) exit 0 ;;
esac

notify-send -a display -t 1500 "󰍹  Display: ${choice#* }" 2>/dev/null || true
