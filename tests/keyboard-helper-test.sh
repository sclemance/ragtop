#!/bin/bash
# keyboard-helper.py's lookups: which key and modifiers type a character. A
# password typed on the on-screen keyboard goes through them, so they must
# run in the helper's own process. A character on a command line can be read
# by any local user from /proc.
#
# This loads the helper as a module, in the sandbox, without connecting to a
# compositor. It needs libxkbcommon and its xkbcli-compile-keymap.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"

# The helper loaded as a module `h`, with every process it starts recorded in
# `started`, and US the plain US layout.
read -r -d '' prelude <<'PY'
import importlib.util, subprocess, sys
spec = importlib.util.spec_from_file_location("helper", sys.argv[1])
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)
started = []
real_popen = subprocess.Popen
class Recording(real_popen):
    def __init__(self, args, *rest, **kw):
        started.append(args)
        super().__init__(args, *rest, **kw)
subprocess.Popen = Recording
US = {"rules": "", "model": "", "layout": "us", "variant": "", "options": ""}
PY

# helper <python>: runs the snippet after the prelude. Leaves stdout in $out.
helper() {
  out=$(sandboxed /usr/bin/python3 -c "$prelude
$1" "${HELPER:-$tests_dir/../keyboard-helper.py}" 2>&1)
}

lookups_start_no_process() {
  helper '
km = h.Keymap(US, 0)
before = len(started)
for c in "pässwörd€Ωж✓ A1-":
    km.lookup(c)
km.lookup("BackSpace", keysym=True)
print(len(started) - before)'
  assert_equal "$out" "0" "processes started by lookups"
}

lookups_find_the_key() {
  helper '
km = h.Keymap(US, 0)
for t, k in [("a", False), ("A", False), ("!", False), (" ", False), ("BackSpace", True), ("Shift_L", True), ("é", False)]:
    print(t, km.lookup(t, keysym=k))'
  assert_equal "$out" "a (30, set())
A (30, {'shift'})
! (2, {'shift'})
  (57, set())
BackSpace (14, set())
Shift_L (42, set())
é None"
}

lookups_follow_the_active_layout() {
  helper '
names = dict(US, layout="us,fr")
for group in (0, 1):
    km = h.Keymap(names, group)
    print(group, km.lookup("a"), km.lookup("é"), km.lookup("Return", keysym=True))'
  assert_equal "$out" "0 (30, set()) None (28, set())
1 (16, set()) (3, set()) (28, set())"
}

run_test "keyboard helper: looking up a character starts no process" lookups_start_no_process
run_test "keyboard helper: finds the key and modifiers for a character or keysym" lookups_find_the_key
run_test "keyboard helper: answers for the active layout, and named keys for any" lookups_follow_the_active_layout
finish
