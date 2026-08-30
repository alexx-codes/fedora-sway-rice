# CLAUDE.md

Project guidance for Claude Code when working in this repository.

## Project overview

Custom Sway window manager rice for Fedora, built from scratch (not using a premade dotfiles repo). Runs on a ThinkPad X1 Carbon, Fedora 44.

**Stack:**
- Compositor: Sway
- Terminal: kitty
- Bar: Waybar
- Shell/widgets: Quickshell
- Tiling: autotiling (systemd user unit)
- Theming: matugen

**Design direction:**
- Dark and minimalistic by default — productivity is the main goal, should feel snappy and fast
- Ashfall (cold, desaturated: ash on charcoal) is the one palette — see theme/colors.env
- [Fill in: still going with the anime-cat visual direction, or has that changed since the rice restart?]

## Known failure history — read before touching autostart/systemd

An earlier version of this rice broke the Sway session badly due to autostart and systemd user-service failures, bad enough that the whole config got wiped and the machine fell back to KDE Plasma. Because of that:

- Never add an autostart/`exec` line without confirming the target binary exists and has a working fallback if it doesn't launch.
- Never assume a systemd user unit is already active — check `systemctl --user status <unit>` reasoning before writing a config that depends on it.
- Prefer changes that can be tested incrementally (one component at a time — e.g. Waybar module, then Quickshell widget) over big-bang config swaps.
- Keep the previous working config backed up (e.g. git-committed or copied aside) before a risky change, so there's a fast rollback.

## Conventions

- **Folder layout:** per-tool top-level folders — `sway/`, `waybar/`, `quickshell/`, `matugen/` — each mirrors what that tool expects in `~/.config/`. Anything matugen generates that multiple tools consume (color files, shared assets) lives in `shared/`, not duplicated per tool.
- **One palette, no toggle.** The dark/light toggle described in earlier revisions is gone; `theme/colors.env` (Ashfall) is the single definition and `scripts/theme-gen.py` derives every app from it behind a WCAG contrast gate.
- **Wallpaper-derived surfaces.** `scripts/theme-from-wallpaper.sh` runs matugen over the current wallpaper and merges its surface/text/accent roles onto `colors.env`. Semantic colors (RED/ORANGE/GREEN) and the ANSI block are deliberately excluded — they carry meaning and drive syntax highlighting. It is a plain script run on a wallpaper change, not a watcher or a systemd unit: a background process tied to systemd is exactly the category of thing that broke this rice before.
- **Script naming:** verb-first (`toggle-theme.sh`, `reload-bar.sh`), flat in a `scripts/` folder. No numbered prefixes — there's no fixed pipeline order that would justify them.

## Workflow

- Validate JSON/config syntax before applying — a malformed Waybar or Quickshell config is the most common way this breaks.
- After any change that touches autostart, systemd, or session startup, test in a way that doesn't require killing the current working session outright (e.g. a nested Sway instance, or a nested Weston session, or a spare TTY) — see `code-reviewer` subagent for a pre-commit check.
- This project needs to run and be tested on the actual local machine (real display, real Wayland session) — not something a cloud sandbox can validate.
