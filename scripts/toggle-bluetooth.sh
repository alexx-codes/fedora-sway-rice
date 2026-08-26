#!/usr/bin/env bash
# toggle-bluetooth.sh — F10 / XF86Bluetooth. Toggles the Bluetooth radio.
# Prefers bluetoothctl (keeps bluez in the loop); falls back to rfkill.
set -u
. "$(dirname "$0")/lib-notify.sh"

msg() {
    notify-send -a bluetooth -h string:x-canonical-private-synchronous:rfkill \
        -t 1500 "$1" 2>/dev/null || true
}

if command -v bluetoothctl >/dev/null 2>&1; then
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
        run_or_report "Bluetooth off" bluetoothctl power off || exit 1
        msg "󰂲  Bluetooth off"
    else
        run_or_report "Bluetooth on" bluetoothctl power on || exit 1
        msg "󰂯  Bluetooth on"
    fi
elif command -v rfkill >/dev/null 2>&1; then
    if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; then
        run_or_report "Bluetooth on" rfkill unblock bluetooth || exit 1
        msg "󰂯  Bluetooth on"
    else
        run_or_report "Bluetooth off" rfkill block bluetooth || exit 1
        msg "󰂲  Bluetooth off"
    fi
else
    notify_fail "Bluetooth toggle unavailable" \
        "Neither bluetoothctl nor rfkill found. Install with: sudo dnf install bluez util-linux"
    exit 127
fi
