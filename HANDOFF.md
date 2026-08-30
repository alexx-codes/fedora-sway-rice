# Sway Rice — Session Findings & Work Plan

Context: Fedora 44, ThinkPad X1 Carbon, Sway + SDDM.
Repo: `github.com/alexx-codes/fedora-sway-rice`

> **Read this first (updated 2026-08-28).** Sections 1.2, 1.3, 1.4 and 2.1 below were
> written from a stale reading and have been corrected in place. The short version:
> LibreWolf is a native RPM, the Flatpak problem is moot, the browser keybind was
> already implemented, and the "Super+B shows Super+L" report was a misread of `wev`
> output — the real fault was silent runtime failure. Details in each section.
>
> Note also that this repo is **Fedora-only**: `packages.tsv` is dnf-based and
> `install.sh` assumes dnf. It is not installable as-is on an Arch/CachyOS box.

---

## PART 1 — What we diagnosed this session (context, mostly resolved)

### 1.1 Sway session wouldn't start (RESOLVED)
**Symptom:** Selecting "Sway" at the SDDM greeter logged into KDE Plasma instead.

**Root cause:** `/var/lib/AccountsService/users/alex` had an empty `Session=` value.
SDDM was never persisting the session choice. Confirmed via `journalctl --user -b -1`
showing only Plasma services (`plasma-kwin_wayland.service`) shutting down — Sway was
never being launched at all, not crashing.

**Contributing factor:** `/usr/share/sddm/themes/` is completely empty. SDDM logs:
`The configured theme "01-breeze-fedora" doesn't exist, using the embedded theme instead.`
The bare fallback greeter appears not to reliably write the session selection.

**Fix applied:** Manually set `Session=sway.desktop` in
`/var/lib/AccountsService/users/alex`. Sway now boots correctly.

**Still open (cosmetic, non-blocking):** No SDDM theme installed. The `sddm` package
(0.21.0-13.fc44) owns `/usr/share/sddm/themes` but ships no theme content there.
Investigated and ruled out: `dnf history` transaction 61 (it was a routine update —
only `Replaced` entries plus old-kernel cleanup, no theme removals); rice scripts
(`grep -rn "sddm"` in the repo returns nothing).
Cause never identified. Low priority.

---

### 1.2 Flatpak sandbox failure — RESOLVED (moot)
**Original symptom:** every Flatpak app failed with
`Sandbox: CanCreateUserNamespace() clone() failure: EPERM`, and the root cause was
never found.

**Current state (verified 2026-08-28):** the workaround already happened. LibreWolf is
installed as a **native package** at `/usr/bin/librewolf`, and `flatpak list --app`
returns **nothing** — there are no Flatpaks left on the machine to fail. The sandbox
bug is therefore unreachable and needs no further investigation.

Nothing to do. Do not spend more time on the EPERM analysis; it only ever affected a
Flatpak that is now gone.

---

### 1.3 Default browser registration (RESOLVED)
`xdg-settings get default-web-browser` now returns **`librewolf.desktop`** — the native
entry at `/usr/share/applications/librewolf.desktop`, not the Flatpak one. The re-point
warned about in the original note has already been done. Verified 2026-08-28.

---

### 1.4 "Super+B shows up as Super+L" — RESOLVED, it was a misread
**The report:** pressing `Super+B` (and later `Super+N`) showed up in `wev` as
`Super+L`, suggesting an input-layer remap.

**It is not a remap.** `Super_L` is the **keysym name for the left Super key** — the
`_L` suffix means *left*, not the letter L. Every `Super`+anything chord emits a
`Super_L` event first, then a *separate* event for the letter. So `Super+B` and
`Super+N` both showing `Super_L` is simply what all chords do, including the ones that
work fine. That two different keys produced identical output is the clue: a real
`b`→`l` remap would not also affect `n`.

To confirm on the machine, read the **second** event's `sym:` line:

```
wev | grep -A1 'state: 1 (pressed)' | grep 'sym:'
```

`Super+B` should print `sym: Super_L` then `sym: b`.

**The real fault was elsewhere** — the keys were bound correctly and the keysyms were
correct; what failed was the thing each binding *ran*, silently. See 2.1.

---

## PART 2 — Work to implement

### 2.1 Default-browser keybind — DONE, plus the silent-failure fix
The original note ("no browser keybind exists") was wrong: `$mod+b` has been bound
since commit `d881762`. It is generated from `keybinds.tsv` into
`config/sway/keybinds.conf:8`:

```
bindsym $mod+b exec ~/.config/rice/scripts/browser.sh
```

`browser.sh` already satisfies the requirement — it resolves the browser through
`xdg-settings` rather than hardcoding LibreWolf, so switching defaults just works.

**What was actually broken (fixed 2026-08-28).** `$mod+b` and `$mod+n` were the only
two binds that did nothing, and they had one root cause: *they were the only two that
could pass every existence check and still fail at runtime, invisibly.*

1. **`browser.sh` had an `exec` bug.** It ran `exec gtk-launch "$browser"`, which
   replaces the shell the moment `gtk-launch` is *found*. When `gtk-launch` then failed
   on a stale `.desktop`, the process was already gone and the three fallbacks below it
   (`xdg-open`, then a scan for known browser binaries) were **unreachable dead code**.
   Fixed: each strategy now runs non-`exec`, its status is tested, and failure falls
   through. A total failure reports through `notify_fail` naming what each strategy
   complained about.

2. **`$mod+n` ran `launch.sh swaync-client -t -sw`.** `swaync-client` is a *client*;
   having the binary installed proves nothing about whether the **swaync daemon** is
   answering on D-Bus. `launch.sh` checks `command -v`, which passed, then `exec`ed —
   and the non-zero exit from an unreachable daemon was swallowed by sway, exactly like
   a missing binary. Fixed: new `scripts/notify-panel.sh` tries the toggle, starts the
   daemon if it is not answering, retries once, and only then reports.

Two guards were added so this class cannot recur:

- `launch.sh --report` runs a command, waits for its exit status, and reports failure
  via `run_or_report` — for any bind whose target can fail *after* it starts. (Not for
  long-running programs like `kitty`/`rofi`; it would block.)
- `verify.sh` now checks that every `~/.config/rice/scripts/*` target in
  `keybinds.conf` **exists and is executable**. The pre-existing check deliberately
  skipped `~/` and `/` paths, so it had never looked at the rice's own scripts — the
  majority of what the keys actually call.

**Still to check on the machine:** `systemctl --user status swaync.service`. If that
unit is dead, it is the direct cause of `$mod+n`, and waybar's `custom/notification`
module (which execs `swaync-client -swb`) will be blank for the same reason.

---

### 2.2 Drag-to-move/resize windows
User wants Hyprland-style behavior: drag a window and have the layout resize around it.

**Check first — this may be a one-line config addition, not a feature build.**
`grep -n "floating_modifier"` currently returns nothing. Sway supports this natively:
```
floating_modifier $mod normal
```
With that set: `$mod`+left-drag moves a window (retiling the tree),
`$mod`+right-drag resizes live. Test this before building anything custom.

---

### 2.3 Wallpaper panel + effects  ← main feature work

**Tooling (verified, not guessed):** Checked three independent wallpaper-effect
projects (`updWallp`, `BlurWal`, `swayblur`) — all use **ImageMagick** for the actual
image processing, with a separate lightweight tool for *display*. So:
- **ImageMagick (`magick`)** — applies the effect
- **`swww`** — sets the wallpaper + handles transitions

Two-stage pipeline: source image → `magick` (effect) → cache dir → `swww img <result>`

**Panel requirements:**
- Opened via a keybind
- Side panel (use **Quickshell** — already in the rice stack)
- Lists wallpapers from a dedicated wallpaper folder, with thumbnails
- Shows the current wallpaper's file path (informational)
- "Add wallpaper" action — file picker that copies the chosen image into the
  wallpaper folder
- Effect selector

**Effect behavior — IMPORTANT:** The effect is a **global setting**, not per-wallpaper.
- Changing wallpaper → currently-active effect is automatically re-applied to the new one
- Changing effect → re-processes the currently-active wallpaper immediately
- Do NOT implement per-image effect memory

**Effect options** (drawn from what real dotfiles actually ship):
- None
- Grayscale — `magick in.jpg -colorspace Gray out.jpg`
- Blur — `magick in.jpg -blur 0x8 out.jpg`
- Dim/darken (aids desktop readability)
- Sepia
- Colorize / tint (should tie into the existing matugen palette)

Grayscale and dim are the highest-value defaults — they serve readability, not just aesthetics.

**Note:** This is a *static filtered wallpaper*, NOT live blur-behind-windows.
Live blur is a different tool entirely (`swayblur`/`wallpablur`) and is out of scope here.

---

### 2.4 Waybar config update — reference received, in progress
Reference: `~/Pictures/waybar-target-config/screenshot_2026-08-28_14-05-31.png`.

**The look:** a fully transparent bar with floating rounded "islands" — fully-rounded
pill ends, semi-transparent dark fill, light text, monospace. Not the current design,
which `style.css` explicitly describes as "hairline separation instead of pills
everywhere"; that header needs rewriting along with the rules.

**Layout read off the reference:**

| Position | Island | Contents |
|---|---|---|
| left | `group/link` | bluetooth, network — icons only, tinted |
| left | `sway/workspaces` | `1 2 3 4 5`, plain numerals; active = filled light circle |
| left | `sway/window` | focused window title |
| center | `group/media` | circular album art + mpris track |
| right | `group/sysload` | cpu, memory, temperature, net down, disk |
| right | `group/io` | volume, battery |
| right | `group/controls` | power-profiles, idle-inhibitor, osk |
| right | `group/time` | date + time |
| right | `custom/notification` | the round button (swaync; right-click = powermenu) |

**Decisions taken:**
- **Colors are wallpaper-derived.** The reference's warm brown is matugen output —
  confirmed by comparing it against a matugen-generated `colors.css` carrying
  `background #19120c` / `on_background #eee0d5`, the same palette. This **reverses**
  the "matugen removed, one static palette" decision in `README.md` and
  `wallpapers/README.md`; those get updated rather than left contradicting the code.
  The WCAG contrast gate in `theme-gen.py` stays — matugen output is exactly where
  contrast slips — but on failure it nudges `fg` lighter instead of aborting, since a
  wallpaper change must never leave you with an unreadable bar.
- **The hover drawer goes away.** Commit `968c3ed` collapsed the four load modules
  behind one icon; the reference shows all of them. The restrained polling intervals
  that commit introduced are kept, so cost does not regress with the layout.
- **Kept despite not being in the reference:** power-profiles-daemon, idle-inhibitor,
  the swaync panel, `systemd-failed-units` (already `hide-on-ok`, so invisible while
  healthy) and `custom/osk` (the one control that must be reachable by touch alone).
- **Dropped:** `sway/mode`, `sway/scratchpad`, `privacy`, `custom/vms`, `backlight`,
  and **`tray`** — tray is the one removal that will be noticed daily.

**Testing note:** the bar is previewed on a separate CachyOS/Hyprland machine by
swapping `sway/*` modules for `hyprland/*` into a scratchpad copy. Nothing in that
machine's own config is modified.

---

### 2.5 Media key OSD (backlog)
Brightness and volume function keys work, but there's no on-screen indicator showing
the level changing. Needs `swayosd` or `wob` wired into the brightness/volume scripts.
Lower priority than the above.

---

## Repo conventions (existing — follow these)
- Per-tool top-level config folders: `sway/`, `waybar/`, `quickshell/`, `matugen/`
- `shared/` folder for generated assets
- Dark/light toggle via pre-baked palettes + symlink swap (no background daemon)
- Scripts named verb-first, flat in a `scripts/` folder
- Theme: Tokyo Night dark (default) + pastel light (toggle); dark, minimal,
  productivity-focused, snappy
