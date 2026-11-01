#!/bin/bash
# Real tour entrance controller, isolated from the desktop and input sinks.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/tour-strip"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Tour.qml" \
    "$tests_dir/qml/tour-strip/shell.qml.in" "$harness/shell.qml"; then
  failed=1
else
  run_qml
fi
finish
