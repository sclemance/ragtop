#!/bin/bash
# Prints one line per missing piece of Ragtop's setup, and nothing when
# it's complete. Ragtop's service runs this at startup and offers to run
# install.sh if anything is printed.

dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
state="$HOME/.local/state/ragtop"
conf="$state/install.conf"

if [[ ! -f $conf ]]; then
  echo "The installer hasn't been run yet."
  exit 0
fi

command -v git >/dev/null || echo "Package missing: git"
command -v monitor-sensor >/dev/null || echo "Package missing: iio-sensor-proxy"
python3 -c "import pywayland" 2>/dev/null || echo "Package missing: python-pywayland"
python3 -c "import gi" 2>/dev/null || echo "Package missing: python-gobject"

grep -qsF "// Ragtop: tablet settings." "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc" ||
  echo "Ragtop's settings aren't in the Omarchy menu."

# Only the overlays the installer was asked to patch.
overlays=$(sed -n 's/^overlays=//p' "$conf")
for overlay in $overlays; do
  grep -qs "id: ragtopMode" "$HOME/.config/omarchy/plugins/$USER.$overlay"/*.qml ||
    echo "The $overlay overlay isn't patched for touch."
done

switch=$("$dir/find-tablet-switch.py" 2>/dev/null)
if [[ -n $switch && ! -r ${switch%%$'\t'*} ]]; then
  echo "Can't read the tablet-mode switch; the installer can fix this."
fi
exit 0
