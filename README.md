# fedora-sway-rice

Anime-cat themed Sway desktop for Fedora on a ThinkPad X1 Carbon, built for
coding and QEMU/KVM work. Two first-class palettes — **Tokyo Night** (dark,
default) and **Pastel Cat** (light) — with a single keybind that switches
every component at once. Stability first: everything supervised runs as a
systemd user service, daily-critical paths use official-repo packages, and
the fancy layer (Quickshell) degrades to fuzzel fallbacks instead of
breaking.

## Install

```sh
git clone <this repo> && cd fedora-sway-rice
# optional but recommended: drop your wallpaper in first
cp ~/Downloads/lofi-girl-night-cat-3840x2160-15268.jpg wallpapers/night.jpg
./install.sh        # packages + configs + services (asks before the one COPR)
./verify.sh         # read-only health check: KVM, libvirt group, fonts, VS Code
# log out, pick "Sway" in the display manager, log in
```

Existing configs are moved to `<name>.bak-<epoch>`, never deleted. Edit
configs **in this repo**, then `./install.sh --configs-only` to redeploy —
that keeps git the single source of truth and every change diffable.

## Components

| Role | Tool | Why |
|------|------|-----|
| Compositor | sway + sway-systemd | systemd session target supervises everything (the old runit-style rice died from ad-hoc `exec_always` supervision) |
| Terminal | foot | Wayland-native, GPU-accelerated, tiny |
| Bar | Waybar | workspaces, clock, tray + prominent CPU/RAM/temp/net for VM load, running-VM count |
| Widgets | Quickshell (COPR) | power menu, volume/brightness OSD, keybind popup — all IPC-driven with fuzzel fallbacks |
| Launcher | fuzzel | official repo, rock solid; deliberately *not* Quickshell |
| Notifications | SwayNotificationCenter | daemon + control center in one official package (chosen over mako for the panel) |
| Lock | swaylock | plain swaylock over swaylock-effects: the fork only lives in stale personal COPRs |
| Idle | swayidle | lock 10 min, screen off 15 min, lock-before-sleep |
| Wallpaper | swww (cargo) → swaybg fallback | animated dark/light transition; falls back cleanly |
| Screenshots | grim + slurp + wrapper | area/full/window, clipboard + `~/Pictures/Screenshots` |
| Clipboard | cliphist | text+image history, `$mod+p` picker |
| Theming | matugen (cargo) + generators | see below |
| GTK/Qt | adw-gtk3 + qt6ct + nwg-look | both toolkits follow the toggle |
| Portals | xdg-desktop-portal-wlr/-gtk | screen share, file pickers, dark/light for libadwaita |
| Polkit | polkit-gnome (or lxqt) | GUI privilege prompts (virt-manager) |
| Prompt | starship | cosmetic; follows terminal palette |

The only third-party repo is COPR `errornointernet/quickshell` (opt-in
prompt during install). matugen and swww build from crates.io via cargo.

## Theme system

```
themes/dark/colors.env    ← single palette definition (Tokyo Night)
themes/light/colors.env   ← single palette definition (Pastel Cat, hand-defined)
        │ scripts/theme-gen.py  (contrast gate: fails the build if FG/BG < 7:1
        ▼                        or any text color < 3:1)
themes/<mode>/{foot.ini, waybar.css, sway-colors.conf, swaync-theme.css,
               fuzzel.ini, swaylock.conf, quickshell.json, qt6ct-colors.conf}
```

At runtime `~/.config/rice/active` is a symlink to the deployed
`themes/<mode>`; every app reads colors through it. `theme-toggle.sh`
(`$mod+Shift+t`, also in the power menu):

1. swaps the symlink — one atomic rename is the commit point;
2. wallpaper via swww animated transition (or swaybg restart);
3. sway colors live via `swaymsg`; waybar via SIGUSR2; swaync CSS reload;
4. open foot terminals are recolored in place via OSC sequences;
5. GTK via gsettings (+ portal for libadwaita), Qt via qt6ct scheme path;
6. failures are collected and reported — a half-applied theme is treated
   as a bug, and the notification tells you which step misbehaved.

**Palette sourcing (as agreed):** matugen derives the *dark* UI chrome from
`wallpapers/night.jpg` (`./scripts/theme-regen.sh`, optional — the committed
palette is hand-tuned Tokyo Night). The *light* palette is hand-defined:
deriving a light scheme from a night image produces mud. Terminal ANSI
colors are hand-curated in both modes and gated on WCAG contrast.

## Keybinds

`keybinds.tsv` is the single source of truth. It generates
`config/sway/keybinds.conf` and [`config/sway/KEYBINDS.md`](config/sway/KEYBINDS.md)
(via `scripts/keybinds-gen.py`), and the `$mod+Shift+/` popup (Quickshell,
fuzzel fallback) reads the same TSV at runtime — the popup and the docs
cannot drift. Conventions kept: `$mod+Return` terminal, `$mod+Shift+q` kill,
`$mod+1…0` workspaces, `$mod+d` launcher.

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
- virt-manager: consoles tile on workspace 4; its dialogs float
  (`config/sway/windowrules.conf`).

## Troubleshooting

- `systemctl --user status waybar swaync quickshell wallpaper-daemon`
- `journalctl --user -u <unit> -e`
- Waybar temperature reading wrong sensor → `verify.sh` lists hwmon paths;
  set `hwmon-path` in `config/waybar/config.jsonc`.
- Quickshell broken after a Fedora Qt update → COPR lag; everything falls
  back to fuzzel until the COPR rebuilds.
