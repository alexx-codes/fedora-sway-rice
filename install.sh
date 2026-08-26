#!/usr/bin/env bash
# install.sh — fedora-sway-rice installer.
#
#   ./install.sh                 full install: packages + configs + services
#   ./install.sh --configs-only  redeploy configs/themes/scripts only (fast;
#                                run after editing anything in the repo)
#   ./install.sh --packages-only just the package steps
#
# Principles baked in:
#   * Fedora/dnf only; systemd user services for everything supervised.
#   * The only third-party repo is COPR errornointernet/quickshell, and it is
#     prompted for explicitly. matugen + swww build from source via cargo
#     (crates.io) instead of adding more COPRs.
#   * Nothing is deleted: existing configs are moved to <name>.bak-<epoch>.
#   * No hardcoded usernames: repo files use __HOME__ where an absolute path
#     is unavoidable; it is substituted with your real $HOME at deploy time.
set -u

repo=$(cd "$(dirname "$0")" && pwd)
mode="${1:-full}"

c_grn=$'\033[0;32m'; c_ylw=$'\033[1;33m'; c_red=$'\033[0;31m'; c_off=$'\033[0m'
ok()   { echo "${c_grn}[ok]${c_off} $*"; }
warn() { echo "${c_ylw}[!!]${c_off} $*"; }
err()  { echo "${c_red}[xx]${c_off} $*"; }
say()  { echo; echo "==> $*"; }

# ---------------------------------------------------------------- packages
install_packages() {
    say "Checking distro"
    if ! grep -qi fedora /etc/os-release 2>/dev/null; then
        err "This installer targets Fedora (dnf). Aborting."
        exit 1
    fi
    ok "Fedora detected"

    say "Installing packages from official Fedora repos"
    # Core session: sway + systemd session glue (sway-systemd provides
    # sway-session.target and env import — the supervision backbone).
    # foot: Wayland-native GPU-accelerated terminal.
    # SwayNotificationCenter (swaync): notification daemon chosen over mako
    #   because it also provides the control center panel — one official-repo
    #   package covers two roles Quickshell would otherwise have to own.
    # swaylock (NOT swaylock-effects): the -effects fork only exists in
    #   stale personal COPRs on Fedora; the aesthetic (wallpaper + themed
    #   ring) is achievable with plain swaylock, and lock screens are the
    #   wrong place for fragile packages.
    # fuzzel: launcher (official repo, rock solid) per confirmed division
    #   of labor; quickshell handles power menu/OSD/cheatsheet only.
    # xdg-desktop-portal-{wlr,gtk}: screenshare/screencast + file pickers
    #   and the settings portal (GTK apps follow dark/light via it).
    # adw-gtk3-theme + papirus: consistent GTK look in both palettes.
    # qt6ct: Qt theme management. (nwg-look is COPR-only on Fedora, so it is
    #   deliberately NOT here — gsettings does the actual GTK switching.)
    # cargo: builds matugen + swww from crates.io (no extra COPRs).
    # unzip: needed by the Nerd Font install step below.
    local pkgs=(
        sway sway-systemd swaybg swayidle swaylock
        foot waybar fuzzel SwayNotificationCenter
        grim slurp wl-clipboard cliphist
        brightnessctl playerctl pavucontrol btop
        xdg-desktop-portal-wlr xdg-desktop-portal-gtk
        qt6ct adw-gtk3-theme papirus-icon-theme
        starship cargo jq python3 unzip
        fontawesome-fonts google-noto-color-emoji-fonts
        polkit
    )
    # dnf5 (F41+) and dnf4 (F40 and older) spell "keep going past a missing
    # package" differently; --skip-unavailable is dnf5-only and aborts dnf4.
    local skipflag
    if dnf --version 2>/dev/null | head -1 | grep -q '^dnf5'; then
        skipflag="--skip-unavailable"
    else
        skipflag="--setopt=strict=0"
    fi
    sudo dnf install -y "$skipflag" "${pkgs[@]}" || {
        err "dnf install failed; fix the error above and re-run"; exit 1; }

    # Skipped packages are silent above, so verify each one landed and say
    # loudly which didn't — a missing package here surfaces later as a dead
    # unit or tofu glyphs, which is much harder to trace back.
    local missing=()
    for p in "${pkgs[@]}"; do
        rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        warn "NOT installed (unavailable in your repos): ${missing[*]}"
        warn "the rice degrades gracefully, but fix these before relying on the affected part"
    else
        ok "all ${#pkgs[@]} official-repo packages installed"
    fi

    # Polkit GUI agent: package name differs across Fedora releases.
    say "Installing a GUI polkit agent"
    sudo dnf install -y polkit-gnome 2>/dev/null \
        || sudo dnf install -y lxqt-policykit 2>/dev/null \
        || warn "no GUI polkit agent package found — install one manually (polkit-gnome or lxqt-policykit)"

    # ------------------------------------------------------------ COPR
    say "Quickshell (COPR errornointernet/quickshell)"
    if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
        ok "quickshell already installed"
    else
        echo "Quickshell has no official Fedora package. Enabling the COPR is a"
        echo "trust decision: errornointernet/quickshell is the de-facto repo."
        echo "Note: after major Fedora Qt6 updates this package can lag a few"
        echo "days; the widget layer has fuzzel fallbacks so nothing breaks."
        read -r -p "Enable COPR errornointernet/quickshell and install quickshell? [y/N] " ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            sudo dnf copr enable -y errornointernet/quickshell \
                && sudo dnf install -y quickshell \
                && ok "quickshell installed" \
                || warn "quickshell install failed (Qt version lag?) — fuzzel fallbacks will be used"
        else
            warn "skipped quickshell — power menu/OSD/cheatsheet use fuzzel fallbacks"
        fi
    fi

    # ------------------------------------------------------------ cargo builds
    say "Building matugen + swww from source (cargo, crates.io — no COPR)"
    if command -v matugen >/dev/null 2>&1; then ok "matugen present"
    else
        cargo install --locked matugen \
            && ok "matugen built" \
            || warn "matugen build failed — optional: committed dark palette works without it"
    fi
    if command -v swww >/dev/null 2>&1; then ok "swww present"
    else
        cargo install --locked swww \
            && ok "swww built" \
            || warn "swww build failed — wallpaper-daemon falls back to swaybg (no animated transitions)"
    fi

    # ------------------------------------------------------------ nerd font
    say "Installing JetBrainsMono Nerd Font (waybar/quickshell glyphs)"
    local fontdir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
        ok "nerd font already installed"
    else
        mkdir -p "$fontdir"
        if curl -fL --retry 3 -o /tmp/JetBrainsMono.zip \
            "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"; then
            unzip -o -q /tmp/JetBrainsMono.zip -d "$fontdir" '*.ttf'
            rm -f /tmp/JetBrainsMono.zip
            fc-cache -f "$fontdir"
            ok "JetBrainsMono Nerd Font installed to ~/.local/share/fonts"
        else
            warn "font download failed — icons will look wrong until you install a Nerd Font"
        fi
    fi
}

# ---------------------------------------------------------------- deploy
backup() { # backup <path>
    local p="$1"
    if [ -e "$p" ] && [ ! -L "$p" ]; then
        local bak
        bak="$p.bak-$(date +%s)"
        mv "$p" "$bak"
        warn "existing $(basename "$p") moved to $bak (nothing deleted)"
    elif [ -L "$p" ]; then
        rm -f "$p"
    fi
}

detect_thermal_zone() {
    # Prefer the CPU package sensor; thermal_zone0 is often acpitz (chassis)
    # on ThinkPads, which shows a plausible but wrong temperature in waybar.
    local want tz type
    for want in x86_pkg_temp TCPU cpu_thermal; do
        for tz in /sys/class/thermal/thermal_zone*; do
            [ -f "$tz/type" ] || continue
            type=$(cat "$tz/type" 2>/dev/null)
            if [ "$type" = "$want" ]; then
                echo "${tz##*thermal_zone}"
                return
            fi
        done
    done
    echo 0
}

deploy_tree() { # deploy_tree <src-dir> <dst-dir>  (copies + placeholder substitution)
    local src="$1" dst="$2"
    mkdir -p "$dst"
    (cd "$src" && find . -type f) | while read -r f; do
        local d="$dst/${f#./}"
        mkdir -p "$(dirname "$d")"
        sed -e "s|__HOME__|$HOME|g" \
            -e "s|__THERMAL_ZONE__|${THERMAL_ZONE:-0}|g" "$src/$f" > "$d"
    done
}

deploy_configs() {
    say "Backing up + deploying configs"
    local cfg="$HOME/.config"
    mkdir -p "$cfg"

    THERMAL_ZONE=$(detect_thermal_zone)
    ok "waybar temperature pinned to thermal_zone$THERMAL_ZONE ($(cat "/sys/class/thermal/thermal_zone$THERMAL_ZONE/type" 2>/dev/null || echo 'type unknown'))"

    # First-run backups of app config dirs we own
    for app in sway waybar foot fuzzel swaync qt6ct; do
        if [ -d "$cfg/$app" ] && [ ! -f "$cfg/$app/.rice-managed" ]; then
            backup "$cfg/$app"
        fi
    done
    if [ -d "$cfg/rice" ] && [ ! -f "$cfg/rice/.rice-managed" ]; then
        backup "$cfg/rice"
    fi

    for app in sway waybar foot swaync qt6ct; do
        deploy_tree "$repo/config/$app" "$cfg/$app"
        touch "$cfg/$app/.rice-managed"
    done
    deploy_tree "$repo/config/quickshell" "$cfg/quickshell"
    deploy_tree "$repo/config/environment.d" "$cfg/environment.d"
    sed "s|__HOME__|$HOME|g" "$repo/config/starship.toml" > "$cfg/starship.toml"

    # The rice dir: themes, scripts, keybinds source of truth, wallpapers
    mkdir -p "$cfg/rice"
    touch "$cfg/rice/.rice-managed"
    deploy_tree "$repo/themes" "$cfg/rice/themes"
    deploy_tree "$repo/scripts" "$cfg/rice/scripts"
    chmod +x "$cfg/rice/scripts/"*.sh "$cfg/rice/scripts/"*.py
    cp "$repo/keybinds.tsv" "$cfg/rice/keybinds.tsv"
    deploy_tree "$repo/config/matugen" "$cfg/rice/matugen"

    mkdir -p "$cfg/rice/wallpapers"
    local found_night=""
    for ext in jpg jpeg png; do
        [ -f "$repo/wallpapers/night.$ext" ] && { cp "$repo/wallpapers/night.$ext" "$cfg/rice/wallpapers/"; found_night=y; }
        [ -f "$repo/wallpapers/day.$ext" ]   && cp "$repo/wallpapers/day.$ext" "$cfg/rice/wallpapers/"
    done
    [ -n "$found_night" ] || warn "wallpapers/night.jpg not in repo — see wallpapers/README.md"

    # swaylock reads a plain file; point it through the active-theme symlink
    mkdir -p "$cfg/swaylock"
    backup "$cfg/swaylock/config"
    ln -sfn "$cfg/rice/active/swaylock.conf" "$cfg/swaylock/config"

    # waybar/swaync import a relative theme.css; make it a symlink into active/
    ln -sfn "$cfg/rice/active/waybar.css" "$cfg/waybar/theme.css"
    ln -sfn "$cfg/rice/active/swaync-theme.css" "$cfg/swaync/theme.css"

    # fuzzel: full per-theme config generated by theme-gen.py; symlink through
    # the active theme (avoids fuzzel's version-dependent `include` support)
    mkdir -p "$cfg/fuzzel"
    touch "$cfg/fuzzel/.rice-managed"
    backup "$cfg/fuzzel/fuzzel.ini"
    ln -sfn "$cfg/rice/active/fuzzel.ini" "$cfg/fuzzel/fuzzel.ini"

    # Active theme symlink: default to dark, keep current choice on re-deploys
    if [ ! -L "$cfg/rice/active" ]; then
        ln -sfn "$cfg/rice/themes/dark" "$cfg/rice/active"
    fi

    # First-boot wallpaper links: theme-toggle.sh maintains these on every
    # switch, but on a fresh install nothing has toggled yet, so create them
    # here or the first session comes up wallpaper-less and swaylock loses
    # its background image (it falls back to a solid color, but still).
    if [ ! -e "$cfg/rice/wallpapers/current" ]; then
        local wallname wallfile ext
        wallname=$(sed -n 's/^WALLPAPER=//p' "$cfg/rice/active/colors.env" 2>/dev/null)
        wallfile=""
        for ext in jpg jpeg png; do
            if [ -f "$cfg/rice/wallpapers/${wallname:-night}.$ext" ]; then
                wallfile="$cfg/rice/wallpapers/${wallname:-night}.$ext"; break
            fi
        done
        if [ -n "$wallfile" ]; then
            ln -sfn "$wallfile" "$cfg/rice/wallpapers/current"
            ln -sfn "$wallfile" "$cfg/rice/wallpapers/current-lock"
        else
            warn "no wallpaper file found for first boot — session starts on a solid color"
        fi
    fi

    # VS Code: desktop-entry override forces native Wayland regardless of env
    mkdir -p "$HOME/.local/share/applications"
    if [ -f /usr/share/applications/code.desktop ]; then
        sed 's|^Exec=/usr/share/code/code|Exec=/usr/share/code/code --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations|' \
            /usr/share/applications/code.desktop > "$HOME/.local/share/applications/code.desktop"
        ok "code.desktop override installed (native Wayland flags)"
    fi

    ok "configs deployed (edit in the repo, re-run ./install.sh --configs-only)"
}

deploy_services() {
    say "Installing systemd user services"
    local unitdir="$HOME/.config/systemd/user"
    mkdir -p "$unitdir"
    cp "$repo"/systemd/*.service "$unitdir/"

    # sway-session.target normally comes from Fedora's sway-systemd package;
    # provide a minimal fallback only if it's missing entirely.
    if ! systemctl --user cat sway-session.target >/dev/null 2>&1; then
        cat > "$unitdir/sway-session.target" <<'EOF'
[Unit]
Description=sway compositor session
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
EOF
        warn "sway-session.target not provided by sway-systemd; installed a fallback"
    fi

    systemctl --user daemon-reload
    systemctl --user enable \
        waybar.service swaync.service swayidle.service quickshell.service \
        wallpaper-daemon.service wallpaper-set.service polkit-agent.service \
        cliphist-text.service cliphist-image.service 2>/dev/null \
        && ok "user services enabled (they start with sway-session.target)"
}

post_setup() {
    say "Initial theme + shell prompt"
    # Apply GTK settings for the active mode without needing a running sway
    # shellcheck disable=SC1091
    . "$HOME/.config/rice/active/colors.env"
    gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME" 2>/dev/null || true

    if ! grep -q 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
        printf '\n# starship prompt (fedora-sway-rice)\ncommand -v starship >/dev/null && eval "$(starship init bash)"\n' >> "$HOME/.bashrc"
        ok "starship hooked into ~/.bashrc"
    fi

    echo
    ok "Install finished."
    echo "  next: run ./verify.sh, then log out and pick the Sway session."
    echo "  keybinds: ~/.config/sway/KEYBINDS.md or \$mod+Shift+/ in-session."
}

case "$mode" in
    --configs-only)  deploy_configs; deploy_services ;;
    --packages-only) install_packages ;;
    full|--full)     install_packages; deploy_configs; deploy_services; post_setup ;;
    *) echo "usage: install.sh [--configs-only|--packages-only]"; exit 2 ;;
esac
