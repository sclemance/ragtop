#!/usr/bin/env python3
"""Generate squeekboard layouts with Esc, Tab, modifier and arrow keys, for Fliparchy.

Squeekboard's layouts are GPL-3.0-or-later data files, so Fliparchy doesn't
ship modified copies. This script builds them locally from squeekboard's
upstream source (the tag matching the installed version) into
~/.local/state/fliparchy/keyboards, which Fliparchy points squeekboard at via
SQUEEKBOARD_KEYBOARDSDIR. Layouts missing there fall back to the built-in ones.

Every view gets a half-height modifier row, like squeekboard's own terminal
layout; terminal layouts, which already have Ctrl/Alt/Shift, just gain Super.
The row ends with a gear key that opens Fliparchy's settings: it sends
XF86Tools, which Fliparchy's installer binds in Hyprland to the Omarchy menu's
Setup › Tablet (squeekboard keys can't run commands themselves).
The keys are squeekboard modifiers: tap one on, tap a key, tap it off. For
Hyprland to run SUPER bindings from them, the squeekboard virtual keyboard
needs resolve_binds_by_sym (see Fliparchy's README).

Usage: squeekboard-layouts.py [--source DIR] [--version X.Y.Z]
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

UPSTREAM = "https://gitlab.gnome.org/World/Phosh/squeekboard.git"
OUT = Path.home() / ".local/state/fliparchy/keyboards"
CACHE = Path.home() / ".cache/fliparchy"
# Content-purpose subdirectories where modifier keys make no sense.
SKIP_DIRS = {"number", "pin", "emoji"}

# (button name, label, what it sends), in row order. Ctrl, Alt, Super and
# Shift are squeekboard modifiers; the rest are ordinary keys. Terminal
# layouts already have Tab and arrows, so they only take Esc and Super.
ESC = ("fl_esc", "Esc", {"keysym": "Escape"})
SUPER = ("fl_super", "Super", {"modifier": "Mod4"})
# The Nerd Font cog (md-cog), like the icons in the Omarchy menu.
SETTINGS = ("fl_settings", "\U000f0493", {"keysym": "XF86Tools"})
ROW_KEYS = [
    ESC,
    ("fl_tab", "Tab", {"keysym": "Tab"}),
    ("fl_ctrl", "Ctrl", {"modifier": "Control"}),
    ("fl_alt", "Alt", {"modifier": "Alt"}),
    SUPER,
    ("fl_shift", "Shift", {"modifier": "Shift"}),
    ("fl_left", "←", {"keysym": "Left"}),
    ("fl_up", "↑", {"keysym": "Up"}),
    ("fl_down", "↓", {"keysym": "Down"}),
    ("fl_right", "→", {"keysym": "Right"}),
    SETTINGS,
]
# Squeekboard uses the outline name as the button's CSS class, so this also
# lets Fliparchy's theme style the keys.
MOD_OUTLINE = "fl-mod"
# Same proportion as squeekboard's terminal "small-row" (27.725 of 52).
ROW_HEIGHT_RATIO = 27.725 / 52


def installed_version():
    out = subprocess.run(["pacman", "-Q", "squeekboard"], capture_output=True, text=True)
    match = re.search(r"squeekboard (\d+\.\d+\.\d+)", out.stdout)
    if not match:
        sys.exit("Couldn't determine the squeekboard version; pass --version or --source.")
    return match.group(1)


def fetch_source(version):
    dest = CACHE / f"squeekboard-{version}"
    if not (dest / "data/keyboards").is_dir():
        CACHE.mkdir(parents=True, exist_ok=True)
        shutil.rmtree(dest, ignore_errors=True)
        subprocess.run(["git", "-c", "advice.detachedHead=false", "clone", "-q", "--depth", "1", "--branch", f"v{version}", UPSTREAM, str(dest)], check=True)
    return dest


def button_width(layout, name):
    outlines = layout.get("outlines") or {}
    button = (layout.get("buttons") or {}).get(name) or {}
    outline = outlines.get(button.get("outline", "default")) or outlines.get("default") or {}
    return float(outline.get("width", 0))


def widest_row(layout):
    return max(
        (sum(button_width(layout, name) for name in row.split())
         for rows in (layout.get("views") or {}).values() for row in rows),
        default=0,
    )


def existing_modifier(buttons, modifier):
    for name, button in buttons.items():
        if isinstance(button, dict) and button.get("modifier") in (modifier, "Mod1" if modifier == "Alt" else None):
            return name
    return None


def patch(layout):
    outlines = layout.get("outlines")
    views = layout.get("views")
    if not isinstance(outlines, dict) or not isinstance(views, dict) or "default" not in outlines:
        return False
    buttons = layout.get("buttons") or {}
    layout["buttons"] = buttons

    alt = existing_modifier(buttons, "Alt")
    if alt:
        # Terminal layouts already have a Ctrl/Alt/Shift row: add Esc at its
        # start (theirs is only on the function-key view), Super after Alt and
        # the settings key at its end.
        alt_outline = (buttons[alt] or {}).get("outline", "default")
        outlines[MOD_OUTLINE] = dict(outlines[alt_outline])
        for name, label, sends in (ESC, SUPER, SETTINGS):
            buttons[name] = dict(sends, outline=MOD_OUTLINE, label=label)
        changed = False
        for rows in views.values():
            for i, row in enumerate(rows):
                keys = row.split()
                if alt not in keys or SUPER[0] in keys:
                    continue
                keys.insert(keys.index(alt) + 1, SUPER[0])
                keys.insert(0, ESC[0])
                keys.append(SETTINGS[0])
                rows[i] = " ".join(keys)
                changed = True
        return changed

    # Everything else: a new half-height row at the top of each view, as wide
    # as the widest existing row.
    width = widest_row(layout) / len(ROW_KEYS)
    height = float(outlines["default"].get("height", 52)) * ROW_HEIGHT_RATIO
    if width <= 0:
        return False
    outlines[MOD_OUTLINE] = {"width": round(width, 3), "height": round(height, 3)}
    for name, label, sends in ROW_KEYS:
        buttons[name] = dict(sends, outline=MOD_OUTLINE, label=label)
    row = " ".join(name for name, _, _ in ROW_KEYS)
    for rows in views.values():
        rows.insert(0, row)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="squeekboard source checkout")
    parser.add_argument("--version", help="squeekboard version to fetch (default: installed)")
    args = parser.parse_args()

    source = args.source or fetch_source(args.version or installed_version())
    keyboards = source / "data/keyboards"
    if not keyboards.is_dir():
        sys.exit(f"No data/keyboards in {source}")

    tmp = OUT.with_name(OUT.name + ".tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    written = 0
    for path in sorted(keyboards.rglob("*.yaml")):
        rel = path.relative_to(keyboards)
        if rel.parts[0] in SKIP_DIRS:
            continue
        layout = yaml.safe_load(path.read_text())
        if not isinstance(layout, dict) or not patch(layout):
            continue
        dest = tmp / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(
            f"# Generated by Fliparchy from squeekboard's {rel} (GPL-3.0-or-later).\n"
            + yaml.safe_dump(layout, allow_unicode=True, sort_keys=False, width=1000)
        )
        written += 1

    shutil.rmtree(OUT, ignore_errors=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp.rename(OUT)
    print(f"Wrote {written} layouts with modifier keys to {OUT}")


if __name__ == "__main__":
    main()
