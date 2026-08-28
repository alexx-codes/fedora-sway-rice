#!/usr/bin/env bash
# notify-panel.sh — $mod+N and XF86Tools. Toggles the swaync notification /
# control center panel.
#
# Why this is not just `launch.sh swaync-client -t -sw`: swaync-client is a
# CLIENT. It talks to the swaync daemon over D-Bus, so having the binary
# installed proves nothing about whether the toggle will work. launch.sh's
# check is `command -v`, which passes, after which it execs and the non-zero
# exit from an unreachable daemon is swallowed by sway. The key then behaves
# exactly like one that was never bound — which is how this actually failed.
#
# So: try the toggle, and if the daemon isn't answering, start it and retry
# once. Only a second failure is worth interrupting you about.
set -u
. "$(dirname "$0")/lib-notify.sh"

require_cmd swaync-client swaync

toggle() { swaync-client -t -sw >/dev/null 2>&1; }

if toggle; then
    exit 0
fi

# Daemon not answering. Start it the way the rice ships it, but never assume
# the unit is active — or even present; a manual `swaync &` is the fallback.
started=""
if command -v systemctl >/dev/null 2>&1 \
   && systemctl --user list-unit-files swaync.service >/dev/null 2>&1; then
    systemctl --user start swaync.service >/dev/null 2>&1 && started="swaync.service"
fi

if [ -z "$started" ] && command -v swaync >/dev/null 2>&1; then
    setsid swaync >/dev/null 2>&1 & started="swaync (detached)"
fi

if [ -z "$started" ]; then
    notify_fail "Notification panel unavailable" \
        "swaync-client is installed but the swaync daemon is not running and \
could not be started. Check: systemctl --user status swaync.service"
    exit 127
fi

# Give the daemon a moment to claim its D-Bus name before retrying.
for _ in $(seq 1 25); do
    toggle && exit 0
    sleep 0.2
done

notify_fail "Notification panel did not open" \
    "Started $started, but swaync-client -t still fails. \
Check: systemctl --user status swaync.service"
exit 1
