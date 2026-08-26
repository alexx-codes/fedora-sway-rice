#!/usr/bin/env bash
# volume.sh up|down|mute|micmute — adjust PipeWire volume via wpctl and show
# the Quickshell OSD (falls back to a notification if quickshell is down).
set -u

case "${1:-}" in
    up)      wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;
    down)    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute)    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    micmute) wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
    *) echo "usage: volume.sh up|down|mute|micmute" >&2; exit 2 ;;
esac

if [ "${1}" = "micmute" ]; then
    out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@)
    kind="mic"
else
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
    kind="volume"
fi
# "Volume: 0.45" or "Volume: 0.45 [MUTED]"
pct=$(awk '{printf "%.0f", $2 * 100}' <<<"$out")
case "$out" in *MUTED*) pct=0; kind="${kind}-muted" ;; esac

qs -c rice ipc call osd show "$kind" "$pct" >/dev/null 2>&1 ||
    notify-send -a osd -h string:x-canonical-private-synchronous:osd \
        -h "int:value:$pct" -t 1200 "${kind}: ${pct}%" 2>/dev/null || true
