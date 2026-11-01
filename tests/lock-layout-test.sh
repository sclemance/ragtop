#!/bin/bash
# Real lock keyboard and XKB layout metadata, in a private runtime with an
# inert password view. Never touches the desktop lock or authenticates.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/lock-layout"
mkdir -p "$harness"
cp "$tests_dir/qml/lock-layout/shell.qml" "$tests_dir/qml/Harness.qml" \
  "$repo/LockKeyboard.qml" "$repo/LockKeyIcon.qml" "$repo/KeyContrast.js" "$harness/"
cp -r "$tests_dir/qml/theme/Commons" "$harness/Commons"
sandboxed /usr/bin/python3 - "$repo" "$harness" <<'PY'
import importlib.util, json, pathlib, sys
repo, harness = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('helper', repo/'keyboard-helper.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
layouts = {}
for name in ['us', 'fr', 'de']:
    keymap = helper.Keymap(dict(rules='', model='', layout=name, variant='', options=''), 0)
    layouts[name] = helper.XkbLabels().letter_rows(keymap.base, 0)
(harness/'Layouts.js').write_text('.pragma library\nvar layouts = '+json.dumps(layouts)+'\n')
PY
run_qml
finish
