#!/usr/bin/env bash
# osk.sh — toggle the squeekboard on-screen keyboard.
# squeekboard runs hidden as a user service and exposes visibility over
# D-Bus (sm.puri.OSK0); this flips it. Bound to $mod+o and the bar's
# keyboard button, so it's reachable by touch alone.
#
# Known limitation, stated plainly: this does NOT work on the swaylock
# screen — swaylock grabs keyboard focus exclusively, so no OSK can type
# into it. Touch-only unlock is the fingerprint reader's job
# (scripts/fingerprint-setup.sh), with the physical keyboard as fallback.
set -u

BUS=(busctl --user)

# Start the service on first use if it isn't running yet
if ! "${BUS[@]}" status sm.puri.OSK0 >/dev/null 2>&1; then
    systemctl --user start squeekboard.service 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        "${BUS[@]}" status sm.puri.OSK0 >/dev/null 2>&1 && break
        sleep 0.2
    done
fi

vis=$("${BUS[@]}" get-property sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 Visible 2>/dev/null | awk '{print $2}')
if [ "$vis" = "true" ]; then
    exec "${BUS[@]}" call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b false
else
    exec "${BUS[@]}" call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true
fi
