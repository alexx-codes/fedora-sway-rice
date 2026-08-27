#!/usr/bin/env bash
# lib-packages.sh — read packages.tsv. Sourced by BOTH install.sh and
# verify.sh so the two can never disagree about what the rice needs.
#
# Locate the manifest whether we're running from the repo or from a deploy:
#   repo:   <repo>/packages.tsv
#   deploy: ~/.config/rice/packages.tsv
pkg_manifest() {
    local here
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    for c in "$here/../packages.tsv" "$here/packages.tsv" \
             "$HOME/.config/rice/packages.tsv"; do
        [ -f "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

# pkg_list [tier...] — package names, optionally filtered by tier.
pkg_list() {
    local m; m=$(pkg_manifest) || return 1
    local tiers="${*:-}"
    awk -F'\t' -v tiers="$tiers" '
        /^[[:space:]]*(#|$)/ { next }
        NF >= 4 {
            if (tiers == "") { print $1; next }
            n = split(tiers, want, " ")
            for (i = 1; i <= n; i++) if ($2 == want[i]) { print $1; break }
        }' "$m"
}

# pkg_field <package> <2|3|4> — tier, provides, or why for one package.
pkg_field() {
    local m; m=$(pkg_manifest) || return 1
    awk -F'\t' -v p="$1" -v f="$2" '
        /^[[:space:]]*(#|$)/ { next }
        NF >= 4 && $1 == p { print $f; exit }' "$m"
}

# pkg_for_binary <binary> — which package provides this binary, if any.
pkg_for_binary() {
    local m; m=$(pkg_manifest) || return 1
    awk -F'\t' -v b="$1" '
        /^[[:space:]]*(#|$)/ { next }
        NF >= 4 && $3 == b { print $1; exit }' "$m"
}

# pkg_present <package> — is this actually usable?
#
# Checks the BINARY first when the manifest names one, because that is what
# actually matters: starship installed via cargo is present even though `rpm
# -q starship` fails, and reporting it missing is a false alarm that trains
# you to ignore the report. Falls back to rpm for packages that ship no
# binary we call (fonts, themes, libraries).
#
# The package field may list alternatives separated by "|" — Fedora renames
# things between releases (fontawesome-fonts became fontawesome4-fonts), and
# hardcoding one name means a spurious failure on the release that renamed it.
pkg_present() {
    local entry="$1" bin name
    bin=$(pkg_field "$entry" 3)
    if [ -n "$bin" ] && [ "$bin" != "-" ]; then
        PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH" \
            command -v "$bin" >/dev/null 2>&1 && return 0
    fi
    local IFS='|'
    for name in $entry; do
        rpm -q "$name" >/dev/null 2>&1 && return 0
    done
    return 1
}

# pkg_installable <package> — does any of its names exist in the enabled repos?
# Used to tell "your Fedora release doesn't ship this" apart from "install it".
pkg_installable() {
    local entry="$1" name
    command -v dnf >/dev/null 2>&1 || return 0
    local IFS='|'
    for name in $entry; do
        dnf -q list --available "$name" >/dev/null 2>&1 && return 0
        dnf -q list --installed "$name" >/dev/null 2>&1 && return 0
    done
    return 1
}

# pkg_missing [tier...] — echo entries that are genuinely not usable.
pkg_missing() {
    local p
    for p in $(pkg_list "$@"); do
        pkg_present "$p" || echo "$p"
    done
}
