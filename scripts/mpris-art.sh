#!/usr/bin/env bash
# mpris-art.sh — prints a path to circular album art for waybar's image module.
#
# The circle is baked into the FILE, not done in CSS. waybar's image module
# renders a GtkImage, and border-radius on that widget paints its background
# corners — it does not clip the pixbuf. A CSS-only circle just draws a round
# backdrop behind a square cover.
#
# Output contract: one line, the path to a PNG. Nothing on stdout means the
# module renders nothing, which is what we want with no player running.
#
# Cost: on a cache hit this is one playerctl call and a `test -f`. ImageMagick
# only runs when the track actually changes.
set -u

# Rendered larger than waybar's "size": 22 in config.jsonc on purpose: that 22
# is a LOGICAL box, so it is 44 device px on the HiDPI panel, and GTK downscales
# a generous source far more cleanly than it upscales a tight one. Override with
# RICE_ART_SIZE if the bar height ever changes.
SIZE="${RICE_ART_SIZE:-64}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/rice/albumart"
# Keep at most a fortnight of covers. Runs only on a cache miss (a track
# change), not every poll, so it costs nothing on the hot path.
PRUNE_DAYS=14

command -v playerctl >/dev/null 2>&1 || exit 0

url=$(playerctl metadata mpris:artUrl 2>/dev/null) || exit 0
[ -n "$url" ] || exit 0

# Cache key covers the size too, so changing RICE_ART_SIZE can't serve a
# stale image at the wrong dimensions.
key=$(printf '%s|%s' "$url" "$SIZE" | sha256sum | cut -c1-32)
out="$CACHE/$key.png"

if [ -f "$out" ]; then
    printf '%s\n' "$out"
    exit 0
fi

mkdir -p "$CACHE" || exit 0
find "$CACHE" -maxdepth 1 -type f -name '*.png' -mtime "+$PRUNE_DAYS" -delete 2>/dev/null || true
command -v magick >/dev/null 2>&1 || exit 0

tmp_src=""
case "$url" in
    file://*)
        # %-decode the path; artUrl is a URI, so spaces arrive as %20.
        src=$(printf '%b' "$(printf '%s' "${url#file://}" | sed 's/%\(..\)/\\x\1/g')")
        [ -f "$src" ] || exit 0
        ;;
    http://*|https://*)
        command -v curl >/dev/null 2>&1 || exit 0
        tmp_src=$(mktemp "${TMPDIR:-/tmp}/rice-art.XXXXXX") || exit 0
        # Bounded in both time and size: a slow OR oversized art host must
        # never stall the bar's poll or fill the cache with one huge image.
        curl -sfL --max-time 5 --max-filesize 20971520 -o "$tmp_src" "$url" \
            || { rm -f "$tmp_src"; exit 0; }
        src="$tmp_src"
        ;;
    *) exit 0 ;;
esac

# Square-crop from the centre, then punch a circular alpha mask through it.
radius=$(awk -v s="$SIZE" 'BEGIN { printf "%.1f", (s - 1) / 2 }')
tmp_out=$(mktemp "${TMPDIR:-/tmp}/rice-art-out.XXXXXX.png") || { rm -f "$tmp_src"; exit 0; }
if magick "$src" -resize "${SIZE}x${SIZE}^" -gravity center -extent "${SIZE}x${SIZE}" \
       \( -size "${SIZE}x${SIZE}" xc:none -fill white \
          -draw "circle $radius,$radius $radius,0" \) \
       -alpha set -compose CopyOpacity -composite \
       "png:$tmp_out" 2>/dev/null; then
    # Atomic: waybar may read this path while we are writing it.
    mv -f "$tmp_out" "$out" && printf '%s\n' "$out"
else
    rm -f "$tmp_out"
fi

rm -f "$tmp_src"
exit 0
