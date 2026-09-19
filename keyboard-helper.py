#!/usr/bin/env python3
"""Sends keys for Ragtop's own on-screen keyboard (Keyboard.qml), as a Wayland
virtual keyboard. QML can't be one itself, so the service runs this and
writes commands to it.

Uploads the same keymap Hyprland builds for the physical keyboard, so keys
mean what they mean there and Hyprland's keybindings match them, then reads
commands on stdin, one per line:

  type <text>                 type text in the active layout; characters the
                              layout lacks go through extra keys added to the
                              keymap on first use
  key <keysym> [mod ...]      press a key once with modifiers (one-shot); a
                              single character works too, e.g. "key - ctrl"
  down <keysym> [mod ...]     press and keep holding (the app repeats it)
  up <keysym>                 release a held key and its modifiers
  hold <mod> / release <mod>  sticky modifiers, applied to later keys
  reload                      re-read Hyprland's layouts, e.g. after a switch
  quit

At startup and after each reload it also prints "labels <json>": the active
layout's name and the characters on its letter keys, row by row, as
[normal, shifted] pairs, for the keyboard to draw.

where mod is shift, ctrl, alt, super or altgr. Prints "ok" or "error: ..."
for each command.
"""

import ctypes
import ctypes.util
import json
import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# Python bindings for the protocols, generated on first run from the XML.
BINDINGS = os.path.expanduser("~/.local/state/ragtop/protocol-bindings")
PROTOCOL_XML = os.path.join(HERE, "protocols", "virtual-keyboard-unstable-v1.xml")
WAYLAND_XML = "/usr/share/wayland/wayland.xml"


def ensure_bindings():
    marker = os.path.join(BINDINGS, "protocols", "virtual_keyboard_unstable_v1.py")
    if os.path.exists(marker) and os.path.getmtime(marker) >= os.path.getmtime(PROTOCOL_XML):
        return
    os.makedirs(BINDINGS, exist_ok=True)
    subprocess.run([sys.executable, "-m", "pywayland.scanner", "-i", WAYLAND_XML, PROTOCOL_XML,
                    "-o", os.path.join(BINDINGS, "protocols")], check=True, capture_output=True)


ensure_bindings()
sys.path.insert(0, BINDINGS)

from pywayland.client import Display  # noqa: E402
from protocols.wayland import WlSeat  # noqa: E402
from protocols.virtual_keyboard_unstable_v1 import ZwpVirtualKeyboardManagerV1  # noqa: E402

XKB = "/usr/lib/xkbcommon"
# Real modifiers in an xkb keymap, by bit: Shift, Lock, Control, Mod1 (Alt),
# Mod4 (Super), Mod5 (AltGr, xkb's LevelThree).
MOD_BITS = {"shift": 1 << 0, "lock": 1 << 1, "ctrl": 1 << 2, "alt": 1 << 3,
            "super": 1 << 6, "altgr": 1 << 7}
MOD_KEYSYMS = {"shift": "Shift_L", "ctrl": "Control_L", "alt": "Alt_L",
               "super": "Super_L", "altgr": "ISO_Level3_Shift"}
# How xkbcli-how-to-type names the modifiers a level needs.
HOW_TO_TYPE_MODS = {"Shift": "shift", "Mod5": "altgr", "LevelThree": None, "Lock": "lock"}
KEYMAP_FORMAT_XKB_V1 = 1
PRESSED, RELEASED = 1, 0
# Characters the layout lacks are typed through keys the keymap names but
# gives no symbols to, least recently used first when they run out. Keycodes
# above 255 would be plentiful, but clients don't receive them.
MAX_KEYCODE = 255
PRINTABLE_ASCII = [chr(c) for c in range(0x20, 0x7f)]


def hyprland_layout():
    """Hyprland's keymap settings and the active layout's index."""
    def option(name):
        out = subprocess.run(["hyprctl", "getoption", f"input:{name}"],
                             capture_output=True, text=True).stdout
        m = re.search(r"str: (.*)", out)
        return m.group(1).strip() if m else ""

    names = {key: option(f"kb_{key}") for key in ("rules", "model", "layout", "variant", "options")}
    active = 0
    devices = json.loads(subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True).stdout)
    real = [k for k in devices["keyboards"]
            if not k["name"].startswith("hl-virtual-keyboard") and k.get("layout")]
    if real:
        active = next((k for k in real if k.get("main")), real[0]).get("active_layout_index", 0)
    return names, active


class XkbLabels:
    """What a keymap's keys type, read with libxkbcommon itself."""

    def __init__(self):
        lib = ctypes.CDLL(ctypes.util.find_library("xkbcommon"))
        lib.xkb_context_new.restype = ctypes.c_void_p
        lib.xkb_context_new.argtypes = [ctypes.c_int]
        lib.xkb_keymap_new_from_string.restype = ctypes.c_void_p
        lib.xkb_keymap_new_from_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
        lib.xkb_keymap_unref.argtypes = [ctypes.c_void_p]
        lib.xkb_keymap_key_by_name.restype = ctypes.c_uint32
        lib.xkb_keymap_key_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.xkb_keymap_key_get_syms_by_level.restype = ctypes.c_int
        lib.xkb_keymap_key_get_syms_by_level.argtypes = [
            ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32,
            ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
        lib.xkb_keysym_to_utf32.restype = ctypes.c_uint32
        lib.xkb_keysym_to_utf32.argtypes = [ctypes.c_uint32]
        lib.xkb_keymap_layout_get_name.restype = ctypes.c_char_p
        lib.xkb_keymap_layout_get_name.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib = lib
        self.context = lib.xkb_context_new(0)

    # The letter rows of a physical keyboard, by xkb key name.
    ROWS = (("AD", 12), ("AC", 11), ("AB", 10))

    def letter_rows(self, keymap_text, group):
        """{"name": layout name, "rows": [[[normal, shifted], ...], ...]}, with
        the keys that type letters; punctuation keys are left to the
        keyboard's symbol pages."""
        lib = self.lib
        keymap = lib.xkb_keymap_new_from_string(self.context, keymap_text.encode(), 1, 0)
        if not keymap:
            return None

        def char(code, level):
            syms = ctypes.POINTER(ctypes.c_uint32)()
            if lib.xkb_keymap_key_get_syms_by_level(keymap, code, group, level, ctypes.byref(syms)) < 1:
                return ""
            u = lib.xkb_keysym_to_utf32(syms[0])
            return chr(u) if u else ""

        rows = []
        for prefix, count in self.ROWS:
            row = []
            for i in range(1, count + 1):
                code = lib.xkb_keymap_key_by_name(keymap, f"{prefix}{i:02d}".encode())
                if code == 0xFFFFFFFF:
                    continue
                normal = char(code, 0)
                if normal.isalpha():
                    row.append([normal, char(code, 1) or normal.upper()])
            rows.append(row)
        name = lib.xkb_keymap_layout_get_name(keymap, group)
        lib.xkb_keymap_unref(keymap)
        return {"name": name.decode() if name else "", "rows": rows}


def xkb_args(names):
    return [arg for key, value in names.items() if value for arg in (f"--{key}", value)]


class Keymap:
    """The keymap text plus lookups of which key types what."""

    def __init__(self, names, group):
        self.names = names
        self.group = group
        self.base = subprocess.run([f"{XKB}/xkbcli-compile-keymap", *xkb_args(names)],
                                   capture_output=True, text=True, timeout=10, check=True).stdout
        self.extras = {}      # keysym name -> key name, oldest use first
        self.lookups = {}
        self.lock = threading.Lock()
        keycodes = self._section("xkb_keycodes")
        codes = {m.group(1): int(m.group(2)) for m in re.finditer(r"<([^>]+)>\s*=\s*(\d+);", keycodes)}
        aliases = {m.group(1): m.group(2) for m in re.finditer(r"alias\s*<([^>]+)>\s*=\s*<([^>]+)>;", keycodes)}
        with_symbols = {aliases.get(m.group(1), m.group(1))
                        for m in re.finditer(r"key\s*<([^>]+)>", self._section("xkb_symbols"))}
        # Spare keys as (name, evdev keycode); evdev codes are xkb's minus 8.
        self.spare = sorted(((name, code - 8) for name, code in codes.items()
                             if code <= MAX_KEYCODE and name not in with_symbols), key=lambda k: k[1])
        self.spare_codes = dict(self.spare)

    def _section(self, name):
        start = self.base.index(name)
        return self.base[start:self.base.index("\n};", start)]

    def text(self):
        """The keymap, with a key for each extra keysym."""
        if not self.extras:
            return self.base
        syms = "".join(f"\tkey <{name}> {{ [ {sym} ] }};\n" for sym, name in self.extras.items())
        return self._insert(self.base, "xkb_symbols", syms)

    @staticmethod
    def _insert(text, section, lines):
        start = text.index(section)
        end = text.index("\n};", start)
        return text[:end + 1] + lines + text[end + 1:]

    def lookup(self, target, keysym=False):
        """(evdev keycode, modifiers) typing a character or keysym in the
        active layout, or None."""
        key = (target, keysym)
        with self.lock:
            if key in self.lookups:
                return self.lookups[key]
        cmd = [f"{XKB}/xkbcli-how-to-type", *xkb_args(self.names)] + (["--keysym"] if keysym else []) + [target]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout.split("=== Access via Compose")[0]
        best = None
        for line in out.splitlines():
            m = re.match(r"\s*(\d+)\s+\S+\s+(\d+)\s+.*?\[\s*(.*?)\s*\]\s*$", line)
            if not m or int(m.group(2)) - 1 != self.group:
                continue
            mods = {HOW_TO_TYPE_MODS.get(x, x.lower()) for x in m.group(3).split()} - {None}
            if "lock" in mods:
                continue  # Caps Lock levels duplicate Shift ones
            if best is None or len(mods) < len(best[1]):
                best = (int(m.group(1)) - 8, mods)
        with self.lock:
            self.lookups[key] = best
        return best

    def extra_key(self, char):
        """(evdev keycode, keymap changed) for a spare key typing `char`; the
        caller re-uploads the keymap if it changed."""
        sym = f"U{ord(char):04X}"
        if sym in self.extras:
            self.extras[sym] = self.extras.pop(sym)  # now the most recent
            return self.spare_codes[self.extras[sym]], False
        if not self.spare:
            raise ValueError(f"can't type {char!r}: this keymap has no spare keys")
        if len(self.extras) < len(self.spare):
            name = self.spare[len(self.extras)][0]
        else:
            name = self.extras.pop(next(iter(self.extras)))  # reuse the oldest
        self.extras[sym] = name
        return self.spare_codes[name], True

    def warm(self):
        """Look up the common characters ahead of first use."""
        for ch in PRINTABLE_ASCII:
            self.lookup(ch)


class Keyboard:
    def __init__(self):
        self.display = Display()
        self.display.connect()
        registry = self.display.get_registry()
        self.seat = None
        self.manager = None
        registry.dispatcher["global"] = self._global
        self.display.dispatch(block=True)
        self.display.roundtrip()
        if not self.seat or not self.manager:
            sys.exit("the compositor has no virtual keyboard support")
        self.vk = None
        self.start = time.monotonic()
        self.held = set()     # sticky modifiers
        self.down = {}        # keysym -> (keycode, modifiers) for held keys
        self.reload()

    def _global(self, registry, name, interface, version):
        if interface == "wl_seat" and not self.seat:
            self.seat = registry.bind(name, WlSeat, 1)
        elif interface == "zwp_virtual_keyboard_manager_v1":
            self.manager = registry.bind(name, ZwpVirtualKeyboardManagerV1, 1)

    def reload(self):
        names, group = hyprland_layout()
        self.keymap = Keymap(names, group)
        self._new_device()
        threading.Thread(target=self.keymap.warm, daemon=True).start()
        try:
            labels = XkbLabels().letter_rows(self.keymap.base, group)
        except OSError:
            labels = None  # no libxkbcommon to read: the keyboard keeps its US labels
        if labels:
            print("labels " + json.dumps(labels, ensure_ascii=False), flush=True)

    def _new_device(self):
        """Replace the virtual keyboard with one carrying the current keymap.
        A new device rather than a new keymap on the old one, because fcitx5,
        which every key passes through on Omarchy, only reads a keyboard's
        keymap when it first sees the keyboard."""
        for keysym in list(self.down):
            self.key_up(keysym)
        if self.vk is not None:
            self.vk.destroy()
        self.vk = self.manager.create_virtual_keyboard(self.seat)
        self._upload()

    def _upload(self):
        text = self.keymap.text().encode() + b"\0"
        fd = os.memfd_create("ragtop-keymap", os.MFD_CLOEXEC)
        os.write(fd, text)
        self.vk.keymap(KEYMAP_FORMAT_XKB_V1, fd, len(text))
        os.close(fd)
        self._send_mods()
        self.display.roundtrip()

    def _time(self):
        return int((time.monotonic() - self.start) * 1000)

    def _send_mods(self, extra=()):
        mask = 0
        for m in set(self.held) | set(extra):
            mask |= MOD_BITS[m]
        for _, mods in self.down.values():
            for m in mods:
                mask |= MOD_BITS[m]
        # The active layout goes in as the locked group.
        self.vk.modifiers(mask, 0, 0, self.keymap.group)

    def _mod_codes(self, mods):
        codes = []
        for m in sorted(mods):
            found = self.keymap.lookup(MOD_KEYSYMS[m], keysym=True)
            if found:
                codes.append(found[0])
        return codes

    def _press(self, code, mods):
        # Press the modifier keys too, like a physical keyboard, as well as
        # sending the modifier state, which the protocol leaves to clients.
        for c in self._mod_codes(mods):
            self.vk.key(self._time(), c, PRESSED)
        self._send_mods(mods)
        self.vk.key(self._time(), code, PRESSED)

    def _release(self, code, mods):
        self.vk.key(self._time(), code, RELEASED)
        for c in reversed(self._mod_codes(mods)):
            self.vk.key(self._time(), c, RELEASED)
        self._send_mods()

    def _find(self, target, keysym):
        found = self.keymap.lookup(target, keysym=keysym)
        if not found and keysym and len(target) == 1:
            # A plain character given where a key name was expected, e.g. "-"
            # in a Ctrl combo: the key that types it.
            found = self.keymap.lookup(target)
        if found:
            return found
        if keysym:
            raise ValueError(f"no key for {target} in this layout")
        code, changed = self.keymap.extra_key(target)
        if changed:
            self._new_device()
        return code, set()

    def type(self, text):
        for ch in text:
            code, mods = self._find(ch, keysym=False)
            mods = set(mods) - self.held
            self._press(code, mods)
            self._release(code, mods)

    def key(self, keysym, mods):
        code, needed = self._find(keysym, keysym=True)
        mods = set(mods) | needed
        self._press(code, mods)
        self._release(code, mods)

    def key_down(self, keysym, mods):
        if keysym in self.down:
            return
        code, needed = self._find(keysym, keysym=True)
        mods = set(mods) | needed
        self.down[keysym] = (code, mods)
        self._press(code, mods)

    def key_up(self, keysym):
        if keysym not in self.down:
            raise ValueError(f"{keysym} isn't held")
        code, mods = self.down.pop(keysym)
        self._release(code, mods)

    def release_all(self):
        for keysym in list(self.down):
            self.key_up(keysym)
        self.held.clear()
        self._send_mods()

    def handle(self, line):
        cmd, _, rest = line.partition(" ")
        parts = rest.split()
        if cmd == "type":
            self.type(rest)
        elif cmd in ("key", "down"):
            bad = [m for m in parts[1:] if m not in MOD_KEYSYMS]
            if not parts or bad:
                raise ValueError(f"usage: {cmd} <keysym> [shift|ctrl|alt|super|altgr ...]")
            (self.key if cmd == "key" else self.key_down)(parts[0], parts[1:])
        elif cmd == "up" and len(parts) == 1:
            self.key_up(parts[0])
        elif cmd in ("hold", "release") and rest in MOD_KEYSYMS:
            (self.held.add if cmd == "hold" else self.held.discard)(rest)
            self._send_mods()
        elif cmd == "reload":
            self.release_all()
            self.reload()
        elif cmd == "quit":
            return False
        else:
            raise ValueError(f"unknown command: {line}")
        self.display.roundtrip()
        return True


def dry_run(log):
    """--dry-run <file>: log each command with when it arrived; send nothing."""
    print("ready", flush=True)
    with open(log, "a", buffering=1) as out:
        for line in sys.stdin:
            out.write(f"{time.time():.3f} {line}")
            print("ok", flush=True)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--dry-run":
        return dry_run(sys.argv[2])
    kb = Keyboard()
    print("ready", flush=True)
    try:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if not line:
                continue
            try:
                if not kb.handle(line):
                    break
                print("ok", flush=True)
            except ValueError as e:
                print(f"error: {e}", flush=True)
    finally:
        try:
            # Never leave a key or modifier stuck down.
            kb.release_all()
            kb.vk.destroy()
            kb.display.roundtrip()
            sys.stdout.flush()
        except Exception:
            pass  # e.g. BrokenPipeError: the shell that read us has exited
        # Skip Python's own teardown, whatever happened above: it frees
        # pywayland objects in an order libwayland crashes on. The
        # compositor cleans up after the socket.
        os._exit(0)


if __name__ == "__main__":
    main()
