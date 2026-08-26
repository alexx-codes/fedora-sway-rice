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

sect "Virtualization (KVM / libvirt)"
if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        pass "/dev/kvm accessible"
    else
        warn "/dev/kvm exists but not writable by $USER (VMs will use slow TCG emulation)"
    fi
else
    fail "/dev/kvm missing — VT-x disabled in firmware? (check BIOS, then 'lsmod | grep kvm')"
fi
if id -nG | tr ' ' '\n' | grep -qx libvirt; then
    pass "user is in the libvirt group"
else
    warn "user NOT in libvirt group — virt-manager will ask for auth each time."
    warn "  fix (your call, not run automatically): sudo usermod -aG libvirt $USER && re-login"
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
