#!/bin/bash
# The window a patched clone gets on an Omarchy whose overlays share one
# OverlayWindow: what it asks the compositor for, closed and open, in laptop
# and in tablet mode, and when it lets its content be seen.
#
# The real patcher makes the clones, and the window under test is the file it
# generated, loaded by the real quickshell with its base type swapped for a
# stand-in (see with_clone in lib.sh). So this tests what the window asks
# for. What Hyprland then does about it -- where focus really goes, what a
# touch really hits -- is not tested here.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$new_omarchy"
clones install menu image-picker
if [[ $rc != 0 ]]; then
  echo "not ok - the clones under test install"
  echo "$err" | sed 's/^/  # /'
  failed=1
  finish
fi

# Ragtop creates the mode file before anything reads it (Service.qml).
echo laptop >"$sandbox/run/ragtop-mode"
qml_harness window
with_clone menu Menu.qml menu
with_clone image-picker ImagePicker.qml picker
run_qml

finish
