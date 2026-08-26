# Keybindings

`$mod` is the **Super** (Windows) key.

> Generated from `keybinds.tsv` — edit that file and run
> `scripts/keybinds-gen.py`, never this one. Press `$mod+Shift+/`
> in-session for this list as a popup.

## Window management

| Keys | Action |
|------|--------|
| `$mod+Shift+q` | Close the focused window |
| `$mod+f` | Toggle fullscreen for the focused window |
| `$mod+Shift+space` | Toggle floating for the focused window |
| `$mod+space` | Switch focus between tiled and floating windows |
| `$mod+h / j / k / l` | Move focus left / down / up / right (arrow keys work too) |
| `$mod+Shift+h / j / k / l` | Move the focused window left / down / up / right (arrows too) |
| `$mod+b` | Split horizontally: next window opens to the right |
| `$mod+v` | Split vertically: next window opens below |
| `$mod+s` | Stacking layout (windows pile up, titles visible) |
| `$mod+w` | Tabbed layout (windows become tabs) |
| `$mod+e` | Back to normal split layout |
| `$mod+a` | Focus the parent container (select a whole split) |
| `$mod+r` | Enter resize mode (h/j/k/l or arrows resize, Esc exits) |
| `$mod+Shift+minus` | Send the focused window to the scratchpad |
| `$mod+minus` | Show / cycle / hide scratchpad windows |

## Workspaces

| Keys | Action |
|------|--------|
| `$mod+1 … $mod+0` | Switch to workspace 1–10 (1=terminal, 2=code, 3=web, 4=VMs) |
| `$mod+Shift+1 … 0` | Move the focused window to workspace 1–10 and follow it |
| `$mod+Tab` | Bounce to the previously focused workspace |
| `$mod+Ctrl+Right` | Next workspace |
| `$mod+Ctrl+Left` | Previous workspace |

## Launching apps

| Keys | Action |
|------|--------|
| `$mod+Return` | Open a terminal (Foot) on the current workspace |
| `$mod+d` | App launcher (fuzzel) |
| `$mod+Shift+c` | Jump to workspace 2 and launch/focus VS Code |
| `$mod+Shift+w` | Jump to workspace 3 and launch/focus the browser |
| `$mod+Shift+v` | Jump to workspace 4 and launch/focus virt-manager |
| `$mod+p` | Clipboard history picker (cliphist via fuzzel) |
| `$mod+n` | Toggle the notification / control center panel |

## Media & brightness

| Keys | Action |
|------|--------|
| `XF86AudioRaiseVolume` | Volume up 5% (with on-screen overlay) |
| `XF86AudioLowerVolume` | Volume down 5% |
| `XF86AudioMute` | Toggle mute |
| `XF86AudioMicMute` | Toggle microphone mute |
| `XF86MonBrightnessUp` | Screen brightness up 5% |
| `XF86MonBrightnessDown` | Screen brightness down 5% |
| `XF86AudioPlay` | Play / pause media |
| `XF86AudioNext` | Next track |
| `XF86AudioPrev` | Previous track |

## Screenshots

| Keys | Action |
|------|--------|
| `Print` | Select an area: copy to clipboard and save to ~/Pictures/Screenshots |
| `$mod+Print` | Full screen screenshot: copy and save |
| `$mod+Shift+Print` | Screenshot the focused window: copy and save |

## Theme

| Keys | Action |
|------|--------|
| `$mod+Shift+t` | Toggle dark (Tokyo Night) / light (pastel) everywhere at once |

## Session & power

| Keys | Action |
|------|--------|
| `$mod+Shift+x` | Lock the screen |
| `$mod+Shift+e` | Power menu (lock / logout / suspend / reboot / shutdown / theme) |
| `$mod+Shift+r` | Reload the Sway configuration |
| `$mod+Shift+slash` | This cheatsheet, as an on-screen popup |
| `Resize mode: h/j/k/l or arrows` | Shrink/grow the window; Enter or Escape leaves resize mode |

## Notes on non-obvious choices

- `$mod+Shift+c/w/v` (app jumps) displaced the i3 default of `$mod+Shift+c`
  for reload; reload lives on `$mod+Shift+r` instead (Sway has no separate
  'restart', so the old restart key was free).
- `$mod+Shift+e` opens the power menu rather than instantly exiting Sway —
  logout is one of its options, so you can't fat-finger your session away.
- Media/brightness keys carry `--locked`, so they keep working on the lock screen.
- The theme toggle (`$mod+Shift+t`) switches Foot, Waybar, Quickshell, GTK, Qt,
  swaync, fuzzel, swaylock and the wallpaper in one atomic step.
