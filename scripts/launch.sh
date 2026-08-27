#!/usr/bin/env bash
# launch.sh <binary> [args...] — run a program from a keybind, and SAY SO when
# it isn't installed.
#
# Why this exists: sway's `bindsym exec` throws away stdout and stderr, so
# `bindsym $mod+a exec rofi -show drun` with rofi missing is indistinguishable
# from a key that was never bound — nothing happens, no message, nowhere to
# look. That is exactly how the volume keys failed originally, and the fix
# then only covered the wrapper scripts; the raw execs kept failing silently.
# Every raw exec now goes through here instead.
#
# It also resolves binaries that live in ~/.local/bin (rice-settings) and
# ~/.cargo/bin (matugen, swww), which are not on sway's PATH unless the
# session was started via the "Sway (rice)" entry.
set -u
. "$(dirname "$0")/lib-notify.sh"

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

[ $# -ge 1 ] || { echo "usage: launch.sh <binary> [args...]" >&2; exit 2; }

bin="$1"; shift

# require_cmd maps the binary to its package via packages.tsv when it can, so
# the notification names something you can actually install.
if ! command -v "$bin" >/dev/null 2>&1; then
    pkg="$bin"
    lib="$(dirname "$0")/lib-packages.sh"
    if [ -f "$lib" ]; then
        # shellcheck source=lib-packages.sh
        . "$lib"
        found=$(pkg_for_binary "$bin" 2>/dev/null) || found=""
        [ -n "$found" ] && pkg="$found"
    fi
    notify_fail "$bin is not installed" \
        "Bound to a key but missing. Install with: sudo dnf install $pkg   (or run ./verify.sh --fix)"
    exit 127
fi

exec "$bin" "$@"
