#!/bin/bash
# Real probe process and retry timer, with an isolated lock IPC stand-in.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/rotation-lock"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
sandboxed /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
  "$tests_dir/qml/rotation-lock/shell.qml.in" "$harness/shell.qml"
mkdir -p "$sandbox/bin"
cat >"$sandbox/bin/omarchy-shell" <<'SH'
#!/bin/bash
read -r code answer <"$XDG_RUNTIME_DIR/probe"
[[ $answer != hang ]] || sleep 5
[[ $answer == empty ]] || printf '%s\n' "$answer"
exit "$code"
SH
chmod +x "$sandbox/bin/omarchy-shell"
run_qml PATH="$sandbox/bin:/usr/bin:/bin"
finish
