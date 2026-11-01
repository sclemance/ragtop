#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/terminal"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$repo/predictor.py" "$repo/terminal-helper.py" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
 "$tests_dir/qml/terminal-lifecycle/shell.qml.in" "$harness/shell.qml"; then
 failed=1
else
 run_qml
fi
finish
