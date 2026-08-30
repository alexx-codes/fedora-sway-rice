"""GTK4 + libadwaita Settings app for fedora-sway-rice.

Toolkit chosen deliberately over Quickshell: Quickshell is COPR-only, lags
Fedora Qt updates, and has never been verified to run. libadwaita is in
Fedora proper, follows the GTK dark/light setting the theme toggle already
drives (so it themes itself), and is HiDPI-correct without extra work.

All state and side effects live in backend.py, which is unit-tested without a
display. This module is presentation only.
"""
from __future__ import annotations

import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

from . import backend as b  # noqa: E402

APP_ID = "dev.rice.Settings"


def toast(page: Adw.PreferencesPage, text: str) -> None:
    win = page.get_root()
    if isinstance(win, Adw.ApplicationWindow) and hasattr(win, "toaster"):
        win.toaster.add_toast(Adw.Toast(title=text, timeout=4))


# ---------------------------------------------------------------- Wallpaper
class WallpaperPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__(title="Wallpaper", icon_name="image-x-generic-symbolic")

        # Added before the wallpaper grid on purpose: the "no wallpapers found"
        # branch below returns early, and a group added after it would never
        # appear on exactly the machine that most needs a manual regen.
        g0 = Adw.PreferencesGroup()
        row = Adw.ActionRow(
            title="Regenerate theme from wallpaper",
            subtitle="Re-derives surfaces, text and accents from the current "
                     "wallpaper, then reloads sway")
        btn = Gtk.Button(label="Regenerate", valign=Gtk.Align.CENTER)
        btn.connect("clicked", self._regen)
        row.add_suffix(btn)
        row.set_activatable_widget(btn)
        g0.add(row)
        self.add(g0)

        d = b.wallpaper_dir()
        g = Adw.PreferencesGroup(title="Wallpapers", description=f"From {d}")
        self.add(g)

        papers = b.list_wallpapers()
        if not papers:
            g.add(Adw.ActionRow(
                title="No wallpapers found",
                subtitle=f"Put images in {d} (jpg, png, webp)"))
            return

        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                           max_children_per_line=4, row_spacing=10,
                           column_spacing=10, margin_top=10, margin_bottom=10,
                           homogeneous=True)
        for p in papers:
            flow.append(self._tile(p))
        wrap = Adw.PreferencesGroup()
        wrap.add(flow)
        self.add(wrap)

    def _tile(self, path):
        btn = Gtk.Button(has_frame=False, tooltip_text=path.name)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        try:
            pic = Gtk.Picture.new_for_filename(str(path))
            pic.set_size_request(190, 110)
            pic.set_content_fit(Gtk.ContentFit.COVER)
            pic.add_css_class("card")
            box.append(pic)
        except GLib.Error:
            box.append(Gtk.Label(label="(unreadable image)"))
        lbl = Gtk.Label(label=path.stem, ellipsize=3, max_width_chars=22)
        lbl.add_css_class("caption")
        box.append(lbl)
        btn.set_child(box)
        btn.connect("clicked", self._apply, path)
        return btn

    # regen_theme_from_wallpaper() / set_wallpaper() shell out to
    # theme-from-wallpaper.sh (matugen + theme-gen + `swaymsg reload`) with a
    # 60 s timeout. Run on the GTK thread that would freeze the whole window,
    # so both go through a worker thread and report back via GLib.idle_add.
    def _run_bg(self, btn, busy_label, work, message):
        if self._bg_busy:
            return
        self._bg_busy = True
        btn.set_sensitive(False)
        restore = btn.get_label() if busy_label is not None else None
        if restore is not None:
            btn.set_label(busy_label)

        def finish(result):
            self._bg_busy = False
            btn.set_sensitive(True)
            if restore is not None:
                btn.set_label(restore)
            toast(self, message(*result))
            return False

        def worker():
            try:
                result = work()
            except Exception as exc:  # never lose the UI to a worker crash
                result = (False, str(exc))
            GLib.idle_add(finish, result)

        threading.Thread(target=worker, daemon=True).start()

    _bg_busy = False

    def _regen(self, btn):
        self._run_bg(
            btn, "Regenerating…", b.regen_theme_from_wallpaper,
            lambda okd, out: "Theme regenerated from wallpaper" if okd
            else f"Could not regenerate theme: {out}")

    def _apply(self, btn, path):
        def message(okd, out):
            if not okd:
                return f"Could not set wallpaper: {out}"
            if out.startswith("note:"):
                return f"Wallpaper set to {path.name} ({out[5:].strip()})"
            return f"Wallpaper set to {path.name}"
        self._run_bg(btn, None, lambda: b.set_wallpaper(path), message)


# ---------------------------------------------------------------- Display
class DisplayPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__(title="Display", icon_name="video-display-symbolic")
        outs = b.outputs()
        if not outs:
            g = Adw.PreferencesGroup(title="No outputs")
            g.add(Adw.ActionRow(title="sway is not running",
                                subtitle="Display settings need a live session"))
            self.add(g)
            return
        for o in outs:
            self.add(self._group(o))

    def _group(self, o):
        name = o.get("name", "?")
        mode = o.get("current_mode") or {}
        desc = " ".join(filter(None, [o.get("make"), o.get("model")])) or "display"
        g = Adw.PreferencesGroup(title=name, description=desc)

        g.add(Adw.ActionRow(
            title="Resolution",
            subtitle=f"{mode.get('width','?')}×{mode.get('height','?')} @ "
                     f"{round(mode.get('refresh', 0) / 1000)} Hz"))

        scale = Adw.ComboRow(
            title="Scale",
            subtitle="Integer scaling keeps XWayland apps crisp; fractional "
                     "gives more room but softens them")
        options = ["1", "1.25", "1.5", "1.75", "2", "2.5", "3"]
        scale.set_model(Gtk.StringList.new(options))
        cur = f"{o.get('scale', 1):g}"
        scale.set_selected(options.index(cur) if cur in options else 0)
        scale.connect("notify::selected", self._on_scale, name, options)
        g.add(scale)

        transform = Adw.ComboRow(title="Rotation")
        tvals = ["normal", "90", "180", "270"]
        transform.set_model(Gtk.StringList.new(tvals))
        tcur = str(o.get("transform", "normal"))
        transform.set_selected(tvals.index(tcur) if tcur in tvals else 0)
        transform.connect("notify::selected", self._on_transform, name, tvals)
        g.add(transform)
        return g

    def _on_scale(self, row, _p, name, options):
        okd, out = b.set_output_scale(name, float(options[row.get_selected()]))
        toast(self, f"{name} scale {options[row.get_selected()]}"
                    if okd else f"Could not set scale: {out}")

    def _on_transform(self, row, _p, name, tvals):
        okd, out = b.set_output_transform(name, tvals[row.get_selected()])
        toast(self, f"{name} rotated" if okd else f"Could not rotate: {out}")


# ---------------------------------------------------------------- Input
class InputPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__(title="Input", icon_name="input-touchpad-symbolic")

        tp = Adw.PreferencesGroup(title="Touchpad")
        self.add(tp)
        for title, sub, prop, on, off in [
            ("Tap to click", "", "tap", "enabled", "disabled"),
            ("Natural scrolling", "Content follows your fingers",
             "natural_scroll", "enabled", "disabled"),
            ("Disable while typing", "Palm rejection",
             "dwt", "enabled", "disabled"),
        ]:
            r = Adw.SwitchRow(title=title, subtitle=sub, active=True)
            r.connect("notify::active", self._toggle, "type:touchpad", prop, on, off)
            tp.add(r)

        tpt = Adw.PreferencesGroup(
            title="TrackPoint",
            description="Hold the middle button and nudge the stick to scroll. "
                        "A plain middle click still pastes.")
        self.add(tpt)
        r = Adw.SwitchRow(title="Middle-button scrolling", active=True)
        r.connect("notify::active", self._toggle, "type:pointer",
                  "scroll_method", "on_button_down", "none")
        tpt.add(r)

        kb = Adw.PreferencesGroup(title="Keyboard")
        self.add(kb)
        rate = Adw.SpinRow.new_with_range(10, 100, 5)
        rate.set_title("Repeat rate")
        rate.set_subtitle("Characters per second when a key is held")
        rate.set_value(40)
        rate.connect("notify::value", self._spin, "type:keyboard", "repeat_rate")
        kb.add(rate)
        delay = Adw.SpinRow.new_with_range(100, 1000, 50)
        delay.set_title("Repeat delay")
        delay.set_subtitle("Milliseconds before repeating starts")
        delay.set_value(300)
        delay.connect("notify::value", self._spin, "type:keyboard", "repeat_delay")
        kb.add(delay)

        touch = Adw.PreferencesGroup(
            title="Touchscreen",
            description="Touch is mapped to the internal panel so coordinates "
                        "stay correct when an external monitor is attached. "
                        "Note: no on-screen keyboard can type into the lock "
                        "screen — swaylock takes an exclusive keyboard grab.")
        self.add(touch)
        n = len([i for i in b.inputs() if i.get("type") == "touch"])
        touch.add(Adw.ActionRow(
            title="Touch devices detected",
            subtitle=str(n) if n else "none (is this a touch model?)"))

    def _toggle(self, row, _p, ident, prop, on, off):
        okd, out = b.set_input_option(ident, prop, on if row.get_active() else off)
        if not okd:
            toast(self, f"Could not apply: {out}")

    def _spin(self, row, _p, ident, prop):
        okd, out = b.set_input_option(ident, prop, str(int(row.get_value())))
        if not okd:
            toast(self, f"Could not apply: {out}")


# ---------------------------------------------------------------- Keyboard
class KeyboardPage(Adw.PreferencesPage):
    """Bindings plus the live key tester.

    The tester exists because of a real failure: F-keys that did nothing, with
    no way to tell an unbound key from a broken one. It shows the keysym GTK
    actually received, needs no extra package (wev is COPR-only on Fedora),
    and answers "is this key even reaching the compositor?" in one press.
    """

    def __init__(self):
        super().__init__(title="Keyboard", icon_name="input-keyboard-symbolic")

        t = Adw.PreferencesGroup(
            title="Key tester",
            description="Press any key — including the F-row and Fn combos — "
                        "to see the keysym your system reports. Nothing shown "
                        "means the key never reached the compositor: check "
                        "FnLock with Fn+Esc.")
        self.add(t)
        self.readout = Adw.ActionRow(title="Waiting for a key…",
                                     subtitle="Click here first, then press a key")
        self.readout.set_activatable(True)
        t.add(self.readout)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)
        self.set_focusable(True)

        by_cat: dict[str, list[dict]] = {}
        for row in b.keybinds():
            by_cat.setdefault(row["category"], []).append(row)
        for cat, rows in by_cat.items():
            g = Adw.PreferencesGroup(title=cat)
            for r in rows:
                g.add(Adw.ActionRow(title=r["keys"], subtitle=r["description"]))
            self.add(g)

    def _on_key(self, _c, keyval, keycode, state):
        name = Gdk.keyval_name(keyval) or f"0x{keyval:x}"
        mods = [m for m, f in (("Super", Gdk.ModifierType.SUPER_MASK),
                               ("Ctrl", Gdk.ModifierType.CONTROL_MASK),
                               ("Alt", Gdk.ModifierType.ALT_MASK),
                               ("Shift", Gdk.ModifierType.SHIFT_MASK))
                if state & f]
        combo = "+".join(mods + [name])
        self.readout.set_title(combo)
        self.readout.set_subtitle(f"keysym {name}   ·   keycode {keycode}")
        return True


# ---------------------------------------------------------------- Power
class PowerPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__(title="Power", icon_name="battery-symbolic")

        profiles, current = b.power_profiles()
        g = Adw.PreferencesGroup(title="Power profile")
        self.add(g)
        if profiles:
            row = Adw.ComboRow(title="Profile")
            row.set_model(Gtk.StringList.new(profiles))
            if current in profiles:
                row.set_selected(profiles.index(current))
            row.connect("notify::selected", self._on_profile, profiles)
            g.add(row)
        else:
            g.add(Adw.ActionRow(
                title="power-profiles-daemon not available",
                subtitle="Install it, and do not run TLP at the same time — "
                         "they conflict"))

        bat = b.battery_info()
        bg = Adw.PreferencesGroup(title="Battery")
        self.add(bg)
        if bat:
            bg.add(Adw.ActionRow(title="Charge",
                                 subtitle=f"{bat.get('capacity','?')}% "
                                          f"({bat.get('status','?')})"))
            if "health" in bat:
                bg.add(Adw.ActionRow(
                    title="Health", subtitle=f"{bat['health']} of design capacity"))
        else:
            bg.add(Adw.ActionRow(title="No battery detected"))

        lid = Adw.PreferencesGroup(
            title="Lid and idle",
            description="Closing the lid suspends — unless a VM is running, in "
                        "which case it locks and blanks instead, so a guest is "
                        "never frozen mid-write. Idle locks at 10 minutes and "
                        "blanks at 15; a visible VM console suppresses both.")
        self.add(lid)

    def _on_profile(self, row, _p, profiles):
        okd, out = b.set_power_profile(profiles[row.get_selected()])
        if not okd:
            toast(self, f"Could not switch profile: {out}")


# ---------------------------------------------------------------- System
class SystemPage(Adw.PreferencesPage):
    def __init__(self):
        super().__init__(title="System", icon_name="computer-symbolic")
        g = Adw.PreferencesGroup(title="System information")
        self.add(g)
        for k, v in b.system_info().items():
            row = Adw.ActionRow(title=k, subtitle=v)
            row.set_subtitle_selectable(True)
            g.add(row)


# ---------------------------------------------------------------- window
class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Settings",
                         default_width=940, default_height=720)
        self.toaster = Adw.ToastOverlay()
        view = Adw.ViewStack()
        for page in (WallpaperPage(), DisplayPage(), InputPage(),
                     KeyboardPage(), PowerPage(), SystemPage()):
            view.add_titled_with_icon(page, page.get_title(),
                                      page.get_title(), page.get_icon_name())

        switcher = Adw.ViewSwitcher(stack=view,
                                    policy=Adw.ViewSwitcherPolicy.WIDE)
        header = Adw.HeaderBar(title_widget=switcher)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.append(header)
        box.append(view)
        view.set_vexpand(True)
        self.toaster.set_child(box)
        self.set_content(self.toaster)


class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID)

    def do_activate(self):
        (self.props.active_window or Window(self)).present()


def main() -> int:
    return App().run(None)
