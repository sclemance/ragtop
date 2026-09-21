#!/bin/bash
# Installs, syncs or removes clones of Omarchy's full-screen overlays (the
# menu, emoji picker, clipboard picker, polkit password prompt and image
# picker) and its lock screen, patched for tablets.
#
# While Ragtop reports tablet mode (via $XDG_RUNTIME_DIR/ragtop-mode),
# each clone:
#   - takes keyboard focus on demand instead of exclusively. Hyprland routes
#     every touch to a layer surface with exclusive focus before hit-testing
#     anything above it, so with a stock overlay a tap on the on-screen
#     keyboard lands on the overlay and closes it. On-demand focus still gets
#     focus when the overlay opens and still receives typed keys.
#   - respects reserved screen space, so it sits above the keyboard instead of
#     running underneath it.
# In laptop mode each behaves exactly like the stock overlay: an on-demand
# overlay can lose focus to a window under the mouse on another monitor.
# Focus approach from Gimbal (MIT): github.com/mechanicsunlocked/gimbal
#
# The lock screen is a session lock, which hides every other surface, the
# on-screen keyboard included, so its clone instead loads Ragtop's own
# LockKeyboard.qml at the bottom of the screen while in tablet mode.
#
# Clones stop receiving Omarchy's updates, so `sync` re-clones and re-patches
# any whose built-in has changed; `install` registers it as an Omarchy
# post-update hook.
#
# The polkit and lock clones keep the authentication capability: Omarchy
# stamps a clone with its source's capabilities via clonedFrom.
#
# Usage: overlay-clones.sh [install|sync|remove|status|installed] [menu|emojis|clipboard|polkit|image-picker|lock ...]
# `installed` succeeds only if every named overlay has a Ragtop clone.
set -euo pipefail

# name:entry-file for each supported built-in overlay.
overlays=(menu:Menu.qml emojis:Emojis.qml clipboard:Clipboard.qml polkit:PolkitAgent.qml
          image-picker:ImagePicker.qml lock:LockView.qml)

# Bumped whenever the patches below change, so `sync` re-clones a clone that
# was made by an older Ragtop even though Omarchy's own file hasn't moved.
patch_revision=2

plugins_dir="$HOME/.config/omarchy/plugins"
builtin_root="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins"
hook_file="$HOME/.config/omarchy/hooks/post-update.d/ragtop-overlay-sync.hook"
self="$(realpath "$0")"

# Every patch includes this, which is also how a Ragtop clone is recognised.
mode_file_view='FileView { id: ragtopMode; property bool tablet: false; path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ragtop-mode"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: tablet = text().trim() === "tablet"; onLoadFailed: tablet = false }'

stock_focus='    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive'
patched_focus="    WlrLayershell.keyboardFocus: ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    $mode_file_view"
# The image picker holds focus only while it's showing something, so its
# line carries that condition; the tablet-mode swap goes inside it.
stock_picker_focus='    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None'
patched_picker_focus="    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? (ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
    $mode_file_view"

stock_exclusion='    exclusionMode: ExclusionMode.Ignore'
patched_exclusion='    exclusionMode: ragtopMode.tablet ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: 0'

# Omarchy 4.0.0.alpha hands a third-party menu no application library, so a
# cloned menu's Apps submenu comes up empty. Its manifest reaches
# pluginShellFor() through an Instantiator, and that round-trip leaves
# Array.isArray(manifest.kinds) false, so manifestHasKind(manifest, "menu")
# fails and PluginShellApi.appLibrary is built as null. Load Omarchy's own
# AppLibrary.qml instead — the same file the shell itself uses, which is
# self-contained — and drop back to the injected one the day it arrives.
stock_menu_apps='  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null'
patched_menu_apps=$(cat <<'MENU_APPS'
  // Ragtop: Omarchy 4.0.0.alpha builds this plugin's appLibrary as null (the
  // manifest reaches pluginShellFor() through an Instantiator, where
  // Array.isArray(kinds) goes false), so Apps would be empty. Load Omarchy's
  // own AppLibrary rather than reimplement it, and prefer the injected one
  // as soon as there is one. Costs one extra icon scan while it is in use.
  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : ragtopAppLibrary.item
  Loader {
    id: ragtopAppLibrary
    active: !(root.shell && root.shell.appLibrary)
    source: "file://" + root.omarchyPath + "/shell/services/AppLibrary.qml"
  }
MENU_APPS
)

stock_lock_import='import qs.Ui'
patched_lock_import='import qs.Ui
import Quickshell
import Quickshell.Io'
stock_lock_view='    BorderSurface {
      id: inputField'
patched_lock_view="    $mode_file_view
    // Ragtop: an on-screen keyboard for the lock screen in tablet mode.
    Loader {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      active: ragtopMode.tablet
      source: \"file://\" + Quickshell.env(\"HOME\") + \"/.config/omarchy/plugins/sclemance.ragtop/LockKeyboard.qml\"
      onLoaded: item.view = root
    }
    BorderSurface {
      id: inputField"

# Per-overlay paths and patch (stock/patched text pairs), set by select_overlay.
name="" entry="" clone_id="" clone_dir="" builtin_dir="" base_file="" patch=()
select_overlay() {
  name="${1%%:*}"
  entry="${1#*:}"
  if [[ $name == lock ]]; then
    patch=("$stock_lock_import" "$patched_lock_import" "$stock_lock_view" "$patched_lock_view")
  elif [[ $name == menu ]]; then
    patch=("$stock_focus" "$patched_focus" "$stock_exclusion" "$patched_exclusion"
           "$stock_menu_apps" "$patched_menu_apps")
  elif [[ $name == image-picker ]]; then
    patch=("$stock_picker_focus" "$patched_picker_focus" "$stock_exclusion" "$patched_exclusion")
  else
    patch=("$stock_focus" "$patched_focus" "$stock_exclusion" "$patched_exclusion")
  fi
  clone_id="$USER.$name"
  clone_dir="$plugins_dir/$clone_id"
  builtin_dir="$builtin_root/$name"
  base_file="$clone_dir/.ragtop-base"
}

# replace <file> <apply|revert>
replace() {
  python3 - "$1" "$2" "${patch[@]}" <<'EOF'
import sys
path, direction, *pairs = sys.argv[1:]
text = open(path).read()
for stock, patched in zip(pairs[0::2], pairs[1::2]):
    old, new = (stock, patched) if direction == "apply" else (patched, stock)
    found = text.count(old)
    # Reverting tolerates a patch that isn't there: a clone made by an older
    # Ragtop carries fewer of them, and what is absent needs no undoing.
    if found == 0 and direction == "revert":
        continue
    if found != 1:
        sys.exit(f"expected exactly one occurrence of:\n{old}\nin {path}")
    text = text.replace(old, new, 1)
open(path, "w").write(text)
EOF
}

# Hash of a plugin directory's files, ignoring the manifest (the clone
# command rewrites it) and our own marker.
dir_hash() {
  (cd "$1" && find . -type f ! -name manifest.json ! -name .ragtop-base -print0 |
    sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1
}

clone_unpatched_hash() {
  local tmp
  tmp=$(mktemp -d)
  cp -a "$clone_dir/." "$tmp/"
  replace "$tmp/$entry" revert
  dir_hash "$tmp"
  rm -rf "$tmp"
}

is_patched() { [[ -f $clone_dir/$entry ]] && grep -q 'id: ragtopMode' "$clone_dir/$entry"; }

# .ragtop-base records what the clone was made from: the built-in's hash on
# the first line, the revision of the patches applied to it on the second.
write_base() { { dir_hash "$clone_dir"; echo "$patch_revision"; } >"$base_file"; }
base_hash() { head -n1 "$base_file" 2>/dev/null; }
base_revision() { sed -n 2p "$base_file" 2>/dev/null; }

# True when nobody but us changed the clone since it was made.
clone_is_ours() {
  is_patched && [[ -f $base_file ]] && [[ $(clone_unpatched_hash) == "$(base_hash)" ]]
}

built_in_unchanged() { [[ $(dir_hash "$builtin_dir") == "$(base_hash)" ]]; }
patches_current() { [[ $patch_revision == "$(base_revision)" ]]; }
in_sync() { built_in_unchanged && patches_current; }

notify() {
  command -v omarchy-notification-send >/dev/null &&
    omarchy-notification-send -g 󰌌 "Ragtop" "$1" || true
}

install_hook() {
  mkdir -p "$(dirname "$hook_file")"
  printf '#!/bin/bash\n# Keeps Ragtop'"'"'s overlay clones in step with Omarchy updates.\n"%s" sync\n' "$self" >"$hook_file"
  chmod +x "$hook_file"
}

install_one() {
  if [[ -d $clone_dir ]] && ! is_patched; then
    echo "$clone_dir exists but isn't Ragtop's; leaving it alone." >&2
    return 1
  fi
  if is_patched; then
    echo "$clone_id is already patched."
    return
  fi
  omarchy plugin clone "omarchy.$name" >/dev/null
  write_base
  replace "$clone_dir/$entry" apply
  echo "Cloned and patched $clone_id."
}

sync_one() {
  if ! is_patched; then return; fi
  if in_sync; then
    echo "$clone_id matches the built-in; nothing to sync."
    return
  fi
  # Either Omarchy's own file moved or Ragtop's patches did. Both are fixed by
  # re-cloning, and neither justifies throwing away someone else's edits.
  local changed="The built-in $name changed" done_msg="Re-cloned $clone_id from the updated built-in."
  if built_in_unchanged; then
    changed="Ragtop's $name patches changed"
    done_msg="Re-patched $clone_id for this version of Ragtop."
  fi
  if ! clone_is_ours; then
    echo "$changed, but $clone_id has edits besides Ragtop's; not replacing it." >&2
    notify "Your $name clone has edits of its own, so it wasn't resynced."
    return 1
  fi
  omarchy plugin remove "$clone_id" --yes >/dev/null
  install_one >/dev/null
  echo "$done_msg"
  synced=1
}

remove_one() {
  if [[ ! -d $clone_dir ]]; then
    echo "No $clone_id clone installed."
  elif ! clone_is_ours; then
    echo "$clone_id has edits besides Ragtop's; remove it yourself with: omarchy plugin remove $clone_id" >&2
    return 1
  else
    omarchy plugin remove "$clone_id" --yes >/dev/null
    echo "Removed $clone_id."
  fi
}

status_one() {
  if ! is_patched; then
    echo "$name: not installed"
  elif in_sync; then
    echo "$name: installed, in sync with the built-in"
  elif built_in_unchanged; then
    echo "$name: installed, Ragtop's patches have changed (run: $self sync)"
  else
    echo "$name: installed, built-in has changed (run: $self sync)"
  fi
  if is_patched && ! clone_is_ours; then echo "$name: note: the clone has edits besides Ragtop's"; fi
}

command="${1:-install}"
shift || true

selected=()
if (( $# == 0 )); then
  selected=("${overlays[@]}")
else
  for want in "$@"; do
    match=""
    for o in "${overlays[@]}"; do [[ ${o%%:*} == "$want" ]] && match="$o"; done
    [[ -n $match ]] || { echo "Unknown overlay: $want (expected: menu, emojis, clipboard, polkit, image-picker, lock)" >&2; exit 2; }
    selected+=("$match")
  done
fi

status=0
synced=0
for o in "${selected[@]}"; do
  select_overlay "$o"
  case "$command" in
    install) install_one || status=1 ;;
    sync) sync_one || status=1 ;;
    remove) remove_one || status=1 ;;
    status) status_one ;;
    installed) is_patched || status=1 ;;
    *) echo "Usage: $0 [install|sync|remove|status|installed] [menu|emojis|clipboard|polkit|image-picker|lock ...]" >&2; exit 2 ;;
  esac
done

case "$command" in
  install)
    install_hook
    echo "Run omarchy-restart-shell to load the clones."
    ;;
  sync)
    (( synced )) && notify "Overlay clones updated. Restart the shell to load them."
    ;;
  remove)
    # Only drop the hook once no clones are left for it to keep in step.
    remaining=0
    for o in "${overlays[@]}"; do select_overlay "$o"; is_patched && remaining=1; done
    (( remaining )) || rm -f "$hook_file"
    echo "Run omarchy-restart-shell to go back to the built-in overlays."
    ;;
esac
exit "$status"
