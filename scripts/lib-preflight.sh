#!/usr/bin/env bash
# lib-preflight.sh — everything that would make install.sh fail, detected
# BEFORE it runs, plus the tiered auto-repair behind verify.sh --fix.
#
# install.sh sources this and calls preflight_check at startup, so a run that
# cannot succeed stops immediately with a clear reason instead of dying
# halfway through and leaving a half-configured desktop.
#
# Repair tiers, deliberately separated so the standing rule holds — safe and
# reversible things are fixed automatically; anything touching trust, group
# membership, or system config still asks first:
#
#   AUTO    official-repo packages, missing dirs, broken symlinks, missing
#           generated theme files, disabled user services, placeholder leaks
#   PROMPT  group membership, COPR, logind drop-in, stopping PackageKit,
#           removing a conflicting package
#   REPORT  absent hardware, unsupported reader, atomic Fedora — never touched
#
# Expects the caller to provide pass/warn/fail/ok/say helpers.

PREFLIGHT_BLOCKERS=0
PREFLIGHT_DRYRUN=0

pf_block() { fail "$*"; PREFLIGHT_BLOCKERS=$((PREFLIGHT_BLOCKERS + 1)); }
pf_would() { # echo an action, or perform it, depending on --dry-run
    if [ "$PREFLIGHT_DRYRUN" = 1 ]; then
        echo "       would run: $*"
        return 0
    fi
    "$@"
}

# ---------------------------------------------------------------- preflight
preflight_check() {
    say "Preflight — can install.sh actually succeed here?"

    # 1. Fedora, and specifically NOT an atomic variant. dnf install simply
    #    does not work on Silverblue/Kinoite/Sericea (rpm-ostree instead), and
    #    without this check install.sh fails confusingly partway through.
    if ! grep -qi fedora /etc/os-release 2>/dev/null; then
        pf_block "Not Fedora. This installer targets Fedora with dnf."
    elif [ -f /run/ostree-booted ] || [ -d /sysroot/ostree ]; then
        pf_block "Fedora Atomic (Silverblue/Kinoite/Sericea) detected."
        fail "  dnf install does not work here. Packages need:"
        fail "    rpm-ostree install <pkg>   (then reboot)"
        fail "  The config half still works: ./install.sh --configs-only"
    else
        pass "Fedora, traditional (dnf-managed) variant"
    fi

    # 2. Release age — packages in the manifest may not exist on an EOL release
    local ver
    ver=$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-}")
    if [ -n "$ver" ] && [ "$ver" -lt 40 ] 2>/dev/null; then
        warn "Fedora $ver is past end of life; some packages may be unavailable"
    elif [ -n "$ver" ]; then
        pass "Fedora $ver"
    fi

    # 3. sudo. Without it every dnf step fails one at a time.
    if [ "$(id -u)" -eq 0 ]; then
        warn "running as root — the rice is a per-user config; run as your user"
    elif sudo -n true 2>/dev/null; then
        pass "sudo available (credentials cached)"
    elif command -v sudo >/dev/null 2>&1; then
        pass "sudo present (will prompt for your password)"
    else
        pf_block "sudo not installed — cannot install packages"
    fi

    # 4. Bootstrap tools install.sh itself uses before it can install anything
    local t missing_tools=()
    for t in rpm curl python3 awk sed find; do
        command -v "$t" >/dev/null 2>&1 || missing_tools+=("$t")
    done
    if [ ${#missing_tools[@]} -gt 0 ]; then
        pf_block "missing bootstrap tools: ${missing_tools[*]}"
    else
        pass "bootstrap tools present"
    fi

    # 5. A held dnf/rpm lock. PackageKit grabbing this is the single most
    #    common Fedora install failure and produces a confusing hang.
    if command -v fuser >/dev/null 2>&1 && \
       fuser /var/lib/rpm/.rpm.lock /var/cache/dnf/metadata_lock.pid >/dev/null 2>&1; then
        warn "the rpm/dnf lock is held by another process"
        pgrep -a packagekitd >/dev/null 2>&1 && \
            warn "  it's PackageKit. --fix can stop it (prompted)"
    elif pgrep -x packagekitd >/dev/null 2>&1; then
        warn "PackageKit is running and may grab the dnf lock mid-install"
        warn "  --fix offers to stop it first (prompted)"
    else
        pass "no competing package manager holding the lock"
    fi

    # 6. Network + working dnf metadata
    if command -v dnf >/dev/null 2>&1; then
        if timeout 25 dnf -q repoquery --qf '%{name}' sway >/dev/null 2>&1; then
            pass "dnf repositories reachable"
        else
            pf_block "cannot query dnf repos — no network, or a broken repo file"
            fail "  check: dnf repolist   and   dnf clean all"
        fi
    fi

    # 7. Disk. The cargo build (swww) needs real space, and a full
    #    root filesystem fails in a way that looks like a compiler error.
    local avail_mb
    avail_mb=$(df -Pm "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$avail_mb" ] && [ "$avail_mb" -lt 2048 ] 2>/dev/null; then
        pf_block "only ${avail_mb}MB free in \$HOME — cargo builds need ~2GB"
    elif [ -n "$avail_mb" ]; then
        pass "disk: ${avail_mb}MB free in \$HOME"
    fi

    # 8. /tmp noexec breaks cargo's build scratch space
    if findmnt -no OPTIONS /tmp 2>/dev/null | grep -q noexec; then
        warn "/tmp is mounted noexec — cargo builds may fail"
        warn "  workaround: CARGO_TARGET_DIR=\$HOME/.cache/cargo-target"
    fi

    echo
    if [ "$PREFLIGHT_BLOCKERS" -gt 0 ]; then
        fail "$PREFLIGHT_BLOCKERS blocker(s) — install.sh would fail. Fix the above first."
        return 1
    fi
    ok "preflight clean — install.sh can proceed"
    return 0
}

# ---------------------------------------------------------------- repair
# Tier AUTO: safe, reversible, no prompts.
repair_auto() {
    local did=0

    # Missing packages from the shared manifest
    local missing=()
    if ! command -v rpm >/dev/null 2>&1; then
        warn "rpm unavailable — cannot check which packages are installed"
        return 0
    fi
    mapfile -t missing < <(pkg_missing base deps hardware integration)
    if [ ${#missing[@]} -gt 0 ]; then
        warn "installing ${#missing[@]} missing package(s): ${missing[*]}"
        local skipflag="--setopt=strict=0"
        dnf --version 2>/dev/null | head -1 | grep -q '^dnf5' && skipflag="--skip-unavailable"
        pf_would sudo dnf install -y "$skipflag" "${missing[@]}" && did=1
    else
        pass "all manifest packages installed"
    fi

    # Directories the scripts write into
    local d
    for d in "${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots" \
             "$HOME/.config/rice/wallpapers" "$HOME/.local/share/applications"; do
        if [ ! -d "$d" ]; then
            warn "creating missing directory: $d"
            pf_would mkdir -p "$d" && did=1
        fi
    done

    # Generated theme files — regenerate rather than hand-repair
    local f incomplete=0
    for f in colors.env foot.ini colors.css sway-colors.conf rofi.rasi \
             swaylock.conf quickshell.json qt6ct-colors.conf; do
        [ -f "$HOME/.config/rice/theme/$f" ] || incomplete=1
    done
    if [ "$incomplete" = 1 ]; then
        warn "theme files are missing — regenerating"
        pf_would "$RICE_REPO/scripts/theme-gen.py" && did=1
        pf_would "$RICE_REPO/install.sh" --configs-only && did=1
    else
        pass "theme files complete"
    fi

    # Wallpaper links (the B3 first-boot bug, in case it recurs)
    if [ ! -e "$HOME/.config/rice/wallpapers/current" ]; then
        warn "wallpaper link missing — redeploying configs"
        pf_would "$RICE_REPO/install.sh" --configs-only && did=1
    fi

    # Placeholder leak means a deploy was interrupted
    if grep -rql '__HOME__\|__THERMAL_ZONE__\|__PANEL_SCALE__' \
        "$HOME/.config/sway" "$HOME/.config/waybar" 2>/dev/null; then
        warn "unsubstituted placeholders found — redeploying configs"
        pf_would "$RICE_REPO/install.sh" --configs-only && did=1
    fi

    # Installed-but-disabled user services
    local u
    for u in waybar swaync swayidle quickshell wallpaper-daemon polkit-agent \
             cliphist-text cliphist-image squeekboard; do
        [ -f "$HOME/.config/systemd/user/$u.service" ] || continue
        if ! systemctl --user is-enabled "$u.service" >/dev/null 2>&1; then
            warn "enabling $u.service"
            pf_would systemctl --user enable "$u.service" && did=1
        fi
    done
    if [ -f "$HOME/.config/systemd/user/battery-watch.timer" ] && \
       ! systemctl --user is-enabled battery-watch.timer >/dev/null 2>&1; then
        warn "enabling battery-watch.timer"
        pf_would systemctl --user enable battery-watch.timer && did=1
    fi

    [ "$did" = 0 ] && ok "nothing needed auto-repair"
    return 0
}

# Tier PROMPT: trust or system-level. Always asks, never assumes.
repair_prompted() {
    local ans

    _ask() { # _ask <question> ; returns 0 on yes
        if [ "$PREFLIGHT_DRYRUN" = 1 ]; then
            echo "       would ask: $1"
            return 1
        fi
        read -r -p "       $1 [y/N] " ans
        [[ "$ans" =~ ^[Yy] ]]
    }

    # video group — the brightness-key bug
    if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx video; then
        warn "you are not in the 'video' group — brightness keys cannot work"
        warn "  brightnessctl writes /sys/class/backlight, granted to that group"
        if _ask "Run: sudo usermod -aG video $ME ?"; then
            sudo usermod -aG video "$ME" && \
                ok "added — takes effect after you log out and back in"
        else
            warn "  skipped; brightness keys will keep failing"
        fi
    else
        pass "in the 'video' group (brightness keys can work)"
    fi

    # libvirt group
    if ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx libvirt; then
        if command -v virsh >/dev/null 2>&1; then
            warn "not in the 'libvirt' group — virt-manager will prompt every launch"
            if _ask "Run: sudo usermod -aG libvirt $ME ?"; then
                sudo usermod -aG libvirt "$ME" && \
                    ok "added — takes effect after you log out and back in"
            fi
        fi
    else
        pass "in the 'libvirt' group"
    fi

    # PackageKit holding the dnf lock
    if pgrep -x packagekitd >/dev/null 2>&1; then
        warn "PackageKit is running and can grab the dnf lock mid-install"
        if _ask "Stop packagekit for this session?"; then
            sudo systemctl stop packagekit && ok "packagekit stopped"
        fi
    fi

    # TLP vs power-profiles-daemon — they conflict
    if systemctl is-active tlp >/dev/null 2>&1 && \
       systemctl is-active power-profiles-daemon >/dev/null 2>&1; then
        warn "BOTH TLP and power-profiles-daemon are active — they conflict"
        if _ask "Disable TLP and keep power-profiles-daemon (the Fedora default)?"; then
            sudo systemctl disable --now tlp && ok "TLP disabled"
        fi
    fi
    return 0
}

# Tier REPORT: never touched, only described.
repair_report_only() {
    [ -e /dev/kvm ] || warn "no /dev/kvm — enable VT-x in firmware (not fixable from here)"
    if command -v fprintd-list >/dev/null 2>&1 && \
       fprintd-list "$ME" 2>&1 | grep -q 'No devices available'; then
        warn "fprintd sees no reader — check the USB ID against libfprint's"
        warn "  supported list; an unsupported sensor is not fixable in software"
    fi
    return 0
}
