#!/usr/bin/env python3
"""Generate per-application theme files from themes/<mode>/colors.env.

colors.env is the single palette definition per mode. This script derives the
app-specific color files (foot, waybar, sway, swaync, fuzzel, swaylock,
quickshell, qt6ct) so no app config ever hand-codes a color twice.

It also enforces the legibility rule: WCAG contrast of text-bearing colors
against the background is checked, and the script FAILS if terminal
foreground/background contrast drops below 7:1 or any ANSI text color below
3:1. A pretty color that hurts contrast should be flagged, not shipped.

Run after editing a colors.env:  ./scripts/theme-gen.py
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
THEMES = REPO / "themes"

# __HOME__ is substituted with the real $HOME by install.sh at deploy time,
# so nothing in the repo hardcodes a username.
LOCK_IMAGE = "__HOME__/.config/rice/wallpapers/current-lock"


def parse_env(path: Path) -> dict:
    vals = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        vals[k.strip()] = v.strip().strip('"')
    return vals


def srgb_lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hexcol: str) -> float:
    r, g, b = (int(hexcol[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * srgb_lin(r) + 0.7152 * srgb_lin(g) + 0.0722 * srgb_lin(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check_contrast(mode: str, t: dict):
    problems = []
    fg_bg = contrast(t["FG"], t["BG"])
    if fg_bg < 7.0:
        problems.append(f"FG on BG is {fg_bg:.1f}:1 (need >= 7:1 for terminal text)")
    for name in ["FG_DIM", "ACCENT", "ACCENT2", "PINK", "RED", "GREEN", "YELLOW", "CYAN", "TEAL", "ORANGE"]:
        c = contrast(t[name], t["BG"])
        if c < 3.0:
            problems.append(f"{name} on BG is {c:.1f}:1 (need >= 3:1)")
    for i in range(1, 16):
        if i == 8:  # bright black is allowed to be dim: it's the 'comment' color
            continue
        c = contrast(t[f"ANSI{i}"], t["BG"])
        if c < 3.0:
            problems.append(f"ANSI{i} on BG is {c:.1f}:1 (need >= 3:1)")
    if problems:
        sys.exit(f"[{mode}] contrast check FAILED:\n  " + "\n  ".join(problems))
    print(f"[{mode}] contrast ok: FG/BG {fg_bg:.1f}:1, all ANSI/accent colors >= 3:1")


def gen_foot(t):
    lines = ["# GENERATED from colors.env by scripts/theme-gen.py", "[colors]"]
    lines.append(f"foreground={t['FG']}")
    lines.append(f"background={t['BG']}")
    lines.append(f"selection-foreground={t['FG'] if t['MODE']=='light' else t['FG']}")
    lines.append(f"selection-background={t['BG_SEL']}")
    lines.append(f"urls={t['CYAN']}")
    for i in range(8):
        lines.append(f"regular{i}={t[f'ANSI{i}']}")
    for i in range(8):
        lines.append(f"bright{i}={t[f'ANSI{i+8}']}")
    return "\n".join(lines) + "\n"


CSS_TOKENS = [
    ("bg", "BG"), ("bg-alt", "BG_ALT"), ("bg-hl", "BG_HL"), ("bg-sel", "BG_SEL"),
    ("fg", "FG"), ("fg-dim", "FG_DIM"), ("muted", "MUTED"), ("border", "BORDER"),
    ("accent", "ACCENT"), ("accent2", "ACCENT2"), ("pink", "PINK"), ("red", "RED"),
    ("orange", "ORANGE"), ("yellow", "YELLOW"), ("green", "GREEN"),
    ("teal", "TEAL"), ("cyan", "CYAN"),
]


def gen_css(t):
    lines = ["/* GENERATED from colors.env by scripts/theme-gen.py */"]
    for css, key in CSS_TOKENS:
        lines.append(f"@define-color {css} #{t[key]};")
    return "\n".join(lines) + "\n"


def gen_sway(t):
    l = [
        "# GENERATED from colors.env by scripts/theme-gen.py",
        "# border | background | text | indicator | child_border",
        f"client.focused          #{t['ACCENT']} #{t['BG_HL']} #{t['FG']} #{t['PINK']} #{t['ACCENT']}",
        f"client.focused_inactive #{t['BORDER']} #{t['BG_ALT']} #{t['FG_DIM']} #{t['BORDER']} #{t['BORDER']}",
        f"client.unfocused        #{t['BORDER']} #{t['BG_ALT']} #{t['MUTED']} #{t['BORDER']} #{t['BORDER']}",
        f"client.urgent           #{t['RED']} #{t['RED']} #{t['BG']} #{t['RED']} #{t['RED']}",
        f"output * bg #{t['BG']} solid_color",
    ]
    return "\n".join(l) + "\n"


FUZZEL_BASE = """\
# GENERATED from colors.env by scripts/theme-gen.py — full config per theme
# (fuzzel's `include` needs >=1.10, so we generate the whole file instead;
# ~/.config/fuzzel/fuzzel.ini is a symlink through ~/.config/rice/active/).
[main]
font=JetBrainsMono Nerd Font:size=12
prompt=" ❯ "
icon-theme=Papirus
terminal=foot -e
width=42
lines=12
horizontal-pad=18
vertical-pad=12
inner-pad=6
line-height=24

[border]
width=2
radius=12
"""


def gen_fuzzel(t):
    # ONLY the color keys fuzzel has supported since 1.9 are emitted here.
    # An unrecognized key in [colors] is FATAL — fuzzel aborts at config
    # parse and never launches, which would take out the launcher, the
    # clipboard picker, and the power-menu/cheatsheet fallbacks at once.
    # prompt/input/placeholder/counter are newer additions and are
    # deliberately omitted; they inherit `text`, which is already themed.
    a = "ff"  # opaque
    l = [
        FUZZEL_BASE,
        "[colors]",
        f"background={t['BG']}f2",
        f"text={t['FG']}{a}",
        f"match={t['PINK']}{a}",
        f"selection={t['BG_SEL']}{a}",
        f"selection-text={t['FG']}{a}",
        f"selection-match={t['PINK']}{a}",
        f"border={t['ACCENT']}{a}",
    ]
    return "\n".join(l) + "\n"


def gen_swaylock(t):
    a = "ff"
    inside = t["BG"] + "cc"
    l = [
        "# GENERATED from colors.env by scripts/theme-gen.py",
        f"image={LOCK_IMAGE}",
        "scaling=fill",
        "indicator-radius=110",
        "indicator-thickness=10",
        "font=JetBrainsMono Nerd Font",
        f"color={t['BG']}{a}",
        f"inside-color={inside}",
        f"ring-color={t['ACCENT']}{a}",
        f"line-color={t['BG']}00",
        f"separator-color={t['BG']}00",
        f"text-color={t['FG']}{a}",
        f"key-hl-color={t['PINK']}{a}",
        f"bs-hl-color={t['RED']}{a}",
        f"inside-ver-color={inside}",
        f"ring-ver-color={t['ACCENT2']}{a}",
        f"text-ver-color={t['FG']}{a}",
        f"inside-wrong-color={inside}",
        f"ring-wrong-color={t['RED']}{a}",
        f"text-wrong-color={t['RED']}{a}",
        f"inside-clear-color={inside}",
        f"ring-clear-color={t['GREEN']}{a}",
        f"text-clear-color={t['FG']}{a}",
        "ignore-empty-password",
        "show-failed-attempts",
    ]
    return "\n".join(l) + "\n"


def gen_quickshell(t):
    data = {
        "mode": t["MODE"],
        "name": t["NAME"],
        "colors": {css: f"#{t[key]}" for css, key in CSS_TOKENS},
    }
    return json.dumps(data, indent=2) + "\n"


def qt_c(hexcol):
    return f"#ff{hexcol}"


def gen_qt6ct(t):
    # Qt palette role order used by qt6ct color scheme files (21 entries):
    # WindowText Button Light Midlight Dark Mid Text BrightText ButtonText
    # Base Window Shadow Highlight HighlightedText Link LinkVisited
    # AlternateBase Unused ToolTipBase ToolTipText PlaceholderText
    active = [
        t["FG"], t["BG_HL"], t["BG_SEL"], t["BG_HL"], t["BG_ALT"], t["BORDER"],
        t["FG"], t["PINK"], t["FG"],
        t["BG_ALT"] if t["MODE"] == "dark" else "ffffff",
        t["BG"], t["BG_ALT"],
        t["ACCENT"], t["BG"] if t["MODE"] == "light" else t["BG_ALT"],
        t["CYAN"], t["ACCENT2"],
        t["BG_HL"], t["BG"], t["BG_HL"], t["FG"], t["MUTED"],
    ]
    disabled = list(active)
    disabled[0] = t["MUTED"]; disabled[6] = t["MUTED"]; disabled[8] = t["MUTED"]
    line = lambda cols: ", ".join(qt_c(c) for c in cols)
    return (
        "; GENERATED from colors.env by scripts/theme-gen.py\n"
        "[ColorScheme]\n"
        f"active_colors={line(active)}\n"
        f"disabled_colors={line(disabled)}\n"
        f"inactive_colors={line(active)}\n"
    )


def main():
    for mode_dir in sorted(THEMES.iterdir()):
        env = mode_dir / "colors.env"
        if not env.is_file():
            continue
        t = parse_env(env)
        check_contrast(mode_dir.name, t)
        (mode_dir / "foot.ini").write_text(gen_foot(t))
        (mode_dir / "waybar.css").write_text(gen_css(t))
        (mode_dir / "swaync-theme.css").write_text(gen_css(t))
        (mode_dir / "sway-colors.conf").write_text(gen_sway(t))
        (mode_dir / "fuzzel.ini").write_text(gen_fuzzel(t))
        (mode_dir / "swaylock.conf").write_text(gen_swaylock(t))
        (mode_dir / "quickshell.json").write_text(gen_quickshell(t))
        (mode_dir / "qt6ct-colors.conf").write_text(gen_qt6ct(t))
        print(f"[{mode_dir.name}] generated 8 theme files")


if __name__ == "__main__":
    main()
