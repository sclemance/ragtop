#!/bin/bash
# Shared by the test files. Each test gets a sandbox of its own: a HOME, a
# runtime dir and a copy of one of the Omarchy trees under fixtures/, so
# nothing a test does can reach the real ~/.config, the real Omarchy or the
# running shell. The environment is rebuilt from nothing for the same reason:
# with WAYLAND_DISPLAY or HYPRLAND_INSTANCE_SIGNATURE left in it, something
# under test could find the compositor.

tests_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(dirname -- "$tests_dir")
old_omarchy="$tests_dir/fixtures/omarchy-4.0.4"
new_omarchy="$tests_dir/fixtures/omarchy-7cc6a55"
# The first release with the shared OverlayWindow, which from here on reads
# qs.Commons to mirror itself for right-to-left languages.
rc_omarchy="$tests_dir/fixtures/omarchy-4.5.0-rc1"

failed=0
sandbox=""
# Every sandbox of a test file goes in here, so one trap clears them all,
# including the ones made inside run_test's subshells.
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ragtop-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

# make_sandbox <fixture tree>
make_sandbox() {
  sandbox=$(mktemp -d "$test_root/XXXXXX")
  mkdir -p "$sandbox/home" "$sandbox/tmp" "$sandbox/run"
  chmod 700 "$sandbox/run"
  cp -a "$1" "$sandbox/omarchy"
  # Always there on a real machine: it is where Ragtop itself is installed.
  plugins="$sandbox/home/.config/omarchy/plugins"
  mkdir -p "$plugins"
}

# Swaps the sandbox's Omarchy for another one, the way an update or a
# downgrade would.
switch_omarchy() {
  rm -rf "$sandbox/omarchy"
  cp -a "$1" "$sandbox/omarchy"
}

# Runs a command the way a session would, minus the session. Extra
# VAR=value arguments come first, as with env.
sandboxed() {
  env -i PATH="$tests_dir/stub-bin:/usr/bin:/bin" HOME="$sandbox/home" USER=tester \
    TMPDIR="$sandbox/tmp" XDG_RUNTIME_DIR="$sandbox/run" OMARCHY_PATH="$sandbox/omarchy" \
    STUB_LOG="$sandbox/calls.log" "$@"
}

# clones [VAR=value ...] <command> [overlay ...]: the real patcher. Leaves
# its output in $out and $err and its exit status in $rc.
clones() {
  local -a vars=()
  while [[ ${1:-} == *=* ]]; do vars+=("$1"); shift; done
  rc=0
  sandboxed "${vars[@]}" bash "$repo/overlay-clones.sh" "$@" >"$sandbox/out" 2>"$sandbox/err" || rc=$?
  out=$(<"$sandbox/out")
  err=$(<"$sandbox/err")
}

fail() {
  echo "  # $*"
  exit 1
}

assert_rc() {
  [[ $rc == "$1" ]] || fail "expected exit $1, got $rc${2:+ ($2)}
  # stdout: $out
  # stderr: $err"
}

# assert_contains <haystack> <needle> [what]
assert_contains() {
  local got="$1"
  # A whole source file is no help in a failure message.
  (( ${#got} <= 2000 )) || got="${got:0:400} ... (${#1} characters in all)"
  [[ $1 == *"$2"* ]] || fail "${3:-text} should contain: $2
  # got: $got"
}

assert_lacks() {
  [[ $1 != *"$2"* ]] || fail "${3:-text} should not contain: $2"
}

assert_equal() {
  [[ $1 == "$2" ]] || fail "${3:-values} differ
  # expected: $2
  # got:      $1"
}

assert_file() { [[ -f $1 ]] || fail "missing file: $1"; }
assert_no_path() { [[ ! -e $1 && ! -L $1 ]] || fail "should not exist: $1"; }

# How many times a fixed string occurs in a file.
count_in() { /usr/bin/python3 -c 'import sys; print(open(sys.argv[1]).read().count(sys.argv[2]))' "$1" "$2"; }

# What the stub CLI was asked to do, one call per line.
calls() { cat "$sandbox/calls.log" 2>/dev/null || true; }

# run_test <description> <function>: in a subshell, so a failed assertion
# ends that test and no other. Not written as `( ... ) || failed=1`: bash
# switches errexit off for everything on the left of ||.
run_test() {
  local result
  set +e
  result=$(set -e; "$2" 2>&1)
  local status=$?
  if (( status == 0 )); then
    echo "ok - $1"
  else
    echo "not ok - $1"
    [[ -z $result ]] || echo "$result"
    failed=1
  fi
}

# qml_harness <name> [file ...]: a directory in the sandbox to run
# tests/qml/<name>/shell.qml from, with the harness and the named files
# beside it. Leaves its path in $harness.
qml_harness() {
  harness="$sandbox/$1"
  mkdir -p "$harness"
  cp "$tests_dir/qml/Harness.qml" "$tests_dir/qml/$1/shell.qml" "${@:2}" "$harness/"
  # What qs.Commons resolves to: a folder of that name at the shell's root,
  # here a stand-in for the little of Omarchy's that a window reads.
  cp -r "$tests_dir/qml/Commons" "$harness/"
}

# with_clone <overlay> <entry file> <directory>: puts a patched clone's window
# where the harness can import it as <directory>. A real PanelWindow needs a
# compositor with layer shell, and a test has no business putting a surface
# on anybody's screen, so three things in the generated window are swapped:
# its base type becomes FakePanelWindow, and the WlrLayershell attached object
# and the Hyprland singleton become plain properties of that. Everything else
# is the file the patcher wrote. Entry.qml beside it is the window out of the patched entry file,
# bindings and all, in a stand-in for the rest of that file.
with_clone() {
  mkdir -p "$harness/$3"
  cp "$tests_dir"/qml/Fake*.qml "$harness/$3/"
  /usr/bin/python3 - "$plugins/tester.$1" "$2" "$tests_dir/qml/Entry.qml.in" "$harness/$3" <<'EOF'
import sys
clone, entry, template, out = sys.argv[1:]

def faked(text):
    text = text.replace("PanelWindow {", "FakePanelWindow {").replace("WlrLayershell.", "layershell.")
    return text.replace("Hyprland.monitors", "hyprland.monitors").replace("Hyprland.focusedMonitor", "hyprland.focusedMonitor").replace("Hyprland.refreshMonitors", "hyprland.refreshMonitors")

open(f"{out}/RagtopOverlayWindow.qml", "w").write(faked(open(f"{clone}/RagtopOverlayWindow.qml").read()))

# The window out of the patched entry file: from where it starts to the
# namespace line, which is the last thing it sets before what it draws.
lines = open(f"{clone}/{entry}").read().split("\n")
start = lines.index("  RagtopOverlayWindow {")
end = next(i for i in range(start, len(lines)) if "WlrLayershell.namespace:" in lines[i])
window = "\n".join(lines[start:end + 1])
open(f"{out}/Entry.qml", "w").write(open(template).read().replace("@WINDOW@", faked(window)))
EOF
}

# run_qml [VAR=value ...]: runs $harness/shell.qml under quickshell and relays
# each of its checks. Offscreen, so it has no display to draw on and no
# compositor to talk to, and under a timeout, so a test that never reaches
# its end cannot hang the run. Anything QML itself complains about counts as
# a failure: a binding that does not resolve is a broken clone.
run_qml() {
  local log="$sandbox/qml.log" line complaints
  if ! command -v quickshell >/dev/null; then
    echo "ok - ${harness##*/} # SKIP quickshell is not installed"
    return
  fi
  sandboxed QT_QPA_PLATFORM=offscreen "$@" timeout 60 quickshell -p "$harness/shell.qml" >"$log.raw" 2>&1
  sed 's/\x1b\[[0-9;]*m//g' "$log.raw" >"$log"
  while IFS= read -r line; do
    case "$line" in
    "TEST ok - "*) echo "${line#TEST }" ;;
    "TEST not ok - "*) echo "${line#TEST }"; failed=1 ;;
    esac
  done < <(grep -o 'TEST .*' "$log")
  complaints=$(grep -E 'TypeError|ReferenceError|Unable to assign|Cannot assign|Binding loop|is not a type|non-existent property|Failed to load' "$log" || true)
  if [[ -n $complaints ]]; then
    echo "not ok - ${harness##*/}: QML ran without complaint"
    echo "$complaints" | sed 's/^/  # /'
    failed=1
  fi
  if ! grep -q 'TEST done' "$log"; then
    echo "not ok - ${harness##*/}: ran to the end"
    tail -n 15 "$log" | sed 's/^/  # /'
    failed=1
  fi
}

finish() {
  if (( failed )); then
    echo "FAILED: ${BASH_SOURCE[1]##*/}"
    exit 1
  fi
  echo "passed: ${BASH_SOURCE[1]##*/}"
}
