#!/usr/bin/python3
"""Prints "<device path>\t<device name>" for the input device reporting the
tablet-mode switch (SW_TABLET_MODE, bit 1 of its switch bitmask), or nothing.

Mirrors Service.qml's findSwitchDevice, which runs inside the shell.
"""

import re

def find_switch(devices):
    # A switch-only device can be made readable without exposing key events.
    # Prefer it to a combined device, but keep the latter as a fallback.
    fallback = None
    for block in re.split(r"\n\s*\n", devices):
        handler = re.search(r"^H: Handlers=.*\b(event\d+)\b", block, re.M)
        sw = re.search(r"^B: SW=([0-9a-fA-F ]+)$", block, re.M)
        name = re.search(r'^N: Name="(.*)"', block, re.M)
        if handler and sw and int(sw.group(1).split()[-1], 16) & 2:
            candidate = (f"/dev/input/{handler.group(1)}", name.group(1) if name else "")
            if not re.search(r"^B: KEY=", block, re.M):
                return candidate
            if fallback is None:
                fallback = candidate
    return fallback


if __name__ == "__main__":
    result = find_switch(open("/proc/bus/input/devices", encoding="utf-8").read())
    if result:
        print("\t".join(result))
