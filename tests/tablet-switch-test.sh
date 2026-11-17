#!/bin/bash
# The setup script and service must choose the same tablet switch.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"

python_cases() {
  /usr/bin/python3 - "$repo/find-tablet-switch.py" "$tests_dir/fixtures/tablet-switch-cases.json" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('find_switch', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for case in json.load(open(sys.argv[2], encoding='utf-8')):
    got = module.find_switch(case['devices'])
    want = (case['path'], case['name']) if case['path'] else None
    assert got == want, f"{case['description']}: expected {want!r}, got {got!r}"
PY
}
run_test 'setup chooses the expected tablet switch for each fixture' python_cases

harness="$sandbox/tablet-switch"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
if /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" "$tests_dir/qml/tablet-switch/shell.qml.in" "$harness/shell.qml"; then
  /usr/bin/python3 - "$harness/shell.qml" "$tests_dir/fixtures/tablet-switch-cases.json" <<'PY'
import json, sys
path, fixtures = sys.argv[1:]
with open(path, encoding='utf-8') as f:
    text = f.read()
with open(fixtures, encoding='utf-8') as f:
    cases = json.load(f)
with open(path, 'w', encoding='utf-8') as f:
    f.write(text.replace('@CASES@', json.dumps(cases)))
PY
  run_qml
else
  echo 'not ok - service switch detection could be extracted'
  failed=1
fi
finish
