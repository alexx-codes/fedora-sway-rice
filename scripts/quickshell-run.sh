#!/usr/bin/env bash
# quickshell-run.sh — ExecStart wrapper for quickshell.service (the binary
# may be `qs` or `quickshell` depending on packaging, and systemd's fixed
# ExecStart search path can't see ~/.cargo/bin-style locations).
set -u
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

for bin in qs quickshell; do
    if command -v "$bin" >/dev/null 2>&1; then
        exec "$bin" -c rice
    fi
done
echo "quickshell not installed; widgets disabled (rofi fallbacks still work)" >&2
exit 0
