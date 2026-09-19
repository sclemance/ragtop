#!/bin/bash
# Installs, syncs or removes a clone of Omarchy's menu patched for tablets.
#
# While Fliparchy reports tablet mode (via $XDG_RUNTIME_DIR/fliparchy-mode),
# the clone:
#   - takes keyboard focus on demand instead of exclusively. Hyprland routes
#     every touch to a layer surface with exclusive focus before hit-testing
#     anything above it, so with the stock menu a tap on the on-screen
#     keyboard lands on the menu and closes it. On-demand focus still gets
#     focus when the menu opens and still receives typed keys.
#   - respects reserved screen space, so the menu sits above the keyboard
#     instead of running underneath it.
# In laptop mode it behaves exactly like the stock menu: an on-demand menu can
# lose focus to a window under the mouse on another monitor.
# Focus approach from Gimbal (MIT): github.com/mechanicsunlocked/gimbal
#
# A clone stops receiving Omarchy's menu updates, so `sync` re-clones and
# re-patches when the built-in menu has changed; `install` registers it as an
# Omarchy post-update hook.
#
# Usage: menu-clone.sh [install|sync|remove|status]
set -euo pipefail

clone_id="$USER.menu"
clone_dir="$HOME/.config/omarchy/plugins/$clone_id"
builtin_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/menu"
base_file="$clone_dir/.fliparchy-base"
hook_file="$HOME/.config/omarchy/hooks/post-update.d/fliparchy-menu-sync.hook"
self="$(realpath "$0")"

# stock line <TAB-free separator> patched text, one pair per replacement.
stock_focus='    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive'
patched_focus='    WlrLayershell.keyboardFocus: fliparchyMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    FileView { id: fliparchyMode; property bool tablet: false; path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/fliparchy-mode"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: tablet = text().trim() === "tablet"; onLoadFailed: tablet = false }'
stock_exclusion='    exclusionMode: ExclusionMode.Ignore'
patched_exclusion='    exclusionMode: fliparchyMode.tablet ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: 0'

# replace <file> <direction: apply|revert>
replace() {
  python3 - "$1" "$2" "$stock_focus" "$patched_focus" "$stock_exclusion" "$patched_exclusion" <<'EOF'
import sys
path, direction, *pairs = sys.argv[1:]
text = open(path).read()
for stock, patched in zip(pairs[0::2], pairs[1::2]):
    old, new = (stock, patched) if direction == "apply" else (patched, stock)
    if text.count(old) != 1:
        sys.exit(f"expected exactly one occurrence of:\n{old}\nin {path}")
    text = text.replace(old, new, 1)
open(path, "w").write(text)
EOF
}

# Hash of a plugin directory's files, ignoring the manifest (the clone
# command rewrites it) and our own marker.
dir_hash() {
  (cd "$1" && find . -type f ! -name manifest.json ! -name .fliparchy-base -print0 |
    sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1
}

# Hash of the clone as it would be without our patch.
clone_unpatched_hash() {
  local tmp
  tmp=$(mktemp -d)
  cp -a "$clone_dir/." "$tmp/"
  replace "$tmp/Menu.qml" revert
  dir_hash "$tmp"
  rm -rf "$tmp"
}

is_patched() { [[ -f $clone_dir/Menu.qml ]] && grep -q 'id: fliparchyMode' "$clone_dir/Menu.qml"; }

# True when nobody but us changed the clone since it was made.
clone_is_ours() {
  is_patched && [[ -f $base_file ]] && [[ $(clone_unpatched_hash) == "$(cat "$base_file")" ]]
}

notify() {
  command -v omarchy-notification-send >/dev/null &&
    omarchy-notification-send -g 󰌌 "Fliparchy" "$1" || true
}

install_hook() {
  mkdir -p "$(dirname "$hook_file")"
  printf '#!/bin/bash\n# Keeps Fliparchy'"'"'s menu clone in step with Omarchy updates.\n"%s" sync\n' "$self" >"$hook_file"
  chmod +x "$hook_file"
}

install() {
  if [[ -d $clone_dir ]] && ! is_patched; then
    echo "$clone_dir exists but isn't Fliparchy's; leaving it alone." >&2
    exit 1
  fi
  if ! is_patched; then
    omarchy plugin clone omarchy.menu
    dir_hash "$clone_dir" >"$base_file"
    replace "$clone_dir/Menu.qml" apply
    echo "Patched $clone_id."
  else
    echo "$clone_id is already patched."
  fi
  install_hook
  echo "Run omarchy-restart-shell to load it."
}

sync() {
  if ! is_patched; then
    echo "No Fliparchy menu clone installed; nothing to sync."
    return
  fi
  if [[ $(dir_hash "$builtin_dir") == "$(cat "$base_file" 2>/dev/null)" ]]; then
    echo "$clone_id matches the built-in menu; nothing to sync."
    return
  fi
  if ! clone_is_ours; then
    echo "The built-in menu changed, but $clone_id has edits besides Fliparchy's; not replacing it." >&2
    notify "Omarchy's menu was updated, but your menu clone has other edits, so it wasn't resynced."
    exit 1
  fi
  omarchy plugin remove "$clone_id" --yes >/dev/null
  install >/dev/null
  echo "Re-cloned $clone_id from the updated built-in menu."
  notify "Menu clone updated to match Omarchy. Restart the shell to load it."
}

remove() {
  if [[ ! -d $clone_dir ]]; then
    echo "No $clone_id clone installed."
  elif ! clone_is_ours; then
    echo "$clone_id has edits besides Fliparchy's; remove it yourself with: omarchy plugin remove $clone_id" >&2
    exit 1
  else
    omarchy plugin remove "$clone_id" --yes
    echo "Removed $clone_id. Run omarchy-restart-shell to go back to the built-in menu."
  fi
  rm -f "$hook_file"
}

status() {
  if ! is_patched; then echo "not installed"; return; fi
  if [[ $(dir_hash "$builtin_dir") == "$(cat "$base_file" 2>/dev/null)" ]]; then
    echo "installed, in sync with the built-in menu"
  else
    echo "installed, built-in menu has changed (run: $self sync)"
  fi
  clone_is_ours || echo "note: the clone has edits besides Fliparchy's"
}

case "${1:-install}" in
  install) install ;;
  sync) sync ;;
  remove) remove ;;
  status) status ;;
  *) echo "Usage: $0 [install|sync|remove|status]" >&2; exit 2 ;;
esac
