#!/usr/bin/env python3
"""Generate every app's colors from theme/colors.env.

One palette. No modes, no toggle, no active-symlink indirection — those were
removed as complexity that earned nothing. What survives is the part that
does real work: a single place to change a color, and a WCAG contrast gate
that REFUSES to generate anything unreadable.

That gate is not ceremony. It rejected five colors during the original build,
and a deliberately grim palette (near-black surfaces, desaturated accents) is
exactly the case where contrast quietly slips.

    ./scripts/theme-gen.py        # regenerate after editing colors.env
    ./scripts/theme-gen.py --from-wallpaper <palette.env> [--out <dir>]

--from-wallpaper overlays matugen's wallpaper-derived SURFACE, TEXT and ACCENT
roles onto colors.env and regenerates everything from the merged result. The
semantic colors (RED/ORANGE/GREEN/...) and the ANSI block are NOT overlaid:
they carry meaning and drive syntax highlighting, and re-hueing them per
wallpaper makes a critical-battery badge decorative and every language look
wrong.

The contrast gate still runs on the merged palette — matugen output is exactly
where contrast slips. The one difference is that it NUDGES a failing color
toward the background's opposite until it clears, instead of aborting. A
static palette that fails is an editing mistake worth stopping for; a
wallpaper that fails must never leave you with an unreadable bar.

--out writes elsewhere than theme/. Deployed, theme/ resolves to
~/.config/rice/theme and writing there is exactly right; run from a git
checkout it would commit wallpaper colors over the authored palette, so the
preview harness points --out at a scratch dir instead.
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
THEME = REPO / "theme"
SRC = THEME / "colors.env"

# __HOME__ is substituted with the real $HOME by install.sh at deploy time,
# so nothing in the repo hardcodes a username.
LOCK_IMAGE = "__HOME__/.config/rice/wallpapers/current-lock"

# Text must clear this against the background.
FG_FLOOR = 7.0      # terminal body text
ACCENT_FLOOR = 3.0  # anything else carrying text
# The window border carries no text, so it needs less — but a wallpaper-derived
# BORDER still has to stay visibly distinct from BG. At ~1.4:1 the unfocused
# border vanished; the authored BORDER (= ANSI8) sits at ~2.4:1.
BORDER_FLOOR = 2.2


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
    r, g, b = (int(hexcol[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * srgb_lin(r) + 0.7152 * srgb_lin(g) + 0.0722 * srgb_lin(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# Keys the wallpaper may drive. Everything else stays as authored.
WALLPAPER_KEYS = ("BG", "BG_ALT", "BG_HL", "BG_SEL", "BORDER",
                  "FG", "FG_DIM", "MUTED", "ACCENT", "ACCENT2")


def blend(a: str, b: str, f: float) -> str:
    return "".join(f"{round(int(a[i:i+2], 16) * (1 - f) + int(b[i:i+2], 16) * f):02x}"
                   for i in (0, 2, 4))


def nudge(col: str, bg: str, floor: float) -> str:
    """Walk col toward the background's opposite until it clears floor."""
    if contrast(col, bg) >= floor:
        return col
    target = "ffffff" if luminance(bg) < 0.5 else "000000"
    for step in range(1, 41):
        c = blend(col, target, step / 40)
        if contrast(c, bg) >= floor:
            return c
    return target


def checked_pairs(t: dict):
    """(key, floor) for every color the gate covers. One definition, used by
    both the strict path and the nudging path so they can never disagree."""
    yield "FG", FG_FLOOR
    for name in ("FG_DIM", "ACCENT", "ACCENT2", "PINK", "RED", "GREEN",
                 "YELLOW", "CYAN", "TEAL", "ORANGE"):
        yield name, ACCENT_FLOOR
    # BORDER is wallpaper-driven (matugen's outline_variant) but never
    # contrast-checked otherwise, so a low-contrast wallpaper used to push the
    # unfocused border back to invisible.
    yield "BORDER", BORDER_FLOOR
    for i in range(1, 16):
        if i == 8:  # bright black is the comment color; allowed to be dim
            continue
        yield f"ANSI{i}", ACCENT_FLOOR


def relax_contrast(t: dict) -> None:
    """Nudge rather than abort. Used for wallpaper-derived palettes."""
    fixed = []
    for name, floor in checked_pairs(t):
        before = t[name]
        after = nudge(before, t["BG"], floor)
        if after != before:
            t[name] = after
            fixed.append(f"{name} {before} -> {after} "
                         f"({contrast(before, t['BG']):.1f} -> "
                         f"{contrast(after, t['BG']):.1f}:1)")
    if fixed:
        print(f"contrast: nudged {len(fixed)} color(s) to clear the floor:")
        for line in fixed:
            print(f"  {line}")
    else:
        print("contrast ok: nothing needed nudging")


def check_contrast(t: dict) -> None:
    # Iterates the same checked_pairs() the nudging path uses below, rather
    # than keeping a second hardcoded copy of the color list — the two paths
    # covering different colors was a real risk, not a hypothetical one.
    problems = []
    for name, floor in checked_pairs(t):
        c = contrast(t[name], t["BG"])
        if c < floor:
            label = "for body text" if name == "FG" else ""
            problems.append(f"{name} on BG is {c:.1f}:1 (need >= {floor}:1{' ' + label if label else ''})")
    if problems:
        sys.exit("contrast check FAILED — nothing generated:\n  " + "\n  ".join(problems))
    fg_bg = contrast(t["FG"], t["BG"])
    print(f"contrast ok: FG/BG {fg_bg:.1f}:1, every accent and ANSI color "
          f">= {ACCENT_FLOOR}:1")


def gen_kitty(t):
    # kitty.conf is "key value", not foot's ini sections, and every color needs
    # a leading "#" where foot took bare hex. regular0-7/bright0-7 collapse into
    # one color0-15 run. Same set of roles as before, nothing added.
    lines = ["# GENERATED from theme/colors.env by scripts/theme-gen.py",
             f"foreground #{t['FG']}", f"background #{t['BG']}",
             f"selection_foreground #{t['FG']}",
             f"selection_background #{t['BG_SEL']}",
             f"url_color #{t['CYAN']}"]
    for i in range(16):
        lines.append(f"color{i} #{t[f'ANSI{i}']}")
    return "\n".join(lines) + "\n"


CSS_TOKENS = [
    ("bg", "BG"), ("bg-alt", "BG_ALT"), ("bg-hl", "BG_HL"), ("bg-sel", "BG_SEL"),
    ("fg", "FG"), ("fg-dim", "FG_DIM"), ("muted", "MUTED"), ("border", "BORDER"),
    ("accent", "ACCENT"), ("accent2", "ACCENT2"), ("pink", "PINK"), ("red", "RED"),
    ("orange", "ORANGE"), ("yellow", "YELLOW"), ("green", "GREEN"),
    ("teal", "TEAL"), ("cyan", "CYAN"),
]


def gen_css(t):
    lines = ["/* GENERATED from theme/colors.env by scripts/theme-gen.py */"]
    for css, key in CSS_TOKENS:
        lines.append(f"@define-color {css} #{t[key]};")
    # The waybar islands float over the wallpaper, so their fill is a
    # translucent surface rather than a flat one. Derived here so both the
    # static and wallpaper palettes get it for free.
    r, g, b = (int(t["BG_ALT"][i:i + 2], 16) for i in (0, 2, 4))
    lines.append(f"@define-color pill rgba({r}, {g}, {b}, 0.82);")
    return "\n".join(lines) + "\n"


def gen_sway(t):
    # No `output * bg` here on purpose. `output * bg <c> solid_color` makes sway
    # spawn its own `swaybg -c <c>`, an opaque surface that hides the photo drawn
    # by wallpaper-daemon.service's swaybg — and every theme-from-wallpaper run
    # regenerates it with the new BG and `swaymsg reload`s it back on top. The
    # daemon (Restart=on-failure, plus its own `swaybg -c` last resort) is the
    # single owner of the background.
    return "\n".join([
        "# GENERATED from theme/colors.env by scripts/theme-gen.py",
        "# border | background | text | indicator | child_border",
        f"client.focused          #{t['ACCENT']} #{t['BG_HL']} #{t['FG']} #{t['ACCENT2']} #{t['ACCENT']}",
        f"client.focused_inactive #{t['BORDER']} #{t['BG_ALT']} #{t['FG_DIM']} #{t['BORDER']} #{t['BORDER']}",
        f"client.unfocused        #{t['BORDER']} #{t['BG_ALT']} #{t['MUTED']} #{t['BORDER']} #{t['BORDER']}",
        f"client.urgent           #{t['RED']} #{t['RED']} #{t['BG']} #{t['RED']} #{t['RED']}",
    ]) + "\n"


ROFI_BASE = """\
/* GENERATED from theme/colors.env by scripts/theme-gen.py — do not edit.
 * Self-contained: rofi resolves @import relative to its own config dir, so
 * config and theme live in one file that install.sh copies into place. */

configuration {
    modes:               "drun,run,window";
    font:                "JetBrainsMono Nerd Font 12";
    show-icons:          true;
    icon-theme:          "Papirus";
    terminal:            "kitty";
    drun-display-format: "{name}";
    display-drun:        "";
    display-run:         "";
    display-window:      "";
    kb-cancel:           "Escape";
}

"""


def gen_rofi(t):
    c = {k: f"#{t[v]}" for k, v in [
        ("bg", "BG"), ("bg_alt", "BG_ALT"), ("sel", "BG_SEL"), ("fg", "FG"),
        ("fg_dim", "FG_DIM"), ("muted", "MUTED"), ("accent", "ACCENT"),
        ("accent2", "ACCENT2"), ("pink", "PINK"), ("red", "RED"),
        ("border", "BORDER"),
    ]}
    return ROFI_BASE + f"""* {{
    bg:          {c['bg']};
    bg-alt:      {c['bg_alt']};
    selected:    {c['sel']};
    fg:          {c['fg']};
    fg-dim:      {c['fg_dim']};
    muted:       {c['muted']};
    accent:      {c['accent']};
    accent2:     {c['accent2']};
    pink:        {c['pink']};
    urgent-col:  {c['red']};
    border-col:  {c['border']};

    background-color: transparent;
    text-color:       @fg;
    margin:  0;
    padding: 0;
    spacing: 0;
}}

window {{
    transparency:     "real";
    location:         center;
    anchor:           center;
    width:            42em;
    border:           1px;
    border-radius:    6px;
    border-color:     @border-col;
    background-color: @bg;
    padding:          16px;
}}

mainbox {{ spacing: 12px; children: [ inputbar, listview ]; }}

inputbar {{
    spacing:          8px;
    padding:          9px 12px;
    border-radius:    4px;
    background-color: @bg-alt;
    children:         [ prompt, entry ];
}}

prompt {{ text-color: @accent2; vertical-align: 0.5; }}
entry  {{ placeholder: "search"; placeholder-color: @muted;
          text-color: @fg; vertical-align: 0.5; cursor: text; }}

listview {{
    lines: 12; columns: 1; scrollbar: false;
    fixed-height: false; spacing: 1px; cycle: true; dynamic: true;
}}

element {{ padding: 7px 10px; spacing: 10px; border-radius: 4px; cursor: pointer; }}
element normal.normal    {{ background-color: transparent; text-color: @fg; }}
element alternate.normal {{ background-color: transparent; text-color: @fg; }}
element selected.normal  {{ background-color: @selected;   text-color: @fg; }}
element normal.urgent    {{ background-color: transparent; text-color: @urgent-col; }}
element selected.urgent  {{ background-color: @urgent-col; text-color: @bg; }}
element normal.active    {{ background-color: transparent; text-color: @accent; }}
element selected.active  {{ background-color: @accent;     text-color: @bg; }}

element-icon {{ size: 1.1em; vertical-align: 0.5; }}
element-text {{ highlight: bold {c['pink']}; vertical-align: 0.5; text-color: inherit; }}

message  {{ padding: 9px; border-radius: 4px; background-color: @bg-alt; }}
textbox  {{ text-color: @fg-dim; }}
"""


def gen_swaylock(t):
    a = "ff"
    inside = t["BG"] + "cc"
    return "\n".join([
        "# GENERATED from theme/colors.env by scripts/theme-gen.py",
        f"image={LOCK_IMAGE}",
        "scaling=fill", "indicator-radius=100", "indicator-thickness=8",
        "font=JetBrainsMono Nerd Font",
        f"color={t['BG']}{a}",
        f"inside-color={inside}", f"ring-color={t['ACCENT']}{a}",
        f"line-color={t['BG']}00", f"separator-color={t['BG']}00",
        f"text-color={t['FG']}{a}", f"key-hl-color={t['ACCENT2']}{a}",
        f"bs-hl-color={t['RED']}{a}",
        f"inside-ver-color={inside}", f"ring-ver-color={t['ACCENT2']}{a}",
        f"text-ver-color={t['FG']}{a}",
        f"inside-wrong-color={inside}", f"ring-wrong-color={t['RED']}{a}",
        f"text-wrong-color={t['RED']}{a}",
        f"inside-clear-color={inside}", f"ring-clear-color={t['GREEN']}{a}",
        f"text-clear-color={t['FG']}{a}",
        "ignore-empty-password", "show-failed-attempts",
    ]) + "\n"


def gen_quickshell(t):
    return json.dumps({
        "name": t.get("NAME", "theme"),
        "colors": {css: f"#{t[key]}" for css, key in CSS_TOKENS},
    }, indent=2) + "\n"


def gen_qt6ct(t):
    def q(h):
        return f"#ff{h}"
    active = [
        t["FG"], t["BG_HL"], t["BG_SEL"], t["BG_HL"], t["BG_ALT"], t["BORDER"],
        t["FG"], t["ACCENT2"], t["FG"], t["BG_ALT"], t["BG"], t["BG_ALT"],
        t["ACCENT"], t["BG"], t["CYAN"], t["ACCENT2"],
        t["BG_HL"], t["BG"], t["BG_HL"], t["FG"], t["MUTED"],
    ]
    disabled = list(active)
    disabled[0] = disabled[6] = disabled[8] = t["MUTED"]
    line = lambda cols: ", ".join(q(c) for c in cols)  # noqa: E731
    return ("; GENERATED from theme/colors.env by scripts/theme-gen.py\n"
            "[ColorScheme]\n"
            f"active_colors={line(active)}\n"
            f"disabled_colors={line(disabled)}\n"
            f"inactive_colors={line(active)}\n")


def main():
    if not SRC.is_file():
        sys.exit(f"missing {SRC.relative_to(REPO)}")
    t = parse_env(SRC)

    args = sys.argv[1:]
    wallpaper_src = None
    out_dir = THEME
    if "--out" in args:
        i = args.index("--out")
        if i + 1 >= len(args):
            sys.exit("--out needs a directory")
        out_dir = Path(args[i + 1])
        del args[i:i + 2]
    if args and args[0] == "--from-wallpaper":
        if len(args) != 2:
            sys.exit("usage: theme-gen.py --from-wallpaper <palette.env> [--out <dir>]")
        wallpaper_src = Path(args[1])
        if not wallpaper_src.is_file():
            sys.exit(f"missing wallpaper palette: {wallpaper_src}")
    elif args:
        sys.exit(f"unknown argument: {args[0]}")
    out_dir.mkdir(parents=True, exist_ok=True)

    if wallpaper_src:
        derived = parse_env(wallpaper_src)
        missing = [k for k in WALLPAPER_KEYS if k not in derived]
        if missing:
            sys.exit(f"{wallpaper_src}: missing keys: {', '.join(missing)}")
        for k in WALLPAPER_KEYS:
            t[k] = derived[k].lstrip("#").lower()
        t["NAME"] = f"{t.get('NAME', 'Ashfall')} (wallpaper)"
        relax_contrast(t)
    else:
        check_contrast(t)
    outputs = {
        "kitty.conf": gen_kitty(t),
        "colors.css": gen_css(t),
        "sway-colors.conf": gen_sway(t),
        "rofi.rasi": gen_rofi(t),
        "swaylock.conf": gen_swaylock(t),
        "quickshell.json": gen_quickshell(t),
        "qt6ct-colors.conf": gen_qt6ct(t),
    }
    for name, body in outputs.items():
        (out_dir / name).write_text(body)

    # A sentinel, not a parse of the generated output: colors.env is only
    # ever READ by this script, never written, so install.sh cannot detect
    # "currently wallpaper-derived" by inspecting anything theme-gen.py
    # produces. The marker is the one place that state actually lives.
    marker = out_dir / ".wallpaper-derived"
    if wallpaper_src:
        marker.write_text(f"derived from {wallpaper_src}\n")
    elif marker.exists():
        marker.unlink()

    print(f"generated {len(outputs)} files in {out_dir} for '{t.get('NAME', '?')}'")


if __name__ == "__main__":
    main()
