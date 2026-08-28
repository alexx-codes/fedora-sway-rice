# Wallpapers

Drop images here (or in `~/Pictures/wallpapers`, which the Settings app prefers
when it exists) and pick one from Settings → Wallpaper.

The file used at login is whichever matches the `WALLPAPER=` name in
`theme/colors.env` — `night.jpg`, `night.jpeg` or `night.png`, in that order.
`.jpg` beats the committed `.png` fallback, so dropping your own art in as
`night.jpg` is all it takes.

**The palette follows the wallpaper — but only halfway.**
`scripts/theme-from-wallpaper.sh` runs matugen over the current image and takes
its surface, text and accent roles. The semantic colors (RED/ORANGE/GREEN) and
the whole ANSI block stay pinned in `theme/colors.env`.

That split is deliberate, and it is the answer to the original objection that
deriving a palette from an arbitrary image gives you unreadable terminal text:
the colors that carry meaning or drive syntax highlighting never move, and
everything that does move still goes through `theme-gen.py`'s WCAG contrast
gate. The gate nudges a failing color until it clears rather than aborting,
so no wallpaper can leave you with an unreadable bar.

Run it after changing the wallpaper; it is a plain script, not a watcher.

`night.png` and `day.png` are generated fallbacks so a fresh clone is never
wallpaper-less. Regenerate them with:

```sh
pip install --user pillow   # or: sudo dnf install python3-pillow
python3 scripts/gen-fallback-wallpapers.py
```

Note that the committed fallbacks are purple/indigo lofi-style images, which
sit oddly against the cold Ashfall palette. A darker, desaturated image suits
it better — worth swapping when you have one you like.
