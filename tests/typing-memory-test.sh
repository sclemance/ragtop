#!/bin/bash
# Service.qml's typing memory, its own members run offscreen with what they
# touch stood in for (tests/qml/memory): what full, word and none keep while
# keys are typed, and that a field taking focus, a hide, another field or
# none, and a change of setting each let it go.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
harness="$sandbox/memory"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$repo/typed-record.js" "$harness/"
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
    "$tests_dir/qml/memory/shell.qml.in" "$harness/shell.qml"; then
  echo "not ok - typing memory: Service.qml's members could be found"
  failed=1
else
  run_qml
fi

finish
