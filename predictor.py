#!/usr/bin/python3
"""Word suggestions for Ragtop's keyboard: what the word being typed could
be, for the suggestion strip (Service.qml).

Reads a word list from wordfreq (https://github.com/rspeer/wordfreq) in the
form wordfreq publishes it, downloaded by `ragtop words install`. That form
carries its licence, CC-BY-SA 4.0, with it, and its author asks that it not
be turned into a plain list that drops the attribution, so it is read as it
is rather than converted (see read_wordlist).

  predictor.py <words-dir>             lists at <dir>/<lang>/small_<lang>.msgpack.gz
  predictor.py <wordlist.msgpack.gz>   one list, as English

then commands on stdin, one per line:

  lang <code>         use that language's list, reading it the first time
  complete <word>     suggestions for a partly typed word
  rows <json>         the active layout's letter rows, [["q", "w", ...], ...],
                      which decide which keys are neighbours (QWERTY until
                      told)
  keys <json>         where each letter's key is, for swipes:
                      {"unit": key width, "keys": {"q": [x, y], ...}}
  swipe <json>        the path a finger drew across the keys, [[x, y], ...],
                      in the same coordinates
  peek <json>         the same for a path still being drawn, for the strip
                      to show the guess so far
  quit

and answers "ready <count>" once a single list is read, "ready <lang>
<count>" or "missing <lang>" for each "lang" (the service offers to fetch a
missing one), then "suggest <json>" for each "complete": a list of
words, most likely first, capitalised the way the typed word was, and
"swiped <json>" for each "swipe", the words it most likely spelled, and
"peeked <json>" for each "peek", the same answer under its own name so a
guess so far is never taken for a finished word.

What is typed arrives here and nowhere else. It is never printed except as
the suggestions, which only the service reads, and never logged: a word
being typed may be part of a password.
"""

import bisect
import gzip
import heapq
import json
import math
import os
import struct
import sys
import unicodedata

SHOWN = 8
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
    return sum(1 for c in word if fold(c) != c)


def spelled_right(words, ranks):
    """`words` without the misspellings wordfreq also counts: "ete" and
    "garcon" beside "été" and "garçon", "étre" beside "être". A word goes when
    another with the same letters, as many accents or more, is at least ten
    times commoner. A word is never beaten by one with fewer accents: the real
    words without them are the commoner ones, "la" beside "là", "a" beside
    "à", and how far apart a real pair is overlaps with how far a misspelling
    is, so only the accents tell them apart."""
    best = {}  # folded letters -> [(accent count, rank)]
    for w in words:
        best.setdefault(fold(w), []).append((accents(w), ranks[w]))
    return [w for w in words
            if not any(n >= accents(w) and ranks[w] - r >= MISSPELLING_GAP
                       for n, r in best[fold(w)])]


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
        # Every word under its folded form, sorted, for prefix search, and by
        # it, for corrections.
        self.folded = sorted((fold(w), w) for w in self.ranks)
        self.keys = [f for f, _ in self.folded]
        self.by_fold = {}
        for f, w in self.folded:
            self.by_fold.setdefault(f, []).append(w)
        self.near = neighbours(QWERTY)

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
        against = any(t != w and fold(t) != t for t, w in zip(typed, word))
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

    def suggest(self, typed):
        # After an elision and its apostrophe, l'ét, the rest is a word of
        # its own: completed alone, and offered with the elision in front.
        head, apostrophe, tail = typed.rpartition("'")
        if apostrophe and head.lower() in self.elisions and not any(self.completions(typed.lower())):
            return [head + "'" + w for w in self.suggest(tail)] if tail else []
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
        found = {w: found[w] for w in spelled_right(list(found), self.ranks)}
        best = heapq.nsmallest(SHOWN, found.items(), key=lambda kv: (kv[1], kv[0]))
        return [cased(w, typed) for w, _ in best]


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
# as much as the path being a third of a key further off on average.
LOCATION_WEIGHT = 1.0
SHAPE_WEIGHT = 1.0
FREQUENCY_WEIGHT = 1 / 300
# How far the finger travelled, against how far the word's keys are apart,
# in key widths. Without it a common short word whose path lies along a
# longer one's wins it: "the" for "there", "so" for "stop", since the two
# comparisons above resample both to the same number of points.
LENGTH_WEIGHT = 0.15
# Where the finger landed and lifted, against the first and last keys. The
# ends are the surest part of a swipe, and the part the comparisons above
# weigh least: "her" for "here" ends one key short.
ENDS_WEIGHT = 0.5


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
    def __init__(self, ranks):
        self.ranks = ranks
        self.keys = {}
        self.unit = 1.0
        self.ends = {}

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
            letters = [c for c in fold(word) if c != "'"]
            if len(letters) >= 2 and all(c in self.keys for c in letters):
                self.ends.setdefault((letters[0], letters[-1]), []).append(word)

    def ideal(self, word):
        """The path through a word's keys, a letter typed twice in a row
        being one stop, as it is for a finger."""
        out = []
        for c in fold(word):
            if c == "'":
                continue
            p = self.keys[c]
            if not out or out[-1] != p:
                out.append(p)
        return out

    def near(self, point, slack):
        return [c for c, p in self.keys.items() if math.dist(p, point) <= slack * self.unit]

    def decode(self, path):
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
        scored = []
        for a in starts:
            for b in ends:
                for word in self.ends.get((a, b), ()):
                    if any(closest[c] > VISIT_SLACK * self.unit for c in fold(word) if c != "'"):
                        continue
                    ideal = self.ideal(word)
                    template = resample(ideal)
                    location = mean_distance(sampled, template) / self.unit
                    form = mean_distance(shape, normalised(template))
                    stretch = abs(travelled - path_length(ideal)) / self.unit
                    ends_off = (math.dist(path[0], ideal[0]) + math.dist(path[-1], ideal[-1])) / self.unit
                    score = (LOCATION_WEIGHT * location + SHAPE_WEIGHT * form
                             + LENGTH_WEIGHT * stretch + ENDS_WEIGHT * ends_off
                             + FREQUENCY_WEIGHT * self.ranks[word])
                    scored.append((score, word))
        keep = set(spelled_right([w for _, w in scored], self.ranks))
        scored = [(score, w) for score, w in scored if w in keep]
        return [w for _, w in heapq.nsmallest(SHOWN, scored)]


# A language code is what names a list's folder and file, so it is checked
# before it is let near a path.
def valid_lang(code):
    return 2 <= len(code) <= 3 and code.isascii() and code.isalpha() and code.islower()


class Session:
    """The language in use, its predictor and its swipe decoder, and the
    layout's rows and keys, which carry over when the language changes."""

    def __init__(self, source):
        self.source = source
        self.loaded = {}      # lang -> (Predictor, Swipes), or None when missing
        self.predictor = self.swipes = None
        self.rows = self.keys = None

    def use(self, lang, path):
        if lang not in self.loaded:
            try:
                p = Predictor(read_wordlist(path), lang)
                self.loaded[lang] = (p, Swipes(p.ranks))
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
    if len(sys.argv) != 2:
        sys.exit("usage: predictor.py <words-dir | wordlist.msgpack.gz>")
    source = sys.argv[1]
    session = Session(source)
    if not os.path.isdir(source):
        # One list, the way this began: English, read now.
        try:
            if session.use("en", source):
                print(f"ready {len(session.predictor.words)}", flush=True)
            else:
                print("missing", flush=True)
        except (OSError, ValueError, EOFError) as e:
            # The file, never what was typed: nothing has been typed yet.
            sys.exit(f"can't read the word list: {e}")
    for line in sys.stdin:
        cmd, _, rest = line.rstrip("\n").partition(" ")
        if cmd == "quit":
            break
        if cmd == "lang" and os.path.isdir(source) and valid_lang(rest):
            # Dropped from what is loaded and tried again when it was missing,
            # so a list fetched since is found.
            if session.loaded.get(rest, 0) is None:
                del session.loaded[rest]
            try:
                ok = session.use(rest, os.path.join(source, rest, f"small_{rest}.msgpack.gz"))
            except (OSError, ValueError, EOFError):
                ok = False
            print(f"ready {rest} {len(session.predictor.words)}" if ok else f"missing {rest}", flush=True)
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
                    words = session.swipes.decode(json.loads(rest))
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
        elif cmd == "complete":
            words = session.predictor.suggest(rest) if session.predictor else []
            print("suggest " + json.dumps(words, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
