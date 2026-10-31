#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
if ! PYTHONPATH="$repo" /usr/bin/python3 "$tests_dir/swipe-geometry.py"; then failed=1; fi
harness="$sandbox/geometry"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
  "$tests_dir/qml/swipe-geometry/shell.qml.in" "$harness/shell.qml"; then
  failed=1
else
  run_qml
fi
finish
