#!/usr/bin/env python3
"""Unit tests for the Settings app backend. No display required.

Focus is the settings.conf writer, because that file is included by the sway
config: a bug here doesn't just misbehave, it can stop the session loading.
Every test that produces settings lines also feeds them through the real sway
parser when sway is available.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rice_settings import backend as b  # noqa: E402


def sway_accepts(lines: list[str]) -> tuple[bool, str]:
    """Validate directives against the real sway parser, if present."""
    if not b.has("sway"):
        return True, "sway not available; skipped"
    with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False) as f:
        f.write("set $mod Mod4\n")
        f.write("\n".join(lines) + "\n")
        path = f.name
    env = {"XDG_RUNTIME_DIR": "/tmp", "WLR_BACKENDS": "headless",
           "WLR_RENDERER": "pixman", "PATH": "/usr/bin:/bin", "HOME": str(b.HOME)}
    p = subprocess.run(["sway", "--validate", "--config", path],
                       capture_output=True, text=True, env=env)
    Path(path).unlink(missing_ok=True)
    bad = [l for l in (p.stdout + p.stderr).splitlines() if "sway/config.c" in l]
    return (p.returncode == 0 and not bad), "\n".join(bad)


class TestSettingsWriter(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "settings.conf"

    def tearDown(self):
        self.tmp.cleanup()

    def test_roundtrip(self):
        b.set_setting("output eDP-1 scale 2", self.path)
        self.assertEqual(b.read_managed(self.path),
                         {"output eDP-1 scale": "output eDP-1 scale 2"})

    def test_replacing_a_setting_does_not_duplicate_it(self):
        b.set_setting("output eDP-1 scale 2", self.path)
        b.set_setting("output eDP-1 scale 1.5", self.path)
        got = b.read_managed(self.path)
        self.assertEqual(len(got), 1, "same property written twice must collapse")
        self.assertIn("1.5", got["output eDP-1 scale"])
        self.assertEqual(self.path.read_text().count("output eDP-1 scale"), 1)

    def test_different_properties_coexist(self):
        b.set_setting("output eDP-1 scale 2", self.path)
        b.set_setting("output eDP-1 transform 90", self.path)
        self.assertEqual(len(b.read_managed(self.path)), 2)

    def test_hand_written_lines_outside_the_block_survive(self):
        self.path.write_text("# mine\nworkspace_layout tabbed\n")
        b.set_setting("output eDP-1 scale 2", self.path)
        text = self.path.read_text()
        self.assertIn("workspace_layout tabbed", text)
        self.assertIn("# mine", text)

    def test_clear_removes_only_that_setting(self):
        b.set_setting("output eDP-1 scale 2", self.path)
        b.set_setting("output eDP-1 transform 90", self.path)
        b.clear_setting("output eDP-1 scale 2", self.path)
        got = b.read_managed(self.path)
        self.assertNotIn("output eDP-1 scale", got)
        self.assertIn("output eDP-1 transform", got)

    def test_trailing_comment_is_rejected(self):
        # sway parse-errors on a trailing '#', and because this file is an
        # INCLUDE, plain `sway --validate` exits 0 and misses it entirely.
        with self.assertRaises(ValueError):
            b.set_setting("output eDP-1 scale 2  # my note", self.path)

    def test_empty_block_is_still_valid_sway(self):
        b.set_setting("output eDP-1 scale 2", self.path)
        b.clear_setting("output eDP-1 scale 2", self.path)
        okd, err = sway_accepts(self.path.read_text().splitlines())
        self.assertTrue(okd, err)

    def test_written_output_lines_parse_in_real_sway(self):
        for line in ["output eDP-1 scale 2",
                     "output eDP-1 scale 1.5",
                     "output eDP-1 transform 90",
                     "output eDP-1 mode 2880x1800@60Hz"]:
            b.set_setting(line, self.path)
        okd, err = sway_accepts(self.path.read_text().splitlines())
        self.assertTrue(okd, f"settings.conf must parse in sway: {err}")

    def test_written_input_lines_parse_in_real_sway(self):
        for line in ['input type:touchpad tap enabled',
                     'input type:touchpad natural_scroll disabled',
                     'input type:pointer scroll_method on_button_down',
                     'input type:keyboard repeat_rate 40']:
            b.set_setting(line, self.path)
        okd, err = sway_accepts(self.path.read_text().splitlines())
        self.assertTrue(okd, f"input settings must parse in sway: {err}")

    def test_repeated_writes_are_stable(self):
        for _ in range(5):
            b.set_setting("output eDP-1 scale 2", self.path)
        first = self.path.read_text()
        b.set_setting("output eDP-1 scale 2", self.path)
        self.assertEqual(first, self.path.read_text(), "writer must be idempotent")


class TestParsingHelpers(unittest.TestCase):
    def test_key_for_groups_by_property(self):
        self.assertEqual(b._key_for("output eDP-1 scale 2"), "output eDP-1 scale")
        self.assertEqual(b._key_for("input type:touchpad tap enabled"),
                         "input type:touchpad tap")
        self.assertEqual(b._key_for("workspace_layout tabbed"), "workspace_layout")

    def test_keybinds_reads_the_tsv_and_hides_hidden_rows(self):
        tsv = Path(__file__).resolve().parent.parent / "keybinds.tsv"
        if not tsv.is_file():
            self.skipTest("keybinds.tsv not present")
        rows = [l.split("\t") for l in tsv.read_text().splitlines()
                if l.strip() and not l.lstrip().startswith("#")]
        visible = [r for r in rows if len(r) == 5 and "hide" not in r[2]]
        orig, b.RICE = b.RICE, tsv.parent
        try:
            self.assertEqual(len(b.keybinds()), len(visible))
        finally:
            b.RICE = orig

    def test_system_info_never_raises_and_is_all_strings(self):
        info = b.system_info()
        self.assertIsInstance(info, dict)
        for k, v in info.items():
            self.assertIsInstance(v, str, f"{k} must be a string")

    def test_readers_degrade_gracefully_when_sway_is_absent(self):
        # In a container swaymsg is missing; these must return empty, not raise.
        self.assertIsInstance(b.outputs(), list)
        self.assertIsInstance(b.inputs(), list)
        self.assertIsInstance(b.battery_info(), dict)

    def test_run_handles_a_missing_binary(self):
        rc, out = b.run(["definitely-not-a-real-binary-xyz"])
        self.assertEqual(rc, 127)
        self.assertIn("not installed", out)


class TestSetWallpaper(unittest.TestCase):
    """set_wallpaper shells out; pin the branch behaviour without a real
    compositor, wallpaper daemon, or matugen."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.img = root / "pic.png"
        self.img.write_bytes(b"\x89PNG\r\n")
        self._orig = (b.RICE, b.SCRIPTS, b.has, b.run)
        b.RICE = root / ".config" / "rice"
        b.SCRIPTS = b.RICE / "scripts"
        b.SCRIPTS.mkdir(parents=True)
        (b.SCRIPTS / "theme-from-wallpaper.sh").write_text("#!/bin/sh\nexit 0\n")
        self.calls = []
        b.run = lambda cmd, timeout=10: (self.calls.append(cmd) or (0, ""))

    def tearDown(self):
        b.RICE, b.SCRIPTS, b.has, b.run = self._orig
        self.tmp.cleanup()

    def _ran_palette(self):
        return any("theme-from-wallpaper.sh" in " ".join(c) for c in self.calls)

    def test_missing_image_is_rejected_before_any_shell_out(self):
        okd, out = b.set_wallpaper(self.img.parent / "nope.png")
        self.assertFalse(okd)
        self.assertEqual(self.calls, [])

    def test_palette_is_rederived_when_matugen_present(self):
        b.has = lambda binary: binary == "matugen"
        okd, out = b.set_wallpaper(self.img)
        self.assertTrue(okd)
        self.assertTrue(self._ran_palette())

    def test_palette_is_skipped_without_matugen(self):
        b.has = lambda binary: False
        okd, _ = b.set_wallpaper(self.img)
        self.assertTrue(okd)
        self.assertFalse(self._ran_palette())

    def test_wallpaper_failure_short_circuits_palette(self):
        b.has = lambda binary: binary == "matugen"

        def fail_daemon(cmd, timeout=10):
            self.calls.append(cmd)
            return (1, "boom") if "wallpaper-daemon.service" in cmd else (0, "")

        b.run = fail_daemon
        okd, out = b.set_wallpaper(self.img)
        self.assertFalse(okd)
        self.assertFalse(self._ran_palette())


if __name__ == "__main__":
    unittest.main(verbosity=2)
