#!/usr/bin/env bash
# toggle-wifi.sh — F8 / XF86WLAN. Toggles Wi-Fi via NetworkManager and
# reports the resulting state. Uses nmcli rather than rfkill so NetworkManager
# stays aware of the change (rfkill behind its back leaves NM confused).
set -u
. "$(dirname "$0")/lib-notify.sh"

require_cmd nmcli NetworkManager

state=$(nmcli -t radio wifi 2>/dev/null) || {
    notify_fail "Wi-Fi toggle failed" "NetworkManager is not responding."
    exit 1
}

if [ "$state" = "enabled" ]; then
    run_or_report "Wi-Fi off" nmcli radio wifi off || exit 1
    notify-send -a network -h string:x-canonical-private-synchronous:rfkill \
        -t 1500 "󰤮  Wi-Fi off" 2>/dev/null || true
else
    run_or_report "Wi-Fi on" nmcli radio wifi on || exit 1
    notify-send -a network -h string:x-canonical-private-synchronous:rfkill \
        -t 1500 "󰤨  Wi-Fi on" 2>/dev/null || true
fi
