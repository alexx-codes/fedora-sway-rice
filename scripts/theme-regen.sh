#!/usr/bin/env bash
# theme-regen.sh — re-derive the dark palette from the night wallpaper with
# matugen, re-run the theme generator (with its contrast gate), and redeploy.
# Optional: the committed dark palette is hand-tuned Tokyo Night and works
# without ever running this.
set -eu
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"

command -v matugen >/dev/null 2>&1 || {
    echo "matugen not installed (cargo install matugen). The committed dark" >&2
    echo "palette is hand-tuned Tokyo Night, so this step is optional." >&2
    exit 1
}

wall=""
for ext in jpg jpeg png; do
    [ -f "wallpapers/night.$ext" ] && { wall="wallpapers/night.$ext"; break; }
done
[ -n "$wall" ] || { echo "wallpapers/night.{jpg,png} not found" >&2; exit 1; }

matugen -c config/matugen/config.toml -m dark image "$wall"
./scripts/theme-gen.py          # regenerates app theme files + contrast gate
./install.sh --configs-only     # redeploy to ~/.config
echo "dark palette regenerated from $wall; run theme-toggle.sh --apply (or dark) to see it"
