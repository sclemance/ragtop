#!/bin/bash
# typed-record.js, loaded by quickshell offscreen: what each typing-memory
# setting keeps of what is typed, and that capitals and full stops still
# work with the least of it.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
qml_harness record "$repo/typed-record.js"
run_qml

finish
