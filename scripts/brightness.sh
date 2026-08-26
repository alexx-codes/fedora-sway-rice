#!/usr/bin/env bash
# brightness.sh up|down|kbd — backlight control with OSD.
#
# brightnessctl writes to /sys/class/backlight, and its udev rule grants that
# to the `video` GROUP — which Fedora does not add you to by default. That is
# why the brightness keys did nothing on first login. The failure is a
# permission denial, so it is reported explicitly here with the fix, instead
# of vanishing into sway's discarded stderr.
set -u
. "$(dirname "$0")/lib-notify.sh"

require_cmd brightnessctl

# kbd: the ThinkPad keyboard backlight is a separate device with 3 levels
# (off/low/high) rather than a percentage, so it cycles instead of stepping.
if [ "${1:-}" = "kbd" ]; then
    dev=tpacpi::kbd_backlight
    if ! brightnessctl -d "$dev" info >/dev/null 2>&1; then
        notify_fail "Keyboard backlight unavailable" \
            "No $dev device — check that the thinkpad_acpi module is loaded."
        exit 1
    fi
    cur=$(brightnessctl -d "$dev" get 2>/dev/null || echo 0)
    max=$(brightnessctl -d "$dev" max 2>/dev/null || echo 2)
    next=$(( (cur + 1) % (max + 1) ))
    brightnessctl -q -d "$dev" set "$next" 2>/dev/null || {
        notify_fail "Keyboard backlight failed" \
            "Permission denied? Add yourself to the 'video' group: sudo usermod -aG video \$(id -un)"
        exit 1
    }
    notify-send -a osd -h string:x-canonical-private-synchronous:osd -t 1200 \
        "Keyboard backlight: $next/$max" 2>/dev/null || true
    exit 0
fi

case "${1:-}" in
    up)   args=(-q set +5%) ;;
    down) args=(-q -n set 5%-) ;;   # -n: never go fully black
    *) echo "usage: brightness.sh up|down|kbd" >&2; exit 2 ;;
esac

if ! err=$(brightnessctl "${args[@]}" 2>&1); then
    case "$err" in
        *[Pp]ermission*|*denied*|*"Operation not permitted"*)
            notify_fail "Brightness keys need the 'video' group" \
                "Run: sudo usermod -aG video $(id -un)  — then log out and back in. (Or: ./verify.sh --fix)"
            ;;
        *)  notify_fail "Brightness change failed" "${err:-unknown error}" ;;
    esac
    exit 1
fi

pct=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub("%","",$4); print $4}')
[ -n "$pct" ] || pct=0

qs -c rice ipc call osd show brightness "$pct" >/dev/null 2>&1 ||
    notify-send -a osd -h string:x-canonical-private-synchronous:osd \
        -h "int:value:$pct" -t 1200 "brightness: ${pct}%" 2>/dev/null || true
