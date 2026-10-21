#!/bin/bash
# predictor.py: reading a word list in wordfreq's own format, and what it
# suggests for a partly typed word. The list here is made up for the test,
# in the same format, so no wordfreq data lives in the repository: the real
# one is downloaded by `ragtop words install` (see the README).
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"

# wordlist <file> <rank:word ...>: writes a wordfreq "cB" list, a header and
# then one bucket of words per rank.
wordlist() {
  local file=$1; shift
  /usr/bin/python3 - "$file" "$@" <<'PY'
import gzip, struct, sys
def pack(v):
    if isinstance(v, bool): return b"\xc3" if v else b"\xc2"
    if isinstance(v, int): return bytes([v]) if v < 128 else b"\xcc" + bytes([v])
    if isinstance(v, str):
        b = v.encode()
        return (bytes([0xa0 | len(b)]) if len(b) < 32 else b"\xd9" + bytes([len(b)])) + b
    if isinstance(v, dict):
        return bytes([0x80 | len(v)]) + b"".join(pack(k) + pack(x) for k, x in v.items())
    if isinstance(v, list):
        head = bytes([0x90 | len(v)]) if len(v) < 16 else b"\xdc" + struct.pack(">H", len(v))
        return head + b"".join(pack(x) for x in v)
buckets = [[] for _ in range(700)]
for arg in sys.argv[2:]:
    rank, word = arg.split(":", 1)
    buckets[int(rank)].append(word)
with gzip.open(sys.argv[1], "wb") as f:
    f.write(pack([{"format": "cB", "version": 1}] + buckets))
PY
}

# suggest <list> <typed ...>: one line of suggestions per typed word. Lines
# in the array `pre` go first, for commands other than complete.
pre=()
suggest() {
  local list=$1; shift
  out=$(printf '%s\n' "${pre[@]}" "${@/#/complete }" | sandboxed /usr/bin/python3 "$repo/predictor.py" "$list" 2>&1) || true
}

words="$sandbox/en.msgpack.gz"
make_words() {
  wordlist "$words" 127:the 230:her 280:"don't" 300:he 325:help 380:held 400:hell \
    400:hello 425:beauty 430:beautiful 500:helm 520:receive 560:keyboard \
    600:helpful 300:0.5 400:2nd
}

completions_by_rank() {
  make_words
  suggest "$words" hel
  assert_contains "$out" "ready 14"
  # her is a far slip (see below), so it comes after every completion.
  assert_contains "$out" 'suggest ["help", "held", "hell", "hello", "helm", "helpful", "her"]'
}

case_follows_the_typing() {
  make_words
  suggest "$words" Hel HEL
  assert_contains "$out" 'suggest ["Help", "Held"'
  assert_contains "$out" 'suggest ["HELP", "HELD"'
}

one_slip_is_corrected() {
  make_words
  suggest "$words" recieve keybaord teh
  assert_contains "$out" 'suggest ["receive"]'
  assert_contains "$out" 'suggest ["keyboard"]'
  assert_contains "$out" 'suggest ["the"]'
}

# "hel" is on its way to help, not a slip for he.
shorter_words_wait_for_no_completion() {
  make_words
  suggest "$words" hel hex
  assert_lacks "$(sed -n 2p <<<"$out")" '"he"'
  assert_contains "$(sed -n 3p <<<"$out")" '"he"'
}

# A slip lands on a neighbouring key, so "hwlp" is help (e and w are
# neighbours) while "hel" is hardly her (l and r are not): her, far commoner
# than any completion, still comes after all of them.
slips_are_to_neighbouring_keys() {
  make_words
  suggest "$words" hwlp hel
  assert_contains "$(sed -n 2p <<<"$out")" '"help"'
  assert_contains "$(sed -n 3p <<<"$out")" '"helpful", "her"]'
}

# On a layout whose rows put r beside l, the same slip is a near one.
neighbours_follow_the_layout() {
  make_words
  pre=('rows [["q","w","e"],["a","l","r"]]')
  suggest "$words" hel
  assert_contains "$out" 'suggest ["help", "her",'
}

apostrophes_are_letters() {
  make_words
  suggest "$words" don
  assert_contains "$out" "\"don't\""
}

numbers_are_not_words() {
  make_words
  suggest "$words" 0 2
  assert_lacks "$out" "0.5"
  assert_lacks "$out" "2nd"
}

nothing_typed_nothing_offered() {
  make_words
  suggest "$words" "" qzx
  assert_equal "$(grep -c '^suggest \[\]$' <<<"$out")" 2 "empty suggestion lines"
}

a_missing_list_says_so() {
  suggest "$sandbox/nowhere.msgpack.gz" hel
  assert_contains "$out" "missing
suggest []"
}

a_wrong_file_is_refused() {
  printf 'not a word list' | gzip >"$words"
  suggest "$words" hel
  assert_contains "$out" "can't read the word list"
  assert_lacks "$out" "hel"
}

# ---- Swipes ---------------------------------------------------------------

# swipes <word ...>: the commands that place QWERTY's keys and then draw each
# word through the middle of its keys, every stop pushed a fixed third of a
# key off centre in a different direction, the way a finger misses. Fixed
# rather than random, so a failure is the same failure every run.
swipes() {
  /usr/bin/python3 - "$@" <<'PY'
import json, sys
U = 60.0
rows, off = ["qwertyuiop", "asdfghjkl", "zxcvbnm"], [0, 0.25, 0.75]
keys = {c: [(i + off[r]) * U + U / 2, r * U * 1.2 + U / 2] for r, row in enumerate(rows) for i, c in enumerate(row)}
print("keys " + json.dumps({"unit": U, "keys": keys}))
miss = [(0.33, 0.0), (0.0, 0.33), (-0.33, 0.0), (0.0, -0.33)]
for word in sys.argv[1:]:
    stops = [keys[c] for c in word]
    stops = [(x + miss[i % 4][0] * U, y + miss[i % 4][1] * U) for i, (x, y) in enumerate(stops)]
    path = []
    for a, b in zip(stops, stops[1:]):
        path += [(a[0] + (b[0] - a[0]) * t / 5, a[1] + (b[1] - a[1]) * t / 5) for t in range(5)]
    path.append(stops[-1])
    print("swipe " + json.dumps(path))
PY
}

swipe_words() {
  wordlist "$words" 127:the 230:her 260:there 280:here 300:he 325:help 400:hello \
    400:hell 420:world 430:would 440:word 500:keyboard 520:quick 540:brown 560:jumps
}

swiped_lines() { grep '^swiped ' <<<"$out"; }

a_swipe_spells_its_word() {
  swipe_words
  mapfile -t pre < <(swipes hello world keyboard quick brown jumps help)
  suggest "$words"
  assert_equal "$(swiped_lines | sed 's/^swiped \["\([^"]*\)".*/\1/' | tr '\n' ' ')" \
    "hello world keyboard quick brown jumps help " "first word of each swipe"
}

# A path that comes back to e is here, though her is commoner and its path
# runs along the same keys.
a_swipe_goes_by_where_it_ends() {
  swipe_words
  mapfile -t pre < <(swipes here her there the)
  suggest "$words"
  assert_equal "$(swiped_lines | sed 's/^swiped \["\([^"]*\)".*/\1/' | tr '\n' ' ')" \
    "here her there the " "first word of each swipe"
}

a_swipe_offers_the_runners_up() {
  swipe_words
  mapfile -t pre < <(swipes word)
  suggest "$words"
  assert_contains "$out" 'swiped ["word", '
  assert_contains "$(swiped_lines)" '"world"'
}

no_keys_no_swipe() {
  swipe_words
  pre=('swipe [[0,0],[100,0]]' 'swipe not json')
  suggest "$words"
  assert_equal "$(swiped_lines | tr '\n' ' ')" "swiped [] swiped [] " "swipes with no keys placed"
}

run_test "predictor: completions come most common first" completions_by_rank
run_test "predictor: suggestions take the typed word's capitals" case_follows_the_typing
run_test "predictor: a word typed with one slip is corrected" one_slip_is_corrected
run_test "predictor: a shorter correction waits until nothing completes" shorter_words_wait_for_no_completion
run_test "predictor: a changed letter is a slip only to a neighbouring key" slips_are_to_neighbouring_keys
run_test "predictor: which keys are neighbours follows the layout" neighbours_follow_the_layout
run_test "predictor: an apostrophe is part of a word" apostrophes_are_letters
run_test "predictor: numbers in the list are never suggested" numbers_are_not_words
run_test "predictor: nothing typed, nothing offered" nothing_typed_nothing_offered
run_test "predictor: a missing list says so and suggests nothing" a_missing_list_says_so
run_test "predictor: a file that is not a word list is refused, and says nothing typed" a_wrong_file_is_refused
run_test "predictor: a swipe spells the word drawn" a_swipe_spells_its_word
run_test "predictor: a swipe goes by where it ends, not only by which word is commoner" a_swipe_goes_by_where_it_ends
run_test "predictor: a swipe offers the runners-up" a_swipe_offers_the_runners_up
run_test "predictor: with no keys placed, or no path, a swipe spells nothing" no_keys_no_swipe
finish
