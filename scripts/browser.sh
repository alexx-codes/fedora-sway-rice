#!/usr/bin/env bash
# browser.sh — $mod+B. Opens your system default browser, whatever it is.
#
# Deliberately launch-only, not jump-or-focus: focusing an existing window
# needs a fixed app_id, and the whole point of using the system default is
# that we don't hardcode which browser you use. It still lands on the browser
# workspace because workspaces.conf assigns common browser app_ids there.
#
# Every strategy below is tried in turn and MUST NOT use `exec` until the
# last one. An earlier revision ran `exec gtk-launch ...`, which replaced the
# shell the moment gtk-launch was *found* — so when gtk-launch then failed on
# a stale or invalid .desktop entry (exactly what the fallbacks exist for),
# the script was already gone and every fallback below was unreachable dead
# code. The key looked unbound: nothing happened, no message, nowhere to look.
set -u
. "$(dirname "$0")/lib-notify.sh"

# Collected so a total failure can say what each strategy actually complained
# about, rather than just "didn't work".
errs=""
note() { errs="${errs}${errs:+$'\n'}  - $1"; }

# xdg-settings gives the real answer; fall back to xdg-open's own resolution,
# then to whatever browser is actually installed.
browser=""
if command -v xdg-settings >/dev/null 2>&1; then
    browser=$(xdg-settings get default-web-browser 2>/dev/null) || browser=""
fi

# 1. The registered default, via its .desktop entry.
if [ -n "$browser" ] && command -v gtk-launch >/dev/null 2>&1; then
    if err=$(gtk-launch "${browser%.desktop}" 2>&1); then
        exit 0
    fi
    note "gtk-launch $browser: ${err:-failed}"
fi

# 2. xdg-open's own resolution, which can differ from xdg-settings'.
if command -v xdg-open >/dev/null 2>&1; then
    if err=$(xdg-open "about:blank" 2>&1); then
        exit 0
    fi
    note "xdg-open: ${err:-failed}"
fi

# 3. Last resort: whatever is actually on PATH. exec is correct here — there
#    is nothing left to fall through to.
for b in librewolf firefox chromium brave-browser google-chrome epiphany; do
    if command -v "$b" >/dev/null 2>&1; then
        exec "$b"
    fi
done
note "no known browser binary on PATH"

notify_fail "Could not open a browser" \
    "Every strategy failed:${errs:+$'\n'}$errs

Set a default with: xdg-settings set default-web-browser <name>.desktop"
exit 127
