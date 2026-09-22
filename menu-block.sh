#!/bin/bash
# Ragtop's rows in the Omarchy menu (Setup › Tablet), written into the user's
# menu extension file between two marker comments. Both the installer and the
# in-shell setup use this, so the rows are written in exactly one place.
#
# Usage: menu-block.sh add|remove
set -euo pipefail

menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
case "${1:-}" in
  add|remove) ;;
  *) echo "Usage: $0 add|remove" >&2; exit 2 ;;
esac

python3 - "$1" "$menu_file" <<'EOF'
import json, os, sys, tomllib
action, path = sys.argv[1:]
start = "  // Ragtop: tablet settings. Added by Ragtop's installer; removed by its uninstaller."
end = "  // End of Ragtop's tablet settings."
cmd = "$HOME/.config/omarchy/plugins/sclemance.ragtop/ragtop"

# The themes Ragtop ships, plus the user's own, laid out as Omarchy lays its
# themes out: <slug>/ragtop.toml, and the user's own wins by slug. Omarchy's
# own look first, then the rest by name.
theme_dirs = [os.path.join(os.path.dirname(cmd.replace("$HOME", os.path.expanduser("~"))), "themes"),
              os.path.expanduser("~/.config/ragtop/themes")]
theme_labels = {}
for d in theme_dirs:
    if not os.path.isdir(d):
        continue
    for slug in sorted(os.listdir(d)):
        theme_path = os.path.join(d, slug, "ragtop.toml")
        if not os.path.isfile(theme_path):
            continue
        try:
            label = tomllib.load(open(theme_path, "rb")).get("name")
        except Exception:
            label = None
        theme_labels[slug] = label if isinstance(label, str) and label.strip() else slug
themes = sorted(theme_labels.items(), key=lambda row: (row[0] != "omarchy", row[0]))

overlays = [
    ("menu", "\U000f035c", "Omarchy Menu"),
    ("emojis", "\U000f0785", "Emoji Picker"),
    ("clipboard", "\U000f014c", "Clipboard Picker"),
    ("polkit", "\U000f033e", "Password Prompt"),
    ("image-picker", "\U000f056c", "Image Picker"),
    ("lock", "\U000f0ddb", "Lock Screen"),
]
rows = {
    "setup.tablet": dict(icon="\U000f04f6", label="Tablet", aliases=["tablet", "ragtop"],
                        when=f'[[ -x "{cmd}" ]]'),
    # Behaviour.
    "setup.tablet.mode": dict(icon="\U000f04f6", label="Tablet Mode"),
    "setup.tablet.mode.auto": dict(icon="\U000f006a", label="Automatic",
        checked=f'"{cmd}" tablet-mode is auto', action=f'"{cmd}" tablet-mode set auto'),
    "setup.tablet.mode.on": dict(icon="\U000f04f6", label="Always On",
        checked=f'"{cmd}" tablet-mode is on', action=f'"{cmd}" tablet-mode set on'),
    "setup.tablet.mode.off": dict(icon="\U000f0322", label="Always Off",
        checked=f'"{cmd}" tablet-mode is off', action=f'"{cmd}" tablet-mode set off'),
    "setup.tablet.auto-show": dict(icon="\U000f030c", label="Auto Keyboard",
        checked=f'"{cmd}" auto-show enabled',
        action=f'"{cmd}" auto-show toggle'),
    # Appearance. A theme writes the settings below, so what the menu
    # shows is always what the keyboard does.
    "setup.tablet.theme": dict(icon="\U000f03d8", label="Theme"),
    **{f"setup.tablet.theme.{name}": dict(icon="\U000f03d8", label=label,
        checked=f'"{cmd}" theme is {name}', action=f'"{cmd}" theme apply {name}')
       for name, label in themes},
    "setup.tablet.shape": dict(icon="\U000f0831", label="Key Shape"),
    **{f"setup.tablet.shape.{name}": dict(icon="\U000f0831", label=label,
        checked=f'"{cmd}" shape is {name}', action=f'"{cmd}" shape set {name}')
       for name, label in (("omarchy", "Omarchy"), ("rounded", "Rounded"), ("pill", "Pill"),
                           ("angular", "Angular"))},
    "setup.tablet.relief": dict(icon="\U000f0764", label="Key Relief"),
    **{f"setup.tablet.relief.{name}": dict(icon="\U000f0764", label=label,
        checked=f'"{cmd}" relief is {name}', action=f'"{cmd}" relief set {name}')
       for name, label in (("flat", "Flat"), ("raised", "Raised"))},
    "setup.tablet.fill": dict(icon="\U000f0764", label="Key Fill"),
    **{f"setup.tablet.fill.{name}": dict(icon="\U000f0764", label=label,
        checked=f'"{cmd}" fill is {name}', action=f'"{cmd}" fill set {name}')
       for name, label in (("auto", "Automatic"), ("dark", "Dark"), ("light", "Light"),
                           ("outline", "Outline"))},
    "setup.tablet.size": dict(icon="\U000f004c", label="Key Size"),
    **{f"setup.tablet.size.{name}": dict(icon="\U000f004c", label=label,
        checked=f'"{cmd}" size is {name}', action=f'"{cmd}" size set {name}')
       for name, label in (("compact", "Compact"), ("normal", "Normal"), ("large", "Large"))},
    "setup.tablet.key-transparency": dict(icon="\U000f1853", label="Key Transparency"),
    **{f"setup.tablet.key-transparency.{level}": dict(icon="\U000f1853", label=label,
        checked=f'"{cmd}" key-transparency is {level}', action=f'"{cmd}" key-transparency set {level}')
       for level, label in (("opaque", "Opaque"), ("low", "Low"), ("medium", "Medium"),
                            ("high", "High"), ("full", "Full"))},
    "setup.tablet.background": dict(icon="\U000f06a0", label="Background"),
    **{f"setup.tablet.background.{name}": dict(icon="\U000f06a0", label=label,
        checked=f'"{cmd}" background is {name}', action=f'"{cmd}" background set {name}')
       for name, label in (("tint", "Tint"), ("gradient", "Gradient"))},
    "setup.tablet.transparency": dict(icon="\U000f1853", label="BG Transparency"),
    **{f"setup.tablet.transparency.{level}": dict(icon="\U000f1853", label=label,
        checked=f'"{cmd}" transparency is {level}', action=f'"{cmd}" transparency set {level}')
       for level, label in (("auto", "Match Bar"), ("opaque", "Opaque"), ("low", "Low"),
                            ("medium", "Medium"), ("high", "High"), ("full", "Full"))},
    "setup.tablet.edge": dict(icon="\U000f08a6", label="Edge"),
    **{f"setup.tablet.edge.{name}": dict(icon="\U000f08a6", label=label,
        checked=f'"{cmd}" edge is {name}', action=f'"{cmd}" edge set {name}')
       for name, label in (("border", "Border"), ("fade", "Fade"), ("none", "None"))},
    "setup.tablet.overlays": dict(icon="\U000f0328", label="System Overlays"),
    "setup.tablet.setup": dict(icon="\U000f05b7", label="Run Setup",
        action=f'"{cmd}" setup'),
}
for name, icon, label in overlays:
    rows[f"setup.tablet.overlays.{name}"] = dict(
        icon=icon, label=label,
        checked=f'"{cmd}" overlay enabled {name}',
        action=f'"{cmd}" overlay toggle {name}')
block = [start] + [f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}," for k, v in rows.items()] + [end]

text = open(path).read() if os.path.exists(path) else ""
lines = text.split("\n")
if start in lines:
    i = lines.index(start)
    j = lines.index(end, i)
    del lines[i:j + 1]
    changed = "removed"
else:
    changed = None

if action == "add":
    if not text.strip():
        lines = ["{"] + block + ["}", ""]
    else:
        opening = next((i for i, l in enumerate(lines) if l.strip() == "{"), None)
        if opening is None:
            sys.exit("no line with just an opening brace")
        lines[opening + 1:opening + 1] = block
    changed = "updated" if changed else "added"

if changed:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write("\n".join(lines))
    print(f"   {changed} in {path.replace(os.path.expanduser('~'), '~', 1)}")
EOF
