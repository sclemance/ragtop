#!/usr/bin/env python3
"""What the touchscreen itself reports, finger by finger, for laying against
what Ragtop did with each touch (`ragtop touch-trace compare`).

    sudo bench/touch-trace.py [/dev/input/eventN]

Reads the kernel's touch events, before Hyprland or Ragtop see them, so a
tap that the panel reported and Ragtop never acted on can be told apart from
one the panel never reported at all. Needs root, since the touchscreen is
only readable by root and the input group. Runs until Ctrl+C.

Each finger down and up is appended to $XDG_RUNTIME_DIR/ragtop-touch-kernel.log
(of the user who ran sudo) as a JSON line: {"t": milliseconds since the
epoch, "ev": "down" or "up", "slot": the finger, "x", "y": the share of the
panel's width and height}. It is in the runtime folder, so it goes at the
next reboot, and it is the user's to delete before then. Where a finger is
says roughly which key it was on, so it is kept nowhere else.

The panel's x and y are its own, unrotated: with the screen turned, they are
turned with it. The comparison goes by time first for that reason.
"""
import fcntl
import json
import os
import struct
import sys

EV_SYN, EV_ABS = 0x00, 0x03
SYN_REPORT = 0
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID = 0x2F, 0x35, 0x36, 0x39
EVENT = struct.Struct("llHHi")       # struct input_event on 64-bit Linux
ABSINFO = struct.Struct("iiiiii")    # value, minimum, maximum, fuzz, flat, resolution


def eviocgabs(code):
    return 0x80184540 + code         # _IOR('E', 0x40 + code, struct input_absinfo)


def find_touchscreen():
    """The device that reports multitouch positions and is not a touchpad
    or a pen: /proc/bus/input/devices names each, with its handlers."""
    name = handler = None
    found = []
    with open("/proc/bus/input/devices") as f:
        for line in f.read().split("\n") + [""]:
            if line.startswith("N: Name="):
                name = line[8:].strip('"')
            elif line.startswith("H: Handlers="):
                handler = next((h for h in line[len("H: Handlers="):].split() if h.startswith("event")), None)
            elif line.startswith("B: ABS="):
                bits = int(line.split("=")[1].replace(" ", ""), 16)
                if name and handler and bits >> ABS_MT_POSITION_X & 1 \
                        and not any(w in name.lower() for w in ("touchpad", "stylus", "pen", "mouse")):
                    found.append((name, "/dev/input/" + handler))
            elif line == "":
                name = handler = None
    return found


def main():
    if len(sys.argv) > 1:
        device = sys.argv[1]
    else:
        found = find_touchscreen()
        if not found:
            sys.exit("No touchscreen found. Name one: bench/touch-trace.py /dev/input/eventN")
        name, device = found[0]
        print(f"Touchscreen: {name} ({device})")
    uid = int(os.environ.get("SUDO_UID", os.getuid()))
    gid = int(os.environ.get("SUDO_GID", os.getgid()))
    log = f"/run/user/{uid}/ragtop-touch-kernel.log"
    with open(device, "rb") as dev:
        ranges = {}
        for axis in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y):
            info = ABSINFO.unpack(fcntl.ioctl(dev, eviocgabs(axis), b"\0" * ABSINFO.size))
            ranges[axis] = (info[1], max(1, info[2] - info[1]))
        out = open(log, "a", buffering=1)
        os.chown(log, uid, gid)
        os.chmod(log, 0o600)
        print(f"Recording to {log}. Type, and Ctrl+C when done.")
        slot = 0
        slots = {}        # slot -> {"id", "x", "y", "new"}
        while True:
            data = dev.read(EVENT.size)
            if len(data) < EVENT.size:
                break
            sec, usec, kind, code, value = EVENT.unpack(data)
            t = sec * 1000 + usec // 1000
            if kind == EV_ABS:
                if code == ABS_MT_SLOT:
                    slot = value
                elif code == ABS_MT_TRACKING_ID:
                    if value == -1:
                        if slot in slots:
                            s = slots.pop(slot)
                            out.write(json.dumps({"t": t, "ev": "up", "slot": slot,
                                                  "x": s["x"], "y": s["y"]}) + "\n")
                    else:
                        slots[slot] = {"id": value, "x": None, "y": None, "new": True}
                elif code in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y) and slot in slots:
                    low, span = ranges[code]
                    slots[slot]["x" if code == ABS_MT_POSITION_X else "y"] = round((value - low) / span, 4)
            elif kind == EV_SYN and code == SYN_REPORT:
                for n, s in slots.items():
                    if s["new"] and s["x"] is not None and s["y"] is not None:
                        s["new"] = False
                        out.write(json.dumps({"t": t, "ev": "down", "slot": n,
                                              "x": s["x"], "y": s["y"]}) + "\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except PermissionError:
        sys.exit("The touchscreen is only readable by root: run it with sudo.")
