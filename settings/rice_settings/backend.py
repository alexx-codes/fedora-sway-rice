"""Backend logic for the Settings app — deliberately GUI-free.

Everything that reads state, writes settings, or shells out lives here and
imports nothing from GTK. That is what makes it unit-testable without a
display, which matters because a container has no display and an untested
settings app is exactly how you end up with a settings app that corrupts
your config.

Design rules:
  * Never reimplement what a script already does. Theme switching calls
    theme-toggle.sh; the contrast gate is theme-gen.py. One implementation.
  * All persistence goes to ~/.config/rice/settings.conf, which sway includes
    last and install.sh never overwrites.
  * sway rejects trailing "#" comments on a command line, so written lines
    never carry one. (Learned the hard way — plain `sway --validate` does not
    catch it inside an included file.)
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
RICE = HOME / ".config" / "rice"
SETTINGS = RICE / "settings.conf"
SCRIPTS = RICE / "scripts"

HEADER = """\
# Runtime overrides, written by the Settings app ($mod+Shift+S).
# Included last by ~/.config/sway/config, so anything here wins over the
# generated defaults. install.sh never touches this file.
#
# Syntax note: sway does NOT accept a trailing "#" comment on a command line.
# Put comments on their own line. Validate edits with:
#   ~/.config/rice/scripts/validate-config.sh
"""

# Marker delimiting the region this app owns, so hand-written lines outside
# it survive untouched.
BEGIN = "# >>> rice-settings managed >>>"
END = "# <<< rice-settings managed <<<"


def run(cmd: list[str], timeout: int = 10) -> tuple[int, str]:
    """Run a command, returning (returncode, combined output). Never raises."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except FileNotFoundError:
        return 127, f"{cmd[0]}: not installed"
    except subprocess.TimeoutExpired:
        return 124, f"{cmd[0]}: timed out"
    except OSError as e:
        return 1, str(e)


def has(binary: str) -> bool:
    return shutil.which(binary) is not None


# ---------------------------------------------------------------- settings io
def read_managed(path: Path = SETTINGS) -> dict[str, str]:
    """Parse the managed block into {key: full sway line}."""
    if not path.is_file():
        return {}
    text = path.read_text()
    if BEGIN not in text or END not in text:
        return {}
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    out: dict[str, str] = {}
    for line in block.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out[_key_for(line)] = line
    return out


def _key_for(line: str) -> str:
    """Identity of a setting, so rewriting one doesn't duplicate it.

    'output eDP-1 scale 2' and 'output eDP-1 scale 1.5' must collide;
    'output eDP-1 scale 2' and 'output eDP-1 transform 90' must not.
    """
    parts = line.split()
    if parts and parts[0] in ("output", "input"):
        # <cmd> <device> <property>
        return " ".join(parts[:3])
    if parts and parts[0] == "seat":
        return " ".join(parts[:3])
    return parts[0] if parts else line


def write_managed(entries: dict[str, str], path: Path = SETTINGS) -> None:
    """Rewrite only the managed block, preserving anything outside it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text() if path.is_file() else ""

    if BEGIN in existing and END in existing:
        before = existing.split(BEGIN, 1)[0]
        after = existing.split(END, 1)[1]
    else:
        before = existing if existing.strip() else HEADER
        if not before.endswith("\n"):
            before += "\n"
        after = ""

    body = "\n".join(entries[k] for k in sorted(entries)) if entries else ""
    block = f"{BEGIN}\n{body}\n{END}" if body else f"{BEGIN}\n{END}"
    path.write_text(f"{before}{block}{after}")


def set_setting(line: str, path: Path = SETTINGS) -> None:
    """Add or replace one sway directive in the managed block."""
    if "#" in line:
        raise ValueError(
            "sway rejects a trailing '#' comment on a command line; "
            "settings lines must not contain '#'"
        )
    entries = read_managed(path)
    entries[_key_for(line)] = line.strip()
    write_managed(entries, path)


def clear_setting(key_line: str, path: Path = SETTINGS) -> None:
    entries = read_managed(path)
    entries.pop(_key_for(key_line), None)
    write_managed(entries, path)


def apply_live(line: str) -> tuple[bool, str]:
    """Apply a directive to the running sway immediately."""
    rc, out = run(["swaymsg", line])
    return rc == 0, out


# ---------------------------------------------------------------- theme
def current_theme() -> str:
    try:
        return (RICE / "active").resolve().name
    except OSError:
        return "dark"


def theme_palette(mode: str | None = None) -> dict[str, str]:
    """Colors of a theme, read from its generated quickshell.json."""
    mode = mode or current_theme()
    f = RICE / "themes" / mode / "quickshell.json"
    try:
        return json.loads(f.read_text()).get("colors", {})
    except (OSError, json.JSONDecodeError):
        return {}


def set_theme(mode: str) -> tuple[bool, str]:
    """Switch theme by calling theme-toggle.sh — never reimplement it."""
    if mode not in ("dark", "light"):
        return False, f"unknown theme: {mode}"
    rc, out = run([str(SCRIPTS / "theme-toggle.sh"), mode], timeout=30)
    return rc == 0, out


# ---------------------------------------------------------------- wallpaper
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp"}


def wallpaper_dir() -> Path:
    env = os.environ.get("RICE_WALLPAPER_DIR")
    if env:
        return Path(env).expanduser()
    pics = HOME / "Pictures" / "wallpapers"
    return pics if pics.is_dir() else RICE / "wallpapers"


def list_wallpapers() -> list[Path]:
    d = wallpaper_dir()
    if not d.is_dir():
        return []
    return sorted(
        p for p in d.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXT and not p.is_symlink()
    )


def set_wallpaper(path: Path) -> tuple[bool, str]:
    """Apply a wallpaper. Uses swww when its daemon is up, else swaybg."""
    path = Path(path)
    if not path.is_file():
        return False, f"no such image: {path}"
    for link in ("current", "current-lock"):
        target = RICE / "wallpapers" / link
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_symlink() or target.exists():
                target.unlink()
            target.symlink_to(path)
        except OSError as e:
            return False, f"could not update {link}: {e}"

    if has("swww") and run(["swww", "query"])[0] == 0:
        rc, out = run(
            ["swww", "img", str(path), "--resize", "crop",
             "--transition-type", "grow", "--transition-duration", "1.2"],
            timeout=20)
        return rc == 0, out
    rc, out = run(["systemctl", "--user", "restart", "wallpaper-daemon.service"])
    return rc == 0, out


def regen_palette_from(path: Path) -> tuple[bool, str]:
    """Re-derive the dark palette from an image, GATED ON CONTRAST.

    This is the risk called out when the wallpaper switcher was proposed: a
    palette derived from an arbitrary image can come out unreadable. So the
    old palette is kept, matugen writes a new one, theme-gen.py's existing
    contrast gate judges it, and on failure the old palette is restored and
    the failing colors are reported. The wallpaper still changes either way.
    """
    if not has("matugen"):
        return False, "matugen is not installed — wallpaper changed, palette kept"

    colors = RICE / "themes" / "dark" / "colors.env"
    backup = colors.with_suffix(".env.bak")
    try:
        if colors.is_file():
            shutil.copy2(colors, backup)
    except OSError as e:
        return False, f"could not back up the current palette: {e}"

    cfg = RICE / "matugen" / "config.toml"
    rc, out = run(["matugen", "-c", str(cfg), "-m", "dark", "image", str(path)],
                  timeout=60)
    if rc != 0:
        _restore(backup, colors)
        return False, f"matugen failed, palette unchanged: {out}"

    rc, out = run([str(SCRIPTS / "theme-gen.py")], timeout=60)
    if rc != 0:
        _restore(backup, colors)
        run([str(SCRIPTS / "theme-gen.py")])
        return False, (
            "palette from this image failed the contrast check and was "
            "reverted — your text stays readable.\n" + out
        )

    backup.unlink(missing_ok=True)
    run([str(SCRIPTS / "theme-toggle.sh"), "--apply"], timeout=30)
    return True, "palette regenerated from this wallpaper and passed contrast"


def _restore(backup: Path, target: Path) -> None:
    try:
        if backup.is_file():
            shutil.copy2(backup, target)
            backup.unlink(missing_ok=True)
    except OSError:
        pass


# ---------------------------------------------------------------- display
def outputs() -> list[dict]:
    rc, out = run(["swaymsg", "-t", "get_outputs", "-r"])
    if rc != 0:
        return []
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return []


def set_output_scale(name: str, scale: float) -> tuple[bool, str]:
    line = f"output {name} scale {scale:g}"
    okd, out = apply_live(line)
    if okd:
        set_setting(line)
    return okd, out


def set_output_transform(name: str, transform: str) -> tuple[bool, str]:
    line = f"output {name} transform {transform}"
    okd, out = apply_live(line)
    if okd:
        set_setting(line)
    return okd, out


# ---------------------------------------------------------------- input
def inputs() -> list[dict]:
    rc, out = run(["swaymsg", "-t", "get_inputs", "-r"])
    if rc != 0:
        return []
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return []


def set_input_option(identifier: str, prop: str, value: str) -> tuple[bool, str]:
    line = f'input {identifier} {prop} {value}'
    okd, out = apply_live(line)
    if okd:
        set_setting(line)
    return okd, out


# ---------------------------------------------------------------- keybinds
def keybinds() -> list[dict]:
    """Read keybinds.tsv — the same single source of truth as the docs."""
    f = RICE / "keybinds.tsv"
    rows: list[dict] = []
    if not f.is_file():
        return rows
    for line in f.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 5:
            continue
        cat, keys, flags, _cmd, desc = (p.strip() for p in parts)
        if "hide" in flags:
            continue
        rows.append({"category": cat, "keys": keys, "description": desc})
    return rows


# ---------------------------------------------------------------- power
def power_profiles() -> tuple[list[str], str]:
    if not has("powerprofilesctl"):
        return [], ""
    rc, out = run(["powerprofilesctl", "list"])
    if rc != 0:
        return [], ""
    profs = re.findall(r"^\s*\*?\s*(\w[\w-]*):", out, re.M)
    cur = run(["powerprofilesctl", "get"])[1]
    return profs, cur


def set_power_profile(profile: str) -> tuple[bool, str]:
    rc, out = run(["powerprofilesctl", "set", profile])
    return rc == 0, out


def battery_info() -> dict[str, str]:
    info: dict[str, str] = {}
    base = Path("/sys/class/power_supply")
    if not base.is_dir():
        return info
    for bat in sorted(base.glob("BAT*")):
        def rd(n: str) -> str:
            try:
                return (bat / n).read_text().strip()
            except OSError:
                return ""
        info["name"] = bat.name
        info["capacity"] = rd("capacity")
        info["status"] = rd("status")
        full, design = rd("energy_full"), rd("energy_full_design")
        if not full:
            full, design = rd("charge_full"), rd("charge_full_design")
        if full and design:
            try:
                info["health"] = f"{100 * int(full) / int(design):.0f}%"
            except (ValueError, ZeroDivisionError):
                pass
        break
    return info


# ---------------------------------------------------------------- system info
def _first(path: str, pattern: str) -> str:
    try:
        for line in Path(path).read_text().splitlines():
            m = re.match(pattern, line)
            if m:
                return m.group(1).strip()
    except OSError:
        pass
    return ""


def system_info() -> dict[str, str]:
    info: dict[str, str] = {}
    info["Host"] = run(["hostname"])[1] or "?"
    info["OS"] = _first("/etc/os-release", r'PRETTY_NAME="?([^"]+)"?') or "?"
    info["Kernel"] = run(["uname", "-r"])[1] or "?"
    info["CPU"] = _first("/proc/cpuinfo", r"model name\s*:\s*(.+)") or "?"

    kb = _first("/proc/meminfo", r"MemTotal:\s+(\d+) kB")
    if kb:
        info["Memory"] = f"{int(kb) / 1024 / 1024:.1f} GiB"

    rc, out = run(["df", "-Ph", "/"])
    if rc == 0 and len(out.splitlines()) > 1:
        f = out.splitlines()[1].split()
        if len(f) >= 5:
            info["Disk /"] = f"{f[3]} free of {f[1]} ({f[4]} used)"

    try:
        up = float(Path("/proc/uptime").read_text().split()[0])
        info["Uptime"] = f"{int(up // 3600)}h {int(up % 3600 // 60)}m"
    except (OSError, ValueError, IndexError):
        pass

    info["Session"] = os.environ.get("XDG_SESSION_TYPE", "?")
    info["Compositor"] = (run(["swaymsg", "-t", "get_version", "-r"])[1] or "")[:80] or "not running"

    if has("vainfo"):
        rc, out = run(["vainfo"], timeout=15)
        driver = next((l for l in out.splitlines() if "Driver version" in l), "")
        info["VA-API"] = driver.split(":", 1)[-1].strip() if driver else "not working"
    else:
        info["VA-API"] = "vainfo not installed"

    if has("fwupdmgr"):
        rc, out = run(["fwupdmgr", "--version"], timeout=15)
        info["fwupd"] = out.splitlines()[0][:60] if rc == 0 and out else "?"

    info["Secret Service"] = "available" if (
        has("secret-tool") and run(["secret-tool", "search", "x", "y"])[0] in (0, 1)
    ) else "unavailable (VS Code / git credentials will not persist)"

    return info
