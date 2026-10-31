#!/bin/bash
# Batched refreshes preserve active IDs/config and publish only finished clones.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

all_six_refresh_without_per_clone_ipc() {
  make_sandbox "$old_omarchy"
  mkdir -p "$sandbox/home/.config/omarchy"
  printf '%s\n' '{"version":1,"bar":{"layout":{"left":[{"id":"omarchy.menu","custom":123}],"right":[],"center":[]}},"plugins":[],"unrelated":{"keep":true}}' >"$sandbox/home/.config/omarchy/shell.json"
  clones install
  assert_rc 0
  cp "$sandbox/home/.config/omarchy/shell.json" "$sandbox/before.json"
  : >"$sandbox/calls.log"
  switch_omarchy "$new_omarchy"
  clones sync menu menu emojis clipboard polkit image-picker lock
  assert_rc 0
  assert_contains "$out" 'Applied 6 overlay replacements together.'
  assert_lacks "$(calls)" 'remove '
  assert_lacks "$(calls)" 'clone '
  cmp "$sandbox/before.json" "$sandbox/home/.config/omarchy/shell.json"
  clones status
  assert_lacks "$out" 'edits besides'
  assert_equal "$(printf '%s\n' "$out" | grep -c 'in sync')" 6
  clones sync
  assert_rc 0
  assert_lacks "$out" 'Applied '
}
run_test 'all six refresh together with no enable/disable IPC or config churn' all_six_refresh_without_per_clone_ipc

make_sandbox "$old_omarchy"
sandboxed /usr/bin/python3 - "$repo/overlay-publish.py" "$sandbox" <<'PY'
import importlib.util
from pathlib import Path
import sys
spec = importlib.util.spec_from_file_location('publish', sys.argv[1])
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
root = Path(sys.argv[2])

def pair(name):
    live, staged = root / (name + '-live'), root / (name + '-staged')
    live.mkdir(); staged.mkdir()
    (live / 'content').write_text('old')
    (staged / 'content').write_text('new')
    (staged / '.ragtop-base').write_text('test\n6\n')
    return dict(live=str(live), staged=str(staged), before=p.signature(live))

# A preparation failure or a later external edit must touch no live clone.
a, b = pair('first'), pair('second')
Path(b['staged'], '.ragtop-base').unlink()
try: p.publish([a, b])
except ValueError: pass
else: raise AssertionError('unpatched replacement accepted')
assert Path(a['live'], 'content').read_text() == 'old'
print('ok - incomplete replacement prevents the whole publication')
Path(b['staged'], '.ragtop-base').write_text('test\n6\n')
Path(b['live'], 'content').write_text('user edit')
try: p.publish([a, b])
except ValueError: pass
else: raise AssertionError('external edit overwritten')
assert Path(a['live'], 'content').read_text() == 'old'
assert Path(b['live'], 'content').read_text() == 'user edit'
print('ok - external edits during preparation abort publication')

# Failure of the second exchange must roll back the first exchange.
b['before'] = p.signature(b['live'])
real_exchange = p.exchange
calls = 0
def fail_second(first, second):
    global calls
    calls += 1
    if calls == 2: raise OSError('simulated exchange failure')
    real_exchange(first, second)
p.exchange = fail_second
try: p.publish([a, b])
except OSError: pass
else: raise AssertionError('exchange failure ignored')
assert Path(a['live'], 'content').read_text() == 'old'
assert Path(b['live'], 'content').read_text() == 'user edit'
print('ok - failed exchange rolls back already published clones')
p.exchange = real_exchange
p.publish([a, b])
assert all(Path(r['live'], 'content').read_text() == 'new' for r in [a, b])
assert Path(a['staged'], 'content').read_text() == 'old'
assert Path(b['staged'], 'content').read_text() == 'user edit'
print('ok - successful exchanges retain old copies as backups')
PY
[[ $? == 0 ]] || failed=1
finish
