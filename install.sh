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

# Set from the flags; see the usage text.
assume_yes=0
skip_udev=0
# "ask", or "on"/"off" from --overlays/--no-overlays.
overlays_choice=ask
overlays_enabled=0

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Ragtop's menu rows and the switch access rule both live in their own
# scripts, because the in-shell setup writes exactly the same things.
menu_block() { "$repo/menu-block.sh" "$1"; }

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
  offer_udev_rule && return
  warn "Alternatively, join its group and log in again (this also exposes your keyboards):"
  warn "  sudo usermod -aG $(stat -c %G "$path") $USER"
}

# offer_udev_rule: with permission, install the uaccess rule. The rule and
# everything that runs as root are in udev-rule.sh.
offer_udev_rule() {
  local rule
  rule=$("$repo/udev-rule.sh" rule)
  echo "   Ragtop can install a udev rule giving the logged-in user read access"
  echo "   to switch devices only (tablet mode, lid, headphone jack; never keyboards):"
  printf '     %s\n' $rule
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
  if "$repo/udev-rule.sh" install >/dev/null; then
    echo "   installed; the switch is readable now"
  else
    warn "couldn't install the rule."
    return 1
  fi
}

remove_udev_rule() {
  if (( skip_udev )); then
    echo "   left alone (--no-udev)"
    return 0
  fi
  echo "   removing the switch access rule needs your password"
  "$repo/udev-rule.sh" remove && echo "   removed" || warn "couldn't remove it."
}

# Touch typing in Omarchy's own overlays means running patched clones of them
# from the user's config, so it's the one thing the installer asks about that
# changes Omarchy itself: offered once, off unless taken, and changeable per
# overlay afterwards in Setup › Tablet › System Overlays.
offer_overlays() {
  say "Touch typing in Omarchy's overlays"
  local on
  on=$("$repo/overlay-clones.sh" status | sed -n 's/^\([a-z-]*\): installed.*/\1/p' | tr '\n' ' ')
  on="${on% }"
  if [[ -n $on ]]; then
    echo "   already on for: $on"
    echo "   Change it per overlay in Setup › Tablet › System Overlays."
    return
  fi

  echo "   Omarchy's menu, its pickers, its password prompt and its lock screen can't"
  echo "   be worked by touch as they ship. Ragtop can run patched clones of them"
  echo "   instead: touch typing in each, a keyboard on the lock screen, and arrows"
  echo "   and a Select button for the theme and background pickers."
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

  # The password prompt comes first, because the polkit agent that shows it
  # may be one of the clones about to be removed: taking those away first
  # leaves pkexec with nothing to ask with, and the rule stays behind.
  say "Removing the switch access rule"
  remove_udev_rule

  say "Removing overlay clones"
  "$repo/overlay-clones.sh" remove | grep -v "omarchy-restart-shell" | sed 's/^/   /' || true

  say "Removing Ragtop's settings from the Omarchy menu"
  menu_block remove

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
