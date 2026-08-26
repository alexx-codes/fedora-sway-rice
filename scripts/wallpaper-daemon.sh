#!/usr/bin/env bash
# wallpaper-daemon.sh — ExecStart for wallpaper-daemon.service.
# Prefers swww (animated transitions for the theme toggle); falls back to
# swaybg with the current wallpaper if swww isn't installed, so the desktop
# never ends up wallpaper-less. systemd restarts us if either daemon dies.
set -u
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

if command -v swww-daemon >/dev/null 2>&1; then
    exec swww-daemon
fi

wall="$HOME/.config/rice/wallpapers/current"
if [ -e "$wall" ]; then
    exec swaybg -i "$wall" -m fill
fi
# Last resort: solid color so the session still looks intentional
exec swaybg -c '#1a1b26'
