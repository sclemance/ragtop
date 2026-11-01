#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
make_sandbox "$old_omarchy"
copy="$sandbox/repo"
mkdir -p "$copy" "$sandbox/home/.config/ragtop"
cp "$repo/install.sh" "$repo/i18n.sh" "$copy/"
cp -r "$repo/i18n" "$copy/"
printf '#!/bin/bash\necho "edited clone" >&2\nexit 1\n' >"$copy/overlay-clones.sh"
chmod +x "$copy/overlay-clones.sh"
ln -s "$copy" "$plugins/sclemance.ragtop"
printf 'keyboard=on\n' >"$sandbox/home/.config/ragtop/settings.conf"
printf '{"rows": []}\n' >"$sandbox/run/ragtop-layout.json"
rc=0
sandboxed bash "$copy/install.sh" uninstall --yes --no-udev --no-restart >"$sandbox/out" 2>"$sandbox/err" || rc=$?
[[ $rc == 1 ]] || fail 'uninstall did not stop on failed clone cleanup'
assert_file "$sandbox/home/.config/ragtop/settings.conf"
assert_file "$sandbox/run/ragtop-layout.json"
[[ -L $plugins/sclemance.ragtop ]] || fail 'plugin removed despite surviving clone'
assert_contains "$(cat "$sandbox/err")" 'Ragtop was kept'
assert_equal "$(calls)" '' 'no plugin IPC after failed cleanup'
echo 'ok - failed overlay cleanup preserves plugin, settings and runtime layout'
finish
