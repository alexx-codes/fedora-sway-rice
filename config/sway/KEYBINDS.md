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
| `$mod+v` | Split vertically: next window opens below |
| `$mod+s` | Stacking layout (windows pile up, titles visible) |
| `$mod+w` | Tabbed layout (windows become tabs) |
| `$mod+e` | Back to normal split layout |
| `$mod+r` | Enter resize mode (h/j/k/l or arrows resize, Esc exits) |
| `$mod+Shift+minus` | Send the focused window to the scratchpad |
| `$mod+minus` | Show / cycle / hide scratchpad windows |

## Workspaces

| Keys | Action |
|------|--------|
| `$mod+1 … $mod+0` | Switch to workspace 1–10 (1=terminal, 2=code, 3=web, 4=VMs) |
| `$mod+Shift+1 … 0` | Move the focused window to workspace 1–10 and follow it |
| `$mod+Tab` | Bounce to the previously focused workspace |
| `3-finger swipe ←/→` | Switch to the next / previous workspace (touchpad) |
| `$mod+Ctrl+Right` | Next workspace |
| `$mod+Ctrl+Left` | Previous workspace |

## Launching apps

| Keys | Action |
|------|--------|
| `$mod+Return` | Open a terminal (Foot) on the current workspace |
| `$mod+a` | App launcher (rofi) |
| `$mod+Shift+c` | Jump to workspace 2 and launch/focus VS Code |
| `$mod+b` | Open your default browser (whatever xdg-settings reports) |
| `$mod+Shift+v` | Jump to workspace 4 and launch/focus virt-manager |
| `$mod+Shift+s` | Open the Settings app (theme, wallpaper, display, keys, system info) |
| `$mod+p` | Clipboard history picker (cliphist via rofi) |
| `$mod+n` | Toggle the notification / control center panel |
| `$mod+o` | Toggle the on-screen keyboard (squeekboard, for touch) |

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
| `Fn+Space` | Cycle the keyboard backlight (off / low / high) |

## ThinkPad F-row

| Keys | Action |
|------|--------|
| `F7 (XF86Display)` | Display menu: internal only / external only / extend |
| `F8 (XF86WLAN)` | Toggle Wi-Fi on / off |
| `F9 (XF86Tools)` | Toggle the notification / control center panel |
| `F10 (XF86Bluetooth)` | Toggle Bluetooth on / off |
| `F11 / F12` | Open the Settings app (firmware differs on which keysym it sends) |
| `XF86PowerOff` | Power button: open the power menu instead of instantly suspending |
| `Fn+Esc` | FnLock. Not a sway binding — firmware. With it ON the top row sends plain F1-F12 and none of the above fire. |

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
| `Lid close` | Suspend — unless a VM is running: then lock + screen off, no suspend |
| `Resize mode: h/j/k/l or arrows` | Shrink/grow the window; Enter or Escape leaves resize mode |

## If a key does nothing

1. **Check FnLock first.** `Fn+Esc` toggles it. With FnLock ON the top
   row sends plain `F1`–`F12` instead of the media keysyms, so none of
   the ThinkPad F-row bindings above will fire. This is firmware
   behavior — no amount of sway config changes it.
2. **Open Settings → Keyboard** (`$mod+Shift+S`) and use the live key
   tester: press the key and it shows you the keysym actually being
   received. If nothing appears, the key never reaches Wayland.
3. **Run `./verify.sh`.** It checks that every binding's backing binary
   is installed, and that you are in the `video` group (brightness keys
   fail silently without it) — `./verify.sh --fix` repairs both.

Key scripts now report failures as notifications instead of failing
silently, so a missing package or permission problem says so.

## Notes on non-obvious choices

- `$mod+Shift+c/w/v` (app jumps) displaced the i3 default of `$mod+Shift+c`
  for reload; reload lives on `$mod+Shift+r` instead (Sway has no separate
  'restart', so the old restart key was free).
- `$mod+Shift+e` opens the power menu rather than instantly exiting Sway —
  logout is one of its options, so you can't fat-finger your session away.
- Media/brightness keys carry `--locked`, so they keep working on the lock screen.
- The theme toggle (`$mod+Shift+t`) switches Foot, Waybar, Quickshell, GTK, Qt,
  swaync, rofi, swaylock and the wallpaper in one atomic step.
