#!/usr/bin/env bash
# polkit-agent.sh — ExecStart wrapper: launch whichever GUI polkit
# authentication agent is installed. Needed for GUI privilege prompts
# (virt-manager connecting to qemu:///system, GNOME Disks, etc.).
set -u

for agent in \
    /usr/libexec/polkit-gnome-authentication-agent-1 \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/libexec/lxqt-policykit-agent \
    /usr/bin/lxqt-policykit-agent; do
    [ -x "$agent" ] && exec "$agent"
done
echo "no polkit agent found (install polkit-gnome or lxqt-policykit)" >&2
exit 1
