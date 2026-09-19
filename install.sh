#!/bin/bash
# Installs Fliparchy and the pieces it needs outside its plugin folder, or
# removes them again. Safe to re-run: each step checks before it changes
# anything.
#
# Usage: install.sh [--skip-polkit] [--no-overlays] [--no-restart]
#        install.sh uninstall [--no-restart]
set -euo pipefail

repo="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
id="sclemance.fliparchy"
plugins_dir="$HOME/.config/omarchy/plugins"
plugin_dir="$plugins_dir/$id"
state_dir="$HOME/.local/state/fliparchy"
gtk_css="$HOME/.config/gtk-3.0/gtk.css"
input_lua="$HOME/.config/hypr/input.lua"
layouts_hook="$HOME/.config/omarchy/hooks/post-update.d/fliparchy-layouts.hook"

# Lines added to the user's config. Each block is identified by its last
# line; the comment lines above it are removed with it on uninstall.
gtk_block=(
  "/* Fliparchy: on-screen keyboard styled from the active Omarchy theme */"
  "@import url(\"file://$state_dir/squeekboard.css\");"
)
input_block=(
  "-- Fliparchy: let SUPER shortcuts work from the on-screen keyboard's Super key."
  "-- Squeekboard uploads its own keymap, so match its keys by symbol, not keycode."
  'hl.device({ name = "hl-virtual-keyboard-squeekboard", resolve_binds_by_sym = true })'
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
  command -v iio-hyprland >/dev/null || { missing+=(iio-hyprland); hints+=("iio-hyprland-git (AUR)"); }
  command -v squeekboard >/dev/null || { missing+=(squeekboard); hints+=(squeekboard); }
  command -v evtest >/dev/null || { missing+=(evtest); hints+=(evtest); }
  command -v git >/dev/null || { missing+=(git); hints+=(git); }
  python3 -c "import yaml" 2>/dev/null || { missing+=(python-yaml); hints+=(python-yaml); }
  for cmd in omarchy omarchy-shell hyprctl gdbus; do
    command -v "$cmd" >/dev/null || die "$cmd not found; Fliparchy needs Omarchy 4 with Hyprland."
  done
  if (( ${#missing[@]} )); then
    die "missing ${missing[*]}. Install: ${hints[*]}"
  fi
  echo "   all present"
}

check_switch() {
  say "Looking for a tablet-mode switch"
  local device
  device=$(python3 - <<'EOF'
import re
for block in re.split(r"\n\s*\n", open("/proc/bus/input/devices").read()):
    handler = re.search(r"^H: Handlers=.*\b(event\d+)\b", block, re.M)
    sw = re.search(r"^B: SW=([0-9a-fA-F ]+)$", block, re.M)
    name = re.search(r'^N: Name="(.*)"', block, re.M)
    if handler and sw and int(sw.group(1).split()[-1], 16) & 2:
        print(f"/dev/input/{handler.group(1)}\t{name.group(1) if name else ''}")
        break
EOF
)
  if [[ -z $device ]]; then
    warn "no device reports a tablet-mode switch. Fliparchy will keep looking (a detachable's keyboard may add one),"
    warn "but tablet mode won't be detected until one appears. See 'Tablet-mode detection' in the README."
    return
  fi
  local path="${device%%$'\t'*}"
  echo "   found ${device#*$'\t'} at $path"
  if [[ ! -r $path ]]; then
    warn "$path isn't readable by $USER, so tablet mode can't be detected."
    warn "Add yourself to its group and log in again: sudo usermod -aG $(stat -c %G "$path") $USER"
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
  printf '#!/bin/bash\n# Regenerates Fliparchy'"'"'s keyboard layouts when squeekboard is upgraded.\n"%s" >/dev/null\n' \
    "$repo/squeekboard-layouts.py" >"$layouts_hook"
  chmod +x "$layouts_hook"
  echo "   regenerated after Omarchy updates by ${layouts_hook/#$HOME/\~}"
}

restart_shell() {
  say "Restarting the Omarchy shell"
  omarchy-restart-shell
}

install() {
  local overlays=(menu emojis clipboard polkit) restart=1 with_overlays=1
  for arg in "$@"; do
    case "$arg" in
      --skip-polkit) overlays=(menu emojis clipboard) ;;
      --no-overlays) with_overlays=0 ;;
      --no-restart) restart=0 ;;
      *) die "unknown option: $arg" ;;
    esac
  done

  check_deps
  check_switch
  link_plugin

  say "Theming the keyboard (GTK)"
  add_block "$gtk_css" "${gtk_block[@]}"

  say "Letting SUPER shortcuts work from the keyboard (Hyprland)"
  if [[ -f $input_lua ]]; then
    add_block "$input_lua" "${input_block[@]}"
  else
    warn "${input_lua/#$HOME/\~} not found; add this line to your Hyprland config yourself:"
    warn "  ${input_block[-1]}"
  fi

  install_layouts

  if (( with_overlays )); then
    say "Patching Omarchy's overlays for touch: ${overlays[*]}"
    "$repo/overlay-clones.sh" install "${overlays[@]}" | grep -v "omarchy-restart-shell" | sed 's/^/   /'
  fi

  (( restart )) && restart_shell
  say "Done. Fliparchy's icons appear in the bar in tablet mode."
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
  remove_block "$gtk_css" "${gtk_block[@]}"
  remove_block "$input_lua" "${input_block[@]}"

  say "Removing generated files and hooks"
  rm -f "$layouts_hook"
  rm -rf "$state_dir" "$HOME/.cache/fliparchy"
  rm -f "${XDG_RUNTIME_DIR:-/tmp}/fliparchy-mode"

  say "Removing the plugin"
  if plugin_enabled; then omarchy plugin disable "$id" >/dev/null && echo "   disabled"; fi
  if [[ -L $plugin_dir ]]; then
    rm "$plugin_dir" && echo "   unlinked ${plugin_dir/#$HOME/\~}"
  elif [[ -d $plugin_dir ]]; then
    echo "   left ${plugin_dir/#$HOME/\~} in place (remove it with: omarchy plugin remove $id)"
  fi

  (( restart )) && restart_shell
  say "Fliparchy removed."
}

case "${1:-}" in
  uninstall) shift; uninstall "$@" ;;
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) install "$@" ;;
esac
