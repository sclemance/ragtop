#!/usr/bin/env python3
"""Watches a tablet-mode switch: tablet-switch.py <device, e.g. /dev/input/event12>.

Prints "tablet" or "laptop" at start and again whenever the switch moves.
Reads the device's events rather than polling, and asks the kernel for
the state (EVIOCGSW) at start and whenever events were dropped. Exits
non-zero if the device can't be read or goes away.
"""

import ctypes
import fcntl
import os
import signal
import struct
import sys

EV_SYN, SYN_DROPPED = 0x00, 3
EV_SW, SW_TABLET_MODE = 0x05, 1
EVENT = struct.Struct("llHHi")  # struct input_event: timeval, type, code, value


def eviocgsw(size):
    return (2 << 30) | (size << 16) | (ord("E") << 8) | 0x1B  # _IOR('E', 0x1b, size)


def query(fd):
    buf = bytearray(8)
    fcntl.ioctl(fd, eviocgsw(len(buf)), buf)
    return bool(buf[SW_TABLET_MODE // 8] & (1 << SW_TABLET_MODE % 8))


def report(tablet):
    print("tablet" if tablet else "laptop", flush=True)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    # End with the shell that started us: otherwise a leftover copy would
    # only notice at the next fold, when writing fails.
    ctypes.CDLL(None).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    try:
        fd = os.open(sys.argv[1], os.O_RDONLY)
        tablet = query(fd)
    except OSError as e:
        sys.exit(f"{sys.argv[1]}: {e.strerror}")
    report(tablet)
    while True:
        try:
            data = os.read(fd, EVENT.size * 64)
        except OSError as e:
            sys.exit(f"{sys.argv[1]}: {e.strerror}")
        if not data:
            sys.exit(f"{sys.argv[1]}: device went away")
        for _, _, type_, code, value in EVENT.iter_unpack(data):
            if type_ == EV_SW and code == SW_TABLET_MODE:
                now = bool(value)
            elif type_ == EV_SYN and code == SYN_DROPPED:
                now = query(fd)
            else:
                continue
            if now != tablet:
                tablet = now
                report(tablet)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
