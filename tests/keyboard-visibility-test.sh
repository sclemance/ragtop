#!/bin/bash
# The desktop keyboard fades without hiding its item or unmapping its surface.
# This checks the source contract; the rendering failure needs a real compositor.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

check_keyboard_visibility() {
  /usr/bin/python3 - "$repo/Service.qml" <<'PY'
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
window = source.split('    id: keyboardWindow\n', 1)[1].split('    Keyboard {\n', 1)[0]
keyboard = source.split('    Keyboard {\n      id: keyboard\n', 1)[1].split('\n    }\n', 1)[0]
assert re.search(r'^    visible: root\.keyboardAvailable && root\.layerRulesReady$', window, re.M), "keyboard surface must stay mapped while available"
assert re.search(r'^      opacity: root\.keysShown \? 1 : 0$', keyboard, re.M), "keys must follow the requested visibility"
assert not re.search(r'^      visible:', keyboard, re.M), "keyboard item must not be hidden during the fade"
PY
}

run_test "desktop keyboard fades without unmapping or hiding its item" check_keyboard_visibility
finish
