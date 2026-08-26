#!/usr/bin/env bash
# theme-toggle.sh — atomically switch the whole desktop between dark
# (Tokyo Night) and light (Pastel Cat), or apply one explicitly:
#     theme-toggle.sh            # toggle
#     theme-toggle.sh dark|light # set a specific mode
#     theme-toggle.sh --apply    # re-apply current mode (used at login)
#
# Design: ~/.config/rice/active is a symlink to themes/<mode>. Every config
# reads colors through that symlink, so the swap itself is a single atomic
# rename. Everything after the swap is "wake the apps up": each step is
# best-effort and failures are collected and reported instead of aborting,
# so one broken component can never leave the rest half-switched.
set -u

RICE="$HOME/.config/rice"
THEMES="$RICE/themes"
ACTIVE="$RICE/active"

fail_list=()
step() { # step <name> <cmd...>
    local name="$1"; shift
    "$@" >/dev/null 2>&1 || fail_list+=("$name")
}

current() {
    local t
    t=$(readlink "$ACTIVE" 2>/dev/null) || { echo dark; return; }
    basename "$t"
}

mode="${1:-}"
cur="$(current)"
case "$mode" in
    dark|light) target="$mode" ;;
    --apply|"" ) if [ "$mode" = "--apply" ]; then target="$cur"
                 elif [ "$cur" = "dark" ]; then target="light"
                 else target="dark"; fi ;;
    *) echo "usage: theme-toggle.sh [dark|light|--apply]" >&2; exit 2 ;;
esac

tdir="$THEMES/$target"
for f in colors.env foot.ini waybar.css sway-colors.conf swaync-theme.css \
         fuzzel.ini swaylock.conf quickshell.json qt6ct-colors.conf; do
    if [ ! -f "$tdir/$f" ]; then
        echo "theme '$target' is incomplete: missing $f — aborting, nothing changed" >&2
        exit 1
    fi
done

# shellcheck disable=SC1091
. "$tdir/colors.env"

# --- 1. the atomic commit point: swap the active symlink -------------------
tmp="$ACTIVE.tmp.$$"
ln -sfn "$tdir" "$tmp" && mv -T "$tmp" "$ACTIVE" || {
    rm -f "$tmp"; echo "failed to swap active theme symlink" >&2; exit 1
}

# --- 2. wallpaper ----------------------------------------------------------
wall=""
for ext in jpg jpeg png; do
    if [ -f "$RICE/wallpapers/$WALLPAPER.$ext" ]; then
        wall="$RICE/wallpapers/$WALLPAPER.$ext"; break
    fi
done
if [ -n "$wall" ]; then
    ln -sfn "$wall" "$RICE/wallpapers/current"
    ln -sfn "$wall" "$RICE/wallpapers/current-lock"
    if command -v swww >/dev/null 2>&1 && swww query >/dev/null 2>&1; then
        step wallpaper swww img "$wall" --resize crop \
            --transition-type grow --transition-pos center \
            --transition-duration 1.2 --transition-fps 60
    else
        # swaybg fallback path: the daemon reads wallpapers/current on start
        step wallpaper systemctl --user restart wallpaper-daemon.service
    fi
else
    fail_list+=("wallpaper(missing file: $WALLPAPER.{jpg,png})")
fi

# --- 3. sway colors (no full reload: apply live, config include persists) --
step sway-colors swaymsg "client.focused #$ACCENT #$BG_HL #$FG #$PINK #$ACCENT; \
client.focused_inactive #$BORDER #$BG_ALT #$FG_DIM #$BORDER #$BORDER; \
client.unfocused #$BORDER #$BG_ALT #$MUTED #$BORDER #$BORDER; \
client.urgent #$RED #$RED #$BG #$RED #$RED; \
output * bg #$BG solid_color"

# --- 4. waybar: SIGUSR2 = reload config + css ------------------------------
step waybar pkill -USR2 -x waybar

# --- 5. live-recolor open foot terminals via OSC sequences -----------------
# New terminals pick colors up from the config include; running ones get the
# palette pushed onto their pty (same technique pywal uses). Best-effort.
build_seq() {
    local s=""
    local i hexvar
    for i in $(seq 0 15); do
        hexvar="ANSI$i"
        s+="\033]4;$i;#${!hexvar}\007"
    done
    s+="\033]10;#$FG\007\033]11;#$BG\007\033]12;#$FG\007"
    printf '%b' "$s"
}
seq_data="$(build_seq)"
for pts in /dev/pts/[0-9]*; do
    [ -w "$pts" ] && printf '%s' "$seq_data" > "$pts" 2>/dev/null || true
done

# --- 6. GTK (live: gsettings; libadwaita follows color-scheme portal) ------
step gtk-theme  gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
step gtk-scheme gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME"
step gtk-icons  gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"

# --- 7. Qt: qt6ct color_scheme_path points through the active symlink ------
# (new Qt apps pick it up automatically; only the icon theme name needs a poke)
if [ -f "$HOME/.config/qt6ct/qt6ct.conf" ]; then
    step qt6ct sed -i "s/^icon_theme=.*/icon_theme=$ICON_THEME/" "$HOME/.config/qt6ct/qt6ct.conf"
fi

# --- 8. swaync + quickshell ------------------------------------------------
step swaync sh -c 'swaync-client --reload-css && swaync-client --reload-config'
# quickshell watches quickshell.json but the watch follows the old symlink
# target, so poke it explicitly; harmless if quickshell isn't running.
if command -v qs >/dev/null 2>&1; then
    step quickshell qs -c rice ipc call theme reload
fi

# --- report ----------------------------------------------------------------
if [ ${#fail_list[@]} -eq 0 ]; then
    notify-send -a "theme" "Theme: $NAME" "Switched to $target mode" 2>/dev/null || true
    echo "switched to $target ($NAME)"
else
    notify-send -u critical -a "theme" "Theme: $NAME (partial!)" \
        "Failed steps: ${fail_list[*]}" 2>/dev/null || true
    echo "switched to $target, but these steps failed: ${fail_list[*]}" >&2
    exit 1
fi
