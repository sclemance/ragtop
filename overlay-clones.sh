#!/bin/bash
# Installs, syncs or removes clones of Omarchy's full-screen overlays (the
# menu, emoji picker, clipboard picker, polkit password prompt and image
# picker) and its lock screen, patched for tablets.
#
# While the Keyboard setting enables the keyboard (Always On, or Follow
# Sensor with tablet mode from $XDG_RUNTIME_DIR/ragtop-mode), each clone:
#   - takes keyboard focus on demand instead of exclusively. Hyprland routes
#     every touch to a layer surface with exclusive focus before hit-testing
#     anything above it, so with a stock overlay a tap on the on-screen
#     keyboard lands on the overlay and closes it. On-demand focus still gets
#     focus when the overlay opens and still receives typed keys.
#   - respects reserved screen space, so it sits above the keyboard instead of
#     running underneath it.
# With the keyboard disabled each behaves like the stock overlay: an on-demand
# overlay can lose focus to a window under the mouse on another monitor.
# Focus approach from Gimbal (MIT): github.com/mechanicsunlocked/gimbal
#
# Omarchy has written these overlays two ways, and both are patched. On 4.0.4
# each is a window of its own and the two lines above are in its entry file.
# Later (checked at 7cc6a55) the menu and the three pickers are instances of
# one shared window, and the lines are in that. Such a clone gets a patched
# copy of the shared window to itself. See stock_window and the helper patch
# below. Either way the surface maps when the overlay opens and unmaps when
# it closes, which is how Ragtop's service follows it. Anything written a
# third way is not patched.
#
# The lock screen is a session lock, which hides every other surface, the
# on-screen keyboard included, so its clone instead loads Ragtop's own
# LockKeyboard.qml at the bottom, following Ragtop's Keyboard setting.
#
# Clones stop receiving Omarchy's updates, so `sync` re-clones and re-patches
# any whose built-in has changed. `install` registers it as an Omarchy
# post-update hook.
#
# The polkit and lock clones keep the authentication capability: Omarchy
# stamps a clone with its source's capabilities via clonedFrom.
#
# Usage: overlay-clones.sh [install|sync|remove|status|installed|tappable] [menu|emojis|clipboard|polkit|image-picker|lock ...]
# `installed` succeeds only if every named overlay has a Ragtop clone.
# `tappable` is for Ragtop's service: see tappable_one.
#
# Tested by tests/overlay-clones-test.sh. Run tests/run.
set -euo pipefail

# name:entry-file for each supported built-in overlay.
overlays=(menu:Menu.qml emojis:Emojis.qml clipboard:Clipboard.qml polkit:PolkitAgent.qml
          image-picker:ImagePicker.qml lock:LockView.qml)

# Bumped whenever the patches below change, so `sync` re-clones a clone that
# was made by an older Ragtop even though Omarchy's own file hasn't moved.
patch_revision=6

plugins_dir="$HOME/.config/omarchy/plugins"
omarchy_root="${OMARCHY_PATH:-/usr/share/omarchy}"
builtin_root="$omarchy_root/shell/plugins"
hook_file="$HOME/.config/omarchy/hooks/post-update.d/ragtop-overlay-sync.hook"
self="$(realpath "$0")"

# Every patch includes this, which is also how a Ragtop clone is recognised.
# With no XDG_RUNTIME_DIR it reads nothing and stays in laptop mode. It used
# to fall back to /tmp, where any local user can create ragtop-mode first and
# so decide how the password prompt and the lock screen take focus.
mode_file_view='FileView { id: ragtopMode; property bool tablet: false; path: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/ragtop-mode" : ""; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: tablet = text().trim() === "tablet"; onLoadFailed: tablet = false }'
# What revision 3 and earlier wrote, so their clones are still recognised.
legacy_mode_file_view='FileView { id: ragtopMode; property bool tablet: false; path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ragtop-mode"; watchChanges: true; printErrors: false; onFileChanged: reload(); onLoaded: tablet = text().trim() === "tablet"; onLoadFailed: tablet = false }'

stock_focus='    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive'
patched_focus="    WlrLayershell.keyboardFocus: ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive
    $mode_file_view"
# The image picker holds focus only while it's showing something, so its
# line carries that condition, and the tablet-mode swap goes inside it.
stock_picker_focus='    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None'
patched_picker_focus="    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? (ragtopMode.tablet ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
    $mode_file_view"

stock_exclusion='    exclusionMode: ExclusionMode.Ignore'
patched_exclusion='    exclusionMode: ragtopMode.tablet ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: 0'

# Later Omarchy (checked at 7cc6a55) draws the menu, the emoji, clipboard and
# image pickers in an OverlayWindow, one component in qs.Ui that they share.
# The focus and exclusion lines above are inside it, not in the entry file,
# and it is not Ragtop's to patch: every other overlay Omarchy has uses it too. So the clone gets a
# patched copy of it to itself (see make_helper) and the entry file is pointed
# at the copy. What the entry file asks of its window -- when it is shown,
# when it wants the keyboard -- stays as Omarchy wrote it.
shared_window="$omarchy_root/shell/Ui/OverlayWindow.qml"
helper_name=RagtopOverlayWindow.qml
stock_window='  OverlayWindow {
    id: panel'
patched_window="  RagtopOverlayWindow {
    id: panel
    ragtopTablet: ragtopMode.tablet
    $mode_file_view"
# What such an entry file has to look like for that to be all it needs: one
# OverlayWindow and no surface besides, nothing in it overriding what the
# window decides about focus and reserved space, and the imports the mode
# reader uses.
window_checks=(--once 'OverlayWindow {' --never 'PanelWindow {'
               --never 'WlrLayershell.keyboardFocus:' --never 'exclusionMode:' --never 'exclusiveZone:'
               --line 'import Quickshell' --line 'import Quickshell.Io')

# What the copy of OverlayWindow gets. Every line is looked for in Omarchy's
# file as it stands, so a rewrite of it upstream stops the patch rather than
# producing a window nobody has read.
stock_helper_focus='  WlrLayershell.keyboardFocus: shownKeyboardFocus'
patched_helper_focus=$(cat <<'HELPER_FOCUS'
  WlrLayershell.keyboardFocus: ragtopShownFocus

  // Ragtop: set by the entry file, from the mode file it reads.
  property bool ragtopTablet: false

  // Ragtop: in tablet mode an overlay that wants the keyboard exclusively
  // gets it on demand instead, so a touch can reach the on-screen keyboard
  // (see overlay-clones.sh). Hyprland hands an on-demand layer the keyboard
  // only when it maps, though, and the image picker maps before it wants
  // one. So every time the overlay starts wanting the keyboard it asks
  // exclusively for a moment and then lets go, which is what Omarchy's own
  // KeyboardPanel does and where the interval comes from. What the entry
  // file asks for is left alone: an overlay that wants no keyboard yet still
  // gets none.
  property bool ragtopFocusPrimed: false
  readonly property bool ragtopWantsKeyboard: shown && shownKeyboardFocus === WlrKeyboardFocus.Exclusive
  readonly property int ragtopShownFocus: ragtopTablet && ragtopFocusPrimed && ragtopWantsKeyboard
    ? WlrKeyboardFocus.OnDemand : shownKeyboardFocus
  function ragtopBeginPrime() {
    if (ragtopWantsKeyboard && backingWindowVisible) ragtopPrimeTimer.restart()
  }
  onRagtopWantsKeyboardChanged: {
    ragtopPrimeTimer.stop()
    ragtopFocusPrimed = false
    ragtopBeginPrime()
  }
  // The moment of exclusive focus has to be spent on a surface that exists.
  onBackingWindowVisibleChanged: ragtopBeginPrime()
  Timer {
    id: ragtopPrimeTimer
    interval: 75
    onTriggered: if (window.ragtopWantsKeyboard) window.ragtopFocusPrimed = true
  }
HELPER_FOCUS
)
stock_helper_exclusion='  exclusionMode: ExclusionMode.Ignore'
patched_helper_exclusion='  exclusionMode: ragtopTablet ? ExclusionMode.Normal : ExclusionMode.Ignore
  exclusiveZone: 0'
# Omarchy keeps the overlay's content transparent until the surface is the
# size of the whole screen. Out of reserved space it never is, so in tablet
# mode that wait would never end and the overlay would stay invisible. The
# wait for the screen's scale, on the same line's neighbours, is left alone.
stock_helper_geometry='    && width === targetScreen.width && height === targetScreen.height'
patched_helper_geometry='    && (ragtopTablet || (width === targetScreen.width && height === targetScreen.height))'
# The rest of what the patched copy relies on and leaves as Omarchy wrote it,
# and everything the patch refers to by name. The `visible` line is what makes
# the surface map per open, which the focus prime and Ragtop's service both
# go by.
helper_checks=(--once 'PanelWindow {
  id: window
' --line 'import QtQuick' --line 'import Quickshell.Wayland' --line '  property bool shown: false'
               --line '  property int shownKeyboardFocus: WlrKeyboardFocus.Exclusive'
               --line '  visible: shown && !!targetScreen && !!targetMonitor'
               --line '  WlrLayershell.layer: shownLayer'
               # The patch adds this handler to the copied root. A second
               # binding would make QML reject the window after a successful
               # clone, so reject the source before enabling such a copy.
               --never 'onBackingWindowVisibleChanged' --never 'ragtop')

# Omarchy 4 (checked on 4.0.4) hands a third-party menu no application library, so a
# cloned menu's Apps submenu comes up empty. Its manifest reaches
# pluginShellFor() through an Instantiator, and that round-trip leaves
# Array.isArray(manifest.kinds) false, so manifestHasKind(manifest, "menu")
# fails and PluginShellApi.appLibrary is built as null. Load Omarchy's own
# AppLibrary.qml instead, the same file the shell itself uses and one that
# stands on its own, and drop back to the injected one the day it arrives.
stock_menu_apps='  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null'
patched_menu_apps=$(cat <<'MENU_APPS'
  // Ragtop: Omarchy 4 builds this plugin's appLibrary as null (the
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

# Patched text earlier revisions wrote. `revert` strips these as well, so a
# clone made by an older Ragtop is still recognised as ours and gets
# re-patched instead of refused. Revision 2 named an Omarchy version here.
legacy_menu_apps=${patched_menu_apps/Omarchy 4 builds/Omarchy 4.0.0.alpha builds}
# Revision 3 and earlier read the mode file with a /tmp fallback.
legacy_focus=${patched_focus/"$mode_file_view"/"$legacy_mode_file_view"}
legacy_picker_focus=${patched_picker_focus/"$mode_file_view"/"$legacy_mode_file_view"}

stock_lock_import='import qs.Ui'
patched_lock_import='import qs.Ui
import Quickshell
import Quickshell.Io'
stock_lock_view='    BorderSurface {
      id: inputField'
legacy_lock_view_v4="    $mode_file_view
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
legacy_lock_view=${legacy_lock_view_v4/"$mode_file_view"/"$legacy_mode_file_view"}

# The lock keyboard follows the same policy as the desktop keyboard. Read
# only the setting here: the lock screen must also work without the desktop
# keyboard surface or its service. Ordinary overlays share this policy so
# Always On works in laptop mode and Never restores stock focus.
lock_settings_view=$(cat <<'LOCK_SETTINGS'
    FileView {
      id: ragtopKeyboardSettings
      property string mode: "sensor"
      readonly property bool available: mode === "on" || (mode === "sensor" && ragtopMode.tablet)
      path: Quickshell.env("HOME") + "/.config/ragtop/settings.conf"
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: {
        ragtopSettingsRetry.stop()
        var value = "sensor"
        text().split("\n").forEach(function(line) {
          var eq = line.indexOf("=")
          if (eq > 0 && line.slice(0, eq).trim() === "keyboard")
            value = line.slice(eq + 1).trim()
        })
        mode = value === "on" || value === "off" ? value : "sensor"
      }
      onLoadFailed: {
        mode = "sensor"
        ragtopSettingsRetry.start()
      }
    }
    Timer {
      id: ragtopSettingsRetry
      interval: 3000
      repeat: true
      onTriggered: ragtopKeyboardSettings.reload()
    }
LOCK_SETTINGS
)
patched_lock_view="    $mode_file_view
$lock_settings_view
    // Ragtop: Always On, Never, or automatic with tablet mode.
    Loader {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      active: ragtopKeyboardSettings.available
      source: \"file://\" + Quickshell.env(\"HOME\") + \"/.config/omarchy/plugins/sclemance.ragtop/LockKeyboard.qml\"
      onLoaded: item.view = root
    }
    BorderSurface {
      id: inputField"

# Revisions 4–5 used only physical tablet mode. Keep their exact patch text
# for provenance checks before switching ordinary overlays to Keyboard policy.
previous_focus=$patched_focus
previous_picker_focus=$patched_picker_focus
previous_exclusion=$patched_exclusion
previous_window=$patched_window
patched_focus=${patched_focus//ragtopMode.tablet/ragtopKeyboardSettings.available}
patched_focus="$patched_focus
$lock_settings_view"
patched_picker_focus=${patched_picker_focus//ragtopMode.tablet/ragtopKeyboardSettings.available}
patched_picker_focus="$patched_picker_focus
$lock_settings_view"
patched_exclusion=${patched_exclusion//ragtopMode.tablet/ragtopKeyboardSettings.available}
patched_window=${patched_window/ragtopTablet: ragtopMode.tablet/ragtopTablet: ragtopKeyboardSettings.available}
patched_window="$patched_window
$lock_settings_view"

# Per-overlay paths and patch (stock/patched text pairs), set by select_overlay.
# `window_patch` is what an entry file gets instead of `patch` when its
# surface is an instance of the shared OverlayWindow. `legacy` holds pairs
# that only ever get reverted: text this script used to write and no longer
# does. `helper_patch` is for the clone's copy of OverlayWindow.
name="" entry="" clone_id="" clone_dir="" builtin_dir="" base_file="" progress_file="" patch=() window_patch=() legacy=()
helper_patch=("$stock_helper_focus" "$patched_helper_focus"
              "$stock_helper_exclusion" "$patched_helper_exclusion"
              "$stock_helper_geometry" "$patched_helper_geometry")
select_overlay() {
  name="${1%%:*}"
  entry="${1#*:}"
  legacy=()
  window_patch=()
  if [[ $name == lock ]]; then
    patch=("$stock_lock_import" "$patched_lock_import" "$stock_lock_view" "$patched_lock_view")
    legacy=("$stock_lock_view" "$legacy_lock_view_v4" "$stock_lock_view" "$legacy_lock_view")
  elif [[ $name == menu ]]; then
    patch=("$stock_focus" "$patched_focus" "$stock_exclusion" "$patched_exclusion"
           "$stock_menu_apps" "$patched_menu_apps")
    window_patch=("$stock_window" "$patched_window" "$stock_menu_apps" "$patched_menu_apps")
    legacy=("$stock_menu_apps" "$legacy_menu_apps" "$stock_focus" "$legacy_focus")
  elif [[ $name == image-picker ]]; then
    patch=("$stock_picker_focus" "$patched_picker_focus" "$stock_exclusion" "$patched_exclusion")
    window_patch=("$stock_window" "$patched_window")
    legacy=("$stock_picker_focus" "$legacy_picker_focus")
  else
    patch=("$stock_focus" "$patched_focus" "$stock_exclusion" "$patched_exclusion")
    # The password prompt is still a window of its own at 7cc6a55.
    [[ $name == polkit ]] || window_patch=("$stock_window" "$patched_window")
    legacy=("$stock_focus" "$legacy_focus")
  fi
  if [[ $name != lock ]]; then
    legacy+=("$stock_focus" "$previous_focus" "$stock_picker_focus" "$previous_picker_focus"
             "$stock_exclusion" "$previous_exclusion" "$stock_window" "$previous_window")
  fi
  clone_id="$USER.$name"
  clone_dir="$plugins_dir/$clone_id"
  builtin_dir="$builtin_root/$name"
  base_file="$clone_dir/.ragtop-base"
  # Cloning and patching are two steps. This says the first has happened and
  # the second hasn't, so an interrupted run leaves something recognisable
  # rather than a clone nobody can tell from one of the user's own. It lives
  # outside the clone, which the next clone command replaces wholesale.
  progress_file="$plugins_dir/.ragtop-cloning-$name"
}

# replace <file> <apply|revert> [check ...] <stock> <patched> [<stock> <patched> ...]
#
# A check is one of these, and says what the file has to look like before
# anything in it is replaced. A patch that finds its lines is not enough to
# go on when the lines around them are what it relies on:
#   --line <text>     exactly one line is this
#   --once <text>     this occurs exactly once
#   --never <text>    this does not occur
replace() {
  /usr/bin/python3 - "$@" <<'EOF'
import sys
path, direction, *rest = sys.argv[1:]
text = open(path).read()
while rest and rest[0] in ("--line", "--once", "--never"):
    check, wanted, *rest = rest
    if check == "--line":
        found, expected = text.split("\n").count(wanted), 1
    else:
        found, expected = text.count(wanted), 1 if check == "--once" else 0
    if found != expected:
        sys.exit(f"expected {'exactly one' if expected else 'no'} occurrence of:\n{wanted}\nin {path}")
pairs = rest
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
    LC_ALL="${2:-C}" sort -z | xargs -0 sha256sum) | sha256sum | cut -d' ' -f1
}

# Revisions through 5 sorted paths using the caller's locale. A shell launched
# from the desktop and one launched by an update hook can disagree. Accept
# those historical orderings only while verifying old records; all new hashes
# use C. File contents still have to match the recorded digest exactly.
dir_matches_base() {
  local directory=$1 wanted=$2 collation
  [[ $(dir_hash "$directory") == "$wanted" ]] && return 0
  [[ $(base_revision) =~ ^[1-5]$ ]] || return 1
  while IFS= read -r collation; do
    [[ $collation == C || $collation == C.utf8 || $collation == POSIX ]] && continue
    [[ $(dir_hash "$directory" "$collation") == "$wanted" ]] && return 0
  done < <(locale -a)
  return 1
}

file_hash() { sha256sum "$1" | cut -d' ' -f1; }

# Whether an entry file draws itself in the shared OverlayWindow.
uses_shared_window() { (( ${#window_patch[@]} )) && grep -q '^  OverlayWindow {$' "$1"; }

# Gives the clone its own, patched copy of the shared OverlayWindow. Never
# over a file the built-in came with, and the copy has to be the file
# write_base just recorded, or the record would vouch for a window made from
# something else.
make_helper() {
  [[ ! -e $clone_dir/$helper_name ]] &&
    cp "$shared_window" "$clone_dir/$helper_name" &&
    [[ $(file_hash "$clone_dir/$helper_name") == "$(base_window_hash)" ]] &&
    replace "$clone_dir/$helper_name" apply "${helper_checks[@]}" "${helper_patch[@]}"
}

# True when the clone's own window is the one make_helper wrote: taking the
# patch back out leaves exactly the OverlayWindow recorded when it was copied.
# A clone made without one has none to check, and a file of that name in it
# is caught by the directory hash like any other stray.
window_is_ours() {
  local want tmp ours=1
  want=$(base_window_hash)
  [[ -n $want ]] || return 0
  [[ -f $clone_dir/$helper_name ]] || return 1
  tmp=$(mktemp)
  cp "$clone_dir/$helper_name" "$tmp"
  if replace "$tmp" revert "${helper_patch[@]}" && [[ $(file_hash "$tmp") == "$want" ]]; then ours=0; fi
  rm -f "$tmp"
  return "$ours"
}

# Patches a fresh clone, whichever of the two ways its entry file is written.
patch_clone() {
  if uses_shared_window "$clone_dir/$entry"; then
    make_helper && replace "$clone_dir/$entry" apply "${window_checks[@]}" "${window_patch[@]}"
  else
    # The lines `patch` looks for are a window's own. Found in a file that
    # also has an OverlayWindow, they are not what they were written for.
    replace "$clone_dir/$entry" apply --never 'OverlayWindow {' "${patch[@]}"
  fi
}

clone_matches_base() {
  local tmp result=1
  tmp=$(mktemp -d)
  cp -a "$clone_dir/." "$tmp/"
  replace "$tmp/$entry" revert "${patch[@]}" "${window_patch[@]}" "${legacy[@]}"
  # The window Ragtop added is no part of the built-in. window_is_ours
  # answers for it.
  [[ -z $(base_window_hash) ]] || rm -f "$tmp/$helper_name"
  if dir_matches_base "$tmp" "$(base_hash)"; then result=0; fi
  rm -rf "$tmp"
  return "$result"
}

is_patched() { [[ -f $clone_dir/$entry ]] && grep -q 'id: ragtopMode' "$clone_dir/$entry"; }

# .ragtop-base records what the clone was made from: the built-in's hash on
# the first line, the revision of the patches applied to it on the second
# and, for a clone that draws itself in the shared OverlayWindow, the hash of
# that file on the third. There is no third line otherwise.
write_base() {
  {
    dir_hash "$clone_dir"
    echo "$patch_revision"
    if uses_shared_window "$clone_dir/$entry"; then file_hash "$shared_window"; fi
  } >"$base_file"
}
base_hash() { head -n1 "$base_file" 2>/dev/null; }
base_revision() { sed -n 2p "$base_file" 2>/dev/null; }
base_window_hash() { sed -n 3p "$base_file" 2>/dev/null; }

# True when nobody but us changed the clone since it was made.
clone_is_ours() {
  is_patched && [[ -f $base_file ]] && window_is_ours && clone_matches_base
}

# The shared OverlayWindow is as much what a clone was made from as the
# built-in's own files are, and an Omarchy update can change it and leave the
# plugin alone. Empty for a built-in that does not use it, which matches a
# record with no third line.
built_in_window_hash() {
  if uses_shared_window "$builtin_dir/$entry"; then file_hash "$shared_window" 2>/dev/null || echo missing; fi
}
built_in_unchanged() {
  dir_matches_base "$builtin_dir" "$(base_hash)" && [[ $(built_in_window_hash) == "$(base_window_hash)" ]]
}
patches_current() { [[ $patch_revision == "$(base_revision)" ]]; }
in_sync() { built_in_unchanged && patches_current; }

# Its notifications, in the language Omarchy is set to (i18n.sh).
repo=$(dirname "$self")
source "$repo/i18n.sh"

notify() {
  command -v omarchy-notification-send >/dev/null &&
    omarchy-notification-send -g 󰌌 "Ragtop" "$1" || true
}

# Omarchy's plugin commands ask the running shell to rescan and enable, and
# give it two seconds to answer. A shell busy reloading a plugin can take
# longer, and both a clone and the settings rows written just before one set
# it reloading. A clone whose answer comes late is deleted again by Omarchy,
# with the settings it had already changed left behind (forget_clone). Ten
# seconds is for that, and only for these commands.
plugin() { OMARCHY_SHELL_IPC_TIMEOUT="${OMARCHY_SHELL_IPC_TIMEOUT:-10s}" omarchy plugin "$@"; }

# A clone that failed after the shell was told to use it is deleted by
# Omarchy's clone command, but what that told the shell is not undone: the
# bar keeps a place for a clone that is gone and the built-in stays switched
# off, so there is neither. This puts back what Omarchy itself puts back when
# a clone goes (PluginRegistry.qml, restoreCloneSource): the built-in where
# the clone was, and switched on again if the clone had switched it off. Only
# for a clone that is not there. The shell watches the file and follows it.
forget_clone() {
  [[ -e $clone_dir || -L $clone_dir ]] && return 0
  /usr/bin/python3 - "$HOME/.config/omarchy/shell.json" "$clone_id" "omarchy.$name" <<'EOF'
import json, os, sys, tempfile
path, clone, source = sys.argv[1:]
try:
    config = json.load(open(path))
except (OSError, ValueError):
    sys.exit(0)
if not isinstance(config, dict):
    sys.exit(0)

def entry_id(entry):
    return entry.get("id") if isinstance(entry, dict) else entry

changed = False
bar = config.get("bar")
layout = bar.get("layout") if isinstance(bar, dict) else None
if isinstance(layout, dict):
    sections = [s for s in ("left", "center", "right") if isinstance(layout.get(s), list)]
    if any(entry_id(e) == clone for s in sections for e in layout[s]):
        # The clone's place, with whatever else its entry said, goes back to
        # the built-in, and any other place the built-in had goes.
        for s in sections:
            layout[s] = [e for e in layout[s] if entry_id(e) != source]
        placed = False
        for s in sections:
            kept = []
            for e in layout[s]:
                if entry_id(e) != clone:
                    kept.append(e)
                elif not placed:
                    kept.append(dict(e, id=source) if isinstance(e, dict) else {"id": source})
                    placed = True
            layout[s] = kept
        changed = True
plugins = config.get("plugins")
if isinstance(plugins, list) and any(isinstance(p, dict) and p.get("id") == clone for p in plugins):
    config["plugins"] = [p for p in plugins if not (isinstance(p, dict) and p.get("id") == clone)]
    changed = True
restores = config.get("cloneSourceRestores")
if isinstance(restores, list) and clone in restores:
    disabled = config.get("disabledPlugins")
    if isinstance(disabled, list):
        disabled = [d for d in disabled if d != source]
        if disabled:
            config["disabledPlugins"] = disabled
        else:
            del config["disabledPlugins"]
    restores = [r for r in restores if r != clone]
    if restores:
        config["cloneSourceRestores"] = restores
    else:
        del config["cloneSourceRestores"]
    changed = True

if changed:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".shell.json.")
    with os.fdopen(fd, "w") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)
EOF
}

install_hook() {
  mkdir -p "$(dirname "$hook_file")"
  printf '#!/bin/bash\n# Keeps approved Ragtop overlays in step with Omarchy updates.\nhelper=%q\n[[ -x $helper ]] || exit 0\nexec "$helper" sync\n' "$self" >"$hook_file"
  chmod +x "$hook_file"
}

# Every step checks for itself rather than leaning on set -e. This runs as
# `install_one || status=1`, and bash switches errexit off for the whole of a
# function called on the left of ||, so a failed step used to fall through:
# the progress marker went, "Cloned and patched" was printed, and what was
# left was an unpatched clone with no marker and no .ragtop-base, which
# install, sync and remove all then refused as somebody else's.
install_one() {
  if [[ -d $clone_dir ]] && ! is_patched; then
    if [[ ! -f $progress_file ]]; then
      echo "$clone_dir exists but isn't Ragtop's, so leaving it alone." >&2
      return 1
    fi
    # Ours, cloned but never patched, by a run that was cut short. Start over.
    plugin remove "$clone_id" --yes >/dev/null || return 1
  fi
  if is_patched; then
    echo "$clone_id is already patched."
    return
  fi
  : >"$progress_file" || return 1
  if ! plugin clone "omarchy.$name" >/dev/null; then
    # Omarchy takes away what it made, but not what it told the shell.
    if [[ ! -e $clone_dir && ! -L $clone_dir ]]; then
      forget_clone
      rm -f "$progress_file"
      echo "Couldn't clone omarchy.$name, so Omarchy's own $name stays in use." >&2
    else
      echo "Couldn't clone omarchy.$name." >&2
    fi
    return 1
  fi
  if ! write_base || ! patch_clone; then
    # Usually an Omarchy update that changed the lines the patch looks for.
    # An unpatched clone is only a stale copy of the built-in, and for the
    # password prompt and the lock screen a stale copy is the worst thing to
    # leave running, so take it away and let the built-in stand.
    echo "Couldn't patch $clone_id, so it was removed and Omarchy's own $name stays in use." >&2
    plugin remove "$clone_id" --yes >/dev/null && rm -f "$progress_file"
    return 1
  fi
  rm -f "$progress_file"
  echo "Cloned and patched $clone_id."
}

sync_one() {
  if ! is_patched; then
    # Nothing to sync unless an earlier run left a clone half-made.
    if [[ -f $progress_file ]]; then
      install_one >/dev/null || return 1
      echo "Finished an interrupted $clone_id clone."
      synced=1
    fi
    return
  fi
  if in_sync; then
    echo "$clone_id matches the built-in, so nothing to sync."
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
    echo "$changed, but $clone_id has edits besides Ragtop's, so not replacing it." >&2
    notify "$(t clones.edited "$(t "overlay.name.$name")")"
    return 1
  fi
  plugin remove "$clone_id" --yes >/dev/null || return 1
  # Whatever goes wrong from here, install_one leaves either a patched clone or
  # none, and says which on stderr. Only a patched one has been synced.
  if ! install_one >/dev/null; then
    notify "$(t clones.removed "$(t "overlay.name.$name")")"
    return 1
  fi
  echo "$done_msg"
  synced=1
}

# Refresh approved clones without repeatedly disabling/enabling their IDs.
# Preparation is hidden from Omarchy's watcher; only complete replacements
# are published, in a short group of directory exchanges. Exceptional cases
# (interrupted installs or an unsupported new upstream shape) retain the
# existing recovery/fallback path.
sync_batch() {
  local batch_dir="" spec live record message result=0
  local -a records=() messages=()
  for spec in "${selected[@]}"; do
    select_overlay "$spec"
    if ! is_patched || in_sync || ! clone_is_ours; then
      sync_one || result=1
      continue
    fi
    if [[ -z $batch_dir ]]; then
      batch_dir=$(mktemp -d "$plugins_dir/.ragtop-sync.XXXXXX") || return 1
    fi
    live=$clone_dir
    if ! record=$(/usr/bin/python3 "$repo/overlay-publish.py" stage "$builtin_dir" "$live" "$batch_dir/$clone_id"); then
      result=1
      continue
    fi
    message="Re-cloned $clone_id from the updated built-in."
    if built_in_unchanged; then message="Re-patched $clone_id for this version of Ragtop."; fi
    clone_dir="$batch_dir/$clone_id"
    base_file="$clone_dir/.ragtop-base"
    if write_base && patch_clone && omarchy-plugin-validate "$clone_dir"; then
      records+=("$record")
      messages+=("$message")
    else
      # An obsolete authentication clone must not remain in service after
      # an upstream shape change that cannot be patched. Existing removal
      # restores the built-in and reports the compatibility failure.
      select_overlay "$spec"
      sync_one || result=1
    fi
  done
  if (( ${#records[@]} )); then
    if /usr/bin/python3 "$repo/overlay-publish.py" publish "${records[@]}"; then
      printf '%s\n' "${messages[@]}"
      echo "Applied ${#records[@]} overlay replacements together. Previous copies: $batch_dir"
      synced=1
    else
      echo "Overlay batch failed; inspect the staged/previous copies in $batch_dir" >&2
      result=1
    fi
  fi
  return "$result"
}

# One user-approved selection, including first-time additions/removals.
# Nothing live is touched until every requested change is prepared.
apply_selection() {
  local additions=$1 removals=$2 wanted spec operation batch_dir record live found
  local -a operations=() records=()
  for operation in add remove; do
    wanted=$additions
    [[ $operation == add ]] || wanted=$removals
    for name in $wanted; do
      found=""
      for spec in "${overlays[@]}"; do [[ ${spec%%:*} == "$name" ]] && found=$spec; done
      [[ -n $found ]] || { echo "Unknown overlay: $name" >&2; return 2; }
      [[ " $additions " != *" $name "* || " $removals " != *" $name "* ]] || {
        echo "Overlay cannot be both added and removed: $name" >&2; return 2;
      }
      [[ " ${operations[*]} " == *" $operation:$found "* ]] || operations+=("$operation:$found")
    done
  done
  if (( ${#operations[@]} == 0 )); then return 0; fi
  # Switching the active session-lock implementation while locked is unsafe.
  if command -v omarchy-hyprland-session-locked >/dev/null; then
    local lock_state=0
    omarchy-hyprland-session-locked || lock_state=$?
    if (( lock_state != 1 )); then
      echo "Overlay selection requires a confirmed unlocked desktop session; unlock it and retry from that session." >&2
      return 1
    fi
  fi
  batch_dir=$(mktemp -d "$plugins_dir/.ragtop-apply.XXXXXX") || return 1
  for spec in "${operations[@]}"; do
    operation=${spec%%:*}
    select_overlay "${spec#*:}"
    live=$clone_dir
    if [[ $operation == add ]]; then
      if is_patched; then continue; fi
      if [[ -e $live || -L $live ]]; then
        echo "$clone_id is not an approved Ragtop clone; nothing changed." >&2
        return 1
      fi
      record=$(/usr/bin/python3 "$repo/overlay-publish.py" stage "$builtin_dir" "$live" "$batch_dir/$clone_id") || return 1
      clone_dir="$batch_dir/$clone_id"
      base_file="$clone_dir/.ragtop-base"
      write_base && patch_clone && omarchy-plugin-validate "$clone_dir" || {
        echo "Could not prepare $clone_id; no overlay selections changed." >&2
        return 1
      }
    else
      if [[ ! -e $live && ! -L $live ]]; then continue; fi
      if ! clone_is_ours; then
        echo "$clone_id has edits besides Ragtop's; no overlay selections changed." >&2
        return 1
      fi
      record=$(/usr/bin/python3 "$repo/overlay-publish.py" remove "$live" "$batch_dir/$clone_id") || return 1
    fi
    records+=("$record")
  done
  if (( ${#records[@]} )); then
    /usr/bin/python3 "$repo/overlay-publish.py" apply "$HOME/.config/omarchy/shell.json" \
      "$omarchy_root/config/omarchy/shell.json" "${records[@]}" || return 1
    echo "Applied ${#records[@]} overlay selection changes together. Backups: $batch_dir"
  fi
  local remaining=0
  for spec in "${overlays[@]}"; do select_overlay "$spec"; is_patched && remaining=1; done
  if (( remaining )); then install_hook || return 1; else rm -f "$hook_file" || return 1; fi
  return 0
}

remove_one() {
  if [[ ! -d $clone_dir ]]; then
    echo "No $clone_id clone installed."
  elif ! clone_is_ours; then
    echo "$clone_id has edits besides Ragtop's. Remove it yourself with: omarchy plugin remove $clone_id" >&2
    return 1
  else
    plugin remove "$clone_id" --yes >/dev/null || return 1
    rm -f "$progress_file"
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

# For Ragtop's service, which raises the on-screen keyboard with an overlay
# and offers the picker its nav strip: prints the name of each overlay that
# lets a touch through to a surface above it, so that doing either is any
# use. Reads only.
#
# A Ragtop clone does. So does Omarchy's own overlay once it has the
# cooperative focus proposed in omacom/omarchy#13193, which an overlay opts
# into in its entry file. shell.json then has the last word: true turns it
# on and false turns it off. With neither, that Omarchy decides for itself,
# and cooperates while something other than its bar reserves part of the
# screen. Ragtop's keyboard and its handle both do, so it counts. An earlier
# form of the proposal had no such default and stayed off until asked, and
# is told apart by its shared window never mentioning "auto".
#
# Any other clone in the overlay's place is somebody else's and is not
# vouched for. The lock screen has no surface above it to reach.
cooperative_focus_setting() {
  /usr/bin/python3 - "$HOME/.config/omarchy/shell.json" <<'EOF' 2>/dev/null || true
import json, sys
overlays = json.load(open(sys.argv[1])).get("overlays")
setting = overlays.get("cooperativeFocus") if isinstance(overlays, dict) else None
print("true" if setting is True else "false" if setting is False else "")
EOF
}
cooperative_focus_is_automatic() { grep -qsF 'cooperativeFocus === "auto"' "$shared_window"; }
cooperative_focus_on() {
  case $(cooperative_focus_setting) in
    true) return 0 ;;
    false) return 1 ;;
    *) cooperative_focus_is_automatic ;;
  esac
}
tappable_one() {
  [[ $name != lock ]] || return 0
  if [[ -e $clone_dir || -L $clone_dir ]]; then
    if is_patched; then echo "$name"; fi
  elif grep -qs '^    cooperativeFocus: ' "$builtin_dir/$entry" && cooperative_focus_on; then
    echo "$name"
  fi
}

command="${1:-install}"
shift || true

# Startup sync, the update hook and Setup can overlap. Serialize mutations
# across processes so one never removes a clone another is still patching.
# Read-only probes do not create a lock or change the plugin directory.
case "$command" in
  install|sync|remove|apply)
    mkdir -p "$plugins_dir"
    exec 9>"$plugins_dir/.ragtop-overlays.lock"
    flock -x 9
    ;;
esac

if [[ $command == apply ]]; then
  [[ $# == 2 ]] || { echo 'Usage: overlay-clones.sh apply "add names" "remove names"' >&2; exit 2; }
  apply_selection "$1" "$2"
  exit $?
fi

selected=()
if (( $# == 0 )); then
  selected=("${overlays[@]}")
else
  for want in "$@"; do
    match=""
    for o in "${overlays[@]}"; do [[ ${o%%:*} == "$want" ]] && match="$o"; done
    [[ -n $match ]] || { echo "Unknown overlay: $want (expected: menu, emojis, clipboard, polkit, image-picker, lock)" >&2; exit 2; }
    [[ " ${selected[*]} " == *" $match "* ]] || selected+=("$match")
  done
fi

status=0
synced=0
if [[ $command == sync ]]; then
  sync_batch || status=1
else
for o in "${selected[@]}"; do
  select_overlay "$o"
  case "$command" in
    install) install_one || status=1 ;;
    remove) remove_one || status=1 ;;
    status) status_one ;;
    installed) is_patched || status=1 ;;
    tappable) tappable_one ;;
    *) echo "Usage: $0 [install|sync|remove|status|installed|tappable] [menu|emojis|clipboard|polkit|image-picker|lock ...]" >&2; exit 2 ;;
  esac
done
fi

case "$command" in
  install)
    install_hook
    echo "Run omarchy-restart-shell to load the clones."
    ;;
  sync)
    (( synced )) && notify "$(t clones.updated)"
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
