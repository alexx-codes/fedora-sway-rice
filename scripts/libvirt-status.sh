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
    tooltip=$(printf 'Running VMs:\\n%s' "$(printf '%s' "$domains" | sed ':a;N;$!ba;s/\n/\\n/g')")
    printf '{"text":"%s","tooltip":"%s","class":"running"}\n' "$count" "$tooltip"
fi
