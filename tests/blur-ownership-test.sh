#!/bin/bash
# Ragtop's blur takes over Hyprland's global blur only when it saw it off
# (Service.qml, blurCheckProc): never when it was on, nor when the answer was
# not understood. Nothing reaches the compositor: hyprctl is printf here.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/blur"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
  "$tests_dir/qml/blur/shell.qml.in" "$harness/shell.qml"; then
  failed=1
else
  run_qml
fi
finish
