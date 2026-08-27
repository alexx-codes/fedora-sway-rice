#!/usr/bin/env bash
# sway-session.sh — launch sway with the session environment already set.
#
# Why this exists (audit finding F4): ~/.config/environment.d/ is read by
# `systemd --user`, so it reaches systemd USER SERVICES (waybar, swaync,
# quickshell) — but an app launched from a sway keybind inherits SWAY's
# environment, which, depending on whether sway is started by a display
# manager or from a TTY, may never have seen that file at all.
#
# The practical symptom is silent: Qt apps ignore qt6ct and don't follow the
# theme toggle. Setting the variables here, before exec'ing sway, makes it
# deterministic — everything sway launches inherits them.
#
# environment.d is deliberately kept as well: it still covers systemd user
# services, which do NOT inherit from sway.
set -u

# Qt applications go through qt6ct, which reads the active theme's color
# scheme — this is the variable whose absence breaks the Qt half of the
# theme toggle.
export QT_QPA_PLATFORMTHEME=qt6ct
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1

# Electron apps (VS Code) run native Wayland instead of XWayland; this is
# what keeps text crisp at HiDPI and the clipboard sane.
export ELECTRON_OZONE_PLATFORM_HINT=auto

# Firefox/LibreWolf native Wayland
export MOZ_ENABLE_WAYLAND=1

# Java apps need this hint under tiling WMs or they render as grey boxes
export _JAVA_AWT_WM_NONREPARENTING=1

# Identify the session so portals pick the right backend (xdg-desktop-portal
# uses XDG_CURRENT_DESKTOP to choose wlr over gtk for screencast).
export XDG_CURRENT_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=sway

# Cargo-installed tools (swww) and user scripts
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

exec sway "$@"
