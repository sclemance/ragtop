#!/usr/bin/python3
"""Ragtop's side of fcitx5, which Omarchy already runs as its input method.

Registers as fcitx5's on-screen keyboard (its "DBus Virtual Keyboard"
addon), which fcitx5 tells three things:

- when a text field gains focus, so the keyboard can come up by itself.
  Printed as "show".
- which input method the focused field is using. Printed as "engine <json>"
  for one that composes text, Mozc, Pinyin or Hangul and the like, as
  {"name", "label", "title"}, and "engine null" for a plain keyboard layout or
  no field at all. "engines <json>" lists every composing one in the user's
  fcitx5 group, the same objects, for the keyboard to offer.
- what the composing one has to choose from. Printed as "candidates <json>",
  {"items": [{"text", "note"}], "prev", "next", "cursor"}, with "items"
  empty when there is nothing to choose.

and reads commands on stdin, one per line:

  select <index>    take that candidate
  prev / next       the candidates' previous or next page
  switch <name>     use that input method in the focused field
  deactivate        back to the plain keyboard layout in the focused field

Candidates only come here while fcitx5 is in on-screen keyboard mode, which
keys sent through its own interface keep it in. keyboard-helper.py does
that while a composing engine is on ("route fcitx"). Keys from anywhere
else, a physical keyboard or the helper's Wayland path, end the mode and
fcitx5 sends a "hide". So every "hide" re-arms it, and a "hide" can't be
told apart from a text field losing focus; it's ignored, and hiding is left
to the user.

What is typed is never printed anywhere but stdout, which only the service
reads: a candidate is what the user is writing.
"""

import ctypes
import json
import re
import signal
import sys

from gi.repository import Gio, GLib

# End with the shell that started us. Nothing else would tell us it's gone
# if it exits uncleanly, and a leftover copy would keep running unseen.
ctypes.CDLL(None).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG

NAME = "org.fcitx.Fcitx5.VirtualKeyboard"
PATH = "/org/fcitx/virtualkeyboard/impanel"
IFACE = "org.fcitx.Fcitx5.VirtualKeyboard1"
FCITX = "org.fcitx.Fcitx5"
CONTROLLER = ("/controller", "org.fcitx.Fcitx.Controller1")
BACKEND = ("/virtualkeyboard", "org.fcitx.Fcitx5.VirtualKeyboardBackend1")

# Every call fcitx5's virtualkeyboard addon makes, with its signature. A
# method left out is refused by GDBus before it reaches us, which is how
# the candidates went missing while this declared only the first two.
XML = f"""
<node>
  <interface name="{IFACE}">
    <method name="ShowVirtualKeyboard"/>
    <method name="HideVirtualKeyboard"/>
    <method name="UpdatePreeditCaret"><arg type="i"/></method>
    <method name="UpdatePreeditArea"><arg type="s"/></method>
    <method name="UpdateCandidateArea">
      <arg type="as"/><arg type="b"/><arg type="b"/><arg type="i"/><arg type="i"/>
    </method>
    <method name="NotifyIMActivated"><arg type="s"/></method>
    <method name="NotifyIMDeactivated"><arg type="s"/></method>
    <method name="NotifyIMListChanged"/>
  </interface>
</node>
"""

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
arming = False
rearm_source = 0
# Whether fcitx5 has ever spoken to us. Until it has, a working arm and one
# that never landed look exactly the same from here.
asked = False
# Every input method fcitx5 has, by unique name: {"name", "label", "title"}.
known = {}
# The composing engines in the user's group, in its order.
group = []
engine = None
# The engine as last printed, so a repeat of the same news says nothing.
printed_engine = "unset"

# fcitx5 gives a candidate and what kind of thing it is as one string:
# "ニホンゴ [カタカナ]" from Mozc, "南 (na)" from Pinyin. The keyboard draws
# the second part smaller, so it is split off here, once, for every engine.
NOTE = re.compile(r"^(.+?) ([\[(][^\[\]()]*[\])])$")


def say(kind, value):
    print(f"{kind} {json.dumps(value, ensure_ascii=False)}", flush=True)


def composing(name):
    """Whether an input method composes text rather than being a layout.
    fcitx5 names every plain layout keyboard-<layout>."""
    return bool(name) and not name.startswith("keyboard-")


def set_engine(name):
    global engine, printed_engine
    engine = known.get(name, {"name": name, "label": "", "title": name}) if composing(name) else None
    if engine != printed_engine:
        printed_engine = engine
        say("engine", engine)
    if engine is None:
        say("candidates", {"items": [], "prev": False, "next": False, "cursor": -1})


def call(where, method, args=None, reply=None, done=None):
    """An asynchronous call to fcitx5. `done` gets the unpacked reply, or is
    not called at all when fcitx5 refused or was gone.

    Never with auto-start, here or anywhere fcitx5 is called by name. D-Bus
    will start a fcitx5 for a call to a name nobody holds, and one started
    that way runs outside Omarchy's service: while the service's own fcitx5
    is restarting, a call landing in the gap leaves two of them, one holding
    the name and one crash-looping."""
    def finish(conn, result):
        try:
            value = conn.call_finish(result)
        except GLib.Error:
            return
        if done:
            done(value.unpack() if value is not None else None)
    bus.call(FCITX, where[0], where[1], method, args,
             GLib.VariantType(reply) if reply else None,
             Gio.DBusCallFlags.NO_AUTO_START, 2000, None, finish)


def refresh_methods():
    """Re-read what fcitx5 has and what the user's group holds."""
    def got_available(value):
        known.clear()
        for unique, name, native, _icon, label, _lang, _cfg in value[0]:
            known[unique] = {"name": unique, "label": label, "title": name or native or unique}
        call(CONTROLLER, "CurrentInputMethodGroup", reply="(s)", done=got_group_name)

    def got_group_name(value):
        call(CONTROLLER, "InputMethodGroupInfo", GLib.Variant("(s)", value),
             "(sa(ss))", got_group)

    def got_group(value):
        global group
        group = [known.get(im, {"name": im, "label": "", "title": im})
                 for im, _layout in value[1] if composing(im)]
        say("engines", group)
        # The labels may have arrived after the engine was named.
        if engine is not None:
            set_engine(engine["name"])

    call(CONTROLLER, "AvailableInputMethods", reply="(a(ssssssb))", done=got_available)


def ask_engine():
    """fcitx5 names the engine when a field gains focus, and not when an arm
    puts it back into on-screen keyboard mode, so after an arm it is asked."""
    call(CONTROLLER, "CurrentInputMethod", reply="(s)", done=lambda v: set_engine(v[0]))


def rearm_in(ms):
    """Arm again, unless an arming is already on its way."""
    global rearm_source
    if rearm_source:
        return
    rearm_source = GLib.timeout_add(ms, arm)


def arm():
    """Put fcitx5 in on-screen-keyboard mode, so it asks on focus again.

    fcitx5 answers by asking to show the keyboard, before replying to this
    call; that request isn't a text field, so it's ignored until the reply.
    """
    global arming, rearm_source
    rearm_source = 0
    arming = True

    def done(conn, result):
        global arming
        arming = False
        try:
            conn.call_finish(result)
        except GLib.Error:
            # Nothing else retries this. The re-arm below only happens on a
            # hide, and fcitx5 only hides a keyboard it was asked to show,
            # so one failed call here is a whole session with no keyboard
            # coming up by itself. It happens when fcitx5 is still starting.
            rearm_in(2000)
            return
        ask_engine()

    bus.call(FCITX, "/virtualkeyboard",
             "org.fcitx.Fcitx.VirtualKeyboard1", "ShowVirtualKeyboard",
             None, None, Gio.DBusCallFlags.NO_AUTO_START, 2000, None, done)
    return GLib.SOURCE_REMOVE


def candidates(texts, has_prev, has_next, _page, cursor):
    items = []
    for text in texts:
        m = NOTE.match(text)
        items.append({"text": m.group(1), "note": m.group(2)[1:-1]} if m
                     else {"text": text, "note": ""})
    say("candidates", {"items": items, "prev": has_prev, "next": has_next, "cursor": cursor})


def on_call(conn, sender, path, iface, method, params, invocation):
    global asked
    invocation.return_value(None)
    asked = True
    args = params.unpack() if params is not None else ()
    if method == "ShowVirtualKeyboard" and not arming:
        print("show", flush=True)
    elif method == "HideVirtualKeyboard":
        # Wait for a burst of typing to settle before re-arming.
        rearm_in(300)
    elif method == "NotifyIMActivated":
        set_engine(args[0])
    elif method == "NotifyIMDeactivated":
        set_engine("")
    elif method == "NotifyIMListChanged":
        refresh_methods()
    elif method == "UpdateCandidateArea":
        candidates(*args)
    # The preedit is drawn by the application, in the field, wherever it
    # supports that, so the keyboard has no use for UpdatePreeditArea.


def on_command(source, condition):
    line = sys.stdin.readline()
    if not line:
        loop.quit()  # the service is gone
        return False
    cmd, _, arg = line.strip().partition(" ")
    if cmd == "select" and arg.lstrip("-").isdigit():
        call(BACKEND, "SelectCandidate", GLib.Variant("(i)", (int(arg),)))
    elif cmd == "prev":
        call(BACKEND, "PrevPage")
    elif cmd == "next":
        call(BACKEND, "NextPage")
    elif cmd == "switch" and arg:
        call(CONTROLLER, "SetCurrentIM", GLib.Variant("(s)", (arg,)))
    elif cmd == "deactivate":
        call(CONTROLLER, "Deactivate")
    return True


def on_fcitx_appeared(conn, name, owner):
    """fcitx5 came back, so whatever we told the old one is gone with it.

    Arming is a request to a running fcitx5, not a setting that survives it.
    A restart of fcitx5, or fcitx5 starting after this bridge, leaves us
    holding the name and being asked nothing, which looks exactly like
    working from every side.
    """
    global asked
    asked = False
    refresh_methods()
    rearm_in(500)


def on_fcitx_vanished(conn, name):
    set_engine("")


def watchdog():
    """Keep asking until fcitx5 answers.

    A failed arm leaves no trace and nothing to notice it by: we hold the
    name, the process is alive, everything reports healthy, and the keyboard
    simply never comes up on its own. So while nothing has ever been
    received, keep trying.
    """
    if not asked:
        rearm_in(0)
    return GLib.SOURCE_CONTINUE


bus.register_object_with_closures2(
    PATH, Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], on_call, None, None)


def on_name(conn, name):
    # fcitx5 notices the new owner and switches its interface over.
    GLib.timeout_add(200, arm)


def on_name_lost(conn, name):
    sys.exit(1)


Gio.bus_watch_name_on_connection(bus, FCITX, Gio.BusNameWatcherFlags.NONE,
                                 on_fcitx_appeared, on_fcitx_vanished)
GLib.timeout_add_seconds(10, watchdog)
GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, on_command)


Gio.bus_own_name_on_connection(bus, NAME, Gio.BusNameOwnerFlags.NONE,
                               on_name, on_name_lost)
loop = GLib.MainLoop()
loop.run()
