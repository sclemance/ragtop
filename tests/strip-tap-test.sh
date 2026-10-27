#!/bin/bash
# Keyboard.qml's taps on the suggestion strip, its own members run offscreen
# with the strip and service stood in for (tests/qml/tap): what was under
# the finger is what a tap takes, and a tap whose suggestions changed or
# whose field lost focus before it lifted takes nothing.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
harness="$sandbox/tap"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Keyboard.qml" \
    "$tests_dir/qml/tap/shell.qml.in" "$harness/shell.qml"; then
  echo "not ok - strip taps: Keyboard.qml's members could be found"
  failed=1
else
  run_qml
fi

finish
