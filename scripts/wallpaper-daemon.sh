#!/usr/bin/env bash
# wallpaper-daemon.sh — ExecStart for wallpaper-daemon.service.
#
# swaybg by default now. swww existed to animate the transition between the
# dark and light palettes; with the theme toggle gone there is no transition
# to animate, and swww is a second daemon holding the framebuffer and doing
# GPU work for a picture that never changes. swaybg draws it once and idles.
#
# swww is still honored if you have it installed and set RICE_USE_SWWW=1 —
# useful if you want animated wallpapers for their own sake.
set -u
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

wall="$HOME/.config/rice/wallpapers/current"

if [ "${RICE_USE_SWWW:-0}" = 1 ] && command -v swww-daemon >/dev/null 2>&1; then
    exec swww-daemon
fi

if [ -e "$wall" ]; then
    exec swaybg -i "$wall" -m fill
fi

# Last resort: the palette's background color, so an absent wallpaper still
# looks deliberate rather than broken.
bg=$(sed -n 's/^BG=//p' "$HOME/.config/rice/theme/colors.env" 2>/dev/null)
exec swaybg -c "#${bg:-0d0e11}"
