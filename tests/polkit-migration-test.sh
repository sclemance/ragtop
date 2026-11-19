#!/bin/bash
# Recreate the exact revision-6 polkit patch and upgrade it through real sync.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
for tree in "$old_omarchy" "$new_omarchy" "$rc_omarchy" "$rel_omarchy"; do
  make_sandbox "$tree"
  clones install polkit
  assert_rc 0
  entry="$plugins/tester.polkit/PolkitAgent.qml"
  sandboxed /usr/bin/python3 - "$entry" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
start=s.index('    FileView { id: ragtopMode;')
settings_end=s.index('    QtObject {\n      id: ragtopPasswordView', start)
end=s.index('    BorderSurface {\n      id: card',settings_end)
settings=s[start:settings_end].rstrip('\n')
s=s[:start]+s[end:]
s=s.replace('    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive',
 '    WlrLayershell.keyboardFocus: ragtopKeyboardSettings.available ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive\n'+settings)
s=s.replace('    exclusionMode: ExclusionMode.Ignore',
 '    exclusionMode: ragtopKeyboardSettings.available ? ExclusionMode.Normal : ExclusionMode.Ignore\n    exclusiveZone: 0')
p.write_text(s)
base=p.parent/'.ragtop-base';lines=base.read_text().splitlines();lines[1]='6';base.write_text('\n'.join(lines)+'\n')
PY
  cp "$entry" "$sandbox/revision6.qml"
  clones status polkit
  assert_lacks "$out" 'edits besides'
  clones sync polkit
  assert_rc 0
  assert_contains "$out" 'Re-patched tester.polkit'
  assert_contains "$(cat "$entry")" 'id: ragtopPasswordView'
  assert_lacks "$(cat "$entry")" 'WlrKeyboardFocus.OnDemand'
  clones status polkit
  assert_contains "$out" 'in sync with the built-in'
  echo "ok - ${tree##*/}: revision-6 authentication clone upgrades to direct password input"
  cp "$sandbox/revision6.qml" "$entry"
  sed -i '2s/.*/6/' "$plugins/tester.polkit/.ragtop-base"
  echo '// user edit' >>"$entry"
  clones sync polkit
  assert_rc 1
  assert_contains "$err" 'edits besides'
  assert_contains "$(cat "$entry")" '// user edit'
  echo "ok - ${tree##*/}: edited authentication clone is preserved and reported"
done
finish
