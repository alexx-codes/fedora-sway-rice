#!/usr/bin/env bash
# fingerprint-setup.sh — guided fingerprint setup for the X1 Carbon's
# Synaptics reader on Fedora. Interactive and idempotent; run it directly:
#
#     ~/.config/rice/scripts/fingerprint-setup.sh
#
# What it deliberately does NOT do:
#   * It never edits files under /etc/pam.d/ — Fedora manages PAM through
#     authselect, and hand edits are silently overwritten on the next
#     profile update. All PAM changes go through
#     `authselect enable-feature with-fingerprint`.
#   * It never disables password auth. Fingerprint is a convenience factor
#     on top of the password, not a replacement — the final step makes you
#     prove the password fallback still works before trusting any of it.
#
# Facts to keep straight (not lectures, just scope):
#   * LUKS at boot still needs the passphrase — the reader isn't available
#     that early. This script changes nothing about disk encryption.
#   * swaylock authenticates through PAM, and fingerprint-on-swaylock is
#     commonly broken in practice (the PAM conversation can block on
#     password input so the reader is never polled). Step 5 tests it for
#     real instead of assuming.
set -u

c_grn=$'\033[0;32m'; c_ylw=$'\033[1;33m'; c_red=$'\033[0;31m'; c_off=$'\033[0m'
ok()   { echo "${c_grn}[ok]${c_off} $*"; }
warn() { echo "${c_ylw}[!!]${c_off} $*"; }
err()  { echo "${c_red}[xx]${c_off} $*"; }
step() { echo; echo "══ $* ══"; }

step "1/5 Reader hardware"
echo "USB devices that look like fingerprint readers:"
if command -v lsusb >/dev/null 2>&1; then
    lsusb | grep -iE 'fingerprint|synaptics|goodix|elan|validity' || \
        warn "none matched by name — full lsusb output may still contain it (Synaptics readers often show as 06cb:xxxx)"
else
    warn "lsusb not found (dnf install usbutils)"
fi
echo
echo "Supported-device check: libfprint must know this reader. If fprintd-list"
echo "below reports 'No devices available', look up the 06cb:xxxx ID on"
echo "https://fprint.freedesktop.org/supported-devices.html — some Synaptics"
echo "IDs are unsupported and no amount of configuration fixes that."

step "2/5 fprintd installed and reachable"
if ! command -v fprintd-list >/dev/null 2>&1; then
    echo "Installing fprintd + PAM module..."
    sudo dnf install -y fprintd fprintd-pam || { err "install failed"; exit 1; }
fi
if fprintd-list "$USER" 2>&1 | grep -q 'No devices available'; then
    err "fprintd sees no reader. Check the lsusb ID against libfprint's list"
    err "before going further — this is the report-don't-assume step."
    exit 1
fi
ok "fprintd reaches a reader"
fprintd-list "$USER" || true

step "3/5 Enroll a finger"
if fprintd-list "$USER" 2>/dev/null | grep -qi 'right-index-finger\|left-index-finger\|fingerprint'; then
    ok "an enrollment already exists (fprintd-enroll to add more fingers)"
else
    echo "Enrolling your right index finger — touch the reader repeatedly..."
    fprintd-enroll || { err "enrollment failed"; exit 1; }
fi

step "4/5 PAM via authselect (never by hand)"
current=$(sudo authselect current 2>/dev/null | head -1 || true)
echo "authselect profile: ${current:-<none>}"
if [ -z "$current" ]; then
    err "authselect is not managing this system's PAM — stopping rather than"
    err "guessing. (On a stock Fedora this should not happen.)"
    exit 1
fi
if sudo authselect current | grep -q 'with-fingerprint'; then
    ok "with-fingerprint already enabled"
else
    sudo authselect enable-feature with-fingerprint || { err "authselect failed"; exit 1; }
    sudo authselect apply-changes 2>/dev/null || true
    ok "with-fingerprint enabled via authselect"
fi
sudo authselect current | sed 's/^/    /'

step "5/5 Test each path FOR REAL — and prove the password fallback"
cat <<'EOF'
Run these yourself, in this order. Do not skip the last one.

  a) sudo:      open a new terminal, run `sudo -k; sudo true`
                — expect a fingerprint prompt; touch the reader.
  b) polkit:    open virt-manager and connect to qemu:///system
                — the GUI privilege prompt should offer the reader.
  c) swaylock:  press $mod+Shift+x, then touch the reader WITHOUT typing.
                If nothing happens until you press a key, fingerprint-on-
                swaylock is broken on this stack — that is a known PAM
                conversation issue, not something to configure around.
                Report it and unlock with the password; do not assume.
  d) FALLBACK:  lock again and unlock with the PASSWORD ONLY, reader
                untouched. Also run `sudo -k; sudo true` and let the
                fingerprint prompt TIME OUT (or press Enter) — it must
                fall through to a password prompt. If either fallback
                fails, run `sudo authselect disable-feature
                with-fingerprint` immediately. You must never be lockable
                out by a dirty sensor or a wet finger.
EOF
