#!/usr/bin/env bash
# lid.sh close|open — VM-aware lid handling.
#
# logind's default HandleLidSwitch=suspend fires unconditionally — including
# with KVM guests running, which freezes them mid-write. install.sh (with
# your consent) sets HandleLidSwitch=ignore via a logind drop-in, and sway's
# bindswitch routes the lid here instead:
#   * no VMs running  -> lock, then suspend (same behavior as before)
#   * VMs running     -> lock + screen off, NO suspend, and a notification
#                        so the choice is visible when you reopen the lid
# Requires the drop-in to be active; without it logind suspends first and
# this script never gets a say.
set -u

running_vms() {
    virsh --connect qemu:///system list --state-running --name 2>/dev/null | sed '/^$/d'
}

case "${1:-}" in
    close)
        vms=$(running_vms)
        if [ -n "$vms" ]; then
            notify-send -u critical -a lid "Lid closed — NOT suspending" \
                "Running VMs: $(echo "$vms" | tr '\n' ' ')" 2>/dev/null || true
            swaylock -f
            swaymsg "output * power off" >/dev/null 2>&1 || true
        else
            # swayidle's before-sleep hook locks ahead of the suspend
            systemctl suspend
        fi
        ;;
    open)
        swaymsg "output * power on" >/dev/null 2>&1 || true
        ;;
    *) echo "usage: lid.sh close|open" >&2; exit 2 ;;
esac
