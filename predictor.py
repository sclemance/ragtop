#!/usr/bin/python3
"""Word suggestions for Ragtop's keyboard: what the word being typed could
be, for the suggestion strip (Service.qml).

Reads a word list from wordfreq (https://github.com/rspeer/wordfreq) in the
form wordfreq publishes it, downloaded by `ragtop words install`. That form
carries its licence, CC-BY-SA 4.0, with it, and its author asks that it not
be turned into a plain list that drops the attribution, so it is read as it
is rather than converted (see read_wordlist).

  predictor.py <words-dir> [<bundled-dir>]
                                       lists at <dir>/<lang>/small_<lang>.msgpack.gz,
                                       and pairs_<lang>.tsv.gz beside them, from
                                       the first folder that has them: downloads,
                                       then Ragtop's own (words/ in the repository)
  predictor.py <wordlist.msgpack.gz>   one list, as English

then commands on stdin, one per line:

  lang <code>         use that language's list, reading it the first time
  complete <word>     suggestions for a partly typed word
  rows <json>         the active layout's letter rows, [["q", "w", ...], ...],
                      which decide which keys are neighbours (QWERTY until
                      told)
  keys <json>         where each letter's key is, for swipes:
                      {"unit": key width, "keys": {"q": [x, y], ...}}
  term <json>         for a terminal: {"cwd", "line"}, the command line as far
                      as it has been typed, answered with commands or files
  after [<word> | -]   the word before the next one, alone for the start of a
                      sentence, - for not known: answered with the words
                      likeliest to come next, and used by every "complete"
                      until the next "after"
  forms <word>        the word's other forms, summed and sums for sum, for a
                      hold on a suggestion to offer
  join <a> <b>        two words typed one after the other, and whether they
                      were one word with a space in it: inter active
  swipe <json>        the path a finger drew across the keys, [[x, y], ...],
                      in the same coordinates
  peek <json>         the same for a path still being drawn, for the strip
                      to show the guess so far
  quit

and answers "ready <count>" once a single list is read, "ready <lang>
<count>" or "missing <lang>" for each "lang" (the service offers to fetch a
missing one), then "suggest <json>" for each "complete": a list of
words, most likely first, capitalised the way the typed word was, and
"forms <json>" for each "forms", most common first, "join <json>" for each
"join", {"word", "strong"} or {} when the two make no word, "dictionary
<lang> <name>" after each "ready <lang>", naming the spelling dictionary in
use, or - for none, "termsuggest <json>"
for each "term", [{"text", "note", "kind", "back"}] with kind command,
dir or file and back the characters of the line it replaces, and
"swiped <json>" for each "swipe", the words it most likely spelled, and
"peeked <json>" for each "peek", the same answer under its own name so a
guess so far is never taken for a finished word.

What is typed arrives here and nowhere else. It is never printed except as
the suggestions, which only the service reads, and never logged: a word
being typed may be part of a password.
"""

import bisect
import ctypes
import ctypes.util
import functools
import glob
import hashlib
import gzip
import heapq
import json
import math
import os
import shlex
import struct
import subprocess
import sys
import threading
import unicodedata

SHOWN = 8
# The next word, from which words follow which (Pairs): a word seen after
# the one before ranks by how often it follows it, and any other by how
# common it is at all, as if this much rarer, in centibels. Tuned with
# bench/bench.py.
CONTEXT_BACKOFF = 40
# What stands for the start of a sentence among the words before.
START = "<s>"
CAPITALS = "<capitals>"
# A correction is a word one edit away from what was typed, typed wrong.
# It ranks as if it were this much rarer, in wordfreq's centibels: a factor
# of ten, so a common word typed with one slip still comes before a rare
# word the letters happen to spell.
CORRECTION_PENALTY = 100
# A letter typed in place of another is a slip of the finger only when the
# two keys are neighbours. Any other swap is far less likely, and without
# this "hel" offered "her" as soon as "help".
FAR_SWAP_PENALTY = 300
QWERTY = [list("qwertyuiop"), list("asdfghjkl"), list("zxcvbnm")]
# Corrections only once a word is long enough to have a shape. One or two
# letters are one edit from half the dictionary.
CORRECT_FROM = 3
LETTERS = "abcdefghijklmnopqrstuvwxyz'"
# A word whose accents are not the ones typed still matches, since accents
# are what a touch keyboard makes hardest to type ("ete" finds "été"), but
# ranks as if this much rarer, so an accent that was typed is respected.
ACCENT_PENALTY = 30
# But an accent that was typed and that the word does not have is a choice
# the word goes against: "ét" is not on its way to "et".
TYPED_ACCENT_PENALTY = 300
MISSPELLING_GAP = 100
# Words that are only ever the first half of an elision, l' in l'été, and
# which wordfreq lists on their own because it splits there. Never offered
# as words; after one and an apostrophe, the rest is completed on its own.
ELISIONS = {
    "fr": {"l", "d", "j", "c", "n", "s", "m", "t", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu"},
}
# Letters that come apart into two, which decomposition does not do.
LIGATURES = {"œ": "oe", "æ": "ae"}


def fold(word):
    """`word` in plain lower-case letters: été as ete, œuvre as oeuvre. What
    a word is matched by, so the letters on the keys reach it."""
    word = "".join(LIGATURES.get(c, c) for c in word.lower())
    return "".join(c for c in unicodedata.normalize("NFD", word)
                   if not unicodedata.combining(c))


def read_msgpack(data):
    """The subset of MessagePack a wordfreq list uses: arrays, a small map,
    strings, small integers and booleans. Anything else is refused, since a
    file that needs more is not one this was written for."""
    def at(i):
        t = data[i]
        if t <= 0x7f:
            return t, i + 1
        if 0x90 <= t <= 0x9f:
            return items(i + 1, t & 0x0f)
        if t == 0xdc:
            return items(i + 3, struct.unpack_from(">H", data, i + 1)[0])
        if t == 0xdd:
            return items(i + 5, struct.unpack_from(">I", data, i + 1)[0])
        if 0x80 <= t <= 0x8f:
            out, i = {}, i + 1
            for _ in range(t & 0x0f):
                key, i = at(i)
                out[key], i = at(i)
            return out, i
        if 0xa0 <= t <= 0xbf:
            return text(i + 1, t & 0x1f)
        if t == 0xd9:
            return text(i + 2, data[i + 1])
        if t == 0xda:
            return text(i + 3, struct.unpack_from(">H", data, i + 1)[0])
        if t == 0xcc:
            return data[i + 1], i + 2
        if t in (0xc2, 0xc3):
            return t == 0xc3, i + 1
        raise ValueError(f"unexpected MessagePack type 0x{t:02x}")

    def items(i, n):
        out = []
        for _ in range(n):
            value, i = at(i)
            out.append(value)
        return out, i

    def text(i, n):
        if i + n > len(data):
            raise ValueError("string runs past the end")
        return data[i:i + n].decode("utf-8"), i + n

    value, _ = at(0)
    return value


def read_wordlist(path):
    """{word: rank}, rank being wordfreq's centibel bucket: 0 for a word
    that is every other word, 600 for one in a million. Lower is commoner.

    wordfreq's "cB" format is a header, then one list of words per bucket."""
    with gzip.open(path, "rb") as f:
        value = read_msgpack(f.read())
    if not isinstance(value, list) or not value or value[0] != {"format": "cB", "version": 1}:
        raise ValueError("not a wordfreq cB list")
    ranks = {}
    for rank, bucket in enumerate(value[1:]):
        for word in bucket:
            # Words only: wordfreq also counts numbers and tokens like
            # "0.0kwh", which are nothing anyone wants suggested.
            if isinstance(word, str) and word.replace("'", "").isalpha():
                ranks.setdefault(word, rank)
    return ranks


def cased(word, typed):
    """`word` capitalised the way `typed` was: HELLO for HEL, Hello for Hel."""
    if len(typed) > 1 and typed.isupper():
        return word.upper()
    if typed[:1].isupper():
        return word[:1].upper() + word[1:]
    return word


def accents(word):
    """How many letters of `word` carry an accent or are a ligature."""
    return sum(1 for c in word if fold_letter(c) != c)


# A letter at a time, remembered: there are only so many letters, and none of
# them is anything typed.
@functools.lru_cache(maxsize=512)
def fold_letter(c):
    return fold(c)


def spelled_right(words, ranks, folds=None):
    """`words` without the misspellings wordfreq also counts: "ete" and
    "garcon" beside "été" and "garçon", "étre" beside "être". A word goes when
    another with the same letters, as many accents or more, is at least ten
    times commoner. A word is never beaten by one with fewer accents: the real
    words without them are the commoner ones, "la" beside "là", "a" beside
    "à", and how far apart a real pair is overlaps with how far a misspelling
    is, so only the accents tell them apart."""
    # folds: {word: (folded, accent count)} worked out once for a list's
    # words (Predictor.folds). Asked here for the same words on every
    # keystroke, working them out each time was nine tenths of what a
    # suggestion cost.
    look = folds.get if folds else (lambda w: None)
    info = {w: look(w) or (fold(w), accents(w)) for w in words}
    best = {}  # folded letters -> [(accent count, rank)]
    for w in words:
        f, n = info[w]
        best.setdefault(f, []).append((n, ranks[w]))
    return [w for w in words
            if not any(n >= info[w][1] and ranks[w] - r >= MISSPELLING_GAP
                       for n, r in best[info[w][0]])]


def neighbours(rows):
    """{letter: set of letters on the keys around it}. Rows are staggered on
    every board, so a key touches the one before and after it, and the two
    or three nearest in the rows above and below."""
    out = {}
    for r, row in enumerate(rows):
        for c, key in enumerate(row):
            near = out.setdefault(key, set())
            for dr in (-1, 0, 1):
                if not 0 <= r + dr < len(rows):
                    continue
                for dc in (-1, 0, 1):
                    if (dr, dc) != (0, 0) and 0 <= c + dc < len(rows[r + dr]):
                        near.add(rows[r + dr][c + dc])
    return out


class Predictor:
    def __init__(self, ranks, lang="en"):
        self.lang = lang
        self.elisions = ELISIONS.get(lang, set())
        self.ranks = {w: r for w, r in ranks.items() if w not in self.elisions}
        self.words = sorted(self.ranks)
        # Each word's folded letters and accent count, once, here: only the
        # list's own words, never anything typed, which is not kept.
        self.folds = {w: (fold(w), accents(w)) for w in self.ranks}
        # Every word under its folded form, sorted, for prefix search, and by
        # it, for corrections.
        self.folded = sorted((f, w) for w, (f, _) in self.folds.items())
        self.keys = [f for f, _ in self.folded]
        self.by_fold = {}
        for f, w in self.folded:
            self.by_fold.setdefault(f, []).append(w)
        self.near = neighbours(QWERTY)
        # A spelling dictionary, when one is installed (Session.use), and
        # the stem index built from it in the background.
        self.dictionary = None
        self.stems = None
        # Which words follow which, when a pairs file is installed (use_pairs).
        self.pair_lines = {}
        self.capitals = set()

    def use_dictionary(self, dictionary, source):
        """Takes a dictionary for joins at once, and, for a language with no
        rules of its own for forms, builds its stem index in the background,
        with a dictionary of its own, since a Hunspell handle is not to be
        shared between threads. Forms are offered once it is done."""
        self.dictionary = dictionary
        if self.lang in FORMS:
            return

        path = stem_cache_path(dictionary, source, len(self.ranks))

        def build():
            # Read back when it was built before; otherwise built with a
            # dictionary of this thread's own, closed when done.
            index = load_stem_index(path)
            if index is None:
                mine = open_dictionary(self.lang)
                if not mine:
                    return
                try:
                    index = stem_index(sorted(self.ranks), mine, path)
                finally:
                    mine.close()
            self.stems = index
        threading.Thread(target=build, daemon=True).start()

    def stem_forms(self, word):
        """A word's forms by its stems: every word of the list with a stem it
        has, commonest first. Possessives only for a word that is one."""
        index = self.stems
        if index is None or self.dictionary is None:
            return []
        family = set()
        for s in set(self.dictionary.stems(word)) or {word}:
            family.update(index.get(s, ()))
        family.discard(word)
        return sorted((w for w in family if "'" not in w or "'" in word),
                      key=lambda w: (self.ranks[w], w))

    def set_rows(self, rows):
        if (isinstance(rows, list) and all(isinstance(r, list) for r in rows)
                and all(isinstance(k, str) for r in rows for k in r)):
            self.near = neighbours([[k.lower() for k in r] for r in rows])

    def rank(self, word, typed):
        """A word's rank for what was typed: its own, or worse by
        ACCENT_PENALTY when only its folded form matches the typing, and by
        TYPED_ACCENT_PENALTY when the typing has an accent the word lacks."""
        if word.startswith(typed):
            return self.ranks[word]
        against = any(t != w and fold_letter(t) != t for t, w in zip(typed, word))
        return self.ranks[word] + (TYPED_ACCENT_PENALTY if against else ACCENT_PENALTY)

    def completions(self, prefix):
        """(rank, word) for every word starting with `prefix`, accents or
        not."""
        key = fold(prefix)
        start = bisect.bisect_left(self.keys, key)
        for f, word in self.folded[start:]:
            if not f.startswith(key):
                break
            yield self.rank(word, prefix), word

    def corrections(self, typed):
        """(rank, word) for every word one edit away from `typed`: a letter
        dropped, added, changed, or two swapped."""
        typed = fold(typed)
        n = len(typed)
        edits = {}

        def add(word, penalty):
            if penalty < edits.get(word, 1 << 30):
                edits[word] = penalty

        for i in range(n + 1):
            head, tail = typed[:i], typed[i:]
            if tail:
                add(head + tail[1:], CORRECTION_PENALTY)
            if len(tail) > 1:
                add(head + tail[1] + tail[0] + tail[2:], CORRECTION_PENALTY)
            for c in LETTERS:
                if tail:
                    near = c in self.near.get(tail[0], ())
                    add(head + c + tail[1:], CORRECTION_PENALTY + (0 if near else FAR_SWAP_PENALTY))
                add(head + c + tail, CORRECTION_PENALTY)
        edits.pop(typed, None)
        for key, penalty in edits.items():
            for word in self.by_fold.get(key, ()):
                yield self.ranks[word] + penalty, word

    def use_pairs(self, path):
        """Which words follow which, from a pairs file (bench/pairs.py): a
        line per word, "word<TAB>follower count follower count ...", each
        word's commonest followers, START for the start of a sentence, and
        CAPITALS for the words always written with a capital.

        Kept as the lines themselves, by word, and a line read only when its
        word comes up (followers), a few dozen numbers at a time. Read whole
        into a dictionary per word, as it first was, they took forty
        megabytes and a third of a second at load; as lines, a few
        megabytes and a few hundredths."""
        lines = {}
        with gzip.open(path, "rt", encoding="utf-8") as f:
            for line in f:
                before, tab, rest = line.rstrip("\n").partition("\t")
                if tab:
                    lines[before] = rest
        caps = lines.pop(CAPITALS, "")
        self.capitals = set(caps.split())
        self.pair_lines = lines

    def followers(self, before):
        """(word, score) for each word known to follow `before`, commonest
        first, START for the start of a sentence: its share of what follows
        `before`, in centibels, the list's own measure. Only words of the
        list, and elisions, which are no words of the list but do follow
        words (j' at a sentence's start)."""
        rest = self.pair_lines.get(before) if before else None
        if not rest:
            return []
        parts = rest.split()
        kept = []
        for k in range(0, len(parts) - 1, 2):
            w, c = parts[k], parts[k + 1]
            if (w in self.ranks or w in self.elisions) and c.isdigit() and int(c) > 0:
                kept.append((w, int(c)))
        total = sum(c for _, c in kept)
        return [(w, round(-100 * math.log10(c / total))) for w, c in kept] if total else []

    def context(self, before):
        """{word: score} of what follows `before`, a few dozen at most, for
        ranking completions and swipes by it."""
        return dict(self.followers(before))

    def next(self, before):
        """The words likeliest to come after `before`, START at the start of
        a sentence, before a letter of them is typed. A French elision comes
        with its apostrophe, j', since it is typed with no space after."""
        out = []
        for w, _ in self.followers(before):
            out.append(w + "'" if w in self.elisions else self.written(w))
            if len(out) == SHOWN:
                break
        return out

    def written(self, word, typed=""):
        """`word` as it is written: with its capital where the pairs say it
        always has one, I and Paris, unless the typing asked for more."""
        if word in self.capitals and not typed[:1].isupper():
            return word[:1].upper() + word[1:]
        return cased(word, typed) if typed else word

    def in_context(self, found, before):
        """`found`, {word: rank}, ranked by the word before as well: a word
        that follows it by how often it does, any other as its own rank and
        CONTEXT_BACKOFF more. A correction's or accent's penalty carries
        over, so context never makes a slip outrank what was typed."""
        seen = self.context(before)
        if not seen:
            return found
        out = {}
        for w, r in found.items():
            penalty = r - self.ranks[w]
            ctx = seen.get(w)
            out[w] = min(self.ranks[w] + CONTEXT_BACKOFF, ctx if ctx is not None else 1 << 30) + penalty
        return out

    def suggest(self, typed, before=None):
        # After an elision and its apostrophe, l'ét, the rest is a word of
        # its own: completed alone, and offered with the elision in front.
        head, apostrophe, tail = typed.rpartition("'")
        if apostrophe and head.lower() in self.elisions and not any(self.completions(typed.lower())):
            return [head + "'" + w for w in self.suggest(tail, head.lower())] if tail else []
        word = typed.lower()
        if not word:
            return []
        found = {}
        for rank, w in self.completions(word):
            found[w] = rank
        if len(word) >= CORRECT_FROM:
            completes = bool(found)
            for rank, w in self.corrections(word):
                # A shorter word is a letter too many, and short words are
                # so common that one would outrank every real completion:
                # "hel" offering "he" before "help". Someone partway through
                # a word that exists is not usually mistyping a shorter one,
                # so those wait until nothing completes what was typed.
                if completes and len(w) < len(word):
                    continue
                if rank < found.get(w, 1 << 30):
                    found[w] = rank
        found = {w: found[w] for w in spelled_right(list(found), self.ranks, self.folds)}
        found = self.in_context(found, before)
        best = heapq.nsmallest(SHOWN, found.items(), key=lambda kv: (kv[1], kv[0]))
        return [self.written(w, typed) for w, _ in best]


# ---- Word forms -----------------------------------------------------------
#
# The almost-right word: sum when summed was wanted. A hold on a suggestion
# offers the word's other forms, found by the rules of how the language
# inflects and kept only where the word list has them, so a rule that makes
# a word nobody writes makes nothing. English first.

# English words whose forms the rules cannot make, each a family.
IRREGULAR_EN = """
arise arose arisen arises arising|awake awoke awoken|be am is are was were been being
bear bore borne|beat beaten|become became becoming becomes|begin began begun beginning begins
bend bent|bet bets betting|bind bound|bite bit bitten|bleed bled|blow blew blown
break broke broken breaking breaks|breed bred|bring brought bringing brings|build built
burn burnt|buy bought buying buys|catch caught catches catching|choose chose chosen choosing
cling clung|come came coming comes|cost costs costing|creep crept|cut cuts cutting
deal dealt|dig dug digging|do does did done doing|draw drew drawn drawing draws
dream dreamt|drink drank drunk drinking drinks|drive drove driven driving drives
eat ate eaten eating eats|fall fell fallen falling falls|feed fed|feel felt feeling feels
fight fought fighting fights|find found finding finds|flee fled|fly flew flown flies flying
forbid forbade forbidden|forget forgot forgotten forgetting forgets|forgive forgave forgiven
freeze froze frozen|get got gotten getting gets|give gave given giving gives
go goes went gone going|grind ground|grow grew grown growing grows|hang hung
have has had having|hear heard hearing hears|hide hid hidden hiding hides
hit hits hitting|hold held holding holds|hurt hurts hurting|keep kept keeping keeps
kneel knelt|know knew known knowing knows|lay laid laying lays|lead led leading leads
lean leant|leap leapt|learn learnt|leave left leaving leaves|lend lent|let lets letting
lie lay lain lying lies|light lit|lose lost losing loses|make made making makes
mean meant meaning means|meet met meeting meets|pay paid paying pays|put puts putting
quit quits quitting|read reading reads|ride rode ridden riding rides|ring rang rung
rise rose risen rising rises|run ran running runs|say said saying says|see saw seen seeing sees
seek sought|sell sold selling sells|send sent sending sends|set sets setting
sew sewn|shake shook shaken|shine shone|shoot shot shooting shoots|show shown
shrink shrank shrunk|shut shuts shutting|sing sang sung singing sings|sink sank sunk
sit sat sitting sits|sleep slept sleeping sleeps|slide slid|speak spoke spoken speaking speaks
speed sped|spend spent spending spends|spin spun|split splits|spread spreads
spring sprang sprung|stand stood standing stands|steal stole stolen|stick stuck
sting stung|stink stank stunk|strike struck|strive strove striven|swear swore sworn
sweep swept|swim swam swum swimming swims|swing swung|take took taken taking takes
teach taught teaching teaches|tear tore torn|tell told telling tells|think thought thinking thinks
throw threw thrown throwing throws|understand understood|wake woke woken|wear wore worn
weep wept|win won winning wins|wind wound|write wrote written writing writes
child children|man men|woman women|person people|mouse mice|foot feet|tooth teeth
goose geese|life lives|knife knives|wife wives|leaf leaves|half halves|wolf wolves
good better best|bad worse worst|far further furthest farther farthest|little less least
"""


def irregular_families(text):
    out = {}
    for group in text.replace("\n", "|").split("|"):
        family = group.split()
        for w in family:
            out.setdefault(w, set()).update(family)
    return out


IRREGULAR = {"en": irregular_families(IRREGULAR_EN)}
VOWELS = set("aeiou")


def grow_en(base):
    """Every form English's regular rules make from `base`, real or not."""
    out = set()
    if base.endswith(("s", "x", "z", "ch", "sh")):
        out.add(base + "es")
    elif base.endswith("y") and len(base) > 2 and base[-2] not in VOWELS:
        out |= {base[:-1] + "ies", base[:-1] + "ied"}
    else:
        out.add(base + "s")
    if base.endswith("e"):
        out |= {base + "d", base[:-1] + "ing"}
    elif base.endswith("ie"):
        out.add(base[:-2] + "ying")
    else:
        out |= {base + "ed", base + "ing"}
    # A short word ending consonant, vowel, consonant doubles the last:
    # stop, stopped. Where it does not, the list has no such word.
    if len(base) >= 3 and base[-1] not in VOWELS | set("wxy") and base[-2] in VOWELS \
            and base[-3] not in VOWELS:
        out |= {base + base[-1] + "ed", base + base[-1] + "ing"}
    return out


def comparatives_en(base, known):
    """happier and happiest, but only as a pair: -er alone makes another
    word as often as a form (summer is not more sum)."""
    stem = base[:-1] + "i" if base.endswith("y") and len(base) > 2 else base
    if len(base) >= 3 and base[-1] not in VOWELS | set("wxy") and base[-2] in VOWELS \
            and base[-3] not in VOWELS:
        doubled = (base + base[-1] + "er", base + base[-1] + "est")
        if all(w in known for w in doubled):
            return set(doubled)
    pair = (stem.rstrip("e") + "er", stem.rstrip("e") + "est") if base.endswith("e") \
        else (stem + "er", stem + "est")
    return set(pair) if all(w in known for w in pair) else set()


def roots_en(word):
    """What `word` could be a form of, by undoing the rules."""
    out = {word}
    for suffix in ("es", "s", "ed", "d", "ing", "er", "est"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 2:
            r = word[:-len(suffix)]
            out |= {r, r + "e"}
            if len(r) >= 3 and r[-1] == r[-2]:
                out.add(r[:-1])
    for suffix in ("ies", "ied", "ier", "iest"):
        if word.endswith(suffix):
            out.add(word[:-len(suffix)] + "y")
    if word.endswith("ying"):
        out.add(word[:-4] + "ie")
    return out


def forms_en(word, ranks):
    """The other forms of `word` the list has, from its commonest root:
    "tried" comes from try and not from tri, "making" from make and not
    from mak."""
    family = set(IRREGULAR["en"].get(word, ()))
    roots = [r for r in roots_en(word) if r in ranks and (r == word or word in grow_en(r)
                                                           | comparatives_en(r, ranks)
                                                           | IRREGULAR["en"].get(r, set()))]
    if roots:
        root = min(roots, key=lambda r: ranks[r])
        irregular = IRREGULAR["en"].get(root, set())
        # Not on two letters. The words that short which really take endings,
        # go, do and be, are all irregular and in the table; the rules on the
        # rest only ever made another word out of a fragment, ly into lying
        # and us into uses, used and using.
        regular = grow_en(root) | comparatives_en(root, ranks) if len(root) >= 3 else set()
        if irregular:
            # The rules run on child too, and wordfreq counts "childs" and
            # "childrens" among its misspellings. Beside an irregular family
            # a rule's form is kept only when it is not far rarer than the
            # root: bears for bear, not childs for child.
            regular = {w for w in regular if w in ranks and ranks[w] - ranks[root] < 150}
        family |= {root} | regular | irregular
    family.discard(word)
    return sorted((w for w in family if w in ranks), key=lambda w: (ranks[w], w))


FORMS = {"en": forms_en}


# Words wordfreq counts because people write them, that are the two words
# written wrong: offering one for "a lot" would correct it into a mistake.
JOIN_WRONG = {"en": {"alot", "aswell", "eachother", "atleast", "everytime", "thankyou",
                     "nevermind", "ofcourse", "noone", "highschool"}}
# A piece this rare or rarer, or no word at all, makes a space between the
# two more likely a slip than meant: inter, wh, al. Ranks are centibels
# (read_wordlist); 440 is about one word in 25,000.
JOIN_RARE = 440


def join_words(a, b, ranks, lang, dictionary=None):
    """The word a and b make written as one, as {"word", "strong"}, or {}.

    Only an offer, never a correction, because most pairs that make a word
    are right both ways: every day and everyday, may be and maybe, on to and
    onto. Strong is when one piece is rare enough, or no word at all, that
    the space was most likely a slip, and the strip leads with it; otherwise
    it only follows the finished word's forms, so a pair typed on purpose is
    not nagged.

    With a spelling dictionary installed (Dictionary), it decides what is a
    word: storeroom and sluggishly, which the frequency list is too short to
    have, and not alot, which the list has because people write it. Without
    one, the list decides, with JOIN_WRONG for what it has wrong, and only
    for English, the one language whose list has been checked for that."""
    if not (a.replace("'", "").isalpha() and b.replace("'", "").isalpha()):
        return {}
    joined = (a + b).lower()
    if dictionary:
        if dictionary.spell(joined):
            word = cased(joined, a)
        elif dictionary.spell(joined[:1].upper() + joined[1:]):
            word = joined[:1].upper() + joined[1:]   # a name: Broadway
        else:
            return {}
    elif lang in JOIN_WRONG and joined in ranks and joined not in JOIN_WRONG[lang]:
        word = cased(joined, a)
    else:
        return {}

    def rare(piece):
        r = ranks.get(piece.lower())
        if r is None or r >= JOIN_RARE:
            return True
        return bool(dictionary) and not dictionary.known(piece)
    return {"word": word, "strong": rare(a) or rare(b)}


# ---- Spelling dictionaries (optional) --------------------------------------
#
# Hunspell's, the ones LibreOffice and Firefox spell-check with, used when
# one is installed for the language and never needed: without one, nothing
# here changes what the keyboard does. They answer what the frequency lists
# cannot, whether something is a word at all and which words share a stem,
# for any language that has one, rather than rules written for each.
#
#   sudo pacman -S hunspell-en_us hunspell-fr-comprehensive
#
# Looked for in $DICPATH, then ~/.local/share/hunspell, /usr/share/hunspell
# and /usr/share/myspell/dicts, as <lang>_<REGION>.dic with its .aff, the
# region of the locale first (en_CA on a Canadian English system), then the
# language's home one (fr_FR, de_DE), then any of the language's, a plain one
# before a -large, then <lang>.dic.

DICTIONARY_DIRS = ["~/.local/share/hunspell", "/usr/share/hunspell", "/usr/share/myspell/dicts"]
_hunspell = None


def hunspell_library():
    """libhunspell through ctypes, or None where it is not installed."""
    global _hunspell
    if _hunspell is not None:
        return _hunspell or None
    _hunspell = False
    names = [ctypes.util.find_library("hunspell"), "libhunspell-1.7.so.0", "libhunspell.so"]
    for name in filter(None, names):
        try:
            lib = ctypes.CDLL(name)
        except OSError:
            continue
        words = ctypes.POINTER(ctypes.c_char_p)
        lib.Hunspell_create.restype = ctypes.c_void_p
        lib.Hunspell_create.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        lib.Hunspell_spell.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.Hunspell_stem.argtypes = [ctypes.c_void_p, ctypes.POINTER(words), ctypes.c_char_p]
        lib.Hunspell_free_list.argtypes = [ctypes.c_void_p, ctypes.POINTER(words), ctypes.c_int]
        lib.Hunspell_destroy.argtypes = [ctypes.c_void_p]
        _hunspell = lib
        break
    return _hunspell or None


def find_dictionary(lang):
    """(aff, dic) paths of an installed dictionary for `lang`, or None."""
    # RAGTOP_DICTIONARY_DIRS, set, is the whole search, and empty means none:
    # the tests' way to choose a dictionary of their own, or none at all.
    only = os.environ.get("RAGTOP_DICTIONARY_DIRS")
    dirs = ([d for d in only.split(":") if d] if only is not None
            else [d for d in os.environ.get("DICPATH", "").split(":") if d] + DICTIONARY_DIRS)
    region = os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or ""
    region = region.split(".")[0] if region.startswith(lang + "_") else ""
    for d in map(os.path.expanduser, dirs):
        # The locale's own region first; then the language's home one, fr_FR
        # rather than fr_BE, which alphabetical order would have taken; then
        # a plain one before a -large or other variant of it.
        home = f"{lang}_{lang.upper()}"
        found = sorted(glob.glob(os.path.join(d, f"{lang}_*.dic")))
        found.sort(key=lambda f: (os.path.basename(f)[:-4] != region,
                                  not os.path.basename(f).startswith(home),
                                  "-" in os.path.basename(f)))
        found += glob.glob(os.path.join(d, f"{lang}.dic"))
        for dic in found:
            aff = dic[:-4] + ".aff"
            if os.path.exists(aff):
                return aff, dic
    return None


class Dictionary:
    """One Hunspell dictionary. Not to be shared between threads, which
    Hunspell does not allow; each thread opens its own."""

    def __init__(self, aff, dic):
        self.lib = hunspell_library()
        self.path = dic
        self.name = os.path.basename(dic)[:-4]
        self.encoding = "utf-8"
        with open(aff, "rb") as f:
            for line in f:
                if line.startswith(b"SET "):
                    self.encoding = line[4:].strip().decode("ascii", "replace")
                    break
        try:
            "".encode(self.encoding)
        except LookupError:
            self.encoding = "utf-8"
        self.handle = self.lib.Hunspell_create(aff.encode(), dic.encode())
        if not self.handle:
            raise OSError("hunspell could not open " + dic)

    def close(self):
        """Hunspell's memory back: ten megabytes or so for a large language."""
        if self.handle:
            self.lib.Hunspell_destroy(self.handle)
            self.handle = None

    def _bytes(self, word):
        return word.encode(self.encoding, "replace")

    def spell(self, word):
        return bool(self.lib.Hunspell_spell(self.handle, self._bytes(word)))

    def known(self, word):
        """A word as typed or as a name: paris counts, since Paris is one."""
        return self.spell(word) or self.spell(word[:1].upper() + word[1:])

    def stems(self, word):
        out = ctypes.POINTER(ctypes.c_char_p)()
        n = self.lib.Hunspell_stem(self.handle, ctypes.byref(out), self._bytes(word))
        found = [out[i].decode(self.encoding, "replace") for i in range(n)]
        self.lib.Hunspell_free_list(self.handle, ctypes.byref(out), n)
        return found


def open_dictionary(lang):
    if not hunspell_library():
        return None
    paths = find_dictionary(lang)
    if not paths:
        return None
    try:
        return Dictionary(*paths)
    except (OSError, UnicodeError):
        return None


# Where stem indexes are kept between runs: built from a list's words and a
# dictionary, never from anything typed, and rebuilt when either changes.
STEMS_CACHE = os.path.expanduser("~/.cache/ragtop/stems")


def stem_cache_path(dictionary, source, count):
    st = os.stat(dictionary.path)
    key = hashlib.sha1(f"{source}|{count}|{dictionary.path}|{st.st_size}|{st.st_mtime}"
                       .encode()).hexdigest()[:16]
    return os.path.join(STEMS_CACHE, f"{dictionary.name}-{key}.json")


def stem_index(words, dictionary, path):
    """{stem: [words of the list with that stem]}, saved to `path`. A second
    or two to build for a list of thirty thousand words, so it is built
    once and read back after (load_stem_index)."""
    index = {}
    for w in words:
        for s in set(dictionary.stems(w)) or {w}:
            index.setdefault(s, []).append(w)
    try:
        os.makedirs(STEMS_CACHE, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(index, f, ensure_ascii=False)
        os.replace(tmp, path)
    except OSError:
        pass
    return index


def load_stem_index(path):
    try:
        with open(path, encoding="utf-8") as f:
            index = json.load(f)
        return index if isinstance(index, dict) else None
    except (OSError, ValueError):
        return None


# ---- Terminals --------------------------------------------------------------
#
# In a terminal the strip offers what a command line is made of rather than
# English: the commands on PATH, with what each is for from its manual, at
# the start of a command, and the files and folders of the terminal's folder
# after it. Only the line as far as Ragtop typed it, which the service sends.

# The commands most typed, first. Anything else on PATH ranks by length.
COMMON_COMMANDS = """cd ls cat grep git vim nvim nano less cp mv rm mkdir sudo man ssh
pacman yay paru top htop btop ps kill find tar curl wget python python3 make
chmod chown echo touch head tail diff systemctl journalctl hyprctl omarchy
code open xdg-open du df free ping ip rsync scp zip unzip sed awk sort uniq
wc tree which exit clear history source export alias jq tmux docker npm node
cargo go rg fd bat fzf lazygit gh""".split()
# Built in to the shell, so on no PATH: bash's, which zsh's mostly are, and
# fish's own, by the shell the terminal runs (the "shell" the service sends).
BUILTINS = {
    "bash": """cd pushd popd dirs export alias unalias source exit history jobs fg bg
set unset type umask ulimit wait eval exec read echo printf test true false
help builtin command trap shift times""".split(),
    "fish": """cd pushd popd dirs set alias functions function funced funcsave source
exit history jobs fg bg type eval exec read echo printf test true false
builtin command abbr and or not begin end if else switch case while for
string math status contains count""".split(),
}
BUILTINS["zsh"] = BUILTINS["bash"] + "setopt unsetopt autoload compdef bindkey".split()
# After one of these, the next word is a command again.
LEADS_TO_COMMAND = {"|", "||", "&&", ";", "sudo", "doas", "time", "exec", "nohup",
                    "watch", "xargs", "env", "nice", "then", "do", "else",
                    "and", "or", "not"}
SHELL_SPECIAL = set(" \t'\"\\$`&()|;<>*?[]#~!{}")


def typeable(name):
    """Whether a name can be offered at all. A control character, a newline
    above all, would end the helper's line in the middle of the name, and
    typed into a terminal it presses Enter, so a name with one is never
    offered: it was not typed, and the shell has ways to reach it."""
    return not any(ord(c) < 32 or 127 <= ord(c) < 160 for c in name)


def shell_escaped(name):
    return "".join("\\" + c if c in SHELL_SPECIAL else c for c in name)


def shell_tokens(line):
    """The line's words as typed, split where the shell splits them: at a
    space that is not escaped and not inside quotes. my\\ docs is one word."""
    tokens, current, quote, escaped = [], "", "", False
    for c in line:
        if escaped:
            current += c
            escaped = False
        elif c == "\\" and quote != "'":
            current += c
            escaped = True
        elif quote:
            current += c
            if c == quote:
                quote = ""
        elif c in "'\"":
            current += c
            quote = c
        elif c == " ":
            tokens.append(current)
            current = ""
        else:
            current += c
    tokens.append(current)
    return tokens


class Terminal:
    def __init__(self):
        self.commands = None    # name -> rank, read the first time it is needed
        self.notes = {}
        self.shell = "bash"

    def set_shell(self, shell):
        shell = shell if shell in BUILTINS else "bash"
        if shell != self.shell:
            self.shell = shell
            self.commands = None

    def load(self):
        names = set(BUILTINS[self.shell])
        for d in os.environ.get("PATH", "").split(":"):
            try:
                for n in os.listdir(d):
                    p = os.path.join(d, n)
                    if typeable(n) and os.access(p, os.X_OK) and not os.path.isdir(p):
                        names.add(n)
            except OSError:
                pass
        common = {n: i for i, n in enumerate(COMMON_COMMANDS)}
        self.commands = {n: common.get(n, len(COMMON_COMMANDS) + len(n)) for n in names}
        # What each is for, from the manuals' one-line descriptions. Sections
        # 1 and 8, commands, and the first found where there are several.
        try:
            out = subprocess.run(["apropos", "-l", "-s", "1,8", "."], capture_output=True,
                                 text=True, timeout=5).stdout
        except (OSError, subprocess.SubprocessError):
            out = ""
        for line in out.splitlines():
            name, _, rest = line.partition(" ")
            _, dash, note = rest.partition(" - ")
            if dash and name in self.commands:
                self.notes.setdefault(name, note.strip())

    def suggest(self, cwd, line):
        """Suggestions, each with "back", how many characters of what was
        typed it replaces: the word being typed, escapes and quotes and all."""
        token = shell_tokens(line)[-1]
        found = self.suggest_for(cwd, line)
        for f in found:
            f["back"] = len(token)
            # A manual's description can run to a sentence, and a cell is a
            # word wide.
            if len(f["note"]) > 30:
                f["note"] = f["note"][:29].rstrip() + "\u2026"
        return found

    def suggest_for(self, cwd, line):
        tokens = shell_tokens(line)
        token = tokens[-1]
        before = [t for t in tokens[:-1] if t]
        command_place = not before or before[-1] in LEADS_TO_COMMAND \
            or before[-1].endswith(("|", ";", "&&"))
        if token.startswith("-"):
            return []
        if command_place:
            return self.command_names(token)
        command = next((t for t in reversed(before) if t not in LEADS_TO_COMMAND), "")
        return self.files(cwd, token, folders_only=command in ("cd", "pushd", "rmdir"))

    def command_names(self, prefix):
        if not prefix:
            return []
        if self.commands is None:
            self.load()
        found = [n for n in self.commands if n.startswith(prefix)]
        found.sort(key=lambda n: (self.commands[n], n))
        return [{"text": n, "note": self.notes.get(n, ""), "kind": "command"} for n in found[:SHOWN]]

    def files(self, cwd, token, folders_only):
        # The typed path as the shell will read it: unescaped, ~ for home.
        try:
            plain = "".join(shlex.split(token)) if token else ""
        except ValueError:
            return []        # an open quote: nothing sure to offer
        if not token and not folders_only:
            return []
        head, base = os.path.split(plain)
        where = os.path.join(cwd, os.path.expanduser(head)) if head else cwd
        try:
            entries = os.listdir(where)
        except OSError:
            return []
        if not base or token.endswith(shell_escaped(base)):
            # The folder part as typed, quotes and all, ahead of the name.
            typed_head = token[:len(token) - len(shell_escaped(base))]
        else:
            # The name was quoted, "re" or 'my d'oc: the token is rewritten
            # whole, escaped, keeping a leading ~ for the shell to expand.
            plain_head = plain[:len(plain) - len(base)]
            home = "~" if plain_head.startswith("~") else ""
            typed_head = home + shell_escaped(plain_head[len(home):])
        out = []
        for name in entries:
            if not name.startswith(base) or (name.startswith(".") and not base.startswith(".")) \
                    or not typeable(name):
                continue
            is_dir = os.path.isdir(os.path.join(where, name))
            if folders_only and not is_dir:
                continue
            out.append((not is_dir, name.lower(), {
                "text": typed_head + shell_escaped(name) + ("/" if is_dir else ""),
                "note": "", "kind": "dir" if is_dir else "file"}))
        out.sort(key=lambda e: e[:2])
        return [e[2] for e in out[:SHOWN]]


# ---- Swipes ---------------------------------------------------------------
#
# A word drawn across the keys is decoded the way SHARK2 does it (Kristensson
# and Zhai, 2004), and FlorisBoard's glide typing after it: every word has an
# ideal path, from the centre of its first key through each of the others, and
# the finger's path is compared with the ideal path of every word that could
# have made it. Two comparisons, because a path can be wrong in two ways:
# where it went (location) and what it looks like (shape), the second
# forgiving a finger that drew the right word a little to one side. Then how
# common each word is decides between paths that fit about equally well.

SAMPLES = 32
# How far, in key widths, the path's ends may be from a word's first and last
# keys and the word still be considered. A finger lands and lifts roughly on
# a key, not on its centre.
END_SLACK = 1.4
# How far every one of a word's keys may be from the path at its nearest.
# A word whose path never comes near one of its letters did not draw it.
VISIT_SLACK = 1.1
# Weights, in key widths, against the frequency prior, which is in
# centibels: 100 centibels, a factor of ten in how common a word is, weigh
# as much as the path being a quarter of a key further off on average.
#
# Tuned with bench/bench.py on held-out words, French and English together,
# at three amounts of wobble, as words come up in writing and as rare words
# (2026-10-26), from 1, 1, 1/300, 0.15 and 0.5: French went from 87 to 91%
# right first, English from 94 to 95%, and rare words most, 65 to 75% and
# 79 to 86%. A step towards what the tuner liked best rather than all the
# way: it wanted shape trusted three times as much, and the paths it was
# tuned on are simulated, smoother than a real finger, so the heavier bet
# would be on the simulation. Real swipes are what should settle the rest.
LOCATION_WEIGHT = 1.0
SHAPE_WEIGHT = 1.5
FREQUENCY_WEIGHT = 1 / 400
# How far the finger travelled, against how far the word's keys are apart,
# in key widths. Without it a common short word whose path lies along a
# longer one's wins it: "the" for "there", "so" for "stop", since the two
# comparisons above resample both to the same number of points.
LENGTH_WEIGHT = 0.1
# Where the finger landed and lifted, against the first and last keys. The
# ends are the surest part of a swipe, and the part the comparisons above
# weigh least: "her" for "here" ends one key short.
ENDS_WEIGHT = 0.75


def resample(points, n=SAMPLES):
    """`points` as n points evenly spaced along the path they make."""
    if len(points) == 1:
        return [points[0]] * n
    lengths = [math.dist(a, b) for a, b in zip(points, points[1:])]
    total = sum(lengths)
    if total == 0:
        return [points[0]] * n
    out, step, walked, i = [], total / (n - 1), 0.0, 0
    for k in range(n):
        target = k * step
        while i < len(lengths) - 1 and walked + lengths[i] < target:
            walked += lengths[i]
            i += 1
        t = 0 if lengths[i] == 0 else min(1.0, (target - walked) / lengths[i])
        a, b = points[i], points[i + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def normalised(points):
    """`points` moved to centre on the origin and scaled to fit a unit box,
    keeping their proportions: the path's shape alone."""
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    w = max(p[0] for p in points) - min(p[0] for p in points)
    h = max(p[1] for p in points) - min(p[1] for p in points)
    scale = max(w, h) or 1.0
    return [((x - cx) / scale, (y - cy) / scale) for x, y in points]


def path_length(points):
    return sum(math.dist(a, b) for a, b in zip(points, points[1:]))


def mean_distance(a, b):
    return sum(math.dist(p, q) for p, q in zip(a, b)) / len(a)


class Swipes:
    def __init__(self, ranks, folds=None, predictor=None):
        self.ranks = ranks
        # For the word before (Predictor.pairs): a swipe after "going" that
        # could be to, too or top is to, as a completion would be.
        self.predictor = predictor
        # The predictor's, for the same reason it keeps them.
        self.folds = folds or {w: (fold(w), accents(w)) for w in ranks}
        self.keys = {}
        self.unit = 1.0
        self.ends = {}
        self.lengths = {}

    def set_keys(self, value):
        """{"unit": w, "keys": {"q": [x, y], ...}} from the keyboard."""
        keys = value.get("keys") if isinstance(value, dict) else None
        unit = value.get("unit") if isinstance(value, dict) else None
        if not isinstance(keys, dict) or not isinstance(unit, (int, float)) or unit <= 0:
            return
        self.keys = {k.lower(): (float(v[0]), float(v[1])) for k, v in keys.items()
                     if isinstance(k, str) and len(k) == 1 and isinstance(v, list) and len(v) == 2}
        self.unit = float(unit)
        # Words by their first and last letters, the ones a path's ends
        # pick between, and only words every letter of which has a key.
        self.ends = {}
        for word in self.ranks:
            letters = [c for c in self.folds[word][0] if c != "'"]
            if len(letters) >= 2 and all(c in self.keys for c in letters):
                self.ends.setdefault((letters[0], letters[-1]), []).append(word)
        # Each word's path length on these keys, for decode's cheap first
        # look at a candidate.
        self.lengths = {w: path_length(self.ideal(w)) for ws in self.ends.values() for w in ws}

    def ideal(self, word):
        """The path through a word's keys, a letter typed twice in a row
        being one stop, as it is for a finger."""
        out = []
        for c in self.folds[word][0]:
            if c == "'":
                continue
            p = self.keys[c]
            if not out or out[-1] != p:
                out.append(p)
        return out

    def near(self, point, slack):
        return [c for c, p in self.keys.items() if math.dist(p, point) <= slack * self.unit]

    def decode(self, path, before=None):
        if not self.keys or len(path) < 2:
            return []
        path = [(float(x), float(y)) for x, y in path]
        starts = self.near(path[0], END_SLACK)
        ends = self.near(path[-1], END_SLACK)
        sampled = resample(path)
        shape = normalised(sampled)
        travelled = path_length(path)
        # How near the path comes to each key, the same for every word, so
        # worked out once here rather than once per candidate: per candidate,
        # it cost time in proportion to the path's points, and a slow finger
        # gives hundreds. Measured, a 120-point swipe went from 330 ms to a
        # small part of that.
        closest = {k: min(math.dist(p, q) for q in path) for k, p in self.keys.items()}
        # Every term of a word's score is zero or more, and three of them cost
        # next to nothing: how common it is, how far the path's ends are from
        # its first and last keys, and how much longer or shorter it is. Those
        # alone are a floor under its score. Candidates are taken floor first,
        # and once the floor reaches the worst of the best found so far, no
        # word left can get in, and the costly part, comparing the path's
        # shape with every remaining word's, is never done. The answer is the
        # same as scoring every word; measured, most are never shaped. Kept
        # three times the words shown, since the misspelling filter after may
        # drop some.
        # How common each word is here: by the word before, where the pairs
        # know it, the same measure completions are ranked by.
        seen = self.predictor.context(before) if self.predictor and before else None

        def commonness(word):
            r = self.ranks[word]
            if not seen:
                return r
            ctx = seen.get(word)
            return min(r + CONTEXT_BACKOFF, ctx) if ctx is not None else r + CONTEXT_BACKOFF

        candidates = []
        for a in starts:
            for b in ends:
                for word in self.ends.get((a, b), ()):
                    letters = self.folds[word][0]
                    if any(closest[c] > VISIT_SLACK * self.unit for c in letters if c != "'"):
                        continue
                    first = self.keys[next(c for c in letters if c != "'")]
                    last = self.keys[next(c for c in reversed(letters) if c != "'")]
                    ends_off = (math.dist(path[0], first) + math.dist(path[-1], last)) / self.unit
                    stretch = abs(travelled - self.lengths[word]) / self.unit
                    floor = (LENGTH_WEIGHT * stretch + ENDS_WEIGHT * ends_off
                             + FREQUENCY_WEIGHT * commonness(word))
                    candidates.append((floor, word))
        candidates.sort()
        kept = 3 * SHOWN
        worst = []   # the best scores so far, negated, as a heap of the worst
        scored = []
        for floor, word in candidates:
            if len(worst) >= kept and floor >= -worst[0]:
                break
            template = resample(self.ideal(word))
            location = mean_distance(sampled, template) / self.unit
            form = mean_distance(shape, normalised(template))
            score = floor + LOCATION_WEIGHT * location + SHAPE_WEIGHT * form
            scored.append((score, word))
            if len(worst) < kept:
                heapq.heappush(worst, -score)
            elif score < -worst[0]:
                heapq.heapreplace(worst, -score)
        keep = set(spelled_right([w for _, w in scored], self.ranks, self.folds))
        scored = [(score, w) for score, w in scored if w in keep]
        return [w for _, w in heapq.nsmallest(SHOWN, scored)]


# A language code is what names a list's folder and file, so it is checked
# before it is let near a path.
def valid_lang(code):
    return 2 <= len(code) <= 3 and code.isascii() and code.isalpha() and code.islower()


class Session:
    """The language in use, its predictor and its swipe decoder, and the
    layout's rows and keys, which carry over when the language changes."""

    def __init__(self, source, bundled=None):
        self.source = source
        # Ragtop's own copy of a language's files, in the repository
        # (words/en): read where no download of them is.
        self.bundled = bundled
        self.loaded = {}      # lang -> (Predictor, Swipes), or None when missing
        self.predictor = self.swipes = None
        self.rows = self.keys = None
        # The word before the one being typed, from "after": START at the
        # start of a sentence, None when it is not known. Held for the next
        # "complete", never written anywhere.
        self.before = None

    def find(self, lang, name):
        """A language's file, downloaded or else bundled, or None."""
        for root in (self.source, self.bundled):
            if root and os.path.isdir(root):
                path = os.path.join(root, lang, name)
                if os.path.exists(path):
                    return path
        return None

    def use(self, lang, path):
        if lang not in self.loaded:
            try:
                p = Predictor(read_wordlist(path), lang)
                d = open_dictionary(lang)
                if d:
                    p.use_dictionary(d, path)
                # Which words follow which, when there are any: optional, as
                # the dictionary is.
                pairs = self.find(lang, f"pairs_{lang}.tsv.gz")
                if pairs:
                    try:
                        p.use_pairs(pairs)
                    except (OSError, ValueError, EOFError):
                        pass
                self.loaded[lang] = (p, Swipes(p.ranks, p.folds, p))
            except FileNotFoundError:
                self.loaded[lang] = None
        if self.loaded[lang] is None:
            self.predictor = self.swipes = None
            return False
        self.predictor, self.swipes = self.loaded[lang]
        if self.rows is not None:
            self.predictor.set_rows(self.rows)
        if self.keys is not None:
            self.swipes.set_keys(self.keys)
        return True


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: predictor.py <words-dir | wordlist.msgpack.gz> [bundled-dir]")
    source = sys.argv[1]
    session = Session(source, sys.argv[2] if len(sys.argv) == 3 else None)
    terminal = Terminal()
    one_list = os.path.isfile(source) or source.endswith(".msgpack.gz")
    if one_list:
        # One list, the way this began: English, read now. A folder that is
        # not there yet is still a folder: a machine that has downloaded
        # nothing, and reads English from Ragtop's own copy.
        try:
            if session.use("en", source):
                print(f"ready {len(session.predictor.words)}", flush=True)
            else:
                print("missing", flush=True)
        except (OSError, ValueError, EOFError) as e:
            # The file, never what was typed: nothing has been typed yet.
            sys.exit(f"can't read the word list: {e}")
    for line in sys.stdin:
        if not handle(session, terminal, source, one_list, line):
            break
        # What was asked about is held for this request only: the request's
        # own names went with handle(), and this one goes now, rather than
        # staying reachable until the next line comes in.
        del line


def handle(session, terminal, source, one_list, line):
    """One request, answered on stdout. False for quit."""
    cmd, _, rest = line.rstrip("\n").partition(" ")
    if cmd == "quit":
        return False
    if cmd == "lang" and not one_list and valid_lang(rest):
        # Dropped from what is loaded and tried again when it was missing,
        # so a list fetched since is found.
        if session.loaded.get(rest, 0) is None:
            del session.loaded[rest]
        try:
            found = session.find(rest, f"small_{rest}.msgpack.gz")
            ok = session.use(rest, found or os.path.join(source, rest, f"small_{rest}.msgpack.gz"))
        except (OSError, ValueError, EOFError):
            ok = False
        print(f"ready {rest} {len(session.predictor.words)}" if ok else f"missing {rest}", flush=True)
        if ok:
            d = session.predictor.dictionary
            print(f"dictionary {rest} {d.name if d else '-'}", flush=True)
    elif cmd == "keys":
        try:
            session.keys = json.loads(rest)
            if session.swipes:
                session.swipes.set_keys(session.keys)
        except (ValueError, TypeError, IndexError):
            pass
    elif cmd in ("swipe", "peek"):
        words = []
        if session.swipes:
            try:
                words = session.swipes.decode(json.loads(rest), session.before)
            except (ValueError, TypeError):
                pass
        reply = "swiped" if cmd == "swipe" else "peeked"
        print(f"{reply} " + json.dumps(words, ensure_ascii=False), flush=True)
    elif cmd == "rows":
        try:
            session.rows = json.loads(rest)
            if session.predictor:
                session.predictor.set_rows(session.rows)
        except ValueError:
            pass
    elif cmd == "term":
        found = []
        try:
            req = json.loads(rest)
            cwd, line = req["cwd"], req["line"]
            # Nushell quotes and escapes otherwise: nothing rather than
            # words it would read wrongly.
            if req.get("shell") == "nu":
                raise ValueError("nushell")
            terminal.set_shell(req.get("shell", "bash"))
            if isinstance(cwd, str) and isinstance(line, str) and os.path.isabs(cwd):
                found = terminal.suggest(cwd, line)
        except (ValueError, KeyError, TypeError):
            pass
        print("termsuggest " + json.dumps(found, ensure_ascii=False), flush=True)
    elif cmd == "forms":
        words = []
        p = session.predictor
        if p and rest:
            low = rest.lower()
            if p.lang in FORMS:
                found = FORMS[p.lang](low, p.ranks)
            else:
                found = p.stem_forms(low)
            words = [cased(w, rest) for w in found][:SHOWN]
        print("forms " + json.dumps(words, ensure_ascii=False), flush=True)
    elif cmd == "join":
        found = {}
        p = session.predictor
        pair = rest.split(" ")
        if p and len(pair) == 2 and all(pair):
            found = join_words(pair[0], pair[1], p.ranks, p.lang, p.dictionary)
        print("join " + json.dumps(found, ensure_ascii=False), flush=True)
    elif cmd == "after":
        # The word just finished, "after" alone at a sentence's start,
        # "after -" when what came before is not known.
        session.before = None if rest == "-" else (rest.lower() if rest else START)
        # j'ai: the word is ai, as the pairs were counted.
        if session.before and "'" in session.before and session.predictor:
            head, _, tail = session.before.partition("'")
            if head in session.predictor.elisions and tail:
                session.before = tail
        p = session.predictor
        found = p.next(session.before) if p and session.before else []
        print("next " + json.dumps(found, ensure_ascii=False), flush=True)
    elif cmd == "complete":
        words = session.predictor.suggest(rest, session.before) if session.predictor else []
        print("suggest " + json.dumps(words, ensure_ascii=False), flush=True)
    return True


if __name__ == "__main__":
    main()
