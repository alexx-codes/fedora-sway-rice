#!/usr/bin/env python3
"""Generate config/sway/keybinds.conf and config/sway/KEYBINDS.md from keybinds.tsv.

keybinds.tsv is the single source of truth for keybindings. The Quickshell
popup and the fuzzel fallback read the TSV directly at runtime; this script
only produces the two derived, committed files. Run it after editing the TSV:

    ./scripts/keybinds-gen.py
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TSV = REPO / "keybinds.tsv"
CONF = REPO / "config" / "sway" / "keybinds.conf"
MD = REPO / "config" / "sway" / "KEYBINDS.md"

CATEGORY_ORDER = [
    "Window management",
    "Workspaces",
    "Launching apps",
    "Media & brightness",
    "Screenshots",
    "Theme",
    "Session & power",
]


def parse():
    rows = []
    for lineno, line in enumerate(TSV.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            sys.exit(f"keybinds.tsv:{lineno}: expected 5 tab-separated fields, got {len(parts)}")
        cat, keys, flags, cmd, desc = (p.strip() for p in parts)
        flagset = set() if flags in ("-", "") else set(flags.split(","))
        unknown = flagset - {"locked", "to-code", "release", "doc", "hide"}
        if unknown:
            sys.exit(f"keybinds.tsv:{lineno}: unknown flags {sorted(unknown)}")
        if "doc" not in flagset and (not cmd or cmd == "-"):
            sys.exit(f"keybinds.tsv:{lineno}: non-doc row needs a command")
        rows.append({"cat": cat, "keys": keys, "flags": flagset, "cmd": cmd, "desc": desc})
    return rows


def gen_conf(rows):
    out = [
        "# GENERATED FILE - do not edit by hand.",
        "# Source of truth: keybinds.tsv (repo root). Regenerate with scripts/keybinds-gen.py",
        "",
    ]
    cur = None
    for r in rows:
        if "doc" in r["flags"]:
            continue
        if r["cat"] != cur:
            cur = r["cat"]
            out += [f"# --- {cur} ---"]
        prefix = "bindsym"
        for fl, opt in (("locked", "--locked"), ("to-code", "--to-code"), ("release", "--release")):
            if fl in r["flags"]:
                prefix += f" {opt}"
        out.append(f"{prefix} {r['keys']} {r['cmd']}")
    out.append("")
    CONF.parent.mkdir(parents=True, exist_ok=True)
    CONF.write_text("\n".join(out))


def gen_md(rows):
    out = [
        "# Keybindings",
        "",
        "`$mod` is the **Super** (Windows) key.",
        "",
        "> Generated from `keybinds.tsv` — edit that file and run",
        "> `scripts/keybinds-gen.py`, never this one. Press `$mod+Shift+/`",
        "> in-session for this list as a popup.",
        "",
    ]
    cats = {}
    for r in rows:
        if "hide" in r["flags"]:
            continue
        cats.setdefault(r["cat"], []).append(r)
    ordered = [c for c in CATEGORY_ORDER if c in cats] + [c for c in cats if c not in CATEGORY_ORDER]
    for cat in ordered:
        out += [f"## {cat}", "", "| Keys | Action |", "|------|--------|"]
        for r in cats[cat]:
            keys = r["keys"].replace("$mod", "$mod").replace("|", "\\|")
            out.append(f"| `{keys}` | {r['desc']} |")
        out.append("")
    notes = [
        "## Notes on non-obvious choices",
        "",
        "- `$mod+Shift+c/w/v` (app jumps) displaced the i3 default of `$mod+Shift+c`",
        "  for reload; reload lives on `$mod+Shift+r` instead (Sway has no separate",
        "  'restart', so the old restart key was free).",
        "- `$mod+Shift+e` opens the power menu rather than instantly exiting Sway —",
        "  logout is one of its options, so you can't fat-finger your session away.",
        "- Media/brightness keys carry `--locked`, so they keep working on the lock screen.",
        "- The theme toggle (`$mod+Shift+t`) switches Foot, Waybar, Quickshell, GTK, Qt,",
        "  swaync, fuzzel, swaylock and the wallpaper in one atomic step.",
        "",
    ]
    out += notes
    MD.write_text("\n".join(out))


def main():
    rows = parse()
    gen_conf(rows)
    gen_md(rows)
    print(f"wrote {CONF.relative_to(REPO)} and {MD.relative_to(REPO)} from {len(rows)} rows")


if __name__ == "__main__":
    main()
