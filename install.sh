#!/bin/bash
# Installs Ragtop and the pieces it needs outside its plugin folder, or
# removes them again. Safe to re-run: each step checks before it changes
# anything.
#
# Usage: install.sh [--no-restart] [--yes] [--no-udev] [--overlays|--no-overlays]
#        install.sh uninstall [--no-restart] [--yes] [--no-udev]
#
#   --no-restart   don't restart the Omarchy shell at the end
#   --yes          don't ask anything, take the offer (the switch access rule
#                  still needs your password, in Omarchy's polkit dialog).
#                  Touch typing in Omarchy's overlays is the exception: it
#                  replaces part of Omarchy, so it stays off unless asked for.
#   --no-udev      leave the switch access rule alone, installing or removing
#   --overlays     turn touch typing on in all of Omarchy's overlays, without
#                  asking. The uninstaller removes them either way
#   --no-overlays  leave it off, without asking
set -euo pipefail

repo="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
id="sclemance.ragtop"
plugins_dir="$HOME/.config/omarchy/plugins"
plugin_dir="$plugins_dir/$id"
state_dir="$HOME/.local/state/ragtop"
config_dir="$HOME/.config/ragtop"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

# Set from the flags. See the usage text.
assume_yes=0
skip_udev=0
# "ask", or "on"/"off" from --overlays/--no-overlays.
overlays_choice=ask
overlays_enabled=0
overlays_failed=0

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
# What the installer says, in the language Omarchy is set to (i18n.sh):
# tell prints a catalog string as an indented paragraph, wrapped to fit,
# since a translation is rarely the length of the English.
source "$repo/i18n.sh"
tell() { t "$@" | fold -s -w 74 | sed 's/^/   /'; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Ragtop's menu rows and the switch access rule both live in their own
# scripts, because the in-shell setup writes exactly the same things.
menu_block() { "$repo/menu-block.sh" "$1"; }

plugin_enabled() {
  omarchy plugin list --json 2>/dev/null |
    /usr/bin/python3 -c "import json,sys; sys.exit(0 if any(p['id']=='$id' and p['enabled'] for p in json.load(sys.stdin)) else 1)"
}

plugin_discovered() {
  omarchy plugin list --json 2>/dev/null |
    /usr/bin/python3 -c "import json,sys; sys.exit(0 if any(p['id']=='$id' for p in json.load(sys.stdin)) else 1)"
}

check_deps() {
  say "$(t install.checking)"
  local missing=() hints=()
  command -v monitor-sensor >/dev/null || { missing+=(monitor-sensor); hints+=(iio-sensor-proxy); }
  command -v git >/dev/null || { missing+=(git); hints+=(git); }
  # The system Python by path, here and everywhere Ragtop runs Python: the
  # packages below are pacman's, installed for /usr/bin/python3 only, and a
  # mise or pyenv python3 earlier on the PATH would not see them.
  /usr/bin/python3 -c "import pywayland" 2>/dev/null || { missing+=(python-pywayland); hints+=(python-pywayland); }
  /usr/bin/python3 -c "import gi" 2>/dev/null || { missing+=(python-gobject); hints+=(python-gobject); }
  for cmd in omarchy omarchy-shell hyprctl gdbus; do
    command -v "$cmd" >/dev/null || die "$cmd not found; Ragtop needs Omarchy 4 with Hyprland."
  done
  if (( ${#missing[@]} )); then
    # A list of package names is a task, and a command is an answer.
    # Name the packages, not the commands that are missing: "monitor-sensor"
    # is not something anybody can install.
    warn "$(t install.missing "${hints[*]}")"
    tell install.missingHow
    echo
    echo "     omarchy pkg add ${hints[*]}"
    echo
    die "$(t install.thenAgain)"
  fi
  tell install.allPresent
}

check_switch() {
  say "$(t install.switch)"
  local device
  device=$("$repo/find-tablet-switch.py")
  if [[ -z $device ]]; then
    warn "$(t install.noSwitch)"
    return
  fi
  local path="${device%%$'\t'*}"
  tell install.found "${device#*$'\t'}" "$path"
  [[ -r $path ]] && return
  warn "$(t install.unreadable "$path" "$USER")"
  offer_udev_rule && return
  warn "$(t install.joinGroup)"
  warn "  sudo usermod -aG $(stat -c %G "$path") $USER"
}

# offer_udev_rule: with permission, install the uaccess rule. The rule and
# everything that runs as root are in udev-rule.sh.
offer_udev_rule() {
  local rule
  rule=$("$repo/udev-rule.sh" rule)
  tell install.ruleOffer
  # Quoted and split on newlines only: `rule` prints the file and the rule on
  # a line each, and unquoted the rule fell apart at every space.
  local line
  while IFS= read -r line; do printf '     %s\n' "$line"; done <<<"$rule"
  if (( skip_udev )); then
    tell install.ruleSkipped
    return 1
  fi
  if (( ! assume_yes )); then
    if [[ ! -t 0 ]]; then
      warn "$(t install.noTerminal)"
      return 1
    fi
    local answer
    # [y/N] is what the answer is read against, so every language keeps it.
    read -r -p "   $(t install.ruleAsk) " answer
    [[ $answer == [yY]* ]] || return 1
  fi
  if "$repo/udev-rule.sh" install >/dev/null; then
    tell install.ruleInstalled
  else
    warn "$(t install.ruleFailed)"
    return 1
  fi
}

remove_udev_rule() {
  if (( skip_udev )); then
    tell install.ruleSkipped
    return 0
  fi
  # The first line `rule` prints is where the rule lives. Only ask for a
  # password when there is one there to remove.
  local rule_file
  rule_file=$("$repo/udev-rule.sh" rule | head -n 1)
  if [[ ! -e $rule_file ]]; then
    tell uninstall.ruleNone
    return 0
  fi
  tell uninstall.rulePassword
  "$repo/udev-rule.sh" remove >/dev/null && echo "   removed" || warn "couldn't remove it."
}

# Touch typing in Omarchy's own overlays means running patched clones of them
# from the user's config, so it's the one thing the installer asks about that
# changes Omarchy itself: offered once, off unless taken, and changeable per
# overlay afterwards in Setup › Tablet › System Overlays.
offer_overlays() {
  say "$(t install.overlays)"
  local on
  on=$("$repo/overlay-clones.sh" status | sed -n 's/^\([a-z-]*\): installed.*/\1/p' | tr '\n' ' ')
  on="${on% }"
  if [[ -n $on ]]; then
    tell install.overlaysOn "$on"
    tell install.overlaysChange
    return
  fi

  tell install.overlaysWhy
  tell install.overlaysCatch

  case "$overlays_choice" in
    on) echo "   turning all of them on (--overlays)" ;;
    off) echo "   left off (--no-overlays)"; return ;;
    *)
      if (( assume_yes )); then
        tell install.overlaysSkipped
        return
      fi
      if [[ ! -t 0 ]]; then
        tell install.overlaysNoTerminal
        return
      fi
      local answer
      read -r -p "   $(t install.overlaysAsk) " answer
      if [[ $answer != [yY]* ]]; then
        tell install.overlaysLeftOff
        return
      fi
      ;;
  esac

  # The overlays are optional, so a failure here is no reason to leave the
  # install half-finished: Ragtop is linked and enabled by now, and the
  # restart and the closing message still matter. The selection is all or
  # nothing, so nothing was changed, and this asks again on the next run.
  if ! "$repo/overlay-clones.sh" apply "menu emojis clipboard polkit image-picker lock" ""; then
    record_overlays
    warn "$(t install.overlaysFailed)"
    overlays_failed=1
    return
  fi
  overlays_enabled=1
  record_overlays
}

# Which overlays are on, for setup-check.sh: it tells a clone that went
# missing from one that was never wanted. `ragtop` keeps this in step after.
record_overlays() {
  local on=() o
  for o in menu emojis clipboard polkit image-picker lock; do
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
  say "$(t install.plugin)"
  if [[ $(realpath "$plugin_dir" 2>/dev/null) == "$repo" ]]; then
    tell install.isCheckout "${plugin_dir/#$HOME/\~}"
  elif [[ -e $plugin_dir || -L $plugin_dir ]]; then
    die "$(t install.exists "${plugin_dir/#$HOME/\~}")"
  else
    mkdir -p "$plugins_dir"
    ln -s "$repo" "$plugin_dir"
    tell install.linked "${plugin_dir/#$HOME/\~}" "$repo"
  fi

  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  for (( i = 0; i < 40; i++ )); do plugin_discovered && break; sleep 0.1; done
  plugin_discovered || die "Omarchy didn't discover $id. Check ${plugin_dir/#$HOME/\~}/manifest.json."
  if plugin_enabled; then
    tell install.alreadyEnabled
  else
    omarchy plugin enable "$id" --section right >/dev/null
    tell install.enabled
  fi
}

# Everything Ragtop generates outside its own folder. Not the themes and
# presets under ~/.config/ragtop: those are the user's own work, which Ragtop
# only reads, and an uninstall is no reason to destroy them. They stay, and
# the folder with them, until the user removes it.
remove_files() {
  rm -rf "$state_dir"
  if [[ -d $config_dir ]]; then
    find "$config_dir" -mindepth 1 -maxdepth 1 ! -name themes ! -name presets -exec rm -rf {} +
    rmdir "$config_dir" 2>/dev/null || true
  fi
  if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
    rm -f "$XDG_RUNTIME_DIR"/ragtop-*.json "$XDG_RUNTIME_DIR/ragtop-mode"
  fi
}

restart_shell() {
  say "$(t install.restart)"
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

  say "$(t install.menu)"
  menu_block add || warn "couldn't edit ${menu_file/#$HOME/\~}; Ragtop's settings won't be in the menu."

  mkdir -p "$state_dir"
  [[ -f $state_dir/install.conf ]] || printf 'overlays=\n' >"$state_dir/install.conf"
  offer_overlays

  if (( restart )); then
    restart_shell
  elif (( overlays_enabled )); then
    warn "$(t install.restartForClones)"
  fi
  say "$(t install.done)"
  # Still a failure to whoever asked for the overlays, --overlays included.
  if (( overlays_failed )); then exit 1; fi
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

  # The password prompt comes first, because the polkit agent that shows it
  # may be one of the clones about to be removed: taking those away first
  # leaves pkexec with nothing to ask with, and the rule stays behind.
  say "$(t uninstall.rule)"
  remove_udev_rule

  say "$(t uninstall.overlays)"
  if ! "$repo/overlay-clones.sh" apply "" "menu emojis clipboard polkit image-picker lock"; then
    die "$(t uninstall.overlaysFailed)"
  fi

  say "$(t uninstall.menu)"
  menu_block remove

  say "$(t uninstall.files)"
  remove_files

  say "$(t uninstall.plugin)"
  if plugin_enabled; then omarchy plugin disable "$id" >/dev/null && echo "   disabled"; fi
  if [[ -L $plugin_dir ]]; then
    rm "$plugin_dir" && echo "   unlinked ${plugin_dir/#$HOME/\~}"
  elif [[ -d $plugin_dir ]]; then
    tell uninstall.leftPlugin "${plugin_dir/#$HOME/\~}" "$id"
  fi

  if (( restart )); then
    restart_shell
    # The shell that was running kept writing these until it went down.
    remove_files
  fi
  if [[ -d $config_dir ]]; then
    tell uninstall.keptThemes "${config_dir/#$HOME/\~}"
  fi
  say "$(t uninstall.done)"
}

case "${1:-}" in
  uninstall) shift; uninstall "$@" ;;
  -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) install "$@" ;;
esac
