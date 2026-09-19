#!/bin/bash
# Installs Ragtop and the pieces it needs outside its plugin folder, or
# removes them again. Safe to re-run: each step checks before it changes
# anything.
#
# Usage: install.sh [--no-restart]
#        install.sh uninstall [--no-restart]
set -euo pipefail

repo="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
id="sclemance.ragtop"
plugins_dir="$HOME/.config/omarchy/plugins"
plugin_dir="$plugins_dir/$id"
state_dir="$HOME/.local/state/ragtop"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

# Lets the person logged in at the machine read switch devices (tablet mode,
# lid, jacks) without joining the `input` group, which would also expose
# every keyboard. Must sort before systemd's 73-seat-late.rules, which applies
# uaccess tags.
udev_rule_file="/etc/udev/rules.d/70-ragtop-tablet-switch.rules"
udev_rule='SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", ENV{ID_INPUT_KEY}!="1", TAG+="uaccess"'

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Ragtop's rows in the Omarchy menu (Setup › Tablet), written into the
# user's menu extension file between two marker comments. They go right after
# the opening brace, each with a trailing comma, which the menu's JSONC
# reader accepts, so they can't break whatever the user has below them.
# menu_block <add|remove>
menu_block() {
  python3 - "$1" "$menu_file" <<'EOF'
import json, os, sys
action, path = sys.argv[1:]
start = "  // Ragtop: tablet settings. Added by Ragtop's installer; removed by its uninstaller."
end = "  // End of Ragtop's tablet settings."
cmd = "$HOME/.config/omarchy/plugins/sclemance.ragtop/ragtop"

overlays = [
    ("menu", "\U000f035c", "Omarchy Menu"),
    ("emojis", "\U000f0785", "Emoji Picker"),
    ("clipboard", "\U000f014c", "Clipboard Picker"),
    ("polkit", "\U000f033e", "Password Prompt"),
    ("lock", "\U000f0ddb", "Lock Screen"),
]
rows = {
    "setup.tablet": dict(icon="\U000f04f6", label="Tablet", aliases=["tablet", "ragtop"],
                        when=f'[[ -x "{cmd}" ]]'),
    "setup.tablet.mode": dict(icon="\U000f04f6", label="Tablet Mode",
        description="Follow the hinge, or keep tablet mode on or off"),
    "setup.tablet.mode.auto": dict(icon="\U000f006a", label="Automatic",
        description="Tablet mode when the screen is folded back",
        checked=f'"{cmd}" tablet-mode is auto', action=f'"{cmd}" tablet-mode set auto'),
    "setup.tablet.mode.on": dict(icon="\U000f04f6", label="Always On",
        description="Tablet controls in laptop mode too",
        checked=f'"{cmd}" tablet-mode is on', action=f'"{cmd}" tablet-mode set on'),
    "setup.tablet.mode.off": dict(icon="\U000f0322", label="Always Off",
        description="Never switch to tablet mode",
        checked=f'"{cmd}" tablet-mode is off', action=f'"{cmd}" tablet-mode set off'),
    "setup.tablet.auto-show": dict(icon="\U000f030c", label="Auto Keyboard",
        description="Bring the on-screen keyboard up when a text field gets focus in tablet mode",
        checked=f'"{cmd}" auto-show enabled',
        action=f'"{cmd}" auto-show toggle'),
    "setup.tablet.modifiers": dict(icon="\U000f0634", label="Modifier Keys",
        description="How Ctrl, Alt, Super and Shift behave on the on-screen keyboard"),
    "setup.tablet.modifiers.oneshot": dict(icon="\U000f0634", label="One-Shot",
        description="Apply to the next key only; tap twice to lock",
        checked=f'"{cmd}" modifiers is oneshot', action=f'"{cmd}" modifiers set oneshot'),
    "setup.tablet.modifiers.sticky": dict(icon="\U000f0634", label="Sticky",
        description="Stay on until tapped again",
        checked=f'"{cmd}" modifiers is sticky', action=f'"{cmd}" modifiers set sticky'),
    "setup.tablet.transparency": dict(icon="\U000f1853", label="Transparency",
        description="Let the desktop show through the on-screen keyboard's background"),
    **{f"setup.tablet.transparency.{level}": dict(icon="\U000f1853", label=label,
        checked=f'"{cmd}" transparency is {level}', action=f'"{cmd}" transparency set {level}')
       for level, label in (("auto", "Match Bar"), ("opaque", "Opaque"), ("low", "Low"),
                            ("medium", "Medium"), ("high", "High"), ("full", "Full"))},
    "setup.tablet.overlays": dict(icon="\U000f0328", label="System Overlays",
        description="Let the on-screen keyboard type into Omarchy's full-screen overlays in tablet mode"),
}
for name, icon, label in overlays:
    rows[f"setup.tablet.overlays.{name}"] = dict(
        icon=icon, label=label,
        description={
            "polkit": "Replaces Omarchy's password prompt with a patched copy that doesn't hold "
                      "the keyboard to itself in tablet mode",
            "lock": "Replaces Omarchy's lock screen with a patched copy that has an on-screen "
                    "keyboard in tablet mode",
        }.get(name, f"Replaces Omarchy's {label.lower()} with a patched copy"),
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
}

plugin_enabled() {
  omarchy plugin list --json 2>/dev/null |
    python3 -c "import json,sys; sys.exit(0 if any(p['id']=='$id' and p['enabled'] for p in json.load(sys.stdin)) else 1)"
}

plugin_discovered() {
  omarchy plugin list --json 2>/dev/null |
    python3 -c "import json,sys; sys.exit(0 if any(p['id']=='$id' for p in json.load(sys.stdin)) else 1)"
}

check_deps() {
  say "Checking dependencies"
  local missing=() hints=()
  command -v monitor-sensor >/dev/null || { missing+=(monitor-sensor); hints+=(iio-sensor-proxy); }
  command -v git >/dev/null || { missing+=(git); hints+=(git); }
  python3 -c "import pywayland" 2>/dev/null || { missing+=(python-pywayland); hints+=(python-pywayland); }
  python3 -c "import gi" 2>/dev/null || { missing+=(python-gobject); hints+=(python-gobject); }
  for cmd in omarchy omarchy-shell hyprctl gdbus; do
    command -v "$cmd" >/dev/null || die "$cmd not found; Ragtop needs Omarchy 4 with Hyprland."
  done
  if (( ${#missing[@]} )); then
    die "missing ${missing[*]}. Install: ${hints[*]}"
  fi
  echo "   all present"
}

check_switch() {
  say "Looking for a tablet-mode switch"
  local device
  device=$("$repo/find-tablet-switch.py")
  if [[ -z $device ]]; then
    warn "no device reports a tablet-mode switch. Ragtop will keep looking (a detachable's keyboard may add one),"
    warn "but tablet mode won't be detected until one appears. See 'Tablet-mode detection' in the README."
    return
  fi
  local path="${device%%$'\t'*}"
  echo "   found ${device#*$'\t'} at $path"
  [[ -r $path ]] && return
  warn "$path isn't readable by $USER, so tablet mode can't be detected."
  offer_udev_rule "$path" && return
  warn "Alternatively, join its group and log in again (this also exposes your keyboards):"
  warn "  sudo usermod -aG $(stat -c %G "$path") $USER"
}

# offer_udev_rule <device>: with permission, install the uaccess rule and
# re-apply it to the device. Succeeds if the device is readable afterwards.
offer_udev_rule() {
  local path="$1"
  echo "   Ragtop can install a udev rule giving the logged-in user read access"
  echo "   to switch devices only (tablet mode, lid, headphone jack; never keyboards):"
  echo "     $udev_rule_file"
  echo "     $udev_rule"
  if [[ ! -t 0 ]]; then
    warn "not running in a terminal, so not asking; re-run install.sh in one to install it."
    return 1
  fi
  local answer
  read -r -p "   Install it now? You'll be asked for your password. [y/N] " answer
  [[ $answer == [yY]* ]] || return 1

  as_root '
    printf "# Installed by Ragtop: read access to switch devices for the logged-in user.\n%s\n" "$1" >"$2"
    udevadm control --reload
    udevadm trigger --action=change "$3"
    udevadm settle
  ' "$udev_rule" "$udev_rule_file" "/sys/class/input/$(basename "$path")" || return 1
  if [[ -r $path ]]; then
    echo "   installed; $path is readable now"
  else
    warn "installed the rule, but $path still isn't readable."
    return 1
  fi
}

remove_udev_rule() {
  [[ -f $udev_rule_file ]] || return 0
  echo "   removing $udev_rule_file needs your password"
  if as_root '
    rm -f "$1"
    udevadm control --reload
    udevadm trigger --action=change --subsystem-match=input
  ' "$udev_rule_file"; then
    echo "   removed"
  else
    warn "couldn't remove it; delete it yourself: sudo rm $udev_rule_file"
  fi
}

# as_root <script> [args...]: run a bash script as root with one password
# prompt: Omarchy's polkit dialog via pkexec, or sudo if pkexec is missing.
as_root() {
  local script="$1"; shift
  if command -v pkexec >/dev/null; then
    pkexec /usr/bin/bash -c "$script" _ "$@"
  else
    sudo /usr/bin/bash -c "$script" _ "$@"
  fi
}

link_plugin() {
  say "Installing the plugin"
  if [[ $(realpath "$plugin_dir" 2>/dev/null) == "$repo" ]]; then
    echo "   ${plugin_dir/#$HOME/\~} is this checkout"
  elif [[ -e $plugin_dir || -L $plugin_dir ]]; then
    die "${plugin_dir/#$HOME/\~} already exists and isn't this checkout; remove it first."
  else
    mkdir -p "$plugins_dir"
    ln -s "$repo" "$plugin_dir"
    echo "   linked ${plugin_dir/#$HOME/\~} -> $repo"
  fi

  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  for (( i = 0; i < 40; i++ )); do plugin_discovered && break; sleep 0.1; done
  plugin_discovered || die "Omarchy didn't discover $id; check ${plugin_dir/#$HOME/\~}/manifest.json."
  if plugin_enabled; then
    echo "   already enabled"
  else
    omarchy plugin enable "$id" --section right >/dev/null
    echo "   enabled in the bar's right section"
  fi
}

restart_shell() {
  say "Restarting the Omarchy shell"
  omarchy-restart-shell
}

install() {
  local restart=1
  for arg in "$@"; do
    case "$arg" in
      --no-restart) restart=0 ;;
      *) die "unknown option: $arg" ;;
    esac
  done

  check_deps
  check_switch
  link_plugin

  say "Adding Ragtop's settings to the Omarchy menu (Setup › Tablet)"
  menu_block add || warn "couldn't edit ${menu_file/#$HOME/\~}; Ragtop's settings won't be in the menu."

  # Touch typing in Omarchy's overlays swaps in patched clones, so it stays
  # off until the user turns it on; `ragtop` records which ones are on.
  if [[ $("$repo/ragtop" overlay status) != *": installed"* ]]; then
    echo "   Touch typing in Omarchy's menu, pickers and password prompt is off. Turn it on per"
    echo "   overlay in Setup › Tablet › System Overlays."
  fi
  mkdir -p "$state_dir"
  [[ -f $state_dir/install.conf ]] || printf 'overlays=\n' >"$state_dir/install.conf"

  (( restart )) && restart_shell
  say "Done. Ragtop's icons appear in the bar in tablet mode."
}

uninstall() {
  local restart=1
  for arg in "$@"; do
    case "$arg" in
      --no-restart) restart=0 ;;
      *) die "unknown option: $arg" ;;
    esac
  done

  say "Removing overlay clones"
  "$repo/overlay-clones.sh" remove | grep -v "omarchy-restart-shell" | sed 's/^/   /' || true

  say "Removing Ragtop's settings from the Omarchy menu"
  menu_block remove

  say "Removing the switch access rule"
  remove_udev_rule

  say "Removing generated files"
  rm -rf "$state_dir" "$HOME/.config/ragtop"
  rm -f "${XDG_RUNTIME_DIR:-/tmp}/ragtop-mode"

  say "Removing the plugin"
  if plugin_enabled; then omarchy plugin disable "$id" >/dev/null && echo "   disabled"; fi
  if [[ -L $plugin_dir ]]; then
    rm "$plugin_dir" && echo "   unlinked ${plugin_dir/#$HOME/\~}"
  elif [[ -d $plugin_dir ]]; then
    echo "   left ${plugin_dir/#$HOME/\~} in place (remove it with: omarchy plugin remove $id)"
  fi

  (( restart )) && restart_shell
  say "Ragtop removed."
}

case "${1:-}" in
  uninstall) shift; uninstall "$@" ;;
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) install "$@" ;;
esac
