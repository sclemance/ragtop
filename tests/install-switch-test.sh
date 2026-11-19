#!/bin/bash
# The real terminal installer check, with no input device or privilege calls.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
copy="$sandbox/repo"
mkdir -p "$copy"
sandboxed /usr/bin/python3 - "$repo/install.sh" "$copy/check.sh" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
body=s.split('check_switch() {',1)[1].split('\n}\n',1)[0]
Path(sys.argv[2]).write_text('check_switch() {'+body+'\n}\n')
PY
printf '#!/bin/bash\nprintf "%%s\\tTest switch\\n" "$HOME/unreadable-device"\n' >"$copy/find-tablet-switch.py"
chmod +x "$copy/find-tablet-switch.py"
for outcome in 0 1; do
  out=$(sandboxed bash -c '
    repo=$1
    source "$repo/check.sh"
    t() { printf "%s" "$1"; }
    say() { :; }
    tell() { :; }
    warn() { printf "%s\n" "$*"; }
    outcome=$2
    offer_udev_rule() { return "$outcome"; }
    check_switch
  ' bash "$copy" "$outcome")
  assert_contains "$out" install.switchManual 'manual mode is offered if access remains unavailable'
  assert_lacks "$out" usermod
  assert_lacks "$out" install.joinGroup
  echo "ok - unreadable switch with rule outcome $outcome offers manual mode without group membership"
done
finish
