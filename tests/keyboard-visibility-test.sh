#!/bin/bash
# Real touch handling and repeat timers, offscreen with an inert key sink.
# The reported blank rendering still needs the affected compositor to check.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
qml_harness keyboard-visibility
sandboxed /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Keyboard.qml" \
  "$tests_dir/qml/keyboard-visibility/KeyboardInput.qml.in" "$harness/KeyboardInput.qml"
sandboxed /usr/bin/python3 - "$repo" "$harness" <<'PY'
from pathlib import Path
import sys

repo, harness = map(Path, sys.argv[1:])
service = (repo / 'Service.qml').read_text()
keyboard = (repo / 'Keyboard.qml').read_text()
# Run the actual placement bindings and touch area alongside the extracted
# handlers. Only layout and the service's external key sink are stand-ins.
placement = service.split('    Keyboard {\n      id: keyboard\n', 1)[1].split('      service: root', 1)[0]
touch = keyboard.split('  MultiPointTouchArea {', 1)[1].split('\n  // ---- Tracing touches', 1)[0]
component = harness / 'KeyboardInput.qml'
component.write_text(component.read_text().replace('  // PLACEMENT', placement)
                     .replace('  // TOUCH AREA', '  MultiPointTouchArea {' + touch))
PY
run_qml QT_QUICK_BACKEND=software
finish
