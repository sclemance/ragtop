#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/completion"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
 "$tests_dir/qml/completion-queue/shell.qml.in" "$harness/shell.qml"; then
 failed=1
else
 run_qml
fi
finish
