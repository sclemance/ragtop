#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
selection_sandbox() {
  make_sandbox "$old_omarchy"
  mkdir -p "$sandbox/home/.config/omarchy"
  printf '%s\n' '{"version":1,"bar":{"layout":{"left":[{"id":"omarchy.menu","custom":123}],"center":[],"right":[]}},"plugins":[],"unrelated":{"keep":true}}' >"$sandbox/home/.config/omarchy/shell.json"
  cp "$sandbox/home/.config/omarchy/shell.json" "$sandbox/before.json"
}
selection_add_remove() {
  selection_sandbox
  clones apply 'menu emojis clipboard polkit image-picker lock' ''
  assert_rc 0
  assert_contains "$out" 'Applied 6 overlay selection changes together.'
  assert_lacks "$(calls)" 'clone '
  assert_lacks "$(calls)" 'remove '
  assert_equal "$(jq -r '.bar.layout.left[0].id' "$sandbox/home/.config/omarchy/shell.json")" tester.menu
  assert_equal "$(jq -r '.bar.layout.left[0].custom' "$sandbox/home/.config/omarchy/shell.json")" 123
  clones status
  assert_equal "$(printf '%s\n' "$out" | grep -c 'in sync')" 6
  clones apply '' 'menu emojis clipboard polkit image-picker lock'
  assert_rc 0
  assert_contains "$out" 'Applied 6 overlay selection changes together.'
  assert_equal "$(jq -S -c . "$sandbox/before.json")" "$(jq -S -c . "$sandbox/home/.config/omarchy/shell.json")"
  assert_no_path "$sandbox/home/.config/omarchy/hooks/post-update.d/ragtop-overlay-sync.hook"
}
selection_failure_keeps_everything() {
  selection_sandbox
  clones apply 'menu' ''
  assert_rc 0
  cp "$sandbox/home/.config/omarchy/shell.json" "$sandbox/current.json"
  echo '// user edit' >>"$plugins/tester.menu/Menu.qml"
  clones apply 'emojis' 'menu'
  assert_rc 1
  assert_file "$plugins/tester.menu/Menu.qml"
  assert_no_path "$plugins/tester.emojis"
  cmp "$sandbox/current.json" "$sandbox/home/.config/omarchy/shell.json"
  clones apply 'clipboard bogus' ''
  assert_rc 2
  assert_no_path "$plugins/tester.clipboard"
  sed -i 's/WlrKeyboardFocus.Exclusive/WlrKeyboardFocus.Different/' "$sandbox/omarchy/shell/plugins/emojis/Emojis.qml"
  clones apply 'clipboard emojis' ''
  assert_rc 1
  assert_no_path "$plugins/tester.clipboard"
  assert_no_path "$plugins/tester.emojis"
  cmp "$sandbox/current.json" "$sandbox/home/.config/omarchy/shell.json"
}
selection_preserves_disabled_sources() {
  selection_sandbox
  jq '.disabledPlugins=["omarchy.emojis"]' "$sandbox/before.json" >"$sandbox/home/.config/omarchy/shell.json"
  clones apply 'emojis' ''
  assert_rc 0
  clones apply '' 'emojis'
  assert_rc 0
  assert_equal "$(jq -c .disabledPlugins "$sandbox/home/.config/omarchy/shell.json")" '["omarchy.emojis"]'
}
selection_rejects_lock() {
  selection_sandbox
  for state in 0 2; do
    clones STUB_SESSION_LOCKED="$state" apply 'menu lock' ''
    assert_rc 1
    assert_no_path "$plugins/tester.menu"
    assert_no_path "$plugins/tester.lock"
    cmp "$sandbox/before.json" "$sandbox/home/.config/omarchy/shell.json" || fail 'locked session config changed'
  done
}
selection_concurrent() {
  selection_sandbox
  sandboxed bash "$repo/overlay-clones.sh" apply 'menu emojis' '' >"$sandbox/first.log" 2>&1 &
  local first=$!
  sandboxed bash "$repo/overlay-clones.sh" apply 'clipboard image-picker' '' >"$sandbox/second.log" 2>&1 &
  local second=$!
  wait "$first" || fail 'first concurrent selection failed'
  wait "$second" || fail 'second concurrent selection failed'
  clones status
  assert_equal "$(printf '%s\n' "$out" | grep -c 'in sync')" 4
  assert_equal "$(jq '.disabledPlugins | length' "$sandbox/home/.config/omarchy/shell.json")" 4 'both selection writes retained'
}
run_test 'locked or indeterminate sessions cannot change overlay selection' selection_rejects_lock
run_test 'concurrent selections serialize and retain both changes' selection_concurrent
run_test 'all six additions/removals publish one config and preserve placement' selection_add_remove
run_test 'invalid requests, edited clones and failed preparation leave selection intact' selection_failure_keeps_everything
run_test 'removal respects a source that was already disabled' selection_preserves_disabled_sources

batch_dirs() { compgen -G "$plugins/.ragtop-apply.*" || true; }
selection_prunes_batches() {
  selection_sandbox
  local i
  for i in 1 2 3; do
    clones apply 'menu' ''
    assert_rc 0
    clones apply '' 'menu'
    assert_rc 0
  done
  assert_equal "$(batch_dirs | wc -l)" 2 'only the newest two published batches are kept'
  local dir
  for dir in $(batch_dirs); do assert_file "$dir/.published"; done
}
selection_failure_leaves_no_batch() {
  selection_sandbox
  sed -i 's/WlrKeyboardFocus.Exclusive/WlrKeyboardFocus.Different/' "$sandbox/omarchy/shell/plugins/emojis/Emojis.qml"
  clones apply 'clipboard emojis' ''
  assert_rc 1
  assert_equal "$(batch_dirs | wc -l)" 0 'a batch that never published is let go'
  clones apply 'menu' ''
  assert_rc 0
  clones apply 'menu' ''
  assert_rc 0
  assert_equal "$(batch_dirs | wc -l)" 1 'a selection with nothing to change leaves no batch'
}
selection_lock_messages() {
  selection_sandbox
  clones STUB_SESSION_LOCKED=0 apply 'menu' ''
  assert_rc 1
  assert_contains "$err" 'The session is locked'
  clones STUB_SESSION_LOCKED=2 apply 'menu' ''
  assert_rc 1
  assert_contains "$err" 'Could not tell whether the session is locked'
  assert_lacks "$err" 'The session is locked'
}
remove_drops_only_its_own_backup() {
  make_sandbox "$old_omarchy"
  clones install menu
  assert_rc 0
  mkdir -p "$plugins/.tester.menu.bak.20200101000000"
  clones remove menu
  assert_rc 0
  assert_no_path "$plugins/tester.menu"
  assert_equal "$(compgen -G "$plugins/.tester.menu.bak.*")" "$plugins/.tester.menu.bak.20200101000000" \
    'the backup made by this removal goes, an older one stays'
}
run_test 'published selection batches are pruned to the newest two' selection_prunes_batches
run_test 'failed or empty selections leave no batch folder' selection_failure_leaves_no_batch
run_test 'a locked session and an undetermined one say different things' selection_lock_messages
run_test "removing Ragtop's clone drops Omarchy's backup of it, not older ones" remove_drops_only_its_own_backup
make_sandbox "$old_omarchy"
sandboxed /usr/bin/python3 - "$repo/overlay-publish.py" "$sandbox" <<'PYTEST'
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('publish',sys.argv[1])
p=importlib.util.module_from_spec(spec); spec.loader.exec_module(p)
root=Path(sys.argv[2]); config=root/'shell.json'
original='{"version":1,"bar":{"layout":{"left":[],"center":[],"right":[]}},"plugins":[]}\n'
config.write_text(original)
records=[]
for name in ('menu','emojis'):
    staged=root/('stage-'+name); staged.mkdir()
    (staged/'manifest.json').write_text(json.dumps({'kinds':['service']}))
    (staged/'.ragtop-base').write_text('test')
    records.append(dict(operation='add',live=str(root/('tester.'+name)),staged=str(staged),before=None))
real_move=p.move_new
calls=0
def fail_second(a,b):
    global calls
    calls+=1
    if calls==2: raise OSError('simulated second publication failure')
    real_move(a,b)
p.move_new=fail_second
try:p.apply(records,config,root/'unused-defaults')
except OSError:pass
else:raise AssertionError('move failure ignored')
assert config.read_text()==original
assert all(not Path(r['live']).exists() and Path(r['staged']).is_dir() for r in records)
print('ok - failed second addition rolls back the first and preserves config')
p.move_new=real_move
real_exchange=p.exchange
def fail_config(a,b):raise OSError('simulated config failure')
p.exchange=fail_config
try:p.apply(records,config,root/'unused-defaults')
except OSError:pass
else:raise AssertionError('config failure ignored')
assert config.read_text()==original
assert all(not Path(r['live']).exists() and Path(r['staged']).is_dir() for r in records)
print('ok - failed config publication rolls back every addition')
p.exchange=real_exchange
p.apply(records,config,root/'unused-defaults')
removals=[dict(operation='remove', live=r['live'], staged=r['staged'], before=p.signature(r['live'])) for r in records]
before=config.read_text(); p.exchange=fail_config
try:p.apply(removals,config,root/'unused-defaults')
except OSError:pass
else:raise AssertionError('removal config failure ignored')
assert config.read_text()==before
assert all(Path(r['live']).is_dir() and not Path(r['staged']).exists() for r in removals)
print('ok - failed removal publication restores every clone and config')
PYTEST
[[ $? == 0 ]] || failed=1
finish
