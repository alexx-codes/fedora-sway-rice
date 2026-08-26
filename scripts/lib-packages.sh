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

# pkg_missing [tier...] — installed-check every package, echo the absent ones.
pkg_missing() {
    local p
    for p in $(pkg_list "$@"); do
        rpm -q "$p" >/dev/null 2>&1 || echo "$p"
    done
}
