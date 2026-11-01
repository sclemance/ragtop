#!/bin/bash
# Prints one line per missing piece of Ragtop's setup, and nothing when
# it's complete. Ragtop's service runs this at startup and offers to run
# install.sh if anything is printed.

dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
# Its reasons are read by a person, in the language Omarchy is set to.
repo=$dir
source "$repo/i18n.sh"
state="$HOME/.local/state/ragtop"
conf="$state/install.conf"

if [[ ! -f $conf ]]; then
  # Protocol, not prose, and so never translated: Service.qml opens setup
  # outright on this word rather than describing what is missing, and nobody
  # reads it. It was an English sentence once, matched as one, which a
  # translation would have quietly broken.
  echo "not-installed"
  exit 0
fi

# One line to fix all of them beats four lines naming them, both here and in
# the notification this feeds.
missing=()
command -v git >/dev/null || missing+=(git)
command -v monitor-sensor >/dev/null || missing+=(iio-sensor-proxy)
/usr/bin/python3 -c "import pywayland" 2>/dev/null || missing+=(python-pywayland)
/usr/bin/python3 -c "import gi" 2>/dev/null || missing+=(python-gobject)
(( ${#missing[@]} )) && t check.missing "omarchy pkg add ${missing[*]}"

grep -qsF "// Ragtop: tablet settings." "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" ||
  t check.noMenu

# Only the overlays the installer was asked to patch.
overlays=$(sed -n 's/^overlays=//p' "$conf")
for overlay in $overlays; do
  grep -qs "id: ragtopMode" "$HOME/.config/omarchy/plugins/$USER.$overlay"/*.qml ||
    t check.unpatched "$(t "overlay.name.$overlay")"
done

switch=$("$dir/find-tablet-switch.py" 2>/dev/null)
if [[ -n $switch && ! -r ${switch%%$'\t'*} ]]; then
  t check.switch
fi
exit 0
