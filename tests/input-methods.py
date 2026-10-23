#!/usr/bin/python3
"""Drives fcitx-osk-bridge.py and keyboard-helper.py's fcitx route against a
real fcitx5, for input-methods-test.sh. Run inside dbus-run-session, in the
sandbox: fcitx5 here is a private one with no display, its own config and a
bus nobody else is on.

usage: input-methods.py <repo> <step> ...

Plays the application with a fcitx5 input context of its own, focused, and
prints one line per thing that happened, which the test compares:

  engine <name or null>       the bridge said which input method is on
  commit <text>               the application was given text
  forward <keysym name>       fcitx5 passed a key on to the application
  wayland <keysym or char>    the helper sent a key the Wayland way instead
  has <text>                  the strip's candidates included <text>
  hide                        fcitx5 said a keyboard device typed, or focus
                              left the field

Steps:
  bridge:<command>            a line on the bridge's stdin (switch mozc, ...)
  type:<text>                 the helper's "type <text>"
  key:<keysym> [mods]         the helper's "key ..."
  pick:<text>                 select the candidate whose text is <text>
  route:<fcitx|wayland>       the helper's "route ..."
  cap:<hex>                   the field's capability flags, as an application
                              declares them, then focus it again
  other:<keysym>              a key from another keyboard: straight to the
                              input context, as a physical one arrives
"""

import importlib.util
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time

import gi
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib  # noqa: E402

repo, steps = sys.argv[1], sys.argv[2:]
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
said = []


def out(line):
    if line not in said[-1:]:
        said.append(line)
        print(line, flush=True)


def pump(seconds):
    end = time.monotonic() + seconds
    ctx = GLib.MainContext.default()
    while time.monotonic() < end:
        while ctx.pending():
            ctx.iteration(False)
        drain()
        time.sleep(0.01)


# --- fcitx5 ---------------------------------------------------------------

fcitx = subprocess.Popen(
    ["fcitx5", "--disable=wayland,waylandim,xcb,xim,classicui,kimpanel,"
     "notificationitem,ibusfrontend,fcitx4frontend,clipboard"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
for _ in range(100):
    try:
        bus.call_sync("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1",
                      "CurrentInputMethod", None, None, Gio.DBusCallFlags.NO_AUTO_START, 200, None)
        break
    except GLib.Error:
        time.sleep(0.1)
else:
    sys.exit("fcitx5 did not start")

# --- the bridge -----------------------------------------------------------

bridge = subprocess.Popen(["/usr/bin/python3", os.path.join(repo, "fcitx-osk-bridge.py")],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
lines = queue.Queue()
threading.Thread(target=lambda: [lines.put(line) for line in bridge.stdout], daemon=True).start()
candidates = []


def drain():
    global candidates
    while not lines.empty():
        kind, _, rest = lines.get().strip().partition(" ")
        if kind == "hide":
            out("hide")
        elif kind == "field":
            value = json.loads(rest)
            out("field " + (",".join(k for k in ("password", "terminal", "noCapitals") if value[k])
                            or "plain") if value else "field null")
        elif kind == "engine":
            value = json.loads(rest)
            out("engine " + (value["name"] if value else "null"))
        elif kind == "candidates":
            candidates = [c["text"] for c in json.loads(rest)["items"]]


def tell_bridge(command):
    bridge.stdin.write(command + "\n")
    bridge.stdin.flush()


pump(1.0)  # the bridge takes the name and arms fcitx5

# --- the application ------------------------------------------------------

IC = "org.fcitx.Fcitx.InputContext1"
ic = bus.call_sync("org.fcitx.Fcitx5", "/org/freedesktop/portal/inputmethod",
                   "org.fcitx.Fcitx.InputMethod1", "CreateInputContext",
                   GLib.Variant("(a(ss))", ([("program", "ragtop-test")],)),
                   GLib.VariantType("(oay)"), Gio.DBusCallFlags.NO_AUTO_START, 2000, None).unpack()[0]


def on_signal(conn, sender, path, iface, signal, params):
    args = params.unpack()
    if signal == "CommitString":
        out("commit " + args[0])
    elif signal == "ForwardKey" and not args[2]:  # presses, not releases
        out("forward " + (Gdk.keyval_name(args[0]) or str(args[0])))


bus.signal_subscribe("org.fcitx.Fcitx5", IC, None, ic, None, Gio.DBusSignalFlags.NONE, on_signal)
for method, args in (("SetCapability", GLib.Variant("(t)", (2,))), ("FocusIn", None)):
    bus.call_sync("org.fcitx.Fcitx5", ic, IC, method, args, None, Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
pump(0.5)

# --- the helper, without a compositor --------------------------------------

spec = importlib.util.spec_from_file_location("helper", os.path.join(repo, "keyboard-helper.py"))
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
kb = object.__new__(h.Keyboard)
kb.keymap = h.Keymap({"rules": "", "model": "", "layout": "us", "variant": "", "options": ""}, 0)
kb.held, kb.down, kb.fcitx_down, kb.fcitx = set(), {}, {}, None


class NoDisplay:
    def roundtrip(self):
        pass


kb.display = NoDisplay()
# The Wayland way, recorded instead of sent: there is no compositor here.
kb._press = lambda code, mods: out("wayland " + str(code))
kb._release = lambda code, mods: None

for step in steps:
    kind, _, arg = step.partition(":")
    if kind == "bridge":
        tell_bridge(arg)
    elif kind == "type":
        for ch in arg:
            kb.handle("type " + ch)
            pump(0.1)
    elif kind == "cap":
        for method, args in (("FocusOut", None), ("SetCapability", GLib.Variant("(t)", (int(arg, 16),))),
                             ("FocusIn", None)):
            bus.call_sync("org.fcitx.Fcitx5", ic, IC, method, args, None,
                          Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
    elif kind == "other":
        sym = Gdk.keyval_from_name(arg)
        for release in (False, True):
            bus.call_sync("org.fcitx.Fcitx5", ic, IC, "ProcessKeyEvent",
                          GLib.Variant("(uuubu)", (sym, 0, 0, release, 0)), GLib.VariantType("(b)"),
                          Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
    elif kind in ("key", "route"):
        kb.handle(f"{kind} {arg}")
    elif kind == "pick":
        pump(0.3)
        if arg not in candidates:
            out(f"missing {arg} in {candidates[:8]}")
            continue
        out("has " + arg)
        tell_bridge(f"select {candidates.index(arg)}")
    pump(0.4)

bridge.stdin.close()
bridge.wait(5)


def stop_mozc_server():
    """Mozc's client starts mozc_server as a process of its own, which
    outlives fcitx5. Left running, it aborts with a core dump when the
    sandbox holding its socket is deleted, a burst of them per test run in
    coredumpctl. So this test's own server, the one with this sandbox's
    HOME, is asked to stop first, and given a moment to."""
    home = ("HOME=" + os.environ["HOME"]).encode()
    mine = []
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() != "mozc_server":
                    continue
            with open(f"/proc/{pid}/environ", "rb") as f:
                if home in f.read().split(b"\0"):
                    mine.append(int(pid))
        except OSError:
            continue
    for pid in mine:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(50):
        if not any(os.path.exists(f"/proc/{pid}") for pid in mine):
            return
        time.sleep(0.05)


stop_mozc_server()
fcitx.terminate()
fcitx.wait(5)
