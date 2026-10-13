#!/bin/bash
# overlay-clones.sh, run for real against copies of two Omarchy trees: 4.0.4,
# whose overlays are each a window of their own, and 7cc6a55, where four of
# them became instances of the shared OverlayWindow.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

all=(menu emojis clipboard polkit image-picker lock)
declare -A entry=([menu]=Menu.qml [emojis]=Emojis.qml [clipboard]=Clipboard.qml
                  [polkit]=PolkitAgent.qml [image-picker]=ImagePicker.qml [lock]=LockView.qml)
hook=".config/omarchy/hooks/post-update.d/ragtop-overlay-sync.hook"

clone_of() { echo "$plugins/tester.$1"; }
entry_of() { echo "$plugins/tester.$1/${entry[$1]}"; }
progress_files() { find "$plugins" -maxdepth 1 -name '.ragtop-cloning-*' 2>/dev/null; }

# --- Omarchy 4.0.4: a surface per open -------------------------------------

old_install_patches_every_overlay() {
  make_sandbox "$old_omarchy"
  clones install
  assert_rc 0
  for o in "${all[@]}"; do
    assert_contains "$out" "Cloned and patched tester.$o."
    assert_equal "$(count_in "$(entry_of "$o")" 'id: ragtopMode')" 1 "mode readers in $o"
    assert_equal "$(wc -l <"$(clone_of "$o")/.ragtop-base")" 2 "lines in $o's .ragtop-base"
    assert_equal "$(jq -r .omarchy.clonedFrom "$(clone_of "$o")/manifest.json")" "omarchy.$o"
  done
  assert_equal "$(progress_files)" "" "progress markers left behind"
  assert_file "$sandbox/home/$hook"
  clones installed
  assert_rc 0
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, in sync with the built-in"; done
  assert_lacks "$out" "edits besides"
}

old_patch_is_the_event_driven_one() {
  make_sandbox "$old_omarchy"
  clones install menu image-picker polkit
  assert_rc 0
  local menu picker
  menu=$(<"$(entry_of menu)")
  picker=$(<"$(entry_of image-picker)")
  assert_contains "$menu" 'WlrLayershell.keyboardFocus: ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive'
  assert_contains "$menu" 'exclusionMode: ragtopMode.tablet ? ExclusionMode.Normal : ExclusionMode.Ignore'
  assert_contains "$menu" 'visible: root.opened && root.rowsLoaded'
  assert_contains "$menu" 'ragtopAppLibrary'
  assert_contains "$picker" 'root.opened && root.imagesLoaded ? (ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None'
  # Nothing but the entry file is touched or added on this Omarchy.
  assert_no_path "$(clone_of menu)/RagtopOverlayWindow.qml"
  assert_equal "$(cd "$(clone_of polkit)" && ls -A | LC_ALL=C sort | tr '\n' ' ')" ".ragtop-base PolkitAgent.qml PolkitModel.js manifest.json "
}

old_installed_fails_without_a_clone() {
  make_sandbox "$old_omarchy"
  clones install menu
  clones installed menu
  assert_rc 0
  clones installed menu emojis
  assert_rc 1
  clones status emojis
  assert_contains "$out" "emojis: not installed"
}

old_remove_takes_clones_and_hook_away() {
  make_sandbox "$old_omarchy"
  clones install
  clones remove menu
  assert_rc 0
  assert_contains "$out" "Removed tester.menu."
  assert_no_path "$(clone_of menu)"
  assert_file "$sandbox/home/$hook"
  clones remove
  assert_rc 0
  for o in "${all[@]}"; do assert_no_path "$(clone_of "$o")"; done
  assert_no_path "$sandbox/home/$hook"
}

old_edited_clone_is_left_alone() {
  make_sandbox "$old_omarchy"
  clones install menu
  echo '// mine' >>"$(entry_of menu)"
  clones status menu
  assert_contains "$out" "menu: note: the clone has edits besides Ragtop's"
  clones remove menu
  assert_rc 1
  assert_contains "$err" "has edits besides Ragtop's"
  echo '// upstream moved' >>"$sandbox/omarchy/shell/plugins/menu/Menu.qml"
  clones sync menu
  assert_rc 1
  assert_contains "$err" "has edits besides Ragtop's, so not replacing it"
  assert_contains "$(<"$(entry_of menu)")" '// mine'
  assert_lacks "$(calls)" "remove tester.menu"
}

old_somebody_elses_clone_is_left_alone() {
  make_sandbox "$old_omarchy"
  sandboxed omarchy plugin clone omarchy.menu >/dev/null
  clones install menu
  assert_rc 1
  assert_contains "$err" "exists but isn't Ragtop's, so leaving it alone"
  clones remove menu
  assert_rc 1
  assert_file "$(entry_of menu)"
  assert_lacks "$(calls)" "remove"
}

old_sync_follows_the_built_in() {
  make_sandbox "$old_omarchy"
  clones install menu emojis
  clones sync
  assert_rc 0
  assert_contains "$out" "tester.menu matches the built-in, so nothing to sync."
  echo '// upstream moved' >>"$sandbox/omarchy/shell/plugins/menu/Menu.qml"
  clones status menu
  assert_contains "$out" "menu: installed, built-in has changed"
  clones sync
  assert_rc 0
  assert_contains "$out" "Re-cloned tester.menu from the updated built-in."
  assert_contains "$out" "tester.emojis matches the built-in, so nothing to sync."
  assert_contains "$(<"$(entry_of menu)")" '// upstream moved'
  assert_contains "$(calls)" "notify -g 󰌌 Ragtop Overlay clones updated."
  clones status menu
  assert_contains "$out" "menu: installed, in sync with the built-in"
}

old_failed_patch_leaves_no_clone() {
  make_sandbox "$old_omarchy"
  sed -i 's/WlrKeyboardFocus.Exclusive/WlrKeyboardFocus.Different/' "$sandbox/omarchy/shell/plugins/emojis/Emojis.qml"
  clones install emojis
  assert_rc 1
  assert_contains "$err" "Couldn't patch tester.emojis, so it was removed and Omarchy's own emojis stays in use."
  assert_no_path "$(clone_of emojis)"
  assert_equal "$(progress_files)" "" "progress markers left behind"
  clones installed emojis
  assert_rc 1
}

old_failed_clone_and_interrupted_run_recover() {
  make_sandbox "$old_omarchy"
  clones STUB_FAIL_CLONE=menu install menu
  assert_rc 1
  assert_contains "$err" "Couldn't clone omarchy.menu."
  assert_no_path "$(clone_of menu)"
  # A run cut short between cloning and patching leaves a marker and a bare
  # clone. Both sync and install finish the job rather than refuse it.
  sandboxed omarchy plugin clone omarchy.menu >/dev/null
  : >"$plugins/.ragtop-cloning-menu"
  clones sync menu
  assert_rc 0
  assert_contains "$out" "Finished an interrupted tester.menu clone."
  assert_equal "$(count_in "$(entry_of menu)" 'id: ragtopMode')" 1
  assert_equal "$(progress_files)" "" "progress markers left behind"
}

# --- Omarchy 7cc6a55: the shared OverlayWindow ------------------------------

helper_of() { echo "$plugins/tester.$1/RagtopOverlayWindow.qml"; }

new_menu_gets_a_window_of_its_own() {
  make_sandbox "$new_omarchy"
  clones install menu
  assert_rc 0
  assert_contains "$out" "Cloned and patched tester.menu."
  local menu
  menu=$(<"$(entry_of menu)")
  assert_equal "$(count_in "$(entry_of menu)" 'id: ragtopMode')" 1 "mode readers in menu"
  assert_contains "$menu" $'\n  RagtopOverlayWindow {\n    id: panel\n    ragtopTablet: ragtopMode.tablet\n'
  assert_lacks "$menu" $'\n  OverlayWindow {'
  # What the entry file asks of its window is not Ragtop's to change.
  assert_contains "$menu" $'\n    shown: root.opened && root.rowsLoaded\n    WlrLayershell.namespace: "omarchy-menu"\n'
  assert_contains "$menu" 'ragtopAppLibrary'
  assert_file "$(helper_of menu)"
  assert_equal "$(progress_files)" "" "progress markers left behind"
}

shared_windows=(menu emojis clipboard image-picker)

new_install_patches_every_overlay() {
  make_sandbox "$new_omarchy"
  clones install
  assert_rc 0
  for o in "${all[@]}"; do
    assert_contains "$out" "Cloned and patched tester.$o."
    assert_equal "$(count_in "$(entry_of "$o")" 'id: ragtopMode')" 1 "mode readers in $o"
    assert_equal "$(jq -r .omarchy.clonedFrom "$(clone_of "$o")/manifest.json")" "omarchy.$o"
  done
  for o in "${shared_windows[@]}"; do
    assert_file "$(helper_of "$o")"
    assert_contains "$(<"$(entry_of "$o")")" $'\n  RagtopOverlayWindow {\n    id: panel\n    ragtopTablet: ragtopMode.tablet\n'
  done
  # The image picker's own focus gate is still the entry file's to state.
  assert_contains "$(<"$(entry_of image-picker)")" $'\n    shown: root.opened\n    shownKeyboardFocus: root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n    WlrLayershell.namespace: "omarchy-image-selector"\n'
  # The password prompt and the lock screen are windows of their own still,
  # and keep the patch and the capability they had.
  assert_no_path "$(helper_of polkit)"
  assert_no_path "$(helper_of lock)"
  assert_contains "$(<"$(entry_of polkit)")" 'WlrLayershell.keyboardFocus: ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive'
  assert_contains "$(<"$(entry_of lock)")" 'sclemance.ragtop/LockKeyboard.qml'
  assert_equal "$(jq -c .omarchy.capabilities "$(clone_of polkit)/manifest.json")" '["authentication"]'
  assert_equal "$(jq -c .omarchy.capabilities "$(clone_of lock)/manifest.json")" '["authentication"]'
  # Omarchy's own component is read, never written.
  cmp -s "$sandbox/omarchy/shell/Ui/OverlayWindow.qml" "$new_omarchy/shell/Ui/OverlayWindow.qml" || fail "the shared OverlayWindow was modified"
  assert_equal "$(progress_files)" "" "progress markers left behind"
  clones installed
  assert_rc 0
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, in sync with the built-in"; done
  assert_lacks "$out" "edits besides"
  clones sync
  assert_rc 0
  for o in "${all[@]}"; do assert_contains "$out" "tester.$o matches the built-in, so nothing to sync."; done
  assert_lacks "$(calls)" "remove"
}

new_remove_takes_clones_and_hook_away() {
  make_sandbox "$new_omarchy"
  clones install
  clones remove menu
  assert_rc 0
  assert_contains "$out" "Removed tester.menu."
  assert_no_path "$(clone_of menu)"
  assert_file "$sandbox/home/$hook"
  clones remove
  assert_rc 0
  for o in "${all[@]}"; do assert_no_path "$(clone_of "$o")"; done
  assert_no_path "$sandbox/home/$hook"
}

new_edited_window_is_left_alone() {
  make_sandbox "$new_omarchy"
  clones install menu emojis clipboard
  assert_rc 0

  # An edit of the user's own in the generated window.
  echo '// mine' >>"$(helper_of menu)"
  clones status menu
  assert_contains "$out" "menu: note: the clone has edits besides Ragtop's"
  clones remove menu
  assert_rc 1 "an edited window"
  assert_contains "$err" "has edits besides Ragtop's"
  echo '// upstream moved' >>"$sandbox/omarchy/shell/plugins/menu/Menu.qml"
  clones sync menu
  assert_rc 1 "an edited window"
  assert_contains "$err" "has edits besides Ragtop's, so not replacing it"
  assert_contains "$(<"$(helper_of menu)")" '// mine'

  # One of Ragtop's own lines changed by hand.
  sed -i 's/interval: 75/interval: 5000/' "$(helper_of emojis)"
  clones remove emojis
  assert_rc 1 "a window with a Ragtop line changed"

  # The window deleted.
  rm "$(helper_of clipboard)"
  clones remove clipboard
  assert_rc 1 "a missing window"
  assert_file "$(entry_of clipboard)"

  assert_lacks "$(calls)" "remove"
}

old_stray_window_file_is_an_edit() {
  make_sandbox "$old_omarchy"
  clones install menu
  cp "$new_omarchy/shell/Ui/OverlayWindow.qml" "$(helper_of menu)"
  clones remove menu
  assert_rc 1 "a file Ragtop never put there"
  assert_file "$(helper_of menu)"
}

new_sync_follows_the_shared_window() {
  make_sandbox "$new_omarchy"
  clones install
  # Omarchy changes OverlayWindow and not one of the plugins that use it.
  echo '// upstream moved' >>"$sandbox/omarchy/shell/Ui/OverlayWindow.qml"
  clones status
  for o in "${shared_windows[@]}"; do assert_contains "$out" "$o: installed, built-in has changed"; done
  assert_contains "$out" "polkit: installed, in sync with the built-in"
  assert_contains "$out" "lock: installed, in sync with the built-in"
  clones sync
  assert_rc 0
  for o in "${shared_windows[@]}"; do
    assert_contains "$out" "Re-cloned tester.$o from the updated built-in."
    assert_contains "$(<"$(helper_of "$o")")" '// upstream moved'
    assert_contains "$(<"$(helper_of "$o")")" 'ragtopTablet'
  done
  assert_contains "$out" "tester.polkit matches the built-in, so nothing to sync."
  assert_contains "$out" "tester.lock matches the built-in, so nothing to sync."
  assert_lacks "$(calls)" "remove tester.polkit"
  assert_lacks "$(calls)" "remove tester.lock"
  assert_contains "$(calls)" "notify -g 󰌌 Ragtop Overlay clones updated."
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, in sync with the built-in"; done
  assert_lacks "$out" "edits besides"
}

new_edited_clone_survives_a_shared_window_change() {
  make_sandbox "$new_omarchy"
  clones install menu emojis
  echo '// mine' >>"$(entry_of menu)"
  echo '// mine' >>"$(helper_of emojis)"
  echo '// upstream moved' >>"$sandbox/omarchy/shell/Ui/OverlayWindow.qml"
  clones sync
  assert_rc 1
  assert_contains "$err" "The built-in menu changed, but tester.menu has edits besides Ragtop's, so not replacing it."
  assert_contains "$err" "The built-in emojis changed, but tester.emojis has edits besides Ragtop's, so not replacing it."
  assert_contains "$(<"$(entry_of menu)")" '// mine'
  assert_contains "$(<"$(helper_of emojis)")" '// mine'
  assert_lacks "$(calls)" "remove"
  assert_contains "$(calls)" "notify -g 󰌌 Ragtop Your menu clone has edits of its own, so it wasn't resynced."
}

# --- What Ragtop's service is told -----------------------------------------

everything_in_the_sandbox() { (cd "$sandbox" && find home run omarchy -printf '%p %s %T@\n' | LC_ALL=C sort); }

# Omarchy's four shared-window overlays as omacom/omarchy#13193 first had
# them: cooperative focus an overlay opts into, off until shell.json asks.
give_omarchy_cooperative_focus() {
  local o
  for o in "${shared_windows[@]}"; do
    sed -i '/^  OverlayWindow {$/{n;s/$/\n    cooperativeFocus: !!root.shell \&\& root.shell.overlaysCooperativeFocus === true/}' \
      "$sandbox/omarchy/shell/plugins/$o/${entry[$o]}"
  done
}
# And as it has them since: the overlay hands the shell's setting on, and the
# shared window cooperates by itself unless told otherwise.
give_omarchy_automatic_cooperative_focus() {
  local o
  for o in "${shared_windows[@]}"; do
    sed -i '/^  OverlayWindow {$/{n;s/$/\n    cooperativeFocus: root.shell ? root.shell.overlaysCooperativeFocus : false\n    ownReservedSpace: root.shell ? root.shell.barReservedSpace : [0, 0, 0, 0]/}' \
      "$sandbox/omarchy/shell/plugins/$o/${entry[$o]}"
  done
  sed -i '0,/^  property bool shown: false$/s//&\n  property var cooperativeFocus: false\n  readonly property bool cooperative: cooperativeFocus === true || (cooperativeFocus === "auto" \&\& competingSurface \&\& cooperationSettled)/' \
    "$sandbox/omarchy/shell/Ui/OverlayWindow.qml"
  grep -qF 'cooperativeFocus === "auto"' "$sandbox/omarchy/shell/Ui/OverlayWindow.qml" || fail "the fixture's shared window was not given automatic cooperative focus"
}
shell_json() { mkdir -p "$sandbox/home/.config/omarchy"; echo "$1" >"$sandbox/home/.config/omarchy/shell.json"; }

tappable_names_ragtops_clones() {
  local before
  for tree in "$old_omarchy" "$new_omarchy"; do
    make_sandbox "$tree"
    clones tappable
    assert_rc 0
    assert_equal "$out" "" "tappable with nothing installed"
    clones install menu polkit image-picker lock
    before=$(everything_in_the_sandbox)
    clones tappable
    assert_rc 0
    assert_equal "$out" $'menu\npolkit\nimage-picker'
    assert_equal "$(everything_in_the_sandbox)" "$before" "the sandbox after asking"
  done
}

tappable_names_omarchys_cooperative_overlays() {
  make_sandbox "$new_omarchy"
  give_omarchy_cooperative_focus

  # Off unless shell.json says so, in so many words.
  clones tappable
  assert_equal "$out" "" "tappable with no shell.json"
  shell_json '{"version": 1}'
  clones tappable
  assert_equal "$out" "" "tappable with the setting absent"
  shell_json '{"overlays": {"cooperativeFocus": false}}'
  clones tappable
  assert_equal "$out" "" "tappable with the setting off"
  shell_json '{"overlays": {"cooperativeFocus": "true"}}'
  clones tappable
  assert_equal "$out" "" "tappable with the setting a string"
  shell_json 'not json'
  clones tappable
  assert_rc 0
  assert_equal "$out" "" "tappable with a shell.json that does not parse"

  # On: the four that opt in, and not the password prompt, which does not.
  shell_json '{"overlays": {"cooperativeFocus": true}}'
  clones tappable
  assert_rc 0
  assert_equal "$out" $'menu\nemojis\nclipboard\nimage-picker'

  # On an Omarchy without it the setting alone means nothing.
  switch_omarchy "$new_omarchy"
  clones tappable
  assert_equal "$out" "" "tappable on an Omarchy with no cooperative focus"
  give_omarchy_cooperative_focus

  # Somebody else's clone stands in for the built-in and is not vouched for.
  sandboxed omarchy plugin clone omarchy.emojis >/dev/null
  clones tappable
  assert_equal "$out" $'menu\nclipboard\nimage-picker'
  # Ragtop's own counts whatever the setting says.
  shell_json '{"version": 1}'
  clones install menu
  clones tappable
  assert_equal "$out" "menu"
}

run_test "tappable: names Ragtop's clones, on both Omarchys, and writes nothing" tappable_names_ragtops_clones
tappable_follows_omarchys_automatic_cooperative_focus() {
  make_sandbox "$new_omarchy"
  give_omarchy_automatic_cooperative_focus
  local four=$'menu\nemojis\nclipboard\nimage-picker'

  # On unless shell.json says false, in so many words. Anything else is what
  # that Omarchy reads as automatic.
  clones tappable
  assert_rc 0
  assert_equal "$out" "$four" "tappable with no shell.json"
  shell_json '{"version": 1}'
  clones tappable
  assert_equal "$out" "$four" "tappable with the setting absent"
  shell_json '{"overlays": {"cooperativeFocus": "auto"}}'
  clones tappable
  assert_equal "$out" "$four" "tappable with the setting automatic"
  shell_json '{"overlays": {"cooperativeFocus": "false"}}'
  clones tappable
  assert_equal "$out" "$four" "tappable with the setting a string"
  shell_json 'not json'
  clones tappable
  assert_rc 0
  assert_equal "$out" "$four" "tappable with a shell.json that does not parse"
  shell_json '{"overlays": {"cooperativeFocus": true}}'
  clones tappable
  assert_equal "$out" "$four" "tappable with the setting on"

  shell_json '{"overlays": {"cooperativeFocus": false}}'
  clones tappable
  assert_rc 0
  assert_equal "$out" "" "tappable with the setting off"

  # Somebody else's clone stands in for the built-in and is not vouched for.
  shell_json '{"version": 1}'
  sandboxed omarchy plugin clone omarchy.emojis >/dev/null
  clones tappable
  assert_equal "$out" $'menu\nclipboard\nimage-picker'
}

run_test "tappable: names Omarchy's own overlays only where they cooperate and the setting is on" tappable_names_omarchys_cooperative_overlays
run_test "tappable: names Omarchy's own overlays unless the setting is off, where they cooperate by themselves" tappable_follows_omarchys_automatic_cooperative_focus

# --- Shapes nobody has read ------------------------------------------------
#
# A clone Ragtop cannot patch with confidence is worse than none: it is a
# stale copy of the built-in at best. Each of these has to end with no clone,
# no marker, and Omarchy's own overlay still in use.

# refused <overlay> <what was wrong>, with the sandbox's Omarchy already bent
refused() {
  clones install "$1"
  assert_rc 1 "$2"
  assert_contains "$err" "Couldn't patch tester.$1, so it was removed and Omarchy's own $1 stays in use." "stderr for $2"
  assert_no_path "$(clone_of "$1")"
  assert_equal "$(progress_files)" "" "progress markers left behind after $2"
  clones installed "$1"
  assert_rc 1 "$2"
}

unknown_shared_window_is_refused() {
  local window=shell/Ui/OverlayWindow.qml

  make_sandbox "$new_omarchy"
  rm "$sandbox/omarchy/$window"
  refused menu "no shared OverlayWindow to copy"

  make_sandbox "$new_omarchy"
  sed -i 's/^  WlrLayershell.keyboardFocus: shownKeyboardFocus$/  WlrLayershell.keyboardFocus: shown ? shownKeyboardFocus : WlrKeyboardFocus.None/' "$sandbox/omarchy/$window"
  refused menu "a focus line Ragtop has not read"

  make_sandbox "$new_omarchy"
  sed -i 's/  exclusionMode: ExclusionMode.Ignore/  exclusionMode: ExclusionMode.Auto/' "$sandbox/omarchy/$window"
  refused emojis "an exclusion line Ragtop has not read"

  # The wait for full-screen geometry is what would keep a clone invisible
  # out of reserved space, so a wait written another way is not guessed at.
  make_sandbox "$new_omarchy"
  sed -i 's/ && height === targetScreen.height$/ \&\& height >= targetScreen.height/' "$sandbox/omarchy/$window"
  refused clipboard "a geometry wait Ragtop has not read"

  # That the surface maps per open is Omarchy's, unpatched, and both the
  # focus prime and Ragtop's service go by it.
  make_sandbox "$new_omarchy"
  sed -i 's/^  visible: shown .*$/  visible: true/' "$sandbox/omarchy/$window"
  refused image-picker "a window that stays mapped when closed"

  make_sandbox "$new_omarchy"
  sed -i 's/^  WlrLayershell.layer: shownLayer$/  WlrLayershell.layer: shown ? shownLayer : WlrLayer.Bottom/' "$sandbox/omarchy/$window"
  refused menu "a window that changes layer when closed"

  make_sandbox "$new_omarchy"
  sed -i 's/  id: window/  id: overlay/; s/window\./overlay./g' "$sandbox/omarchy/$window"
  refused menu "a window under another id"

  make_sandbox "$new_omarchy"
  sed -i 's/property int shownKeyboardFocus: WlrKeyboardFocus.Exclusive/property int shownKeyboardFocus: WlrKeyboardFocus.OnDemand/' "$sandbox/omarchy/$window"
  refused menu "a different default focus"
}

unknown_entry_file_is_refused() {
  local menu=shell/plugins/menu/Menu.qml

  # The entry file overriding what the window decides.
  make_sandbox "$new_omarchy"
  sed -i 's/^    WlrLayershell.namespace: "omarchy-menu"$/&\n    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive/' "$sandbox/omarchy/$menu"
  refused menu "an entry file setting its own focus"

  make_sandbox "$new_omarchy"
  sed -i 's/^    WlrLayershell.namespace: "omarchy-menu"$/&\n    exclusionMode: ExclusionMode.Ignore/' "$sandbox/omarchy/$menu"
  refused menu "an entry file setting its own exclusion"

  # A second surface the patch would leave as it was.
  make_sandbox "$new_omarchy"
  printf '%s\n' '// Item {' '  OverlayWindow {' '    id: second' '  }' >>"$sandbox/omarchy/$menu"
  refused menu "two OverlayWindows"

  make_sandbox "$new_omarchy"
  printf '%s\n' '// Item {' '  PanelWindow {' '    id: second' '  }' >>"$sandbox/omarchy/$menu"
  refused menu "an OverlayWindow and a PanelWindow"

  make_sandbox "$new_omarchy"
  sed -i 's/^    id: panel$/    id: overlay/' "$sandbox/omarchy/$menu"
  refused menu "a window under another id"

  # The patch adds a FileView, which needs these.
  make_sandbox "$new_omarchy"
  sed -i '/^import Quickshell.Io$/d' "$sandbox/omarchy/shell/plugins/clipboard/Clipboard.qml"
  refused clipboard "no Quickshell.Io import"

  # A file of Omarchy's own where Ragtop's window would go.
  make_sandbox "$new_omarchy"
  echo 'import QtQuick; Item {}' >"$sandbox/omarchy/shell/plugins/emojis/RagtopOverlayWindow.qml"
  refused emojis "a built-in that ships a RagtopOverlayWindow.qml"

  # The password prompt moving to the shared window is a shape of its own,
  # and one nobody has checked the prompt's focus handling against.
  make_sandbox "$new_omarchy"
  sed -i 's/^  PanelWindow {$/  OverlayWindow {/' "$sandbox/omarchy/shell/plugins/polkit/PolkitAgent.qml"
  refused polkit "a password prompt in the shared window"
}

sync_onto_an_unknown_shape_removes_the_clone() {
  make_sandbox "$old_omarchy"
  clones install menu polkit
  switch_omarchy "$new_omarchy"
  sed -i 's/^  visible: shown .*$/  visible: true/' "$sandbox/omarchy/shell/Ui/OverlayWindow.qml"
  clones sync
  assert_rc 1
  assert_contains "$err" "Couldn't patch tester.menu, so it was removed and Omarchy's own menu stays in use."
  assert_no_path "$(clone_of menu)"
  assert_equal "$(progress_files)" "" "progress markers left behind"
  assert_contains "$(calls)" "notify -g 󰌌 Ragtop Your menu overlay couldn't be re-patched, so it was removed."
  # The prompt does not use the shared window and is none the worse for it.
  assert_contains "$out" "Re-cloned tester.polkit from the updated built-in."
  clones installed polkit
  assert_rc 0
}

shared_lifecycle_handlers_are_refused() {
  local handler action
  for handler in onBackingWindowVisibleChanged; do
    for action in install sync; do
      make_sandbox "$new_omarchy"
      if [[ $action == sync ]]; then clones install menu; assert_rc 0; fi
      /usr/bin/python3 - "$sandbox/omarchy/shell/Ui/OverlayWindow.qml" "$handler" <<'EOF'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
prefix, suffix = text.rsplit("}", 1)
path.write_text(prefix + "  " + sys.argv[2] + ": {}\n}" + suffix)
EOF
      clones "$action" menu
      assert_rc 1 "$action with upstream $handler"
      assert_no_path "$(clone_of menu)"
      assert_equal "$(progress_files)" "" "markers after refusing $handler"
      assert_lacks "$out" "Cloned and patched tester.menu."
    done
  done
}
run_test "7cc6a55: a conflicting handler fails closed on install and sync" shared_lifecycle_handlers_are_refused

run_test "7cc6a55: a shared OverlayWindow Ragtop has not read is not patched" unknown_shared_window_is_refused
run_test "7cc6a55: an entry file Ragtop has not read is not patched" unknown_entry_file_is_refused
run_test "4.0.4 to 7cc6a55: a sync that cannot patch removes the clone and says so" sync_onto_an_unknown_shape_removes_the_clone

# --- Moving between the two ------------------------------------------------

old_per_open_focus='WlrLayershell.keyboardFocus: ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive'

updating_omarchy_moves_clones_to_the_shared_window() {
  make_sandbox "$old_omarchy"
  clones install
  assert_rc 0
  switch_omarchy "$new_omarchy"
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, built-in has changed"; done
  clones sync
  assert_rc 0
  for o in "${all[@]}"; do assert_contains "$out" "Re-cloned tester.$o from the updated built-in."; done
  for o in "${shared_windows[@]}"; do
    assert_file "$(helper_of "$o")"
    assert_contains "$(<"$(entry_of "$o")")" $'\n  RagtopOverlayWindow {\n'
    assert_lacks "$(<"$(entry_of "$o")")" "PanelWindow {"
    assert_equal "$(wc -l <"$(clone_of "$o")/.ragtop-base")" 3 "lines in $o's .ragtop-base"
  done
  assert_lacks "$(<"$(entry_of menu)")" "$old_per_open_focus"
  assert_contains "$(<"$(entry_of polkit)")" "$old_per_open_focus"
  assert_equal "$(wc -l <"$(clone_of polkit)/.ragtop-base")" 2 "lines in polkit's .ragtop-base"
  assert_equal "$(wc -l <"$(clone_of lock)/.ragtop-base")" 2 "lines in lock's .ragtop-base"
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, in sync with the built-in"; done
  assert_lacks "$out" "edits besides"
  clones remove
  assert_rc 0
  for o in "${all[@]}"; do assert_no_path "$(clone_of "$o")"; done
}

downgrading_omarchy_moves_clones_back() {
  make_sandbox "$new_omarchy"
  clones install
  assert_rc 0
  switch_omarchy "$old_omarchy"
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, built-in has changed"; done
  clones sync
  assert_rc 0
  for o in "${all[@]}"; do
    assert_contains "$out" "Re-cloned tester.$o from the updated built-in."
    assert_no_path "$(helper_of "$o")"
    assert_equal "$(wc -l <"$(clone_of "$o")/.ragtop-base")" 2 "lines in $o's .ragtop-base"
    assert_lacks "$(<"$(entry_of "$o")")" "RagtopOverlayWindow"
  done
  assert_contains "$(<"$(entry_of menu)")" "$old_per_open_focus"
  assert_contains "$(<"$(entry_of menu)")" 'visible: root.opened && root.rowsLoaded'
  clones status
  for o in "${all[@]}"; do assert_contains "$out" "$o: installed, in sync with the built-in"; done
  assert_lacks "$out" "edits besides"
  clones remove
  assert_rc 0
  for o in "${all[@]}"; do assert_no_path "$(clone_of "$o")"; done
}

an_edited_clone_is_kept_across_an_update() {
  make_sandbox "$old_omarchy"
  clones install menu emojis
  echo '// mine' >>"$(entry_of menu)"
  switch_omarchy "$new_omarchy"
  clones sync
  assert_rc 1
  assert_contains "$err" "The built-in menu changed, but tester.menu has edits besides Ragtop's, so not replacing it."
  assert_contains "$out" "Re-cloned tester.emojis from the updated built-in."
  assert_contains "$(<"$(entry_of menu)")" '// mine'
  assert_contains "$(<"$(entry_of menu)")" "$old_per_open_focus"
  assert_lacks "$(calls)" "remove tester.menu"
}

a_clone_from_the_ragtop_before_is_repatched() {
  make_sandbox "$old_omarchy"
  clones install menu
  assert_equal "$(sed -n 2p "$(clone_of menu)/.ragtop-base")" 4 "the patch revision recorded"
  # As the Ragtop before this one left it.
  sed -i '2s/.*/3/' "$(clone_of menu)/.ragtop-base"
  clones status menu
  assert_contains "$out" "menu: installed, Ragtop's patches have changed"
  clones sync menu
  assert_rc 0
  assert_contains "$out" "Re-patched tester.menu for this version of Ragtop."
  assert_equal "$(sed -n 2p "$(clone_of menu)/.ragtop-base")" 4 "the patch revision recorded"
}

run_test "a clone made at patch revision 3 is re-patched at 4" a_clone_from_the_ragtop_before_is_repatched
run_test "4.0.4 to 7cc6a55: sync moves every clone over, the four onto a window of their own" updating_omarchy_moves_clones_to_the_shared_window
run_test "7cc6a55 to 4.0.4: sync moves every clone back and leaves no window file behind" downgrading_omarchy_moves_clones_back
run_test "4.0.4 to 7cc6a55: a clone with edits of its own is kept as it was" an_edited_clone_is_kept_across_an_update

new_clones_read_and_write_nowhere_shared() {
  make_sandbox "$new_omarchy"
  clones install
  for o in "${all[@]}"; do assert_lacks "$(<"$(entry_of "$o")")" '/tmp' "$o's entry file"; done
  for o in "${shared_windows[@]}"; do
    assert_lacks "$(<"$(helper_of "$o")")" '/tmp' "$o's window"
  done
}

run_test "7cc6a55: the menu clone uses a window type of its own, with its loading gate intact" new_menu_gets_a_window_of_its_own
run_test "7cc6a55: no clone reads or writes anywhere another user could" new_clones_read_and_write_nowhere_shared
run_test "7cc6a55: sync re-clones what uses the shared OverlayWindow when Omarchy changes it" new_sync_follows_the_shared_window
run_test "7cc6a55: a clone with edits of its own is kept when the shared OverlayWindow changes" new_edited_clone_survives_a_shared_window_change
run_test "7cc6a55: a clone whose generated window was edited or deleted is left alone" new_edited_window_is_left_alone
run_test "4.0.4: a window file in a clone made without one counts as an edit" old_stray_window_file_is_an_edit
run_test "7cc6a55: install patches all six, and status, installed and sync agree" new_install_patches_every_overlay
run_test "7cc6a55: remove takes the clones away, and the hook with the last" new_remove_takes_clones_and_hook_away

run_test "4.0.4: install patches all six, and status, installed and the hook agree" old_install_patches_every_overlay
run_test "4.0.4: the patch is the per-open one, and only the entry file changes" old_patch_is_the_event_driven_one
run_test "4.0.4: installed fails for an overlay with no clone" old_installed_fails_without_a_clone
run_test "4.0.4: remove takes the clones away, and the hook with the last" old_remove_takes_clones_and_hook_away
run_test "4.0.4: a clone with edits of its own is neither removed nor resynced" old_edited_clone_is_left_alone
run_test "4.0.4: a clone Ragtop did not make is left alone" old_somebody_elses_clone_is_left_alone
run_test "4.0.4: sync re-clones what the built-in moved on from" old_sync_follows_the_built_in
run_test "4.0.4: a patch that does not apply leaves no clone behind" old_failed_patch_leaves_no_clone
run_test "4.0.4: a failed clone and an interrupted run both recover" old_failed_clone_and_interrupted_run_recover

finish
