# fedora-sway-rice

Dark, grim Sway desktop for Fedora on a ThinkPad X1 Carbon Gen 11, built for
coding and QEMU/KVM work. **One palette — Ashfall**: near-black surfaces,
desaturated cold accents, ash-on-charcoal text. No modes, no toggle. Stability
first: everything supervised runs as a systemd user service, daily-critical
paths use official-repo packages, and the fancy layer (Quickshell) degrades to
rofi fallbacks instead of breaking.

## Install

```sh
git clone <this repo> && cd fedora-sway-rice
# optional but recommended: drop your wallpaper in first
cp ~/Downloads/lofi-girl-night-cat-3840x2160-15268.jpg wallpapers/night.jpg
./install.sh        # packages + configs + services (asks before the one COPR)
./verify.sh         # health check   (--preflight / --fix also available)
# log out, pick "Sway (rice)" in the display manager, log in
```

Existing configs are moved to `<name>.bak-<epoch>`, never deleted. Edit
configs **in this repo**, then `./install.sh --configs-only` to redeploy —
that keeps git the single source of truth and every change diffable.

## Components

| Role | Tool | Why |
|------|------|-----|
| Compositor | sway + sway-systemd | systemd session target supervises everything (the old runit-style rice died from ad-hoc `exec_always` supervision) |
| Terminal | kitty | GPU-accelerated, ligature-capable |
| Bar | Waybar | workspaces, clock, album art + prominent CPU/RAM/temp/net for VM load, running-VM count (no tray — see HANDOFF.md) |
| Widgets | Quickshell (COPR) | power menu, volume/brightness OSD, keybind popup — IPC-driven, rofi fallbacks |
| Launcher | rofi-wayland | official repo; also the dmenu backend for the clipboard, power menu and cheatsheet fallbacks |
| Notifications | SwayNotificationCenter | daemon + control center in one official package (chosen over mako for the panel) |
| Lock | swaylock | plain swaylock over swaylock-effects: the fork only lives in stale personal COPRs |
| Idle | swayidle | lock 10 min, screen off 15 min, lock-before-sleep |
| Tiling | autotiling (pipx) | alternates the split direction by window shape; a systemd user unit, not an `exec_always` |
| Wallpaper | swaybg (swww optional) | static; no animated transition needed without a theme toggle |
| Screenshots | grim + slurp + wrapper | area/full/window, clipboard + `~/Pictures/Screenshots` |
| Clipboard | cliphist | text+image history, `$mod+p` picker |
| Theming | one palette + generator with a WCAG gate | see below |
| GTK/Qt | adw-gtk3 + qt6ct | both toolkits use the palette |
| Portals | xdg-desktop-portal-wlr/-gtk | screen share, file pickers, dark/light for libadwaita |
| Polkit | polkit-gnome (or lxqt) | GUI privilege prompts (virt-manager) |
| Prompt | starship | cosmetic; follows terminal palette |

The only third-party repo is COPR `errornointernet/quickshell` (opt-in
prompt during install).

## Theme

One palette, defined once in `theme/colors.env`. `scripts/theme-gen.py` derives
every app's colors from it — kitty, waybar, sway borders, swaync, rofi, swaylock,
quickshell, qt6ct — and **refuses to generate anything unreadable**: body text
must clear 7:1 contrast and every text-bearing accent 3:1. That gate is not
decoration; it rejected five colors during an earlier build, and a deliberately
grim palette is exactly where contrast quietly slips.

```
theme/colors.env  ->  scripts/theme-gen.py  ->  theme/{kitty.conf, colors.css,
                          (WCAG gate)            sway-colors.conf, rofi.rasi,
                                                 swaylock.conf, quickshell.json,
                                                 qt6ct-colors.conf}
```

To change a color: edit `theme/colors.env`, run `./scripts/theme-gen.py`, then
`./install.sh --configs-only`. There is no dark/light toggle and no active-theme
symlink — both removed as complexity that earned nothing.

**matugen is back, for surfaces only.** `scripts/theme-from-wallpaper.sh` derives
the surface, text and accent roles from the current wallpaper and merges them onto
`colors.env`:

```
wallpaper ──matugen──> BG/BG_ALT/FG/ACCENT/…  ─┐
                                               ├──> theme-gen.py ──> theme/*
theme/colors.env ── RED/GREEN/ORANGE + ANSI ──┘      (WCAG gate)
```

The split is the point. Semantic colors and the ANSI block are NOT wallpaper-
derived: a critical-battery badge that turns wallpaper-brown is decoration
rather than a warning, and re-hueing ANSI per wallpaper makes every language
look wrong in kitty. The contrast gate still runs on the merged result — it just
nudges a failing color until it clears instead of aborting, because a wallpaper
change must never leave you with an unreadable bar.

matugen is `optional` in `packages.tsv` (it is not in the Fedora repos —
`cargo install matugen`). Without it the static Ashfall palette is used and
nothing breaks.

## Keybinds

`keybinds.tsv` is the single source of truth. It generates
`config/sway/keybinds.conf` and [`config/sway/KEYBINDS.md`](config/sway/KEYBINDS.md)
(via `scripts/keybinds-gen.py`), and the `$mod+Shift+/` popup (Quickshell,
rofi fallback) reads the same TSV at runtime. The generator also fails
the build if any bind directive appears in a sway config file outside the
generated one, so the popup and docs can't silently drift; the one allowed
exception is bindsym inside a mode block (resize mode), which the TSV
documents with a doc row. Conventions kept: `$mod+Return` terminal,
`$mod+q` kill, `$mod+1…0` workspaces, `$mod+a` launcher, `$mod+b` browser.

Workspaces: **1** terminal · **2** VS Code · **3** browser · **4** VMs ·
5–9 free · 10 misc. `$mod+Shift+c/w/v` jump to 2/3/4 and launch the app if
it isn't running.

## Virtualization & VS Code notes

- Waybar's VM module polls `virsh` (one call/15 s, hidden when libvirt is
  unreachable). `verify.sh` checks `/dev/kvm` and `libvirt` group membership
  and prints the fix commands — it never changes group membership itself.
- VS Code runs native Wayland via `ELECTRON_OZONE_PLATFORM_HINT=auto`
  (environment.d) **and** an overridden `code.desktop` with explicit ozone
  flags; `verify.sh` confirms a running window is Wayland-native, not XWayland.
- virt-manager: consoles tile on the current workspace; its dialogs float
  (`config/sway/windowrules.conf`).

## Troubleshooting

- `systemctl --user status waybar swaync quickshell wallpaper-daemon`
- `journalctl --user -u <unit> -e`
- Waybar temperature reading wrong sensor → `verify.sh` lists hwmon paths;
  set `hwmon-path` in `config/waybar/config.jsonc`.
- Quickshell broken after a Fedora Qt update → COPR lag; everything falls
  back to rofi until the COPR rebuilds.
