#!/bin/bash
# Real page selection and selection state with inert page components.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/setup-navigation"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
sandboxed /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/SetupWizard.qml" \
  "$tests_dir/qml/setup-navigation/shell.qml.in" "$harness/shell.qml"
sandboxed /usr/bin/python3 - "$repo/SetupWizard.qml" "$harness/shell.qml" <<'PY'
from pathlib import Path
import sys
source, target = map(Path, sys.argv[1:])
s = source.read_text()
page = s.split('          sourceComponent: ', 1)[1].split('\n        }', 1)[0]
target.write_text(target.read_text().replace('// PAGE BINDING', 'sourceComponent: ' + page))
PY
run_qml
finish
