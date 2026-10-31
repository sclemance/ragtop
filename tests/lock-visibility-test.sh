#!/bin/bash
# Exercise the actual lock patch with an inert keyboard, offscreen and in a
# private HOME/runtime. Never lock the session or send native input.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
clones install lock
if [[ $rc != 0 ]]; then
  echo "not ok - lock clone installs: $err"
  exit 1
fi
mkdir -p "$sandbox/home/.config/ragtop"
echo laptop >"$sandbox/run/ragtop-mode"
qml_harness lock-visibility
/usr/bin/python3 - "$plugins/tester.lock/LockView.qml" "$harness/Gate.qml" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
start = source.index('    FileView { id: ragtopMode;')
end = source.index('    BorderSurface {\n      id: inputField', start)
block = source[start:end]
block = block.replace('    Loader {', '    Loader {\n      id: keyboard')
source_line = '      source: "file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/sclemance.ragtop/LockKeyboard.qml"'
assert block.count(source_line) == 1
block = block.replace(source_line, '      sourceComponent: Item { property var view: null }')
Path(sys.argv[2]).write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\nItem {\n id: root\n property alias keyboard: keyboard\n' + block + '\n}\n')
PY
run_qml
finish
