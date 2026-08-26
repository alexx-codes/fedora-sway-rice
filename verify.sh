#!/usr/bin/env bash
# verify.sh — read-only health check for the rice + the virtualization and
# VS Code specifics of this machine. CHANGES NOTHING; it reports what needs
# attention and the exact command to fix it, so nothing (group membership,
# flags) is ever changed silently.
set -u

c_grn=$'\033[0;32m'; c_ylw=$'\033[1;33m'; c_red=$'\033[0;31m'; c_off=$'\033[0m'
pass() { echo "${c_grn}[PASS]${c_off} $*"; }
warn() { echo "${c_ylw}[WARN]${c_off} $*"; }
fail() { echo "${c_red}[FAIL]${c_off} $*"; }
sect() { echo; echo "── $* ──"; }

# $USER is not guaranteed to be exported (set -u aborts the whole script on
# it), so resolve the login name once from a source that always works.
ME=$(id -un)

sect "Packages / binaries"
for bin in sway foot waybar fuzzel swaync swaylock swayidle grim slurp \
           wl-copy cliphist brightnessctl qt6ct starship jq; do
    command -v "$bin" >/dev/null 2>&1 && pass "$bin" || fail "$bin missing (dnf install)"
done
for bin in qs matugen swww; do
    PATH="$HOME/.cargo/bin:$PATH" command -v "$bin" >/dev/null 2>&1 \
        && pass "$bin" \
        || warn "$bin missing (optional: quickshell=COPR, matugen/swww=cargo install; fallbacks active)"
done

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
for u in waybar swaync swayidle quickshell wallpaper-daemon polkit-agent cliphist-text; do
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

sect "Theme system"
active=$(readlink "$HOME/.config/rice/active" 2>/dev/null || true)
if [ -n "$active" ]; then
    pass "active theme: $(basename "$active")"
else
    # shellcheck disable=SC2088  # message text, not a path
    fail "~/.config/rice/active symlink missing (run install.sh --configs-only)"
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
