#!/bin/bash
# Read access to the tablet-mode switch, for the person logged in at the
# machine. Both the installer and the in-shell setup use this.
#
# Usage: udev-rule.sh status|install|remove
#
# status  prints "readable", "unreadable", "no-switch" or "installed-but-unreadable"
# install writes the rule and re-applies it; asks for a password through
#         Omarchy's polkit dialog (pkexec), never sudo unless pkexec is absent
# remove  takes it away again
#
# The rule gives the logged-in user read access to switch devices only —
# tablet mode, lid, headphone jack — and never to keyboards, which is what
# joining the `input` group would do. It must sort before systemd's
# 73-seat-late.rules, which is what applies uaccess tags.
set -euo pipefail

here="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
rule_file="/etc/udev/rules.d/70-ragtop-tablet-switch.rules"
rule='SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", ENV{ID_INPUT_KEY}!="1", TAG+="uaccess"'

# The whole of what runs as root: a literal script with a fixed shape, never
# a file from a directory the user can write to.
as_root() {
  local script="$1"; shift
  if command -v pkexec >/dev/null; then
    pkexec /usr/bin/bash -c "$script" _ "$@"
  else
    sudo /usr/bin/bash -c "$script" _ "$@"
  fi
}

switch_path() {
  local device
  device=$("$here/find-tablet-switch.py" 2>/dev/null) || true
  [[ -n $device ]] && printf '%s' "${device%%$'\t'*}"
}

case "${1:-}" in
  status)
    path=$(switch_path)
    if [[ -z $path ]]; then echo "no-switch"
    elif [[ -r $path ]]; then echo "readable"
    elif [[ -f $rule_file ]]; then echo "installed-but-unreadable"
    else echo "unreadable"
    fi
    ;;
  rule)
    printf '%s\n' "$rule_file" "$rule"
    ;;
  install)
    path=$(switch_path)
    [[ -n $path ]] || { echo "No tablet-mode switch found." >&2; exit 1; }
    as_root '
      printf "# Installed by Ragtop: read access to switch devices for the logged-in user.\n%s\n" "$1" >"$2"
      udevadm control --reload
      udevadm trigger --action=change "$3"
      udevadm settle
    ' "$rule" "$rule_file" "/sys/class/input/$(basename "$path")"
    [[ -r $path ]] || { echo "Installed the rule, but $path still isn't readable." >&2; exit 1; }
    echo "readable"
    ;;
  remove)
    [[ -f $rule_file ]] || exit 0
    as_root '
      rm -f "$1"
      udevadm control --reload
      udevadm trigger --action=change --subsystem-match=input
    ' "$rule_file"
    ;;
  *)
    echo "Usage: $0 status|rule|install|remove" >&2; exit 2 ;;
esac
