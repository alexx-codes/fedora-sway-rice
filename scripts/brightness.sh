#!/usr/bin/env bash
# brightness.sh up|down — backlight control with OSD.
set -u

case "${1:-}" in
    up)   brightnessctl -q set +5% ;;
    down) brightnessctl -q -n set 5%- ;;   # -n: never go fully black
    *) echo "usage: brightness.sh up|down" >&2; exit 2 ;;
esac

pct=$(brightnessctl -m | awk -F, '{gsub("%","",$4); print $4}')

qs -c rice ipc call osd show brightness "$pct" >/dev/null 2>&1 ||
    notify-send -a osd -h string:x-canonical-private-synchronous:osd \
        -h "int:value:$pct" -t 1200 "brightness: ${pct}%" 2>/dev/null || true
