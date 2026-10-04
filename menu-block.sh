#!/bin/bash
# Ragtop's rows in the Omarchy menu (Setup › Tablet), written into the user's
# menu extension file between two marker comments. Both the installer and the
# in-shell setup use this, so the rows are written in exactly one place.
#
# Usage: menu-block.sh add|remove|check
#
# check says nothing and succeeds when the block in the file is already the
# one this version writes. It fails when a row is missing, when an older
# Ragtop left one behind, and when a theme of your own has appeared since.
set -euo pipefail

menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
case "${1:-}" in
  add|remove|check) ;;
  *) echo "Usage: $0 add|remove|check" >&2; exit 2 ;;
esac

/usr/bin/python3 - "$1" "$menu_file" <<'EOF'
import json, os, sys, tempfile, tomllib
action, path = sys.argv[1:]
# Protocol, not prose. This exact line is how the block is found again in the
# user's menu file, so an installed Ragtop would stop recognising its own rows
# if it changed: `add` would leave the old block behind and write a second one,
# and `remove` would find nothing. The semicolon stays for that reason alone.
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
    # Whether there is an on-screen keyboard at all. Separate from Tablet
    # Mode, which still decides tiling mode and the patched overlays: a
    # machine can be a tablet and still not want keys, or be a laptop and
    # want them. Icons are reused from the rows above rather than picked by
    # codepoint, since a guessed Nerd Font codepoint draws the wrong thing.
    "setup.tablet.keyboard": dict(icon="\U000f030c", label="Keyboard"),
    "setup.tablet.keyboard.sensor": dict(icon="\U000f006a", label="Follow Sensor",
        checked=f'"{cmd}" keyboard is sensor', action=f'"{cmd}" keyboard set sensor'),
    "setup.tablet.keyboard.on": dict(icon="\U000f030c", label="Always On",
        checked=f'"{cmd}" keyboard is on', action=f'"{cmd}" keyboard set on'),
    "setup.tablet.keyboard.off": dict(icon="\U000f0322", label="Always Off",
        checked=f'"{cmd}" keyboard is off', action=f'"{cmd}" keyboard set off'),
    # Which board the keyboard draws. Auto is the default and changes with
    # the screen, which is the point of it: folding into portrait can take a
    # real keyboard down to the mobile one rather than shrinking the keys.
    "setup.tablet.keyboard-layout": dict(icon="\U000f030c", label="Layout"),
    "setup.tablet.keyboard-layout.auto": dict(icon="\U000f006a", label="Automatic",
        checked=f'"{cmd}" keyboard-layout is auto', action=f'"{cmd}" keyboard-layout set auto'),
    "setup.tablet.keyboard-layout.mobile": dict(icon="\U000f004c", label="Mobile",
        checked=f'"{cmd}" keyboard-layout is mobile', action=f'"{cmd}" keyboard-layout set mobile'),
    "setup.tablet.keyboard-layout.60": dict(icon="\U000f030c", label="60%",
        checked=f'"{cmd}" keyboard-layout is 60', action=f'"{cmd}" keyboard-layout set 60'),
    "setup.tablet.keyboard-layout.75": dict(icon="\U000f030c", label="75%",
        checked=f'"{cmd}" keyboard-layout is 75', action=f'"{cmd}" keyboard-layout set 75'),
    "setup.tablet.keyboard-layout.80": dict(icon="\U000f030c", label="80% (TKL)",
        checked=f'"{cmd}" keyboard-layout is 80', action=f'"{cmd}" keyboard-layout set 80'),
    "setup.tablet.auto-show": dict(icon="\U000f030c", label="Auto Keyboard",
        checked=f'"{cmd}" auto-show enabled',
        action=f'"{cmd}" auto-show toggle'),
    # Appearance. A theme writes the settings below, so what the menu
    # shows is always what the keyboard does.
    "setup.tablet.theme": dict(icon="\U000f03d8", label="Theme"),
    **{f"setup.tablet.theme.{name}": dict(icon="\U000f03d8", label=label,
        checked=f'"{cmd}" theme is {name}', action=f'"{cmd}" theme apply {name}')
       for name, label in themes},
    # What a key looks like is the theme's to say (themes/<slug>/ragtop.toml).
    # What is left here is what no theme author can know: how big the keys
    # need to be on this screen for these eyes, and how much of the window
    # behind them has to stay readable.
    # The panel has a slider for this. A menu cannot slide, so the five names
    # stay as the coarse way in, and Auto joins them.
    "setup.tablet.size-adjust": dict(icon="\U000f004c", label="Key Size"),
    "setup.tablet.size-adjust.auto": dict(icon="\U000f006a", label="Automatic",
        checked=f'"{cmd}" size-adjust is auto', action=f'"{cmd}" size-adjust set auto'),
    **{f"setup.tablet.size-adjust.{name}": dict(icon="\U000f004c", label=label,
        checked=f'"{cmd}" size-adjust is {name}', action=f'"{cmd}" size-adjust set {name}')
       for name, label in (("smallest", "Smallest"), ("smaller", "Smaller"),
                           ("regular", "Regular"), ("larger", "Larger"),
                           ("largest", "Largest"))},
    "setup.tablet.overlays": dict(icon="\U000f0328", label="System Overlays"),
    "setup.tablet.setup": dict(icon="\U000f05b7", label="Run Setup",
        action=f'"{cmd}" setup'),
    # One tap puts everything a report needs on the clipboard, so nobody has
    # to find a terminal on a machine whose keyboard is folded away.
    "setup.tablet.diagnostics": dict(icon="\U000f085e", label="Diagnostics",
        action=f'"{cmd}" diagnostics copy'),
}
for name, icon, label in overlays:
    rows[f"setup.tablet.overlays.{name}"] = dict(
        icon=icon, label=label,
        checked=f'"{cmd}" overlay enabled {name}',
        action=f'"{cmd}" overlay toggle {name}')
block = [start] + [f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}," for k, v in rows.items()] + [end]

text = open(path).read() if os.path.exists(path) else ""
lines = text.split("\n")


def block_end(i):
    """Where the block that starts at line i ends. A start with no end after
    it means the file was edited by hand, and guessing where Ragtop's rows
    stop could take the user's own rows with them, so stop and say so."""
    try:
        return lines.index(end, i)
    except ValueError:
        shown = path.replace(os.path.expanduser("~"), "~", 1)
        sys.exit(f"{shown} has the line that starts Ragtop's settings but not the one "
                 f"that ends them ({end.strip()}). Put it back after Ragtop's rows, "
                 f"or delete Ragtop's rows by hand, then run this again.")


if action == "check":
    if start not in lines:
        sys.exit(1)
    i = lines.index(start)
    j = block_end(i)
    sys.exit(0 if lines[i:j + 1] == block else 1)

if start in lines:
    i = lines.index(start)
    j = block_end(i)
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
    # The whole of the user's menu file lives here, not only Ragtop's rows,
    # so it is written beside itself and renamed into place: a write cut
    # short leaves the old file whole rather than half of the new one. A
    # symlinked file (dotfiles) is written through to where it points.
    real = os.path.realpath(path)
    os.makedirs(os.path.dirname(real), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".omarchy-menu.", dir=os.path.dirname(real))
    try:
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(lines))
        if os.path.exists(real):
            os.chmod(tmp, os.stat(real).st_mode & 0o7777)
        os.replace(tmp, real)
    except BaseException:
        os.unlink(tmp)
        raise
    print(f"   {changed} in {path.replace(os.path.expanduser('~'), '~', 1)}")
EOF
