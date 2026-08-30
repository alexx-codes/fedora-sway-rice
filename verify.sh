#!/usr/bin/env bash
# verify.sh — health check, preflight, and self-repair for the rice.
#
#   ./verify.sh              read-only health check (default; CHANGES NOTHING)
#   ./verify.sh --preflight  only the checks that decide whether install.sh
#                            can succeed. install.sh runs this itself.
#   ./verify.sh --perf       diagnose a sluggish session (read-only)
#   ./verify.sh --fix        repair what is safely repairable, prompt for the
#                            rest. Never deletes anything.
#   ./verify.sh --fix --dry-run   show exactly what --fix would do, do nothing
#
# The default mode stays read-only on purpose: reporting and repairing are
# different jobs, and the report must be trustworthy even when you don't want
# anything touched.
set -u

c_grn=$'\033[0;32m'; c_ylw=$'\033[1;33m'; c_red=$'\033[0;31m'; c_off=$'\033[0m'
pass() { echo "${c_grn}[PASS]${c_off} $*"; }
warn() { echo "${c_ylw}[WARN]${c_off} $*"; }
fail() { echo "${c_red}[FAIL]${c_off} $*"; }
ok()   { echo "${c_grn}[ ok ]${c_off} $*"; }
say()  { echo; echo "══ $* ══"; }
sect() { echo; echo "── $* ──"; }

RICE_REPO=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib-packages.sh
. "$RICE_REPO/scripts/lib-packages.sh"

MODE=health
for a in "$@"; do
    case "$a" in
        --preflight) MODE=preflight ;;
        --perf)      MODE=perf ;;
        --fix)       MODE=fix ;;
        --dry-run)   PREFLIGHT_DRYRUN_REQUESTED=1 ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
    esac
done

# $USER is not guaranteed to be exported (set -u aborts the whole script on
# it), so resolve the login name once from a source that always works.
ME=$(id -un)

# shellcheck source=scripts/lib-preflight.sh
. "$RICE_REPO/scripts/lib-preflight.sh"
PREFLIGHT_DRYRUN=${PREFLIGHT_DRYRUN_REQUESTED:-0}

if [ "$MODE" = perf ]; then
    exec "$RICE_REPO/scripts/diagnose-perf.sh"
fi

if [ "$MODE" = preflight ]; then
    preflight_check
    exit $?
fi

if [ "$MODE" = fix ]; then
    if [ "$PREFLIGHT_DRYRUN" = 1 ]; then
        say "DRY RUN — nothing will be changed"
    fi
    preflight_check || warn "preflight found blockers; repairing what is possible anyway"
    say "Auto-repair (safe and reversible)"
    repair_auto
    say "Needs your decision (trust / system-level)"
    repair_prompted
    say "Reported only — not repairable from here"
    repair_report_only
    echo
    if [ "$PREFLIGHT_DRYRUN" = 1 ]; then
        ok "dry run complete — nothing was changed"
    else
        ok "repair pass complete. Re-run ./verify.sh for a fresh health check."
    fi
    exit 0
fi

sect "Packages (from packages.tsv)"
_missing_req=$(pkg_missing base deps hardware integration)
if [ -z "$_missing_req" ]; then
    pass "all required packages installed ($(pkg_list base deps hardware integration | wc -l) checked)"
else
    for p in $_missing_req; do
        fail "$p missing — $(pkg_field "$p" 4)"
    done
    fail "  fix all of these at once: ./verify.sh --fix"
fi
for p in $(pkg_missing optional); do
    warn "$p not installed (optional) — $(pkg_field "$p" 4)"
done
PATH="$HOME/.cargo/bin:$PATH" command -v qs >/dev/null 2>&1 \
    && pass "quickshell" \
    || warn "quickshell missing (COPR; power menu/OSD/cheatsheet use rofi fallbacks)"

sect "Is the deployed config actually current?"
# The single most confusing failure mode: you pull new commits, nothing
# changes, and the keys you just read about don't exist — because the repo
# and ~/.config are different things and nothing said so.
_drift=0
for f in sway/keybinds.conf sway/config sway/workspaces.conf sway/windowrules.conf; do
    _repo="$RICE_REPO/config/$f"
    _live="$HOME/.config/$f"
    [ -f "$_repo" ] || continue
    if [ ! -f "$_live" ]; then
        fail "$f is not deployed at all"
        _drift=$((_drift + 1))
    elif ! diff -q <(sed "s|__HOME__|$HOME|g; s|__THERMAL_ZONE__|.*|g; s|__PANEL_SCALE__|.*|g" "$_repo") \
                   "$_live" >/dev/null 2>&1; then
        # placeholders make an exact diff meaningless; compare bindings only
        if [ "$f" = "sway/keybinds.conf" ] && ! diff -q "$_repo" "$_live" >/dev/null 2>&1; then
            fail "$f DIFFERS from the repo — sway is running older bindings"
            _drift=$((_drift + 1))
        fi
    fi
done
if [ "$_drift" -gt 0 ]; then
    fail "  your session is not running what the repo says. Fix with:"
    fail "     ./install.sh --configs-only && swaymsg reload"
else
    pass "deployed config matches the repo"
fi

sect "Keybindings vs installed binaries"
# This is the automated form of "I pressed a key and nothing happened": every
# exec target in the generated keybinds.conf is resolved back through
# packages.tsv to the package that must provide it.
_kb="$HOME/.config/sway/keybinds.conf"
[ -f "$_kb" ] || _kb="$RICE_REPO/config/sway/keybinds.conf"
if [ -f "$_kb" ]; then
    _broken=0
    while read -r target; do
        case "$target" in ""|\~*|/*) continue ;; esac
        command -v "$target" >/dev/null 2>&1 && continue
        _pkg=$(pkg_for_binary "$target")
        if [ -n "$_pkg" ]; then
            fail "key binding calls '$target' — not installed (package: $_pkg)"
        else
            fail "key binding calls '$target' — not installed and not in packages.tsv"
        fi
        _broken=$((_broken + 1))
    done < <(awk '/^bindsym|^bindswitch|^bindgesture/ {
                    for (i = 1; i <= NF; i++)
                        if ($i == "exec") { print $(i+1); break }
                  }' "$_kb" | sed 's/^"//')
    [ "$_broken" -eq 0 ] && pass "every key binding's backing binary is installed"
else
    warn "keybinds.conf not found — run ./install.sh --configs-only"
fi

# The check above deliberately skips ~/ and / targets, which means it never
# looked at the rice's OWN scripts — the majority of what the keys actually
# call. A bind pointing at a script that isn't there fails exactly the way a
# missing binary does: nothing happens, no message. Close that gap too.
if [ -f "$_kb" ]; then
    _broken_scripts=0
    while read -r target; do
        case "$target" in \~/.config/rice/scripts/*) ;; *) continue ;; esac
        _name="${target##*/}"
        _path="$HOME/.config/rice/scripts/$_name"
        [ -f "$_path" ] || _path="$RICE_REPO/scripts/$_name"
        if [ ! -f "$_path" ]; then
            fail "key binding calls '$_name' — no such script"
            _broken_scripts=$((_broken_scripts + 1))
        elif [ ! -x "$_path" ]; then
            fail "key binding calls '$_name' — present but not executable"
            _broken_scripts=$((_broken_scripts + 1))
        fi
    done < <(awk '/^bindsym|^bindswitch|^bindgesture/ {
                    for (i = 1; i <= NF; i++)
                        if ($i == "exec") { print $(i+1); break }
                  }' "$_kb" | sed 's/^"//')
    [ "$_broken_scripts" -eq 0 ] && pass "every key binding's rice script exists and is executable"
fi

sect "Waybar module support"
if command -v waybar >/dev/null 2>&1; then
    _wv=$(waybar --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -n "$_wv" ]; then
        # privacy, systemd-failed-units and power-profiles-daemon all landed
        # in 0.10. Waybar disables an unknown module and carries on rather
        # than refusing to start, so an older version degrades, not breaks.
        _maj=${_wv%%.*}; _min=${_wv#*.}
        if [ "$_maj" -gt 0 ] || [ "$_min" -ge 10 ] 2>/dev/null; then
            pass "waybar $_wv (privacy, systemd-failed-units, power-profiles all supported)"
        else
            warn "waybar $_wv is older than 0.10 — privacy, systemd-failed-units and"
            warn "  power-profiles-daemon will be disabled by waybar; the rest still works"
        fi
    else
        warn "could not read the waybar version"
    fi

    # mpris is a meson BUILD OPTION, not something a version number proves —
    # confirmed by checking two different waybar 0.15.0 builds: one links
    # libplayerctl, a distro could ship one that doesn't. A version-only gate
    # would report a bar that passes verify.sh but has a permanently empty
    # media island the moment a player starts.
    if command -v playerctl >/dev/null 2>&1; then
        if ldd "$(command -v waybar)" 2>/dev/null | grep -q libplayerctl; then
            pass "waybar built with mpris support"
        else
            warn "waybar has no libplayerctl linkage — the mpris/media island"
            warn "  will stay empty even with a player running"
        fi
    fi

    if [ -f "$HOME/.config/waybar/config.jsonc" ]; then
        systemctl --user is-active waybar.service >/dev/null 2>&1 \
            && pass "waybar running" \
            || warn "waybar not running (journalctl --user -u waybar -e)"
    fi

    # A hand-edited theme.css missing @pill doesn't fail waybar — it just
    # ships islands with no background, which is invisible until you look.
    if [ -f "$HOME/.config/waybar/theme.css" ]; then
        if grep -q '@define-color pill' "$HOME/.config/waybar/theme.css"; then
            pass "waybar theme.css defines @pill"
        else
            warn "waybar theme.css has no @pill — islands will render with no background"
            warn "  Run ./scripts/theme-gen.py"
        fi
    fi
else
    fail "waybar not installed"
fi

sect "Brightness key prerequisites"
if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx video; then
    pass "in the 'video' group"
else
    fail "NOT in the 'video' group — brightness keys cannot work"
    fail "  brightnessctl writes /sys/class/backlight, granted to that group"
    fail "  fix: ./verify.sh --fix   (or: sudo usermod -aG video $ME, then re-login)"
fi

sect "Fonts"
if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
    pass "JetBrainsMono Nerd Font"
else
    fail "Nerd Font missing — waybar/quickshell icons will be tofu (re-run install.sh)"
fi

sect "Session integration (systemd)"
if systemctl --user cat sway-session.target >/dev/null 2>&1; then
    pass "sway-session.target exists"
else
    fail "sway-session.target missing — is sway-systemd installed?"
fi
for u in waybar swaync swayidle quickshell autotiling wallpaper-daemon polkit-agent cliphist-text; do
    if systemctl --user is-enabled "$u.service" >/dev/null 2>&1; then
        pass "$u.service enabled"
    else
        warn "$u.service not enabled (install.sh does this)"
    fi
done
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_CURRENT_DESKTOP:-}" = "sway" ]; then
    for u in waybar swaync wallpaper-daemon; do
        systemctl --user is-active "$u.service" >/dev/null 2>&1 \
            && pass "$u.service active" \
            || warn "$u.service not running (systemctl --user status $u)"
    done
fi

sect "Sway config validity (including included files)"
if [ -x "$RICE_REPO/scripts/validate-config.sh" ] && command -v sway >/dev/null 2>&1; then
    if out=$("$RICE_REPO/scripts/validate-config.sh" "$HOME/.config/sway/config" 2>&1); then
        pass "${out#config valid: }"
    else
        fail "sway config has errors:"
        printf '%s\n' "$out" | sed 's/^/       /'
    fi
else
    warn "cannot validate config (sway not installed?)"
fi

sect "Theme system"
if [ -f "$HOME/.config/rice/theme/colors.env" ]; then
    pass "theme: $(sed -n 's/^NAME=//p' "$HOME/.config/rice/theme/colors.env" | tr -d '\"')"
else
    fail "theme not deployed (run install.sh --configs-only)"
fi
for w in night day; do
    found=""
    for ext in jpg jpeg png; do
        [ -f "$HOME/.config/rice/wallpapers/$w.$ext" ] && found="$w.$ext"
    done
    [ -n "$found" ] && pass "wallpaper: $found" || warn "wallpaper $w.{jpg,png} missing (see wallpapers/README.md)"
done

sect "Display / scaling"
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v jq >/dev/null 2>&1; then
    swaymsg -t get_outputs 2>/dev/null | jq -r '.[] |
        "       \(.name): \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000 | floor)Hz  scale=\(.scale)  transform=\(.transform)"' \
        || warn "could not read outputs"
    scale=$(swaymsg -t get_outputs 2>/dev/null | jq -r '[.[] | select(.name=="eDP-1") | .scale][0] // empty')
    height=$(swaymsg -t get_outputs 2>/dev/null | jq -r '[.[] | select(.name=="eDP-1") | .current_mode.height][0] // empty')
    if [ -n "$height" ] && [ "$height" -ge 1400 ] 2>/dev/null; then
        if [ "$scale" = "1.000000" ] || [ "$scale" = "1" ]; then
            fail "HiDPI panel (${height}px tall) running at scale 1 — UI will be microscopic."
            fail "  set 'output eDP-1 scale 2' (2880x1800) or 1.5 (2240x1400) in config/sway/config"
        else
            pass "HiDPI panel at scale $scale"
            case "$scale" in
                *.5*|*.25*|*.75*) warn "fractional scale: XWayland apps may look blurry (native Wayland apps are fine)" ;;
            esac
        fi
    fi
else
    warn "not in a sway session — cannot read output scale (run this inside sway)"
fi

sect "Touchscreen"
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v jq >/dev/null 2>&1; then
    ntouch=$(swaymsg -t get_inputs 2>/dev/null | jq '[.[] | select(.type=="touch")] | length')
    if [ "${ntouch:-0}" -gt 0 ]; then
        pass "touch device detected ($ntouch)"
        swaymsg -t get_inputs 2>/dev/null | jq -r '.[] | select(.type=="touch") |
            "       \(.identifier) -> output: \(.libinput.calibration_matrix // "n/a") mapped: \(.type)"' 2>/dev/null || true
    else
        warn "no touch device reported by sway (is the panel a touch model?)"
    fi
    npointer=$(swaymsg -t get_inputs 2>/dev/null | jq '[.[] | select(.type=="pointer")] | length')
    [ "${npointer:-0}" -gt 0 ] && pass "pointer devices: $npointer (TrackPoint scroll config applies to these)"
fi
if command -v squeekboard >/dev/null 2>&1; then
    pass "squeekboard (on-screen keyboard) installed"
    systemctl --user is-enabled squeekboard.service >/dev/null 2>&1 \
        && pass "squeekboard.service enabled" \
        || warn "squeekboard.service not enabled"
else
    fail "squeekboard not installed — no text entry path without a physical keyboard"
fi
warn "reminder: no OSK can type into swaylock (exclusive keyboard grab)."
warn "  touch-only unlock = fingerprint; keep the password fallback working."

sect "Lid / power management"
if [ -f /etc/systemd/logind.conf.d/10-sway-rice-lid.conf ]; then
    pass "logind lid drop-in installed (sway handles the lid, VM-aware)"
else
    warn "logind lid drop-in absent: closing the lid suspends unconditionally,"
    warn "  including with KVM guests running. install.sh offers to add it."
fi
ppd=no; tlp=no
systemctl is-active power-profiles-daemon >/dev/null 2>&1 && ppd=yes
systemctl is-active tlp >/dev/null 2>&1 && tlp=yes
if [ "$ppd" = yes ] && [ "$tlp" = yes ]; then
    fail "BOTH power-profiles-daemon and TLP are active — they conflict."
    fail "  pick one: 'sudo systemctl disable --now tlp' (Fedora default is PPD)"
elif [ "$ppd" = yes ]; then
    pass "power-profiles-daemon active (Fedora default; do not also install TLP)"
    command -v powerprofilesctl >/dev/null 2>&1 && \
        echo "       current profile: $(powerprofilesctl get 2>/dev/null || echo '?')"
elif [ "$tlp" = yes ]; then
    pass "TLP active (do not also enable power-profiles-daemon)"
else
    warn "no power management daemon active (dnf install power-profiles-daemon)"
fi
systemctl --user is-enabled battery-watch.timer >/dev/null 2>&1 \
    && pass "battery-watch.timer enabled (low-battery warning will fire)" \
    || warn "battery-watch.timer not enabled — no low-battery notification"

sect "Virtualization (KVM / libvirt)"
if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        pass "/dev/kvm accessible"
    else
        warn "/dev/kvm exists but not writable by $ME (VMs will use slow TCG emulation)"
    fi
else
    fail "/dev/kvm missing — VT-x disabled in firmware? (check BIOS, then 'lsmod | grep kvm')"
fi
if id -nG | tr ' ' '\n' | grep -qx libvirt; then
    pass "user is in the libvirt group"
else
    warn "user NOT in libvirt group — virt-manager will ask for auth each time."
    warn "  fix (your call, not run automatically): sudo usermod -aG libvirt $ME && re-login"
fi
if command -v virsh >/dev/null 2>&1; then
    if virsh --connect qemu:///system list >/dev/null 2>&1; then
        pass "qemu:///system reachable (waybar VM module will work)"
    else
        warn "qemu:///system not reachable (libvirtd running? group membership applied after re-login?)"
    fi
else
    warn "virsh not installed (dnf install virt-manager libvirt-daemon-config-network)"
fi

# Storage: where VM images actually live, and how much room is left there.
# On a 512 GB single-volume install this is the most likely way to break the
# machine — qcow2 images grow until the root filesystem is full.
if command -v virsh >/dev/null 2>&1 && virsh --connect qemu:///system list >/dev/null 2>&1; then
    pools=$(virsh --connect qemu:///system pool-list --name 2>/dev/null | sed '/^$/d')
    if [ -z "$pools" ]; then
        warn "no libvirt storage pools defined yet (virt-manager creates 'default' on first use)"
    fi
    for p in $pools; do
        path=$(virsh --connect qemu:///system pool-dumpxml "$p" 2>/dev/null |
               sed -n 's:.*<path>\(.*\)</path>.*:\1:p' | head -1)
        [ -n "$path" ] || continue
        mount=$(df -P "$path" 2>/dev/null | awk 'NR==2{print $6}')
        usepct=$(df -P "$path" 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
        avail=$(df -Ph "$path" 2>/dev/null | awk 'NR==2{print $4}')
        echo "       pool '$p' -> $path  (on $mount, ${avail} free, ${usepct}% used)"
        if [ "$mount" = "/" ]; then
            warn "  pool '$p' lives on the ROOT filesystem: a growing image can fill /"
            warn "  and take the whole system down, not just VM storage."
        fi
        if [ -n "$usepct" ] && [ "$usepct" -ge 85 ] 2>/dev/null; then
            fail "  only ${avail} free on $mount (${usepct}% used) — reclaim space before starting VMs"
        fi
    done
fi
root_avail=$(df -Ph / 2>/dev/null | awk 'NR==2{print $4}')
root_pct=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
if [ -n "$root_pct" ] && [ "$root_pct" -ge 90 ] 2>/dev/null; then
    fail "root filesystem ${root_pct}% full (${root_avail} free)"
else
    pass "root filesystem: ${root_avail} free (${root_pct}% used)"
fi

sect "VS Code on Wayland"
if command -v code >/dev/null 2>&1; then
    pass "code installed"
    [ -f "$HOME/.local/share/applications/code.desktop" ] \
        && pass "code.desktop override with Wayland flags present" \
        || warn "no code.desktop override (re-run install.sh --configs-only)"
    grep -q ELECTRON_OZONE_PLATFORM_HINT "$HOME/.config/environment.d/50-sway-rice.conf" 2>/dev/null \
        && pass "ELECTRON_OZONE_PLATFORM_HINT=auto in environment.d" \
        || warn "environment.d entry missing"
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v jq >/dev/null 2>&1; then
        appid=$(swaymsg -t get_tree 2>/dev/null | jq -r '[.. | objects | select(.app_id? // "" | test("(?i)^code")) ] | length')
        if [ "${appid:-0}" -gt 0 ]; then
            pass "running VS Code window is native Wayland (has app_id, not an XWayland class)"
        else
            xw=$(swaymsg -t get_tree 2>/dev/null | jq -r '[.. | objects | select(.window_properties?.class? // "" | test("(?i)code"))] | length')
            [ "${xw:-0}" -gt 0 ] && fail "VS Code is running under XWayland — launch via the overridden .desktop entry" \
                                 || warn "VS Code not currently running; start it and re-run to confirm native Wayland"
        fi
    fi
else
    warn "code not installed (Microsoft repo) — skipping VS Code checks"
fi

sect "Fingerprint reader (report-only; setup via scripts/fingerprint-setup.sh)"
if command -v lsusb >/dev/null 2>&1; then
    fpdev=$(lsusb | grep -iE 'fingerprint|synaptics|goodix|elan|validity' || true)
    if [ -n "$fpdev" ]; then
        pass "reader on USB: $fpdev"
    else
        warn "no obvious fingerprint reader in lsusb (check the 06cb:xxxx ID manually)"
    fi
fi
if command -v fprintd-list >/dev/null 2>&1; then
    if fprintd-list "$ME" 2>&1 | grep -q 'No devices available'; then
        warn "fprintd installed but sees no reader — check libfprint supported-devices for your USB ID"
    elif fprintd-list "$ME" 2>/dev/null | grep -qi finger; then
        pass "fprintd works and a fingerprint is enrolled"
    else
        warn "fprintd works but nothing enrolled (run scripts/fingerprint-setup.sh)"
    fi
else
    warn "fprintd not installed (scripts/fingerprint-setup.sh sets it up)"
fi
if command -v authselect >/dev/null 2>&1; then
    if sudo -n authselect current 2>/dev/null | grep -q with-fingerprint; then
        pass "authselect: with-fingerprint enabled"
    else
        warn "authselect with-fingerprint not enabled (or sudo needs a password: re-run verify with sudo cached)"
    fi
fi

sect "Hardware enablement (X1 Carbon Gen 11)"
if command -v vainfo >/dev/null 2>&1; then
    _va=$(vainfo 2>&1 | grep -i 'Driver version' | head -1 | sed 's/.*: *//')
    if [ -n "$_va" ]; then
        pass "VA-API: $_va"
        case "$_va" in *iHD*) : ;; *) warn "  expected the iHD driver on Iris Xe" ;; esac
    else
        warn "vainfo present but VA-API not working — hardware video decode is off"
    fi
else
    warn "vainfo not installed — cannot confirm Iris Xe video acceleration"
fi
for svc in thermald fwupd; do
    if systemctl is-active "$svc" >/dev/null 2>&1; then
        pass "$svc active"
    elif rpm -q "$svc" >/dev/null 2>&1; then
        warn "$svc installed but not running (systemctl enable --now $svc)"
    else
        warn "$svc not installed"
    fi
done

sect "Secret Service (VS Code / git credentials)"
if command -v secret-tool >/dev/null 2>&1; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] && secret-tool search --all rice probe >/dev/null 2>&1; then
        pass "Secret Service reachable — credential storage will persist"
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
        fail "secret-tool installed but no Secret Service is answering."
        fail "  VS Code and git credentials will silently fail to persist."
        fail "  Check: systemctl --user status gnome-keyring-daemon"
    else
        warn "not in a session — cannot probe the Secret Service"
    fi
else
    fail "secret-tool missing — no Secret Service (VS Code/git credentials won't persist)"
fi

sect "Portals (screen sharing / file pickers)"
for p in xdg-desktop-portal-wlr xdg-desktop-portal-gtk; do
    rpm -q "$p" >/dev/null 2>&1 && pass "$p" || fail "$p not installed"
done

sect "Temperature sensor hint (for waybar)"
if [ -d /sys/class/hwmon ]; then
    for h in /sys/class/hwmon/hwmon*; do
        name=$(cat "$h/name" 2>/dev/null || echo '?')
        echo "       $h: $name"
    done
    echo "       If waybar shows a bogus temperature, set \"hwmon-path\" in"
    echo "       ~/.config/waybar/config.jsonc to the coretemp/thinkpad entry above."
fi

echo
echo "Done. FAILs block daily use; WARNs are quality-of-life. Nothing was changed."
