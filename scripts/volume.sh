#!/usr/bin/env bash
# volume.sh up|down|mute|micmute — adjust PipeWire volume via wpctl and show
# the Quickshell OSD (falls back to a notification if quickshell is down).
#
# wpctl comes from the `wireplumber` package. It was missing from the installer
# originally, which is why every volume key silently did nothing; require_cmd
# now makes that failure mode loud instead of invisible.
set -u
. "$(dirname "$0")/lib-notify.sh"

require_cmd wpctl wireplumber

case "${1:-}" in
    up)      run_or_report "Volume up"   wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ || exit 1 ;;
    down)    run_or_report "Volume down" wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- || exit 1 ;;
    mute)    run_or_report "Mute"        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle || exit 1 ;;
    micmute) run_or_report "Mic mute"    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || exit 1 ;;
    *) echo "usage: volume.sh up|down|mute|micmute" >&2; exit 2 ;;
esac

if [ "${1}" = "micmute" ]; then
    out=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null) || out=""
    kind="mic"
else
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || out=""
    kind="volume"
fi

# "Volume: 0.45" or "Volume: 0.45 [MUTED]"
pct=$(awk '{printf "%.0f", $2 * 100}' <<<"$out")
[ -n "$pct" ] || pct=0
case "$out" in *MUTED*) pct=0; kind="${kind}-muted" ;; esac

qs -c rice ipc call osd show "$kind" "$pct" >/dev/null 2>&1 ||
    notify-send -a osd -h string:x-canonical-private-synchronous:osd \
        -h "int:value:$pct" -t 1200 "${kind}: ${pct}%" 2>/dev/null || true
