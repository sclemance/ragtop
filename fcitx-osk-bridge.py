#!/usr/bin/env python3
"""Report text-field focus from fcitx5, which Omarchy already runs as its
input method, so the on-screen keyboard can come up when one is tapped.

Registers as fcitx5's on-screen keyboard (its "DBus Virtual Keyboard"
addon) and prints "show" each time fcitx5 asks for it, which it does when a
text field gains focus. Only runs while in tablet mode.

fcitx5 counts every key it sees, including the on-screen keyboard's, as a
physical keyboard, and then stops asking and sends a "hide". So every "hide" re-arms
it, and a "hide" can't be told apart from a text field losing focus; it's
ignored, and hiding is left to the user.
"""

import ctypes
import signal
import sys

from gi.repository import Gio, GLib

# End with the shell that started us. Nothing else would tell us it's gone
# if it exits uncleanly, and a leftover copy would keep running unseen.
ctypes.CDLL(None).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG

NAME = "org.fcitx.Fcitx5.VirtualKeyboard"
PATH = "/org/fcitx/virtualkeyboard/impanel"
IFACE = "org.fcitx.Fcitx5.VirtualKeyboard1"

# Only the calls that matter; fcitx5 sends the rest (preedit, candidates)
# without waiting for a reply, so an error back is harmless.
XML = f"""
<node>
  <interface name="{IFACE}">
    <method name="ShowVirtualKeyboard"/>
    <method name="HideVirtualKeyboard"/>
  </interface>
</node>
"""

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
arming = False
rearm_source = 0
# Whether fcitx5 has ever spoken to us. Until it has, a working arm and one
# that never landed look exactly the same from here.
asked = False


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

    bus.call("org.fcitx.Fcitx5", "/virtualkeyboard",
             "org.fcitx.Fcitx.VirtualKeyboard1", "ShowVirtualKeyboard",
             None, None, Gio.DBusCallFlags.NONE, 2000, None, done)
    return GLib.SOURCE_REMOVE


def on_call(conn, sender, path, iface, method, params, invocation):
    global asked
    invocation.return_value(None)
    asked = True
    if method == "ShowVirtualKeyboard" and not arming:
        print("show", flush=True)
    elif method == "HideVirtualKeyboard":
        # Wait for a burst of typing to settle before re-arming.
        rearm_in(300)


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


GLib.timeout_add_seconds(10, watchdog)


Gio.bus_own_name_on_connection(bus, NAME, Gio.BusNameOwnerFlags.NONE,
                               on_name, on_name_lost)
GLib.MainLoop().run()
