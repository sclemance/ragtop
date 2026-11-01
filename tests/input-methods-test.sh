#!/bin/bash
# Chinese, Japanese and Korean through the on-screen keyboard: the fcitx5
# bridge and the helper's fcitx route, run against a real fcitx5 with real
# engines, Mozc, Pinyin and Hangul. Each test gets a private fcitx5 on a bus
# of its own (dbus-run-session), with no display and its config in the
# sandbox, so the fcitx5 the session runs is never touched.
#
# The expected text is fixed, so these need no reading of the languages:
# nihongo is 日本語, nihao is 你好, and gksrmf on a Korean layout is 한글.
#
# Skipped when fcitx5, an engine or dbus-run-session is missing: they are
# what the user installs to type these languages at all, not what Ragtop
# needs.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

have() { [[ -f /usr/share/fcitx5/inputmethod/$1.conf ]]; }

# im <step ...>: runs input-methods.py in a fresh sandbox whose fcitx5 group
# holds a US layout and the three engines. Leaves what happened in $out.
im() {
  make_sandbox "$old_omarchy"
  mkdir -p "$sandbox/home/.config/fcitx5"
  cat >"$sandbox/home/.config/fcitx5/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=

[Groups/0/Items/2]
Name=pinyin
Layout=

[Groups/0/Items/3]
Name=hangul
Layout=

[GroupOrder]
0=Default
EOF
  out=$(sandboxed dbus-run-session -- /usr/bin/python3 "$tests_dir/input-methods.py" "$repo" "$@" 2>&1)
}

japanese_by_choosing() {
  im bridge:"switch mozc" route:fcitx type:nihongo pick:日本語 key:Return
  assert_contains "$out" "engine mozc"
  assert_contains "$out" "has 日本語"
  assert_contains "$out" "commit 日本語"
  assert_lacks "$out" "wayland"
}

japanese_by_converting() {
  im bridge:"switch mozc" route:fcitx type:nihongo key:space key:Return
  assert_contains "$out" "commit 日本語"
}

chinese_commits_on_choosing() {
  im bridge:"switch pinyin" route:fcitx type:nihao pick:你好
  assert_contains "$out" "engine pinyin"
  assert_contains "$out" "commit 你好"
}

korean_needs_no_candidates() {
  im bridge:"switch hangul" route:fcitx type:gksrmf key:space
  assert_contains "$out" "engine hangul"
  assert_contains "$out" "commit 한
commit 글
forward space"
}

shortcuts_stay_wayland() {
  im bridge:"switch mozc" route:fcitx key:"c ctrl"
  assert_contains "$out" "wayland"
  assert_lacks "$out" "commit"
}

deactivating_says_so() {
  im bridge:"switch mozc" bridge:deactivate
  assert_contains "$out" "engine mozc
engine null"
}

# A key from another keyboard is passed on as a hide, which is how the
# service learns that the word it was following has been typed over.
another_keyboard_is_reported() {
  im other:a
  assert_contains "$out" "hide"
}

# Keys through fcitx5's own interface are the on-screen keyboard's, and
# say nothing of the kind.
own_keys_are_not_reported() {
  im bridge:"switch mozc" route:fcitx type:ka
  assert_lacks "$out" "hide"
}

# What kind of field has focus, read from fcitx5's DebugInfo: a password
# field (fcitx5's Password flag, 0x8), a terminal (Terminal, 1 << 32), and a
# plain one. The service keeps nothing typed into the first. Read from the
# report's real shape, copied from a session: a private fcitx5 with no
# display puts its contexts in no group, and those it lists without their
# flags, so a live test could not show this. Needs no fcitx5, so it runs
# before the check for one.
fields_are_told_apart() {
  make_sandbox "$old_omarchy"
  out=$(sandboxed /usr/bin/python3 - "$repo/fcitx-osk-bridge.py" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bridge", sys.argv[1])
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
report = """Group [wayland:] has 3 InputContext(s)
  IC [5d2f] program:omawrite frontend:wayland_v2 cap:100000072 focus:{w}
  IC [8911] program:KeePassXC frontend:wayland_v2 cap:{k} focus:{p}
Group [x11::0] has 1 InputContext(s)
  IC [5f00] program:keepassxc frontend:dbus cap:{e} focus:{x}
Input Context without group
  IC [d9b5] program:t frontend:dbus focus:{g}
"""
def show(**focus):
    f = dict(w=0, p=0, x=0, g=0, k="72", e="72")
    f.update(focus)
    field = b.field_of(report.format(**f))
    print((field["id"] + " " + (",".join(k for k in ("password", "terminal", "noCapitals") if field[k]) or "plain"))
          if field else "null")
show(w=1)                       # a terminal's context: Terminal, 1 << 32
show(p=1, k="7a")               # a password field: Password, 0x8
show(x=1, e="1000000072")       # a sensitive one: Sensitive, 1 << 36
show(p=1, k="1072")             # a URL field: Url, 1 << 12
show(p=1)                       # plain text
show()                          # nothing focused
show(g=1)                       # focused, but listed without its flags
show(w=1, p=1)                  # two focused: no telling which
PY
)
  assert_equal "$out" "5d2f terminal,noCapitals
8911 password,noCapitals
5f00 password,noCapitals
8911 noCapitals
8911 plain
null
null
null"
}

# Which field has focus is asked after every show and every hide, and the
# answers can come back in any order. One older than an answer already
# printed is about a field that may have lost focus since, and is dropped;
# the same field reported twice is printed once.
field_answers_in_order() {
  make_sandbox "$old_omarchy"
  out=$(sandboxed /usr/bin/python3 - "$repo/fcitx-osk-bridge.py" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("bridge", sys.argv[1])
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
pending = []
b.call = lambda where, method, args=None, reply=None, done=None: pending.append(done)
b.say = lambda kind, value: kind == "field" and print(kind, value["id"] if value else None)
one = ("IC [aaaa] program:x frontend:wayland_v2 cap:72 focus:1\n",)
two = ("IC [bbbb] program:x frontend:wayland_v2 cap:72 focus:1\n",)
none = ("IC [aaaa] program:x frontend:wayland_v2 cap:72 focus:0\n",)
b.ask_field(); b.ask_field(); b.ask_field()
pending[1](two)     # the second answer first
pending[0](one)     # older than it: dropped
pending[2](two)     # the same field again: nothing new
b.ask_field()
pending[3](none)    # focus left every field
# A field takes focus: the answer to a question asked before it is about the
# field that had focus then, and is dropped; the answer after it is said even
# when it is a field already said, since the service waits to hear it.
b.arming = False
b.ask_field()                                   # asked before the show
b.on_call(None, "", "", "", "ShowVirtualKeyboard", None, type("I", (), {"return_value": lambda s, v: None})())
pending[4](one)     # the earlier question: dropped
pending[5](none)    # the show's own question
b.on_call(None, "", "", "", "ShowVirtualKeyboard", None, type("I", (), {"return_value": lambda s, v: None})())
pending[6](none)    # the same answer again, said again
# A hide: an answer to a question asked before it is dropped, and the
# hide's own is said even when nothing changed, since the service holds
# what is typed apart until it hears.
b.ask_field()                                   # asked before the hide
b.on_call(None, "", "", "", "HideVirtualKeyboard", None, type("I", (), {"return_value": lambda s, v: None})())
b.rearm_source = 1                              # no timer: there is no main loop here
pending[7](one)     # before the hide: dropped
pending[8](none)    # the hide's own, the same as last said: said again
# fcitx5 goes: an answer still on its way from it is dropped.
b.ask_field()
b.on_fcitx_vanished(None, "")
pending[9](one)
PY
)
  assert_equal "$out" "field bbbb
field None
show
field None
show
field None
hide
field None"
}

# Without the route, keys go the Wayland way and fcitx5 never hears them
# from here. That is today's behaviour on a plain layout, and stays it.
wayland_route_is_untouched() {
  im route:wayland type:ab
  assert_equal "$(grep -c '^wayland' <<<"$out")" 2 "keys sent the Wayland way"
  assert_lacks "$out" "commit"
}

run_test "input methods: a password field, a terminal and a plain field are told apart" fields_are_told_apart
run_test "input methods: an answer about the focused field older than one printed is dropped" field_answers_in_order

missing=""
for need in fcitx5 dbus-run-session; do
  command -v "$need" >/dev/null || missing+=" $need"
done
for pair in mozc:fcitx5-mozc pinyin:fcitx5-chinese-addons hangul:fcitx5-hangul; do
  have "${pair%%:*}" || missing+=" ${pair#*:}"
done
if [[ -n $missing ]]; then
  echo "ok - input methods # SKIP not installed:$missing"
  finish
  exit 0
fi

run_test "input methods: Japanese, choosing 日本語 from the strip" japanese_by_choosing
run_test "input methods: Japanese, converting with Space" japanese_by_converting
run_test "input methods: Chinese commits the candidate tapped" chinese_commits_on_choosing
run_test "input methods: Korean composes with no candidates at all" korean_needs_no_candidates
run_test "input methods: a shortcut goes the Wayland way, for Hyprland" shortcuts_stay_wayland
run_test "input methods: switching back to the layout is reported" deactivating_says_so
run_test "input methods: the Wayland route is what it was" wayland_route_is_untouched
run_test "input methods: a key from another keyboard is reported" another_keyboard_is_reported
run_test "input methods: the keyboard's own keys through fcitx5 are not" own_keys_are_not_reported
finish
