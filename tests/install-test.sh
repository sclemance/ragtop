#!/bin/bash
# The installer with overlays that fail to turn on: Ragtop itself is still
# installed and the run finishes, says why, and asks again the next time.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
copy="$sandbox/repo"
bin="$sandbox/bin"
mkdir -p "$copy" "$bin"
cp "$repo/install.sh" "$repo/i18n.sh" "$repo/manifest.json" "$copy/"
cp -r "$repo/i18n" "$copy/"
# No switch to look for, no menu file to edit.
printf '#!/bin/bash\n' >"$copy/find-tablet-switch.py"
printf '#!/bin/bash\nexit 0\n' >"$copy/menu-block.sh"
# Overlays: none installed, and apply fails until told otherwise.
cat >"$copy/overlay-clones.sh" <<EOF
#!/bin/bash
echo "\$*" >>"$sandbox/clones.log"
case "\$1" in
  apply) [[ -f "$sandbox/apply-works" ]] && exit 0
         [[ -f "$sandbox/hooks-fail" ]] && exit 3
         echo "Could not prepare tester.menu; no overlay selections changed." >&2; exit 1 ;;
  installed) exit 1 ;;
  status) [[ -f "$sandbox/menu-on" ]] && echo "menu: installed, in sync with the built-in"; exit 0 ;;
  hooks) [[ -f "$sandbox/hooks-fail" ]] && exit 3; touch "$sandbox/hooks-written" ;;
esac
exit 0
EOF
chmod +x "$copy"/*.sh "$copy/find-tablet-switch.py"
# Nothing here may reach the real shell or compositor.
for cmd in omarchy-shell hyprctl monitor-sensor; do printf '#!/bin/bash\nexit 0\n' >"$bin/$cmd"; done
cat >"$bin/omarchy" <<EOF
#!/bin/bash
if [[ "\$1 \$2" == "plugin list" ]]; then
  [[ -L "$plugins/sclemance.ragtop" ]] && echo '[{"id": "sclemance.ragtop", "enabled": true}]' || echo '[]'
  exit 0
fi
exec "$tests_dir/stub-bin/omarchy" "\$@"
EOF
chmod +x "$bin"/*

install_run() {
  rc=0
  sandboxed PATH="$bin:$tests_dir/stub-bin:/usr/bin:/bin" \
    bash "$copy/install.sh" --overlays --no-udev --no-restart >"$sandbox/out" 2>"$sandbox/err" || rc=$?
  out=$(<"$sandbox/out")
  err=$(<"$sandbox/err")
}

install_run
assert_rc 1 'failed overlays are still a failure to whoever asked for them'
[[ -L $plugins/sclemance.ragtop ]] || fail 'Ragtop was not linked'
assert_contains "$err" 'Could not prepare tester.menu'
assert_contains "$err" 'Ragtop is installed, but the system overlays could not be turned on'
assert_lacks "$err" 'setup log'
assert_contains "$out" "$(jq -r '."install.done"' "$repo/i18n/en/cli.json")" 'the install still runs to its end'
assert_equal "$(grep '^overlays=' "$sandbox/home/.local/state/ragtop/install.conf")" 'overlays=' 'no overlay recorded as on'
echo 'ok - failed overlays still finish the install, and say so'

touch "$sandbox/hooks-fail"
install_run
assert_rc 1
assert_contains "$err" "couldn't write its hooks"
assert_lacks "$err" 'could not be turned on'
echo 'ok - overlays on without their hooks say exactly that'
rm -f "$sandbox/hooks-fail"

touch "$sandbox/apply-works"
: >"$sandbox/clones.log"
install_run
assert_rc 0
assert_contains "$(cat "$sandbox/clones.log")" 'apply menu emojis clipboard polkit image-picker lock'
echo 'ok - running the installer again offers the overlays again'

# Overlays already on: a rerun, even with --no-restart, puts the hooks back.
touch "$sandbox/menu-on"
install_run
assert_rc 0
assert_file "$sandbox/hooks-written"
echo 'ok - a rerun with overlays on restores their hooks'
touch "$sandbox/hooks-fail"
install_run
assert_rc 1 'a rerun that cannot restore the hooks is not a success'
assert_contains "$err" "couldn't write its hooks"
echo 'ok - and says so when it cannot'
finish
