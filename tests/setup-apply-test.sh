#!/bin/bash
# What Setup's Apply reports when it is done. It runs after the window that
# asked may be gone, so its notification is the only account of how it went,
# and it is checked against the machine: an overlay still there after it was
# to be removed (overlay-clones.sh keeps a copy with edits of its own, on
# purpose) is a failure to say so, not "Setup is done".
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# apply <add> <drop> <chosen>: setup-apply.sh from a copy of the repository
# whose menu and overlay scripts are stand-ins. An overlay is installed when
# $sandbox/clones/<id> exists; installing makes it, removing refuses for one
# marked edited and deletes the rest, and FAILS names overlays whose install
# fails. MENU_FAILS=1 fails the menu rows.
apply() {
  make_sandbox "$old_omarchy"
  local copy="$sandbox/ragtop"
  mkdir -p "$copy" "$sandbox/clones"
  cp "$repo/setup-apply.sh" "$repo/i18n.sh" "$copy/"
  cp -r "$repo/i18n" "$copy/"
  printf '#!/bin/bash\n[[ -z ${MENU_FAILS:-} ]]\n' >"$copy/menu-block.sh"
  cat >"$copy/overlay-clones.sh" <<STUB
#!/bin/bash
cmd=\$1; shift
if [[ \$cmd == apply ]]; then
  add=\$1; drop=\$2
  for o in \$add; do [[ " ${FAILS:-} " == *" \$o "* ]] && exit 1; done
  for o in \$drop; do [[ -e "$sandbox/clones/\$o.edited" ]] && exit 1; done
  for o in \$add; do touch "$sandbox/clones/\$o"; done
  for o in \$drop; do rm -f "$sandbox/clones/\$o"; done
  [[ -z "${HOOK_FAILS:-}" ]] || exit 3
else
  for o in "\$@"; do [[ -e "$sandbox/clones/\$o" ]] || exit 1; done
fi

STUB
  chmod +x "$copy/menu-block.sh" "$copy/overlay-clones.sh"
  for o in ${PRESENT:-}; do touch "$sandbox/clones/$o"; done
  for o in ${EDITED:-}; do touch "$sandbox/clones/$o.edited"; done
  rc=0
  sandboxed MENU_FAILS="${MENU_FAILS:-}" STUB_RESTART_FAILS="${RESTART_FAILS:-}" bash "$copy/setup-apply.sh" "$@" >"$sandbox/out" 2>"$sandbox/err" || rc=$?
  out=$(<"$sandbox/out") err=$(<"$sandbox/err")
}

everything_done_says_so() {
  PRESENT="lock" apply "menu" "lock" "menu"
  assert_rc 0
  assert_contains "$(calls)" "notify -g 󰌌 Ragtop Setup is done." "notification"
  assert_equal "$(cat "$sandbox/home/.local/state/ragtop/install.conf")" "overlays=menu" "the record"
}

unwritten_hooks_are_reported_as_such() {
  HOOK_FAILS=1 apply "menu" "" "menu"
  assert_rc 1
  assert_contains "$(calls)" "couldn't write its hooks" "notification"
  assert_lacks "$(calls)" "Overlay changes failed" "the overlays did change"
  assert_equal "$(cat "$sandbox/home/.local/state/ragtop/install.conf")" "overlays=menu" "the record"
}

a_kept_copy_is_reported() {
  PRESENT="menu" EDITED="menu" apply "" "menu" ""
  assert_rc 1 "a removal that did not happen"
  assert_contains "$(calls)" "These are still Ragtop's copies: the Omarchy menu." "notification"
  assert_lacks "$(calls)" "Setup is done" "notification"
  assert_equal "$(cat "$sandbox/home/.local/state/ragtop/install.conf")" "overlays=menu" "the record, as the machine is"
}

a_failed_menu_is_reported() {
  MENU_FAILS=1 apply "" "" ""
  assert_rc 1
  assert_contains "$(calls)" "Ragtop's settings could not be added to Omarchy's menu." "notification"
}

a_failed_copy_does_not_restart() {
  FAILS="menu" apply "menu" "" "menu"
  assert_rc 1
  assert_contains "$(calls)" "notify" "notification"
  assert_lacks "$(calls)" "restart-shell" "a restart"
}

a_copy_restarts_once() {
  apply "menu" "" "menu"
  assert_rc 0
  assert_lacks "$(calls)" "restart-shell"
}

a_restart_that_lost_the_race_is_tried_again() {
  RESTART_FAILS=1 apply "menu" "" "menu"
  assert_rc 0
  assert_lacks "$(calls)" "restart-shell"
}

run_test "setup: overlays set but hooks unwritten are reported as such" unwritten_hooks_are_reported_as_such
run_test "setup: a setup that did everything says it is done" everything_done_says_so
run_test "setup: an overlay that could not be copied leaves the shell running" a_failed_copy_does_not_restart
run_test "setup: a completed selection uses the shell watcher without restart" a_copy_restarts_once
run_test "setup: batched setup does not depend on the restart command" a_restart_that_lost_the_race_is_tried_again
run_test "setup: a copy that could not be removed is reported, not called done" a_kept_copy_is_reported
run_test "setup: menu rows that could not be added are reported" a_failed_menu_is_reported
finish
