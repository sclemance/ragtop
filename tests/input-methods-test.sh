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

# Without the route, keys go the Wayland way and fcitx5 never hears them
# from here. That is today's behaviour on a plain layout, and stays it.
wayland_route_is_untouched() {
  im route:wayland type:ab
  assert_equal "$(grep -c '^wayland' <<<"$out")" 2 "keys sent the Wayland way"
  assert_lacks "$out" "commit"
}

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
finish
