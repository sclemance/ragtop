#!/bin/bash
# Real preference commands under a private HOME; no desktop input or IPC.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
qml_harness preferences
python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" "$tests_dir/qml/preferences/Preferences.qml.in" "$harness/Preferences.qml"
python3 - "$repo/Service.qml" "$harness/Preferences.qml" "$harness/ragtop" "$repo/ragtop" <<'PY'
import pathlib,re,sys,shlex
source,harness,cli,real=map(pathlib.Path,sys.argv[1:])
processes=[]
for name in ['preferenceProc','displayProc']:
    m=re.search(r'^  Process \{\n    id: '+name+r'\n.*?^  \}', source.read_text(), re.M|re.S)
    assert m
    processes.append(m.group())
harness.write_text(harness.read_text().replace('  // PROCESSES','\n'.join(processes)))
cli.write_text('#!/bin/bash\nsleep 0.03\nexec bash '+shlex.quote(str(real))+' "$@"\n')
PY
run_qml
config="$sandbox/home/.config/ragtop/settings.conf"
sandboxed bash "$repo/ragtop" auto-show enabled || fail 'double toggle lost'
assert_contains "$(cat "$config")" 'keyboard-layout=80' 'last queued layout saved after failure'
assert_contains "$(cat "$config")" 'keyboard=off' 'two rapid keyboard cycles'
assert_contains "$(cat "$config")" 'rotation=unlocked' 'two rapid rotation cycles'
mapfile -t theme_names < <(sandboxed bash "$repo/ragtop" theme list)
assert_equal "$(sandboxed bash "$repo/ragtop" theme get)" "${theme_names[2]}" 'two theme steps'
assert_equal "$(sandboxed bash "$repo/ragtop" display get)" HDMI-A-1 'confirmed display persisted'
for pair in '78 smallest' '88 smaller' '100 regular' '115 larger' '130 largest' '127 custom'; do
  read -r number alias <<<"$pair"
  sandboxed bash "$repo/ragtop" size-adjust set "$number"
  sandboxed bash "$repo/ragtop" size-adjust is "$alias" || fail "size $number not recognized as $alias"
done
sandboxed bash "$repo/ragtop" size-adjust set auto
if sandboxed bash "$repo/ragtop" size-adjust is custom; then fail 'Auto marked custom'; fi
finish
