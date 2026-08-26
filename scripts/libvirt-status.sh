#!/usr/bin/env bash
# libvirt-status.sh — waybar custom module: running libvirt domain count.
# One virsh call every interval; no daemons, no state. If libvirt is
# unreachable (not in libvirt group, libvirtd down) it reports quietly.
set -u

if ! raw=$(virsh --connect qemu:///system list --state-running --name 2>/dev/null); then
    printf '{"text":"–","tooltip":"libvirt unreachable (group membership? libvirtd?)","class":"error"}\n'
    exit 0
fi
domains=$(printf '%s\n' "$raw" | sed '/^$/d')

count=$(printf '%s' "$domains" | grep -c . || true)
if [ "$count" -eq 0 ]; then
    printf '{"text":"0","tooltip":"No running VMs","class":"idle"}\n'
else
    # Build the JSON with jq rather than printf: a domain name containing a
    # quote or backslash would otherwise emit malformed JSON and blank the
    # whole waybar module.
    printf '%s' "$domains" | jq -Rs --arg count "$count" \
        '{text: $count, tooltip: ("Running VMs:\n" + (. | rtrimstr("\n"))), class: "running"}' -c
fi
