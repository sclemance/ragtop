#!/bin/bash
# Real theme parser and renderers, with inert shell tokens and a private HOME.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"
harness="$sandbox/theme"
mkdir -p "$harness"
cp -r "$tests_dir/qml/theme/Commons" "$tests_dir/qml/theme/Ui" "$harness/"
cp "$tests_dir/qml/Harness.qml" "$repo/KeyboardTheme.qml" "$repo/KeyboardKey.qml" \
   "$repo/SupportingTheme.qml" "$repo/SuggestionStrip.qml" \
   "$repo/SculptedKeycap.qml" "$repo/KeyIcon.qml" "$repo/KeyContrast.js" "$repo/GlowColors.js" "$repo/GlowPalette.qml" "$repo/KeyGlow.qml" "$repo/GlowRipple.qml" "$repo/GlowWave.js" "$repo/LockKeyboard.qml" "$repo/LockKeyIcon.qml" "$harness/"

theme_round_trip() {
  sandboxed bash "$repo/ragtop" theme apply focus
  local settings="$sandbox/home/.config/ragtop/settings.conf"
  assert_contains "$(cat "$settings")" 'contrast=strong' 'Focus contrast persisted'
  assert_contains "$(cat "$settings")" 'fill=surface' 'Focus surface persisted'
  sandboxed bash "$repo/ragtop" theme apply omarchy
  assert_lacks "$(cat "$settings")" 'contrast=' 'switching away clears the opt-in'
  assert_contains "$(cat "$settings")" 'fill=light' 'Omarchy fill restored'
}
run_test 'Focus applies and switching away restores legacy defaults' theme_round_trip

mkdir -p "$sandbox/home/.config/ragtop/themes/backlight-fixture"
cp "$tests_dir/fixtures/themes/backlight/ragtop.toml" "$sandbox/home/.config/ragtop/themes/backlight-fixture/ragtop.toml"

backlight_round_trip() {
  sandboxed bash "$repo/ragtop" theme apply backlight-fixture
  local settings="$sandbox/home/.config/ragtop/settings.conf"
  assert_contains "$(cat "$settings")" 'backlight=accent' 'Backlight persisted'
  sandboxed bash "$repo/ragtop" theme apply chiclet
  assert_lacks "$(cat "$settings")" 'backlight=' 'switching away clears backlighting'
}
run_test 'Backlight applies and switching away removes it' backlight_round_trip

ripple_round_trip() {
  local trial="$sandbox/home/.config/ragtop/themes/ripple-fixture"
  mkdir -p "$trial"
  cp "$tests_dir/fixtures/themes/backlight/ragtop.toml" "$trial/ragtop.toml"
  printf '\nbacklight-motion = "ripple"\nbacklight-press-color = "#e0af68"\n' >> "$trial/ragtop.toml"
  sandboxed bash "$repo/ragtop" theme apply ripple-fixture
  local settings="$sandbox/home/.config/ragtop/settings.conf"
  assert_contains "$(cat "$settings")" 'backlight-motion=ripple' 'trial motion persisted'
  assert_contains "$(cat "$settings")" 'backlight-press-color=#e0af68' 'trial colour persisted'
  sandboxed bash "$repo/ragtop" theme apply backlight-fixture
  assert_lacks "$(cat "$settings")" 'backlight-motion=' 'static fixture removes motion'
  assert_lacks "$(cat "$settings")" 'backlight-press-color=' 'static fixture removes alternate colour'
}
run_test 'Ripple trial applies and static fixture restores static light' ripple_round_trip

mkdir -p "$sandbox/home/.config/ragtop/themes/pudding-material"
cat >"$sandbox/home/.config/ragtop/themes/pudding-material/ragtop.toml" <<'THEME'
name = "Pudding material fixture"
shape = "rounded"
relief = "raised"
backlight = "accent"
keycap-material = "pudding"
wall-opacity = 50
THEME

animation_preference() {
  if sandboxed bash "$repo/ragtop" backlight-animation enabled; then fail 'animation must default off'; fi
  sandboxed bash "$repo/ragtop" backlight-animation enable
  sandboxed bash "$repo/ragtop" theme apply pudding-material
  sandboxed bash "$repo/ragtop" backlight-animation enabled || fail 'theme must preserve animation preference'
  local settings="$sandbox/home/.config/ragtop/settings.conf"
  assert_contains "$(cat "$settings")" 'wall-opacity=50' 'Pudding wall opacity persisted'
  sandboxed bash "$repo/ragtop" theme apply omarchy
  assert_lacks "$(cat "$settings")" 'keycap-material=' 'switching away clears material'
  sandboxed bash "$repo/ragtop" backlight-animation enabled || fail 'non-backlit theme must preserve preference'
  sandboxed bash "$repo/ragtop" backlight-animation disable
  if sandboxed bash "$repo/ragtop" backlight-animation enabled; then fail 'animation must disable'; fi
}
run_test 'Animation defaults off and preference survives theme changes' animation_preference

sculpted_round_trip() {
  sandboxed bash "$repo/ragtop" backlight-animation enable
  sandboxed bash "$repo/ragtop" theme apply sculpted
  local settings="$sandbox/home/.config/ragtop/settings.conf"
  assert_contains "$(cat "$settings")" 'keycap-profile=sculpted' 'Sculpted profile persisted'
  assert_contains "$(cat "$settings")" 'keycap-material=solid' 'Sculpted cap is solid'
  assert_contains "$(cat "$settings")" 'blur=off' 'Sculpted does not request frost'
  sandboxed bash "$repo/ragtop" backlight-animation enabled || fail 'Sculpted preserves animation preference'
  sandboxed bash "$repo/ragtop" theme apply pudding-material
  assert_lacks "$(cat "$settings")" 'keycap-profile=' 'switching away clears profile'
}
run_test 'Sculpted profile applies and clears independently of material' sculpted_round_trip

mechanical_preferences() {
  local settings="$sandbox/home/.config/ragtop/settings.conf"
  sandboxed bash "$repo/ragtop" theme apply sculpted
  assert_equal "$(sandboxed bash "$repo/ragtop" theme get)" mechanical 'old slug applies Mechanical'
  sandboxed bash "$repo/ragtop" theme is sculpted || fail 'old alias remains a valid theme query'
  sandboxed bash "$repo/ragtop" theme is mechanical || fail 'canonical theme query failed'
  assert_lacks "$(sandboxed bash "$repo/ragtop" theme list)" sculpted 'alias is not a duplicate theme'
  sandboxed bash "$repo/ragtop" mechanical-backlight disable
  sandboxed bash "$repo/ragtop" mechanical-shine-through disable
  sandboxed bash "$repo/ragtop" mechanical-material set frosted
  sandboxed bash "$repo/ragtop" backlight-animation enable
  sandboxed bash "$repo/ragtop" theme apply omarchy
  sandboxed bash "$repo/ragtop" theme apply mechanical
  assert_contains "$(cat "$settings")" 'mechanical-backlight=off' 'backlight preference survives themes'
  assert_contains "$(cat "$settings")" 'mechanical-shine-through=off' 'glyph preference survives themes'
  assert_equal "$(sandboxed bash "$repo/ragtop" mechanical-material get)" frosted 'material preference survives themes'
  sandboxed bash "$repo/ragtop" mechanical-material set plain
  sandboxed bash "$repo/ragtop" mechanical-backlight enable
  if sandboxed bash "$repo/ragtop" mechanical-shine-through enabled; then fail 'disabled shine preference forgotten'; fi
  sandboxed bash "$repo/ragtop" backlight-animation enabled || fail 'effect preference forgotten'
  if sandboxed bash "$repo/ragtop" mechanical-material set unknown >/dev/null 2>&1; then fail 'invalid material accepted'; fi
  assert_equal "$(sandboxed bash "$repo/ragtop" mechanical-material get)" plain 'invalid write leaves saved choice intact'
  sed -i 's/^theme=mechanical$/theme=sculpted/' "$settings"
  local before
  before=$(cat "$settings")
  sandboxed bash "$repo/ragtop" migrate
  assert_equal "$(cat "$settings")" "${before/theme=sculpted/theme=mechanical}" 'migration only renames selection'
  before=$(cat "$settings")
  sandboxed bash "$repo/ragtop" migrate
  assert_equal "$(cat "$settings")" "$before" 'migration is idempotent'
  # A user-authored theme named Sculpted keeps its identity and contents.
  mkdir -p "$sandbox/home/.config/ragtop/themes/sculpted"
  printf 'name = "My Sculpted"\nfill = "outline"\n' > "$sandbox/home/.config/ragtop/themes/sculpted/ragtop.toml"
  sandboxed bash "$repo/ragtop" theme apply sculpted
  sandboxed bash "$repo/ragtop" migrate
  assert_equal "$(sandboxed bash "$repo/ragtop" theme get)" sculpted 'user theme is not renamed'
  # Restore preferences so the existing independent QML suite starts neutral.
  sandboxed bash "$repo/ragtop" theme apply omarchy
}
run_test 'Mechanical aliases, migration and independent preferences persist' mechanical_preferences

palette_dir="$sandbox/home/.local/state/omarchy/current"
mkdir -p "$palette_dir/theme"
printf 'mode = "dark"\naccent = "#123456"\nblue = "#123456"\nbright_blue = "#7da6ff"\nbright_yellow = "#ff9e64"\n' > "$palette_dir/theme/colors.toml"
printf 'first\n' > "$palette_dir/theme.name"

sandboxed /usr/bin/python3 - "$repo" "$harness" <<'PY'
import json, pathlib, subprocess, sys
repo, harness = map(pathlib.Path, sys.argv[1:])
themes = {}
for path in sorted((repo / 'themes').glob('*/ragtop.toml')):
    output = subprocess.check_output(['bash', str(repo / 'ragtop'), 'theme', 'show', path.parent.name], text=True)
    themes[path.parent.name] = dict(line.split('=', 1) for line in output.splitlines() if '=' in line and line.split('=', 1)[1])
output = subprocess.check_output(['bash', str(repo / 'ragtop'), 'theme', 'show', 'backlight-fixture'], text=True)
backlight = dict(line.split('=', 1) for line in output.splitlines() if '=' in line and line.split('=', 1)[1])
(harness / 'ThemeData.js').write_text('.pragma library\nvar themes = ' + json.dumps(themes)
                                     + '\nvar backlight = ' + json.dumps(backlight) + '\n')
PY

if ! /usr/bin/python3 "$tests_dir/qml/extract.py" "$repo/Service.qml" \
    "$tests_dir/qml/theme/shell.qml.in" "$harness/shell.qml"; then
  failed=1
else
  run_qml
fi
finish
