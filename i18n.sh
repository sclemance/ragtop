#!/bin/bash
# Ragtop's own words for its scripts, sourced by `ragtop`, install.sh,
# overlay-clones.sh, setup-check.sh and setup-apply.sh, which set $repo first.
#
# In the language Omarchy is set to (Setup › Language,
# kept in ~/.config/omarchy/language), from i18n/<code>/cli.json, the form
# Omarchy's own catalogs take: English where a language lacks a string, the
# key itself where neither has it, and %1, %2 ... filled from the arguments
# after the key, so a translation puts them where its grammar wants. Only
# what a person reads: messages on the terminal stay English, as Omarchy's
# own command-line output does.
ragtop_language() {
  local code
  code=$(tr -d '[:space:]' 2>/dev/null <"${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/language" || true)
  [[ $code =~ ^[a-z]{2,3}(-[A-Za-z]{2})?$ ]] || code=en
  echo "$code"
}
t() {
  local key=$1 lang catalog
  shift
  lang=$(ragtop_language)
  catalog="$repo/i18n/$lang/cli.json"
  [[ -f $catalog ]] || catalog="$repo/i18n/en/cli.json"
  jq -rn --arg k "$key" --slurpfile en "$repo/i18n/en/cli.json" --slurpfile tr "$catalog" '
    ($tr[0][$k] // $en[0][$k] // $k) as $s
    | reduce range($ARGS.positional | length) as $i ($s;
        gsub("%" + ($i + 1 | tostring) + "(?![0-9])"; $ARGS.positional[$i]))' --args "$@"
}

