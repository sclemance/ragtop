#!/bin/bash
# Installs Ragtop and the pieces it needs outside its plugin folder, or
# removes them again. Safe to re-run: each step checks before it changes
# anything.
#
# Usage: install.sh [--no-restart] [--yes] [--no-udev] [--overlays|--no-overlays]
#        install.sh uninstall [--no-restart] [--yes] [--no-udev]
#
#   --no-restart   don't restart the Omarchy shell at the end
#   --yes          don't ask anything; take the offer (the switch access rule
#                  still needs your password, in Omarchy's polkit dialog).
#                  Touch typing in Omarchy's overlays is the exception: it
#                  replaces part of Omarchy, so it stays off unless asked for.
#   --no-udev      leave the switch access rule alone, installing or removing
#   --overlays     turn touch typing on in all of Omarchy's overlays, without
#                  asking; the uninstaller removes them either way
#   --no-overlays  leave it off, without asking
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

# Set from the flags; see the usage text.
assume_yes=0
skip_udev=0
# "ask", or "on"/"off" from --overlays/--no-overlays.
overlays_choice=ask
overlays_enabled=0

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

# The presets Ragtop ships, plus the user's own; a user file with the same
# name wins. Omarchy's own look first, then the rest by name.
preset_dirs = [os.path.join(os.path.dirname(cmd.replace("$HOME", os.path.expanduser("~"))), "presets"),
               os.path.expanduser("~/.config/ragtop/presets")]
preset_labels = {}
for d in preset_dirs:
    if not os.path.isdir(d):
        continue
    for f in sorted(os.listdir(d)):
        if not f.endswith(".json"):
            continue
        name = f[:-5]
        try:
            label = json.load(open(os.path.join(d, f))).get("name")
        except Exception:
            label = None
        preset_labels[name] = label if isinstance(label, str) and label.strip() else name
presets = sorted(preset_labels.items(), key=lambda row: (row[0] != "omarchy", row[0]))

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
    "setup.tablet.modifiers": dict(icon="\U000f0634", label="Modifier Keys"),
    "setup.tablet.modifiers.oneshot": dict(icon="\U000f0634", label="One-Shot",
        checked=f'"{cmd}" modifiers is oneshot', action=f'"{cmd}" modifiers set oneshot'),
    "setup.tablet.modifiers.sticky": dict(icon="\U000f0634", label="Sticky",
        checked=f'"{cmd}" modifiers is sticky', action=f'"{cmd}" modifiers set sticky'),
    # Appearance. A preset writes the settings below, so what the menu
    # shows is always what the keyboard does.
    "setup.tablet.preset": dict(icon="\U000f03d8", label="Preset"),
    **{f"setup.tablet.preset.{name}": dict(icon="\U000f03d8", label=label,
        checked=f'"{cmd}" preset is {name}', action=f'"{cmd}" preset apply {name}')
       for name, label in presets},
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
       for name, label in (("dark", "Dark"), ("light", "Light"), ("outline", "Outline"))},
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
  if (( skip_udev )); then
    echo "   left alone (--no-udev)"
    return 1
  fi
  if (( ! assume_yes )); then
    if [[ ! -t 0 ]]; then
      warn "not running in a terminal, so not asking; re-run install.sh in one, or pass --yes."
      return 1
    fi
    local answer
    read -r -p "   Install it now? You'll be asked for your password. [y/N] " answer
    [[ $answer == [yY]* ]] || return 1
  fi

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
  if (( skip_udev )); then
    echo "   left alone (--no-udev)"
    return 0
  fi
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

# Touch typing in Omarchy's own overlays means running patched clones of them
# from the user's config, so it's the one thing the installer asks about that
# changes Omarchy itself: offered once, off unless taken, and changeable per
# overlay afterwards in Setup › Tablet › System Overlays.
offer_overlays() {
  say "Touch typing in Omarchy's overlays"
  local on
  on=$("$repo/overlay-clones.sh" status | sed -n 's/^\([a-z]*\): installed.*/\1/p' | tr '\n' ' ')
  on="${on% }"
  if [[ -n $on ]]; then
    echo "   already on for: $on"
    echo "   Change it per overlay in Setup › Tablet › System Overlays."
    return
  fi

  echo "   Omarchy's menu, its emoji and clipboard pickers, its password prompt and"
  echo "   its lock screen can't be typed into by touch as they ship. Ragtop can run"
  echo "   patched clones of them instead, and give the lock screen a keyboard."
  echo "   The catch: a clone is Omarchy's own code — the password prompt and lock"
  echo "   screen included — copied from its root-owned folder into your config,"
  echo "   where anything running as you can rewrite it, and it stops taking"
  echo "   Omarchy's updates directly (a hook re-clones it after each update)."
  echo "   Leave this off if in doubt: you can turn each overlay on later in"
  echo "   Setup › Tablet › System Overlays. See 'Omarchy's overlays' in the README."

  case "$overlays_choice" in
    on) echo "   turning all of them on (--overlays)" ;;
    off) echo "   left off (--no-overlays)"; return ;;
    *)
      if (( assume_yes )); then
        echo "   left off; pass --overlays to turn them all on without asking"
        return
      fi
      if [[ ! -t 0 ]]; then
        echo "   left off; not running in a terminal, so not asking"
        return
      fi
      local answer
      read -r -p "   Turn all of them on now? [y/N] " answer
      if [[ $answer != [yY]* ]]; then
        echo "   left off"
        return
      fi
      ;;
  esac

  "$repo/overlay-clones.sh" install | grep -v "omarchy-restart-shell" | sed 's/^/   /' || true
  overlays_enabled=1
  record_overlays
}

# Which overlays are on, for setup-check.sh: it tells a clone that went
# missing from one that was never wanted. `ragtop` keeps this in step after.
record_overlays() {
  local on=() o
  for o in menu emojis clipboard polkit lock; do
    "$repo/overlay-clones.sh" installed "$o" && on+=("$o")
  done
  mkdir -p "$state_dir"
  local conf="$state_dir/install.conf"
  if [[ -f $conf ]] && grep -q '^overlays=' "$conf"; then
    sed -i "s/^overlays=.*/overlays=${on[*]}/" "$conf"
  else
    printf 'overlays=%s\n' "${on[*]}" >>"$conf"
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

# Everything Ragtop generates outside its own folder.
remove_files() {
  rm -rf "$state_dir" "$HOME/.config/ragtop"
  rm -f "${XDG_RUNTIME_DIR:-/tmp}"/ragtop-*.json "${XDG_RUNTIME_DIR:-/tmp}/ragtop-mode"
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
      --yes) assume_yes=1 ;;
      --no-udev) skip_udev=1 ;;
      --overlays) overlays_choice=on ;;
      --no-overlays) overlays_choice=off ;;
      *) die "unknown option: $arg" ;;
    esac
  done

  check_deps
  check_switch
  link_plugin

  say "Adding Ragtop's settings to the Omarchy menu (Setup › Tablet)"
  menu_block add || warn "couldn't edit ${menu_file/#$HOME/\~}; Ragtop's settings won't be in the menu."

  mkdir -p "$state_dir"
  [[ -f $state_dir/install.conf ]] || printf 'overlays=\n' >"$state_dir/install.conf"
  offer_overlays

  if (( restart )); then
    restart_shell
  elif (( overlays_enabled )); then
    warn "the clones load when the shell restarts: omarchy-restart-shell"
  fi
  say "Done. Ragtop's icons appear in the bar in tablet mode."
}

uninstall() {
  local restart=1
  for arg in "$@"; do
    case "$arg" in
      --no-restart) restart=0 ;;
      --yes) assume_yes=1 ;;
      --no-udev) skip_udev=1 ;;
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
  remove_files

  say "Removing the plugin"
  if plugin_enabled; then omarchy plugin disable "$id" >/dev/null && echo "   disabled"; fi
  if [[ -L $plugin_dir ]]; then
    rm "$plugin_dir" && echo "   unlinked ${plugin_dir/#$HOME/\~}"
  elif [[ -d $plugin_dir ]]; then
    echo "   left ${plugin_dir/#$HOME/\~} in place (remove it with: omarchy plugin remove $id)"
  fi

  if (( restart )); then
    restart_shell
    # The shell that was running kept writing these until it went down.
    remove_files
  fi
  say "Ragtop removed."
}

case "${1:-}" in
  uninstall) shift; uninstall "$@" ;;
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) install "$@" ;;
esac
