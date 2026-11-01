#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
if ! sandboxed /usr/bin/python3 "$tests_dir/terminal-helper.py" "$repo"; then failed=1; fi
finish
