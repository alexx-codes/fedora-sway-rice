#!/usr/bin/env bash
# wallpaper-set.sh — oneshot run after wallpaper-daemon starts: waits for the
# swww daemon socket, then applies the current theme's wallpaper. No-op in
# the swaybg fallback case (swaybg already got the image on its command line).
set -u
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

command -v swww >/dev/null 2>&1 || exit 0

for _ in $(seq 1 50); do
    swww query >/dev/null 2>&1 && break
    sleep 0.2
done

wall="$HOME/.config/rice/wallpapers/current"
[ -e "$wall" ] && exec swww img "$wall" --resize crop --transition-type none
exit 0
