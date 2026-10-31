#!/bin/bash
# What Setup does when you press Apply, as one script rather than as a command
# line assembled in QML.
#
# Usage: setup-apply.sh "<overlays to add>" "<overlays to remove>" "<overlays chosen>"
#
# It runs as a transient systemd unit, because copying an overlay replaces one
# of Omarchy's own plugins and the shell reloads its plugins when that happens
# taking anything the shell owns down with it, mid-sentence. A unit outlives
# that. Keeping the work in a file also keeps shell syntax away from systemd's
# command-line parser, which expands ${...} itself and quietly turned one
# expansion into an empty string when this lived in the unit's ExecStart.
set -uo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
repo="$here"
source "$repo/i18n.sh"
add="${1:-}"
drop="${2:-}"
chosen="${3:-}"
state="$HOME/.local/state/ragtop"
overlays="menu emojis clipboard polkit image-picker lock"

notify() {
  command -v omarchy-notification-send >/dev/null &&
    omarchy-notification-send -g 󰌌 "$1" "$2" || true
}

# The settings rows, and the record that this machine has been set up. The
# record is written before any overlay is touched: a service that reloads
# mid-way should find a machine that is set up, not offer setup again from
# the beginning.
menu_ok=true
"$here/menu-block.sh" add || menu_ok=false
mkdir -p "$state"
printf 'overlays=%s\n' "$chosen" >"$state/install.conf"

# Which are there now, to know afterwards whether anything changed.
before=""
for o in $overlays; do
  "$here/overlay-clones.sh" installed "$o" && before="$before $o"
done

apply_ok=true
"$here/overlay-clones.sh" apply "$add" "$drop" || apply_ok=false

# However the copies went, the record describes the machine as it is.
on=""
for o in $overlays; do
  "$here/overlay-clones.sh" installed "$o" && on="$on $o"
done
printf 'overlays=%s\n' "${on# }" >"$state/install.conf"

# Say how it went, since the window that asked may be gone by now: checked
# against the machine, so a copy that is still there after it was to go
# (one with edits of its own is kept on purpose) is reported, not missed.
names() {
  local o out=""
  for o in "$@"; do out="$out, $(t "overlay.name.$o")"; done
  echo "${out#, }"
}
missing=() kept=()
for o in $add; do
  "$here/overlay-clones.sh" installed "$o" || missing+=("$o")
done
for o in $drop; do
  "$here/overlay-clones.sh" installed "$o" && kept+=("$o")
done
problems=()
$apply_ok || problems+=("$(t setup.overlaysFailed)")
$menu_ok || problems+=("$(t setup.noMenu)")
((${#missing[@]})) && problems+=("$(t setup.notCopied "$(names "${missing[@]}")")")
((${#kept[@]})) && problems+=("$(t setup.notRemoved "$(names "${kept[@]}")")")
if ((${#problems[@]})); then
  notify "$(t setup.title)" "${problems[*]}"
else
  notify "Ragtop" "$(t setup.done)"
fi

# The completed directory/config batch is noticed by Omarchy's debounced
# plugin watcher. Do not restart the whole shell after its single reload.
((${#problems[@]} == 0))
