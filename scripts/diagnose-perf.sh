#!/usr/bin/env bash
# diagnose-perf.sh — why does this feel sluggish?
#
# Run inside the sway session:  ./verify.sh --perf   (or run this directly)
#
# "Not smooth" has a dozen plausible causes on an X1 Carbon Gen 11 and
# guessing between them wastes time. This measures each one and says what it
# found, in rough order of how often it is the actual culprit. It CHANGES
# NOTHING — including the kernel parameters it reports on.
set -u

c_grn=$'\033[0;32m'; c_ylw=$'\033[1;33m'; c_red=$'\033[0;31m'; c_off=$'\033[0m'
pass() { echo "${c_grn}[ ok ]${c_off} $*"; }
warn() { echo "${c_ylw}[hmm ]${c_off} $*"; }
bad()  { echo "${c_red}[BAD ]${c_off} $*"; }
sect() { echo; echo "── $* ──"; }

FINDINGS=0
note() { bad "$*"; FINDINGS=$((FINDINGS + 1)); }

sect "1. Hardware video decode (the most common cause)"
# Without VA-API, every video in a browser decodes on the CPU: fans, heat,
# dropped frames, and a machine that feels slow whenever anything plays.
if command -v vainfo >/dev/null 2>&1; then
    va=$(vainfo 2>&1 || true)
    drv=$(printf '%s' "$va" | grep -i 'Driver version' | head -1 | sed 's/.*: *//')
    if [ -z "$drv" ]; then
        note "VA-API is NOT working — video decodes on the CPU"
        echo "       install: sudo dnf install libva-intel-media-driver"
    elif printf '%s' "$drv" | grep -qi 'iHD'; then
        pass "VA-API via iHD: $drv"
        printf '%s' "$va" | grep -qi 'VAProfileH264' && pass "  H.264 decode available"
        printf '%s' "$va" | grep -qi 'VAProfileHEVC' && pass "  HEVC decode available"
    else
        warn "VA-API driver is '$drv' — expected iHD on Iris Xe"
    fi
else
    note "vainfo not installed — cannot confirm hardware video decode"
    echo "       install: sudo dnf install libva-utils libva-intel-media-driver"
fi

sect "2. Output scale and refresh"
if command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
   && swaymsg -t get_outputs >/dev/null 2>&1; then
    swaymsg -t get_outputs -r | jq -r '.[] |
        "       \(.name): \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000|floor)Hz scale=\(.scale) vrr=\(.adaptive_sync_status // "?")"'
    sc=$(swaymsg -t get_outputs -r | jq -r '[.[]|select(.name|test("^eDP"))|.scale][0] // 1')
    case "$sc" in
        1|1.000000) pass "integer scale — no fractional-scaling cost" ;;
        2|2.000000) pass "integer scale 2 — XWayland stays crisp" ;;
        *) warn "fractional scale $sc: XWayland clients are rendered at a"
           warn "  higher resolution and downscaled, which costs GPU time and"
           warn "  softens them. Integer 2 avoids both." ;;
    esac
else
    warn "not in a sway session — skipping output checks"
fi

sect "3. XWayland clients (slower at HiDPI)"
if command -v swaymsg >/dev/null 2>&1 && swaymsg -t get_tree >/dev/null 2>&1; then
    xw=$(swaymsg -t get_tree -r | jq -r '[.. | objects
         | select(.app_id == null and .window_properties != null)
         | .window_properties.class] | unique | join(", ")' 2>/dev/null)
    if [ -n "$xw" ] && [ "$xw" != "" ] && [ "$xw" != "null" ]; then
        warn "running under XWayland: $xw"
        warn "  these render through a translation layer; native Wayland is smoother"
    else
        pass "no XWayland clients — everything is native Wayland"
    fi
fi

sect "4. Failed or restarting user services"
if command -v systemctl >/dev/null 2>&1; then
    failed=$(systemctl --user --failed --no-legend 2>/dev/null | awk '{print $1}')
    if [ -n "$failed" ]; then
        note "failed user units: $(echo "$failed" | tr '\n' ' ')"
        echo "       a unit that keeps dying and restarting burns CPU invisibly"
        echo "       look: journalctl --user -u <unit> -e"
    else
        pass "no failed user units"
    fi
fi

sect "5. What is actually using the CPU"
if command -v ps >/dev/null 2>&1; then
    echo "       top 5 by CPU:"
    ps -eo pcpu,pmem,comm --sort=-pcpu 2>/dev/null | head -6 | tail -5 \
        | awk '{printf "         %5s%%  %5s%%  %s\n", $1, $2, $3}'
    for proc in waybar quickshell swww-daemon swaybg; do
        cpu=$(ps -C "$proc" -o pcpu= 2>/dev/null | awk '{s+=$1} END {print s+0}')
        [ -z "$cpu" ] && continue
        if awk "BEGIN{exit !($cpu > 5)}"; then
            note "$proc is using ${cpu}% CPU — that is far too much when idle"
        elif awk "BEGIN{exit !($cpu > 0)}"; then
            pass "$proc: ${cpu}% CPU"
        fi
    done
fi

sect "6. Power profile and thermals"
if command -v powerprofilesctl >/dev/null 2>&1; then
    prof=$(powerprofilesctl get 2>/dev/null || echo '?')
    case "$prof" in
        power-saver) warn "profile is 'power-saver' — the GPU is downclocked hard."
                     warn "  This alone can make the desktop feel sluggish."
                     warn "  Try: powerprofilesctl set balanced" ;;
        *) pass "power profile: $prof" ;;
    esac
else
    warn "power-profiles-daemon not installed"
fi
if systemctl is-active thermald >/dev/null 2>&1; then
    pass "thermald active"
else
    warn "thermald not running — sustained VM load may throttle harder than needed"
fi
for z in /sys/class/thermal/thermal_zone*; do
    [ -f "$z/temp" ] || continue
    t=$(cat "$z/temp" 2>/dev/null) || continue
    ty=$(cat "$z/type" 2>/dev/null || echo '?')
    c=$((t / 1000))
    [ "$c" -ge 85 ] 2>/dev/null && note "$ty at ${c}°C — thermal throttling likely"
done

sect "7. Memory pressure"
if [ -r /proc/meminfo ]; then
    swap_total=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
    swap_free=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
    if [ "${swap_total:-0}" -gt 0 ]; then
        used=$(( (swap_total - swap_free) / 1024 ))
        if [ "$used" -gt 512 ]; then
            note "${used}MB of swap in use — with 32GB RAM that should not happen"
            echo "       something is leaking, or a VM is over-provisioned"
        else
            pass "swap barely touched (${used}MB)"
        fi
    fi
fi
if [ -r /proc/pressure/cpu ]; then
    echo "       PSI (share of time stalled, 10s avg):"
    for r in cpu memory io; do
        [ -r "/proc/pressure/$r" ] || continue
        v=$(awk '/^some/{print $2}' "/proc/pressure/$r" | head -1)
        echo "         $r ${v:-?}"
    done
    echo "       sustained avg10 above ~20 on cpu or io means real contention"
fi

sect "8. Intel panel self-refresh (report only)"
# PSR saves power by letting the panel hold a static image, and on some
# ThinkPad panels it produces visible stutter or flicker. Reported, never
# changed: this is a kernel parameter and yours to decide on.
psr=$(find /sys/kernel/debug/dri -name 'i915_edp_psr_status' 2>/dev/null | head -1)
if [ -n "$psr" ] && [ -r "$psr" ]; then
    if grep -qi 'enabled' "$psr" 2>/dev/null; then
        warn "Intel PSR is enabled. It is a known stutter source on some panels."
        warn "  To test, boot once with i915.enable_psr=0 on the kernel cmdline."
        warn "  Not changed here — that is a system-level decision."
    else
        pass "Intel PSR is off"
    fi
else
    echo "       (PSR status needs root to read; skipped)"
fi

echo
if [ "$FINDINGS" -eq 0 ]; then
    pass "nothing obviously wrong found"
    echo "       If it still feels rough, the next things to try are a"
    echo "       different power profile and testing with PSR disabled."
else
    bad "$FINDINGS likely contributor(s) found — the [BAD] lines above"
fi
