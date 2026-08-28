#!/usr/bin/env bash
# theme-from-wallpaper.sh [wallpaper] — re-derive the palette from an image.
#
# Two stages, deliberately separate:
#   1. matugen extracts Material You SURFACE/TEXT/ACCENT roles into a small
#      env file. It writes nothing an app reads directly.
#   2. theme-gen.py merges those onto theme/colors.env — keeping the semantic
#      and ANSI colors, which must not follow the wallpaper — runs the WCAG
#      contrast gate, and regenerates every app's theme.
#
# matugen never writes app configs itself because that would bypass the
# contrast gate, and matugen output is exactly where contrast slips.
#
# No daemon and no watcher: this runs when something changes the wallpaper,
# which is a discrete event, not a stream. That is the same reasoning that
# kept the old theme toggle out of systemd. rice-settings' set_wallpaper()
# calls it directly after applying the image; it can also be run by hand.
#
# pipefail so a failure inside a pipeline (the fallback-color extraction
# below) is not masked by the last stage's exit; every real error path is
# still handled explicitly with `if ! err=$(...)` rather than `set -e`.
set -u
set -o pipefail
. "$(dirname "$0")/lib-notify.sh"

RICE="${RICE_DIR:-$HOME/.config/rice}"
wall="${1:-$RICE/wallpapers/current}"

require_cmd matugen matugen \
    "Install it with: cargo install matugen  (not in the Fedora repos)"

if [ ! -e "$wall" ]; then
    notify_fail "Wallpaper theme not regenerated" "No such image: $wall"
    exit 1
fi

# Must match matugen/config.toml's output_path exactly. That file is a static
# template — deploy_tree only substitutes __HOME__ into it, nothing else — so
# it always writes to the literal $HOME/.cache/rice, regardless of this
# user's $XDG_CACHE_HOME. Reading the palette back through
# ${XDG_CACHE_HOME:-...} would silently diverge from that on any machine
# where XDG_CACHE_HOME isn't the default, and theme-gen.py would abort with
# "missing wallpaper palette" for a file that in fact exists, just elsewhere.
palette="$HOME/.cache/rice/wallpaper-palette.env"
mkdir -p "$(dirname "$palette")"

# --prefer is not optional: run from a keybind there is no TTY, and matugen
# ABORTS rather than guessing when an image yields several candidate colors.
# --fallback-color covers the other end — a near-monochrome image from which
# no usable accent can be extracted at all.
fallback=$(sed -n 's/^ACCENT=//p' "$RICE/theme/colors.env" 2>/dev/null | tr -d '"')
if ! err=$(matugen --config "$RICE/matugen/config.toml" \
                   --mode dark --prefer saturation \
                   --fallback-color "#${fallback:-8fa0b3}" \
                   image "$wall" 2>&1); then
    notify_fail "Wallpaper palette failed" "matugen: ${err:-unknown error}"
    exit 1
fi

if ! err=$("$RICE/scripts/theme-gen.py" --from-wallpaper "$palette" 2>&1); then
    notify_fail "Wallpaper palette rejected" "theme-gen: ${err:-unknown error}"
    exit 1
fi
printf '%s\n' "$err"

# Same distribution install.sh does — waybar and swaync import a sibling
# theme.css, so regenerating colors.css alone changes nothing on screen.
cp "$RICE/theme/colors.css" "$HOME/.config/waybar/theme.css" 2>/dev/null || true
cp "$RICE/theme/colors.css" "$HOME/.config/swaync/theme.css" 2>/dev/null || true
cp "$RICE/theme/swaylock.conf" "$HOME/.config/swaylock/config" 2>/dev/null || true
cp "$RICE/theme/rofi.rasi" "$HOME/.config/rofi/config.rasi" 2>/dev/null || true

# SIGUSR2 makes waybar reload its CSS in place — no restart, no gap in the bar.
pkill -SIGUSR2 waybar 2>/dev/null || true
swaync-client -rs 2>/dev/null || true

# sway colors are an include, so a reload is what picks them up.
command -v swaymsg >/dev/null 2>&1 && swaymsg reload >/dev/null 2>&1 || true

exit 0
