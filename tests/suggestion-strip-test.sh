#!/bin/bash
# SuggestionStrip.qml, loaded by quickshell offscreen: which item a touch
# means, at the page arrows and scrolled. The keyboard asks it exactly this
# for every touch on the strip, so a wrong answer is a wrong word typed.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
qml_harness strip "$repo/SuggestionStrip.qml" "$tests_dir/qml/strip/KeyboardKey.qml"
run_qml

finish
