#!/usr/bin/env python3
"""Prints "<device path>\t<device name>" for the input device reporting the
tablet-mode switch (SW_TABLET_MODE, bit 1 of its switch bitmask), or nothing.

Mirrors Service.qml's findSwitchDevice, which runs inside the shell.
"""

import re

for block in re.split(r"\n\s*\n", open("/proc/bus/input/devices").read()):
    handler = re.search(r"^H: Handlers=.*\b(event\d+)\b", block, re.M)
    sw = re.search(r"^B: SW=([0-9a-fA-F ]+)$", block, re.M)
    name = re.search(r'^N: Name="(.*)"', block, re.M)
    if handler and sw and int(sw.group(1).split()[-1], 16) & 2:
        print(f"/dev/input/{handler.group(1)}\t{name.group(1) if name else ''}")
        break
