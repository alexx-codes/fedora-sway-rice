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

# packages.tsv is the single manifest shared with verify.sh
# shellcheck source=scripts/lib-packages.sh
. "$repo/scripts/lib-packages.sh"

# ---------------------------------------------------------------- packages
install_packages() {
    # Preflight first: catch everything that would make this run fail — an
    # atomic Fedora variant where dnf can't install at all, a held dnf lock,
    # no network, no disk — BEFORE touching anything, rather than dying
    # halfway and leaving a half-configured desktop.
    if ! "$repo/verify.sh" --preflight; then
        err "Preflight failed. Fix the blockers above, or run:"
        err "  ./verify.sh --fix        repair what can be repaired"
        err "  ./install.sh --configs-only   configs only, no packages"
        exit 1
    fi

    say "Installing packages from packages.tsv"
    # The package list lives in packages.tsv (repo root), shared with
    # verify.sh so the installer and the checker can never disagree about
    # what the rice needs. Each entry carries its tier, the binary it must
    # provide, and why it is here.
    #
    # Deliberately absent: VS Code, browsers, virt-manager. Those are
    # applications you manage yourself. What IS here on their behalf is the
    # integration tier — portals, Secret Service, VA-API — which is what
    # those apps need *from sway* to behave correctly.
    local pkgs=()
    mapfile -t pkgs < <(pkg_list base deps hardware integration optional)
    if [ ${#pkgs[@]} -eq 0 ]; then
        err "packages.tsv is missing or unreadable — cannot continue"; exit 1
    fi
    ok "manifest: ${#pkgs[@]} packages across 5 tiers"

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
    # loudly which didn't, with the reason it mattered — a missing package
    # here otherwise surfaces later as a dead unit, tofu glyphs, or a key
    # that does nothing, all much harder to trace back.
    local missing=()
    mapfile -t missing < <(pkg_missing base deps hardware integration)
    if [ ${#missing[@]} -gt 0 ]; then
        warn "NOT installed (unavailable in your repos):"
        local p
        for p in "${missing[@]}"; do
            warn "  $p — $(pkg_field "$p" 4)"
        done
        warn "run ./verify.sh --fix to retry these"
    else
        ok "every required package installed"
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
        echo "days; the widget layer has rofi fallbacks so nothing breaks."
        read -r -p "Enable COPR errornointernet/quickshell and install quickshell? [y/N] " ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            sudo dnf copr enable -y errornointernet/quickshell \
                && sudo dnf install -y quickshell \
                && ok "quickshell installed" \
                || warn "quickshell install failed (Qt version lag?) — rofi fallbacks will be used"
        else
            warn "skipped quickshell — power menu/OSD/cheatsheet use rofi fallbacks"
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

detect_panel_scale() {
    # HiDPI scale, resolved rather than guessed. Reads the panel's native
    # mode: from sway when we're already inside a session, otherwise straight
    # from DRM sysfs, whose first "modes" line is the preferred mode — which
    # works from a TTY before sway has ever run.
    #
    # Integer 2 is chosen over fractional for tall panels: fractional scaling
    # makes XWayland clients render soft, and everything in this rice is
    # already sized in LOGICAL pixels, so the scale alone corrects it.
    local h=""
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v swaymsg >/dev/null 2>&1 \
       && command -v jq >/dev/null 2>&1; then
        h=$(swaymsg -t get_outputs 2>/dev/null \
            | jq -r '[.[] | select(.name | test("^eDP")) | .current_mode.height][0] // empty')
    fi
    if [ -z "$h" ]; then
        local m
        for m in /sys/class/drm/*eDP*/modes; do
            [ -f "$m" ] || continue
            h=$(head -1 "$m" 2>/dev/null | cut -dx -f2)
            [ -n "$h" ] && break
        done
    fi
    if [ -z "$h" ]; then
        echo 1
        return
    fi
    if   [ "$h" -ge 1700 ] 2>/dev/null; then echo 2
    elif [ "$h" -ge 1300 ] 2>/dev/null; then echo 1.5
    else                                     echo 1
    fi
}

deploy_tree() { # deploy_tree <src-dir> <dst-dir>  (copies + placeholder substitution)
    local src="$1" dst="$2"
    mkdir -p "$dst"
    (cd "$src" && find . -type f) | while read -r f; do
        local d="$dst/${f#./}"
        mkdir -p "$(dirname "$d")"
        sed -e "s|__HOME__|$HOME|g" \
            -e "s|__THERMAL_ZONE__|${THERMAL_ZONE:-0}|g" \
            -e "s|__PANEL_SCALE__|${PANEL_SCALE:-1}|g" "$src/$f" > "$d"
    done
}

deploy_configs() {
    say "Backing up + deploying configs"
    local cfg="$HOME/.config"
    mkdir -p "$cfg"

    THERMAL_ZONE=$(detect_thermal_zone)
    ok "waybar temperature pinned to thermal_zone$THERMAL_ZONE ($(cat "/sys/class/thermal/thermal_zone$THERMAL_ZONE/type" 2>/dev/null || echo 'type unknown'))"

    PANEL_SCALE=$(detect_panel_scale)
    if [ "$PANEL_SCALE" = 1 ]; then
        ok "panel scale 1 (standard-DPI panel, or panel not detected)"
    else
        ok "HiDPI panel detected — output scale set to $PANEL_SCALE"
    fi

    # First-run backups of app config dirs we own
    for app in sway waybar foot rofi swaync qt6ct; do
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
    # verify.sh --fix runs from the deployed copy too, so it needs the manifest
    cp "$repo/packages.tsv" "$cfg/rice/packages.tsv"
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

    # rofi: full per-theme config+theme generated by theme-gen.py; symlink
    # through the active theme. rofi resolves @import relative to its own
    # config dir, which the symlink would break, hence one self-contained file.
    mkdir -p "$cfg/rofi"
    touch "$cfg/rofi/.rice-managed"
    backup "$cfg/rofi/config.rasi"
    ln -sfn "$cfg/rice/active/rofi.rasi" "$cfg/rofi/config.rasi"

    # Active theme symlink: default to dark, keep current choice on re-deploys
    if [ ! -L "$cfg/rice/active" ]; then
        ln -sfn "$cfg/rice/themes/dark" "$cfg/rice/active"
    fi

    # Runtime overrides file, included last by the sway config. Created empty
    # if absent and NEVER overwritten — this is the Settings app's file, and
    # keeping install.sh out of it is what stops runtime changes and the
    # git-tracked repo from fighting.
    if [ ! -f "$cfg/rice/settings.conf" ]; then
        cat > "$cfg/rice/settings.conf" <<'EOF'
# Runtime overrides, written by the Settings app ($mod+Shift+S).
# Included last by ~/.config/sway/config, so anything here wins over the
# generated defaults. install.sh never touches this file.
# Safe to empty or delete to fall back to the repo defaults.
#
# Syntax note: sway does NOT accept a trailing "#" comment on a command line.
#   output eDP-1 scale 2      <- fine
#   output eDP-1 scale 2  # hi <- parse error
# Put comments on their own line. Check your edits with:
#   ~/.config/rice/scripts/validate-config.sh
# (plain `sway --validate` does NOT report errors inside included files)
EOF
        ok "created ~/.config/rice/settings.conf (Settings app overrides)"
    else
        ok "kept your existing settings.conf overrides"
    fi

    # Settings app: GTK4/libadwaita, launched by $mod+Shift+S, F11/F12, and
    # from rofi. Deployed as a package next to a thin launcher on PATH.
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
    rm -rf "$repo/settings/rice_settings/__pycache__"
    deploy_tree "$repo/settings/rice_settings" "$cfg/rice/rice_settings"
    sed "s|__HOME__|$HOME|g" "$repo/settings/rice-settings" \
        > "$HOME/.local/bin/rice-settings"
    chmod +x "$HOME/.local/bin/rice-settings"
    # The launcher adds its own directory to sys.path, so put the package
    # where it can find it.
    rm -rf "$HOME/.local/bin/rice_settings"
    cp -r "$cfg/rice/rice_settings" "$HOME/.local/bin/rice_settings"
    rm -rf "$HOME/.local/bin/rice_settings/__pycache__" \
           "$cfg/rice/rice_settings/__pycache__"
    sed "s|__HOME__|$HOME|g" "$repo/settings/rice-settings.desktop" \
        > "$HOME/.local/share/applications/rice-settings.desktop"
    ok "Settings app installed (\$mod+Shift+S, or 'Settings' in rofi)"

    # Session entry so the display manager offers "Sway (rice)" — the wrapper
    # exports the Qt/Electron env that environment.d cannot reliably deliver
    # to sway-launched apps (audit finding F4).
    mkdir -p "$HOME/.local/share/wayland-sessions"
    sed "s|__HOME__|$HOME|g" "$repo/config/wayland-sessions/sway-rice.desktop" \
        > "$HOME/.local/share/wayland-sessions/sway-rice.desktop"
    ok "session entry installed — pick 'Sway (rice)' at the login screen"

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
        cliphist-text.service cliphist-image.service squeekboard.service \
        battery-watch.timer 2>/dev/null \
        && ok "user services enabled (they start with sway-session.target)"
}

configure_lid() {
    # Lid policy: logind's unconditional HandleLidSwitch=suspend would
    # freeze running KVM guests mid-write. With this drop-in, sway's
    # bindswitch routes the lid to scripts/lid.sh, which suspends normally
    # unless VMs are running (then: lock + screen off, no suspend).
    # This is a system-level change, so it is asked for, never silent.
    say "Lid-switch policy (VM-aware suspend)"
    local dropin=/etc/systemd/logind.conf.d/10-sway-rice-lid.conf
    if [ -f "$dropin" ]; then
        ok "logind lid drop-in already present"
        return
    fi
    echo "To make lid-close VM-aware, logind must stop handling the lid itself"
    echo "(drop-in: HandleLidSwitch=ignore). Tradeoff: outside a running sway"
    echo "session (e.g. sitting at the login screen), closing the lid will no"
    echo "longer suspend. Skipping keeps logind's unconditional suspend."
    read -r -p "Install the logind lid drop-in? [y/N] " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
        sudo mkdir -p /etc/systemd/logind.conf.d
        sudo tee "$dropin" >/dev/null <<'EOF'
# fedora-sway-rice: sway handles the lid (VM-aware; see scripts/lid.sh).
# Remove this file and restart systemd-logind to restore default behavior.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
EOF
        ok "drop-in installed — takes effect after 'sudo systemctl restart systemd-logind' or the next boot"
    else
        warn "skipped — logind will suspend on lid close even with VMs running"
    fi
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
    full|--full)     install_packages; deploy_configs; deploy_services; configure_lid; post_setup ;;
    *) echo "usage: install.sh [--configs-only|--packages-only]"; exit 2 ;;
esac
