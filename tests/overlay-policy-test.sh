#!/bin/bash
# Actual 4.0.4 focus/settings bindings, without native surfaces or input.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
clones install menu emojis clipboard polkit image-picker
if [[ $rc != 0 ]]; then echo "not ok - policy clones install: $err"; exit 1; fi
mkdir -p "$sandbox/home/.config/ragtop"
echo laptop >"$sandbox/run/ragtop-mode"
qml_harness overlay-policy
/usr/bin/python3 - "$plugins" "$harness" <<'PYTHON'
from pathlib import Path
import sys
plugins, harness = map(Path, sys.argv[1:])
for i, (name, entry) in enumerate([('menu','Menu.qml'), ('emojis','Emojis.qml'), ('clipboard','Clipboard.qml'), ('polkit','PolkitAgent.qml'), ('image-picker','ImagePicker.qml')]):
    source = (plugins / ('tester.' + name) / entry).read_text()
    start = source.index('    WlrLayershell.keyboardFocus:')
    end = source.index('    exclusiveZone: 0', start)
    block = source[start:end].replace('WlrLayershell.keyboardFocus:', 'property int askedFocus:').replace('exclusionMode:', 'property int exclusion:')
    (harness / ('Gate' + str(i) + '.qml')).write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\nimport Quickshell.Wayland\nItem {\n id: root\n property bool opened: true\n property bool imagesLoaded: true\n' + block + '\n}\n')
PYTHON
run_qml
finish
