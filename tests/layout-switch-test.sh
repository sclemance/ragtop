#!/bin/bash
# Real chooser and switch process, with no compositor or layout events.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/layout"
mkdir -p "$harness" "$sandbox/bin"
cp "$tests_dir/qml/Harness.qml" "$tests_dir/qml/layout/shell.qml" "$harness/"
cat > "$sandbox/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
sleep 0.05
[[ $3 != 99 ]]
STUB
chmod +x "$sandbox/bin/hyprctl"
/usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Keyboard.qml" "$tests_dir/qml/layout/Chooser.qml.in" "$harness/Chooser.qml"
/usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" "$tests_dir/qml/layout/LayoutService.qml.in" "$harness/LayoutService.qml"
# Keep the real Process and its exit handler in this test too.
/usr/bin/python3 - "$repo/Service.qml" "$harness/LayoutService.qml" <<'PY'
import pathlib, re, sys
source, harness = map(pathlib.Path, sys.argv[1:])
process = re.search(r'^  Process \{\n    id: switchLayoutProc\n.*?^  \}', source.read_text(), re.M | re.S)
assert process
harness.write_text(harness.read_text().replace('  // SWITCH PROCESS', process.group()))
PY
run_qml PATH="$sandbox/bin:/usr/bin:/bin"
assert_equal "$(calls)" $'switchxkblayout all 1\nswitchxkblayout all 0\nswitchxkblayout all 1\nswitchxkblayout all 0\nswitchxkblayout all 99' 'actual switch commands'
finish
