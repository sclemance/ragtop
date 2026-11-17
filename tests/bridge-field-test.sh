#!/bin/bash
# The bridge's field reports (fcitx-osk-bridge.py, ask_field): only the
# newest question is answered. Driven through its own D-Bus handler with the
# bus replaced, so nothing reaches fcitx5.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
out=$(sandboxed /usr/bin/python3 -I - "$repo/fcitx-osk-bridge.py" <<'PY' 2>&1
import importlib.util, io, sys
spec = importlib.util.spec_from_file_location("bridge", sys.argv[1])
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
pending, said = [], []
b.call = lambda where, method, args=None, reply=None, done=None: pending.append(done) if method == "DebugInfo" else None
b.field_of = lambda text: {"id": text}
b.say = lambda kind, value: said.append((kind, value))
b.rearm_in = lambda ms: None
b.set_engine = lambda name: None
class Invocation:
    def return_value(self, v): pass
class Params:
    def __init__(self, *a): self.a = a
    def unpack(self): return self.a
def notify(method, *args):
    b.on_call(None, None, None, None, method, Params(*args) if args else None, Invocation())
def answer(i, field):
    pending[i]((field,))
def check(ok, what):
    print(("ok - " if ok else "not ok - ") + "bridge: " + what)
# A hide, then a newer focus change while its answer is on its way.
notify("HideVirtualKeyboard")
notify("NotifyIMActivated", "keyboard-us")
answer(0, "old")
check(not any(k == "field" for k, _ in said), "an answer to a question since superseded is dropped")
answer(1, "new")
check(said[-1:] == [("field", {"id": "new"})], "the newest answer is said")
# Asked again by the service: the answer is said even if nothing changed.
said.clear()
sys.stdin = io.StringIO("field 3\n")
b.on_command(None, None)
answer(2, "new")
check(said == [("fieldtoken", 3), ("field", {"id": "new"})],
      "asked again with a number, the same field is said again, after that number")
PY
)
echo "$out"
grep -q '^not ok' <<<"$out" && failed=1
grep -q '^ok' <<<"$out" || { echo "not ok - bridge: the test ran"; failed=1; }
finish
