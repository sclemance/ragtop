#!/bin/bash
# What Setup does when you press Apply, as one script rather than as a command
# line assembled in QML.
#
# Usage: setup-apply.sh "<overlays to add>" "<overlays to remove>" "<overlays chosen>"
#
# It runs as a transient systemd unit, because copying an overlay replaces one
# of Omarchy's own plugins and the shell reloads its plugins when that happens
# — taking anything the shell owns down with it, mid-sentence. A unit outlives
# that. Keeping the work in a file also keeps shell syntax away from systemd's
# command-line parser, which expands ${...} itself and quietly turned one
# expansion into an empty string when this lived in the unit's ExecStart.
set -uo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
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
"$here/menu-block.sh" add
mkdir -p "$state"
printf 'overlays=%s\n' "$chosen" >"$state/install.conf"

[[ -n $add ]] && "$here/overlay-clones.sh" install $add
[[ -n $drop ]] && "$here/overlay-clones.sh" remove $drop

# However the copies went, the record describes the machine as it is.
on=""
for o in $overlays; do
  "$here/overlay-clones.sh" installed "$o" && on="$on $o"
done
printf 'overlays=%s\n' "${on# }" >"$state/install.conf"

# Say how it went, since the window that asked may be gone by now.
missing=""
for o in $add; do
  "$here/overlay-clones.sh" installed "$o" || missing="$missing $o"
done
if [[ -n $missing ]]; then
  notify "Ragtop setup" "Set up, but these overlays could not be copied:$missing. Run Setup again to retry."
else
  notify "Ragtop" "Setup is done."
fi

# Copies are only picked up when the shell starts.
[[ -n $add || -n $drop ]] && omarchy-restart-shell
exit 0
