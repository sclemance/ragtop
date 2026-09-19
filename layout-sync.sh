#!/bin/bash
# Tells squeekboard which keyboard layouts Hyprland uses. Squeekboard picks
# its layout from GNOME's org.gnome.desktop.input-sources, which Omarchy
# leaves empty (it sets layouts in Hyprland), so without this squeekboard is
# always US. The active layout goes first, since that's the one squeekboard
# shows. The value found there before the first change is saved, and
# --restore puts it back.
#
# Usage: layout-sync.sh [--restore]
set -euo pipefail

state="$HOME/.local/state/ragtop"
saved="$state/input-sources.orig"
schema=org.gnome.desktop.input-sources

if [[ ${1:-} == --restore ]]; then
  [[ -f $saved ]] || exit 0
  gsettings set "$schema" sources "$(cat "$saved")"
  rm -f "$saved"
  exit 0
fi

# The layouts of a real keyboard, as a GVariant list with the active one
# first. Hyprland's own virtual keyboards (fcitx5's, squeekboard's) can be
# marked main, and squeekboard's reflects its own keymap, so they're skipped.
sources=$(hyprctl devices -j | python3 -c '
import json, sys
keyboards = [k for k in json.load(sys.stdin)["keyboards"]
             if not k["name"].startswith("hl-virtual-keyboard") and k.get("layout")]
if not keyboards:
    sys.exit()
keyboard = next((k for k in keyboards if k.get("main")), keyboards[0])
layouts = keyboard["layout"].split(",")
variants = (keyboard.get("variant") or "").split(",")
names = [l.strip() + ("+" + variants[i].strip() if i < len(variants) and variants[i].strip() else "")
         for i, l in enumerate(layouts)]
active = keyboard.get("active_layout_index", 0)
if 0 <= active < len(names):
    names.insert(0, names.pop(active))
print("[" + ", ".join(f"(\x27xkb\x27, \x27{n}\x27)" for n in names) + "]")
')
[[ -n $sources ]] || exit 0

current=$(gsettings get "$schema" sources)
[[ $current == "$sources" ]] && exit 0
mkdir -p "$state"
[[ -f $saved ]] || printf '%s\n' "$current" >"$saved"
gsettings set "$schema" sources "$sources"
