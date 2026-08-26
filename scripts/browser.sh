#!/usr/bin/env bash
# browser.sh — $mod+B. Opens your system default browser, whatever it is.
#
# Deliberately launch-only, not jump-or-focus: focusing an existing window
# needs a fixed app_id, and the whole point of using the system default is
# that we don't hardcode which browser you use. It still lands on the browser
# workspace because workspaces.conf assigns common browser app_ids there.
set -u
. "$(dirname "$0")/lib-notify.sh"

# xdg-settings gives the real answer; fall back to xdg-open's own resolution,
# then to whatever browser is actually installed.
browser=""
if command -v xdg-settings >/dev/null 2>&1; then
    browser=$(xdg-settings get default-web-browser 2>/dev/null) || browser=""
fi

if [ -n "$browser" ] && command -v gtk-launch >/dev/null 2>&1; then
    exec gtk-launch "${browser%.desktop}" 2>/dev/null
fi

if command -v xdg-open >/dev/null 2>&1; then
    exec xdg-open "about:blank" 2>/dev/null
fi

for b in librewolf firefox chromium brave-browser google-chrome epiphany; do
    if command -v "$b" >/dev/null 2>&1; then
        exec "$b"
    fi
done

notify_fail "No browser found" \
    "Set one with: xdg-settings set default-web-browser <name>.desktop"
exit 127
