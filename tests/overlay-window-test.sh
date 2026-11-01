#!/bin/bash
# quick: skip, about 20 s: loads each Omarchy tree's overlay windows in quickshell.
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

# window_test <tree> <name>: the patched menu and image picker windows of
# that Omarchy, through the checks in tests/qml/window.
window_test() {
  make_sandbox "$1"
  clones install menu image-picker
  if [[ $rc != 0 ]]; then
    echo "not ok - $2: the clones under test install"
    echo "$err" | sed 's/^/  # /'
    failed=1
    return
  fi
  # Ragtop creates the mode file before anything reads it (Service.qml).
  echo laptop >"$sandbox/run/ragtop-mode"
  mkdir -p "$sandbox/home/.config/ragtop"
  echo keyboard=sensor >"$sandbox/home/.config/ragtop/settings.conf"
  qml_harness window
  with_clone menu Menu.qml menu
  with_clone image-picker ImagePicker.qml picker
  # Not piped: run_qml marks a failure in this shell, which a pipe would
  # put in a subshell of its own and lose.
  run_qml >"$sandbox/qml.out"
  sed "s/^\(not \)\{0,1\}ok - /&$2: /" "$sandbox/qml.out"
}

window_test "$new_omarchy" 7cc6a55
window_test "$rc_omarchy" 4.5.0-rc1

finish
