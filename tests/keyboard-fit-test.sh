#!/bin/bash
# Keyboard.qml's sizing, its own members run offscreen with what they read
# stood in for (tests/qml/fit): which board fits the height budget, and that
# the suggestion strip is a whole row only where the board still fits with
# it, without ever costing the board its place.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
harness="$sandbox/fit"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Keyboard.qml" \
    "$tests_dir/qml/fit/shell.qml.in" "$harness/shell.qml"; then
  echo "not ok - keyboard fit: Keyboard.qml's members could be found"
  failed=1
else
  run_qml
fi

finish
