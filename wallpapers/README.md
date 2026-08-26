# Wallpapers

Runtime rule: for each mode the first existing of `night.jpg` / `night.jpeg` /
`night.png` (dark) and `day.jpg` / `day.jpeg` / `day.png` (light) is used —
**.jpg beats the committed .png fallbacks**, so dropping your art in here is
all it takes.

- **Dark mode:** copy your `lofi-girl-night-cat-3840x2160-15268.jpg` into this
  directory as **`night.jpg`**, then run `./install.sh --configs-only`.
  It is 4K; swww/swaybg crop-fill it to the panel, so no pre-scaling needed.
  Optionally run `./scripts/theme-regen.sh` afterwards to let matugen re-derive
  the dark UI chrome from it (the committed palette is hand-tuned Tokyo Night
  and already matches its purple/indigo/magenta tones).
- **Light mode:** supply any soft pastel image as **`day.jpg`** whenever you
  find one you like. Until then the committed pastel fallback is used. The
  light *palette* is hand-defined and does not depend on this image.

`night.png`/`day.png` are generated fallbacks so a fresh install is never
wallpaper-less. If they're missing from your checkout, regenerate them:

```sh
pip install --user pillow   # or: sudo dnf install python3-pillow
python3 scripts/gen-fallback-wallpapers.py
```
