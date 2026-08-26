#!/usr/bin/env bash
# battery-watch.sh — the low-battery warning that actually fires.
# Waybar's battery "states" only change CSS colors; nothing notified. This
# runs from battery-watch.timer (every 2 min while the session is up):
#   <= 25% discharging : one normal notification (once per discharge cycle)
#   <= 10% discharging : critical notification, repeated every run — at 10%
#                        with VMs possibly writing to disk, nagging is a
#                        feature, not a bug
# Plugging in (or climbing back above the threshold) resets the state.
# BATTERY_SYSFS is overridable for testing.
set -u

sysdir="${BATTERY_SYSFS:-/sys/class/power_supply}"
state_file="${XDG_RUNTIME_DIR:-/tmp}/rice-battery-warned"

bat=""
for b in "$sysdir"/BAT*; do
    [ -f "$b/capacity" ] && { bat="$b"; break; }
done
[ -n "$bat" ] || exit 0   # no battery (desktop/dock edge case): nothing to do

capacity=$(cat "$bat/capacity" 2>/dev/null) || exit 0
status=$(cat "$bat/status" 2>/dev/null) || exit 0

if [ "$status" != "Discharging" ]; then
    rm -f "$state_file"
    exit 0
fi

if [ "$capacity" -le 10 ]; then
    notify-send -u critical -a battery -h "int:value:$capacity" \
        -h string:x-canonical-private-synchronous:battery \
        "Battery critical: ${capacity}%" \
        "Plug in now — suspend imminent. Running VMs won't enjoy a hard power-off." \
        2>/dev/null || true
elif [ "$capacity" -le 25 ]; then
    if [ ! -f "$state_file" ]; then
        notify-send -u normal -a battery -h "int:value:$capacity" \
            -h string:x-canonical-private-synchronous:battery \
            "Battery low: ${capacity}%" "Consider plugging in." 2>/dev/null || true
        touch "$state_file"
    fi
else
    rm -f "$state_file"
fi
