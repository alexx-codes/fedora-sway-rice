#!/usr/bin/env bash
# screenshot.sh area|full|window — grim+slurp wrapper.
# Every mode copies to the clipboard AND saves under ~/Pictures/Screenshots.
set -u

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
file="$dir/shot-$(date +%Y%m%d-%H%M%S).png"

case "${1:-area}" in
    full)
        grim "$file" || exit 1
        ;;
    area)
        geom=$(slurp) || exit 0   # Esc pressed: silently do nothing
        grim -g "$geom" "$file" || exit 1
        ;;
    window)
        geom=$(swaymsg -t get_tree | jq -r \
            '.. | select(.focused? == true) | .rect | "\(.x),\(.y) \(.width)x\(.height)"') || exit 1
        grim -g "$geom" "$file" || exit 1
        ;;
    *) echo "usage: screenshot.sh area|full|window" >&2; exit 2 ;;
esac

wl-copy < "$file" 2>/dev/null || true
notify-send -a screenshot -i "$file" "Screenshot saved" "$(basename "$file") (also on clipboard)" 2>/dev/null || true
