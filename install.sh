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
gtk_css="$HOME/.config/gtk-3.0/gtk.css"
input_lua="$HOME/.config/hypr/input.lua"
layouts_hook="$HOME/.config/omarchy/hooks/post-update.d/ragtop-layouts.hook"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

# Lets the person logged in at the machine read switch devices (tablet mode,
# lid, jacks) without joining the `input` group, which would also expose
# every keyboard. Must sort before systemd's 73-seat-late.rules, which applies
# uaccess tags.
udev_rule_file="/etc/udev/rules.d/70-ragtop-tablet-switch.rules"
udev_rule='SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", ENV{ID_INPUT_KEY}!="1", TAG+="uaccess"'

# Lines added to the user's config. Each block is identified by its last
# line; the comment lines above it are removed with it on uninstall.
gtk_block=(
  "/* Ragtop: on-screen keyboard styled from the active Omarchy theme */"
  "@import url(\"file://$state_dir/squeekboard.css\");"
)
input_block=(
  "-- Ragtop: let SUPER shortcuts work from the on-screen keyboard's Super key."
  "-- Squeekboard uploads its own keymap, so match its keys by symbol, not keycode."
  'hl.device({ name = "hl-virtual-keyboard-squeekboard", resolve_binds_by_sym = true })'
)
bindings_lua="$HOME/.config/hypr/bindings.lua"
bindings_block=(
  "-- Ragtop: the on-screen keyboard's gear key sends XF86Tools; open its settings."
  'o.bind("XF86Tools", "Ragtop settings", "omarchy menu summon setup.tablet")'
)

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# add_block <file> <lines...>: append the block unless its last line is there.
add_block() {
  local file="$1"; shift
  local key="${!#}"
  if [[ -f $file ]] && grep -qxF "$key" "$file"; then
    echo "   already in ${file/#$HOME/\~}"
    return
  fi
  mkdir -p "$(dirname "$file")"
  { [[ -s $file ]] && echo; printf '%s\n' "$@"; } >>"$file"
  echo "   added to ${file/#$HOME/\~}"
}

# remove_block <file> <lines...>: drop exactly those lines, plus a blank line
# left directly above them.
remove_block() {
  local file="$1"; shift
  [[ -f $file ]] || return 0
  python3 - "$file" "$@" <<'EOF'
import sys
path, *block = sys.argv[1:]
lines = open(path).read().split("\n")
out = []
for line in lines:
    if line in block:
        if line == block[0] and out and out[-1] == "":
            out.pop()
        continue
    out.append(line)
if out != lines:
    open(path, "w").write("\n".join(out))
    print(f"   removed from {path}")
EOF
}

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
    "setup.tablet.layout-sync": dict(icon="\U000f05ca", label="Match Layout",
        description="Give the on-screen keyboard the same layout as your Hyprland keyboard",
        checked=f'"{cmd}" layout-sync enabled',
        action=f'"{cmd}" layout-sync toggle'),
    "setup.tablet.auto-theme": dict(icon="\U000f03d8", label="Auto Theme",
        description="Style the on-screen keyboard from the current Omarchy theme",
        checked=f'"{cmd}" auto-theme enabled',
        action=f'"{cmd}" auto-theme toggle'),
    "setup.tablet.transparency": dict(icon="\U000f1853", label="Transparency",
        description="Let the desktop show through the on-screen keyboard's background",
        when=f'"{cmd}" auto-theme enabled'),
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
  command -v squeekboard >/dev/null || { missing+=(squeekboard); hints+=(squeekboard); }
  command -v evtest >/dev/null || { missing+=(evtest); hints+=(evtest); }
  command -v git >/dev/null || { missing+=(git); hints+=(git); }
  python3 -c "import yaml" 2>/dev/null || { missing+=(python-yaml); hints+=(python-yaml); }
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
  local file
  for file in "$udev_rule_file" "$old_udev_rule_file"; do
    [[ -f $file ]] || continue
    echo "   removing $file needs your password"
    if as_root '
      rm -f "$1"
      udevadm control --reload
      udevadm trigger --action=change --subsystem-match=input
    ' "$file"; then
      echo "   removed"
    else
      warn "couldn't remove it; delete it yourself: sudo rm $file"
    fi
  done
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

install_layouts() {
  say "Generating keyboard layouts with Esc, Tab, modifier and arrow keys"
  "$repo/squeekboard-layouts.py" | sed 's/^/   /'
  mkdir -p "$(dirname "$layouts_hook")"
  printf '#!/bin/bash\n# Regenerates Ragtop'"'"'s keyboard layouts when squeekboard is upgraded.\n"%s" >/dev/null\n' \
    "$repo/squeekboard-layouts.py" >"$layouts_hook"
  chmod +x "$layouts_hook"
  echo "   regenerated after Omarchy updates by ${layouts_hook/#$HOME/\~}"
}

restart_shell() {
  say "Restarting the Omarchy shell"
  omarchy-restart-shell
}

# Ragtop was called Fliparchy before 1.9.0. This moves a Fliparchy setup over
# to the new names, keeping its settings and the overlays that were turned on.
# Each step only acts on what it finds, so it does nothing on a fresh install.
old_udev_rule_file="/etc/udev/rules.d/70-fliparchy-tablet-switch.rules"
old_switch_device=""
migrate_from_fliparchy() {
  local old_id="sclemance.fliparchy" old_link="$plugins_dir/sclemance.fliparchy"
  local shell_json="$HOME/.config/omarchy/shell.json" hooks="$HOME/.config/omarchy/hooks/post-update.d"
  local old_menu_start="  // Fliparchy: tablet settings. Added by Fliparchy's installer; removed by its uninstaller."

  local in_bar=0
  jq -e --arg id "$old_id" '[.bar.layout[][]? | select(.id? == $id)] | length > 0' "$shell_json" >/dev/null 2>&1 && in_bar=1
  if ! (( in_bar )) && [[ ! -e $old_link && ! -L $old_link && ! -d $HOME/.config/fliparchy &&
        ! -d $HOME/.local/state/fliparchy ]] && ! grep -qsF "$old_menu_start" "$menu_file"; then
    return 0
  fi
  say "Moving your Fliparchy setup over to Ragtop"

  # The bar entry, keeping a switch-device override for the new one.
  if (( in_bar )); then
    old_switch_device=$(jq -r --arg id "$old_id" \
      '[.bar.layout[][]? | select(.id? == $id) | .tabletSwitchDevice // empty][0] // empty' "$shell_json")
    (source omarchy-shell-config
     commit '.bar.layout |= map_values(map(select(.id? != "sclemance.fliparchy")))')
    echo "   removed Fliparchy from the bar"
  fi
  if [[ -L $old_link ]]; then
    rm "$old_link" && echo "   unlinked ${old_link/#$HOME/\~}"
  elif [[ -d $old_link ]]; then
    warn "${old_link/#$HOME/\~} is a plugin folder, not a link; remove it with: omarchy plugin remove $old_id"
  fi

  # Settings, generated files and the squeekboard source cache.
  local dir
  for dir in .config .local/state .cache; do
    if [[ -d $HOME/$dir/fliparchy && ! -e $HOME/$dir/ragtop ]]; then
      mv "$HOME/$dir/fliparchy" "$HOME/$dir/ragtop" && echo "   moved ~/$dir/fliparchy to ~/$dir/ragtop"
    elif [[ -d $HOME/$dir/fliparchy ]]; then
      warn "both ~/$dir/fliparchy and ~/$dir/ragtop exist; left ~/$dir/fliparchy for you to remove"
    fi
  done

  # Config lines; the installer adds the renamed ones back afterwards.
  remove_block "$gtk_css" \
    "/* Fliparchy: on-screen keyboard styled from the active Omarchy theme */" \
    "@import url(\"file://$HOME/.local/state/fliparchy/squeekboard.css\");"
  remove_block "$input_lua" \
    "-- Fliparchy: let SUPER shortcuts work from the on-screen keyboard's Super key." \
    "-- Squeekboard uploads its own keymap, so match its keys by symbol, not keycode." \
    'hl.device({ name = "hl-virtual-keyboard-squeekboard", resolve_binds_by_sym = true })'
  remove_block "$bindings_lua" \
    "-- Fliparchy: the on-screen keyboard's gear key sends XF86Tools; open its settings." \
    'o.bind("XF86Tools", "Fliparchy settings", "omarchy menu summon setup.tablet")'
  if grep -qsF "$old_menu_start" "$menu_file"; then
    python3 - "$menu_file" "$old_menu_start" "  // End of Fliparchy's tablet settings." <<'EOF'
import sys
path, start, end = sys.argv[1:]
lines = open(path).read().split("\n")
i = lines.index(start)
del lines[i:lines.index(end, i) + 1]
open(path, "w").write("\n".join(lines))
EOF
    echo "   removed Fliparchy's rows from the Omarchy menu"
  fi
  rm -f "$hooks/fliparchy-layouts.hook" "$hooks/fliparchy-overlay-sync.hook" "$hooks/fliparchy-menu-sync.hook" \
    "${XDG_RUNTIME_DIR:-/tmp}/fliparchy-mode"

  # Overlay clones that were turned on: re-tag the patch in place, so they
  # stay on without being re-cloned, and re-register their sync hook.
  local overlay file clone migrated=()
  for overlay in menu:Menu.qml emojis:Emojis.qml clipboard:Clipboard.qml polkit:PolkitAgent.qml; do
    clone="$plugins_dir/$USER.${overlay%%:*}"
    file="$clone/${overlay#*:}"
    grep -qs 'id: fliparchyMode' "$file" || continue
    sed -i 's/fliparchyMode/ragtopMode/g; s#/fliparchy-mode"#/ragtop-mode"#' "$file"
    [[ -f $clone/.fliparchy-base ]] && mv "$clone/.fliparchy-base" "$clone/.ragtop-base"
    migrated+=("${overlay%%:*}")
  done
  if (( ${#migrated[@]} )); then
    "$repo/overlay-clones.sh" install "${migrated[@]}" >/dev/null
    echo "   kept overlay clones on: ${migrated[*]}"
  fi

  if [[ -f $old_udev_rule_file ]]; then
    echo "   the switch access rule keeps its old name, ${old_udev_rule_file}; it still"
    echo "   works, and the uninstaller removes it"
  fi
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
  migrate_from_fliparchy
  check_switch
  link_plugin
  if [[ -n $old_switch_device ]]; then
    omarchy bar set "$id" tabletSwitchDevice "$old_switch_device" >/dev/null &&
      echo "   kept your tablet-mode switch device: $old_switch_device"
  fi

  say "Theming the keyboard (GTK)"
  add_block "$gtk_css" "${gtk_block[@]}"

  say "Letting SUPER shortcuts work from the keyboard (Hyprland)"
  if [[ -f $input_lua ]]; then
    add_block "$input_lua" "${input_block[@]}"
  else
    warn "${input_lua/#$HOME/\~} not found; add this line to your Hyprland config yourself:"
    warn "  ${input_block[-1]}"
  fi

  say "Letting the keyboard's gear key open Ragtop's settings (Hyprland)"
  if [[ -f $bindings_lua ]]; then
    add_block "$bindings_lua" "${bindings_block[@]}"
  else
    warn "${bindings_lua/#$HOME/\~} not found; add this line to your Hyprland config yourself:"
    warn "  ${bindings_block[-1]}"
  fi

  install_layouts

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

  say "Removing config lines"
  if [[ -f $state_dir/input-sources.orig ]]; then
    "$repo/layout-sync.sh" --restore && echo "   restored GNOME's keyboard layout setting"
  fi
  menu_block remove
  remove_block "$gtk_css" "${gtk_block[@]}"
  remove_block "$input_lua" "${input_block[@]}"
  remove_block "$bindings_lua" "${bindings_block[@]}"

  say "Removing the switch access rule"
  remove_udev_rule

  say "Removing generated files and hooks"
  rm -f "$layouts_hook"
  rm -rf "$state_dir" "$HOME/.cache/ragtop" "$HOME/.config/ragtop"
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
