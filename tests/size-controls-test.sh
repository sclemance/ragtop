#!/bin/bash
# The key-size controls' memory of what was asked (Service.qml, setSize and
# stepSize): retired once the setting says it or the write fails, so a change
# made elsewhere is what the next step starts from.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
harness="$sandbox/size"
mkdir -p "$harness"
cp "$tests_dir/qml/Harness.qml" "$harness/"
# The CLI, as far as this needs: fails while the flag file is there.
cat >"$harness/ragtop" <<'SH'
#!/bin/bash
[[ -e $RAGTOP_SIZE_FAIL ]] && exit 1
exit 0
SH
if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
  "$tests_dir/qml/size/shell.qml.in" "$harness/shell.qml"; then
  failed=1
else
  run_qml RAGTOP_SIZE_FAIL="$sandbox/size-fails"
fi
finish
