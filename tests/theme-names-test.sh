#!/bin/bash
# A theme folder's name goes into shell commands: the menu's checked and
# action guards, and the tour's loop over `ragtop theme list`. Only the names
# the CLI takes ([a-z0-9-], up to 32) are listed anywhere, and the menu quotes
# them besides, so a folder named like a command is never run.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# A user theme folder named <name>, holding an ordinary theme file.
user_theme() {
  mkdir -p "$sandbox/home/.config/ragtop/themes/$1"
  printf 'name = "%s"\n' "${2:-Mine}" >"$sandbox/home/.config/ragtop/themes/$1/ragtop.toml"
}
menu() { echo "$sandbox/home/.config/omarchy/extensions/omarchy-menu.jsonc"; }
marker() { echo "$sandbox/home/MARKER"; }

a_command_named_theme_is_never_listed() {
  make_sandbox "$old_omarchy"
  user_theme mine
  # shellcheck disable=SC2016  # the name is meant to hold $( ) unexpanded
  user_theme 'audit$(touch MARKER)' Audit
  user_theme 'Spaced Name'
  user_theme "$(printf 'x%.0s' {1..33})"
  user_theme "$(printf 'aaa\nzzz')"
  (cd "$sandbox/home" && sandboxed bash "$repo/menu-block.sh" add >/dev/null)
  local text
  text=$(<"$(menu)")
  assert_contains "$text" 'theme apply mine'
  assert_lacks "$text" 'audit'
  assert_lacks "$text" 'Spaced Name'
  assert_lacks "$text" 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
  # Every guard the menu would run, run: none of them may create the marker.
  /usr/bin/python3 - "$(menu)" >"$sandbox/guards" <<'PY'
import json, re, sys
# JSONC, trailing commas and all: each guard is a JSON string, read as one.
text = open(sys.argv[1]).read()
for m in re.finditer(r'"(?:checked|action|when)":\s*("(?:[^"\\]|\\.)*")', text):
    # Ragtop's command as true: what bash expands before running either is
    # the same.
    print(json.loads(m.group(1)).replace('"$HOME/.config/omarchy/plugins/sclemance.ragtop/ragtop"', "true"))
PY
  assert_contains "$(<"$sandbox/guards")" 'theme is mine'
  local line
  while IFS= read -r line; do
    [[ $line == *" theme "* ]] || continue
    (cd "$sandbox/home" && sandboxed bash -c "$line" >/dev/null 2>&1) || true
  done <"$sandbox/guards"
  assert_equal "$([[ -e $(marker) ]] && echo made)" "" "a theme guard ran the folder's name as a command"
  out=$(sandboxed bash "$repo/ragtop" theme list)
  assert_contains "$out" 'mine'
  assert_lacks "$out" 'audit'
  assert_lacks "$out" 'Spaced'
  assert_lacks "$out" 'aaa'
  assert_lacks "$out" 'zzz'
  sandboxed bash "$repo/ragtop" theme step 1 >/dev/null 2>&1 || fail "theme step failed beside an odd name"
}

# A block written before the names were checked is replaced whole by the next
# add, so an unsafe row left by an older Ragtop goes with it.
an_old_unsafe_row_is_replaced() {
  make_sandbox "$old_omarchy"
  user_theme mine
  mkdir -p "$(dirname "$(menu)")"
  cat >"$(menu)" <<'JSONC'
{
  // Ragtop: tablet settings. Added by Ragtop's installer; removed by its uninstaller.
  "setup.tablet.theme.bad": { "label": "Bad", "checked": "x theme is bad$(touch MARKER)" },
  // End of Ragtop's tablet settings.
}
JSONC
  (cd "$sandbox/home" && sandboxed bash "$repo/menu-block.sh" check) && fail "check passed a stale block"
  (cd "$sandbox/home" && sandboxed bash "$repo/menu-block.sh" add >/dev/null)
  assert_lacks "$(<"$(menu)")" 'MARKER'
  assert_contains "$(<"$(menu)")" 'theme apply mine'
}

run_test "theme names: a folder named like a command is never listed or run" a_command_named_theme_is_never_listed
run_test "theme names: an unsafe row from an older Ragtop is replaced by the next add" an_old_unsafe_row_is_replaced
finish
