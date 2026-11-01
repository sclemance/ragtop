#!/usr/bin/env python3
"""Which words follow which, counted from Tatoeba's sentences, for next-word
prediction (predictor.py, Pairs) and its benchmark (bench.py, next).

    bench/pairs.py build <lang> [--keep N]   counts into the cache
    bench/pairs.py show <lang> <word>         what follows a word

Tatoeba's sentences are everyday speech, in hundreds of languages, under
CC BY 2.0 FR (some CC0): https://tatoeba.org, downloaded per language into
~/.cache/ragtop-bench/tatoeba. Nine tenths of them are counted, by sentence
number, and the other tenth is kept back for testing, so nothing is
measured on what it was built from. Only words in Ragtop's own frequency
list are counted, so a pair can never offer a word the list does not have.

The output is gzipped text, a line per word: "word<TAB>follower count
follower count ...", its commonest followers, most common first, "<s>"
being the start of a sentence; and a "<capitals><TAB>word word ..." line for
the words written with a capital wherever they are, I and I'm. Lines, not
one JSON object, so the predictor reads it a line at a time into flat arrays
without ever holding it all as Python objects. Counts, not probabilities, so the
predictor can weigh them against the list itself.
"""
import argparse
import bz2
import collections
import gzip
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import predictor as P  # noqa: E402

CACHE = os.path.expanduser("~/.cache/ragtop-bench")
TATOEBA = {"en": "eng", "fr": "fra", "de": "deu", "es": "spa"}
START = "<s>"
CAPITALS = "<capitals>"
# One sentence in ten, by its number, is kept back for testing.
HELD_OUT = 10
WORD = re.compile(r"[^\W\d_]+(?:'[^\W\d_]+)*")


def held_out(sentence_id):
    return sentence_id % HELD_OUT == 0


def tokens(sentence, lang):
    """A sentence's words, lower case, split at elisions where the language
    has them (l'été is l and été, as wordfreq counts them)."""
    out = []
    elisions = P.ELISIONS.get(lang, set())
    for w in WORD.findall(sentence.replace("’", "'").lower()):
        head, apostrophe, tail = w.partition("'")
        if apostrophe and head in elisions and tail:
            out += [head, tail]
        else:
            out.append(w)
    return out


def sentences(lang, part):
    """(id, text) for the training or the held-out part, or "all" of them."""
    path = f"{CACHE}/tatoeba/{TATOEBA[lang]}.tsv.bz2"
    with bz2.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or not parts[0].isdigit():
                continue
            n = int(parts[0])
            if part == "all" or (part == "test") == held_out(n):
                yield n, parts[2]


# Tatoeba's own characters, Tom, Mary and Sami, who start more of its
# English sentences than "the" does, are not offered as the next word. What
# marks them is not the capital, which I and every German noun have too, but
# both together: written capitalised mid-sentence at least NAME_SHARE of the
# time, and at least OVERUSED times commoner in these sentences than in
# everyday writing (the word list), so the data says which, in any language.
NAME_SHARE = 0.8
OVERUSED = 10


def capitals(lang, vocab, part="train"):
    """(characters, capitalised): Tatoeba's overused names, left out, and the
    words written capitalised mid-sentence that are not those, I and I'm and
    every German noun, which are offered with their capital. The same
    counts, read two ways, so both come from the data and not from rules."""
    # How often each word is used at all, and, away from the start of a
    # sentence, where a capital says nothing, how often with one.
    used, inside, upper = collections.Counter(), collections.Counter(), collections.Counter()
    total = 0
    for _, text in sentences(lang, part):
        for i, w in enumerate(WORD.findall(text.replace("\u2019", "'"))):
            total += 1
            low = w.lower()
            used[low] += 1
            if i > 0:
                inside[low] += 1
                if w[:1].isupper():
                    upper[low] += 1
    names, caps = set(), set()
    for w, n in inside.items():
        if n < 5 or w not in vocab or upper[w] / n < NAME_SHARE:
            continue
        everyday = 10 ** (-vocab[w] / 100)   # wordfreq's centibels, back to a share
        if (used[w] / total) / everyday >= OVERUSED:
            names.add(w)
        else:
            caps.add(w)
    return names, caps


def build(lang, keep, min_count=2, part="train", out=None):
    """Counts the pairs. For measuring, from the training part only, into
    the cache; for a release (part "all", out a path in the repository or a
    release folder), from every sentence, written the same way every time:
    keys sorted, gzip with no timestamp, so the same sentences give the same
    file and the same SHA-256 to pin."""
    vocab = P.read_wordlist(f"{CACHE}/words/small_{lang}.msgpack.gz")
    skip, caps = capitals(lang, vocab, part)
    counts = collections.defaultdict(collections.Counter)
    for _, text in sentences(lang, part):
        prev = START
        for w in tokens(text, lang):
            if w not in vocab:
                prev = None   # a word it does not know breaks the chain
                continue
            if prev is not None:
                counts[prev][w] += 1
            prev = w
    table = {}
    for prev, followers in counts.items():
        # Ties broken by the word, so the order, and so the file, is the
        # same every run.
        ranked = sorted(followers.items(), key=lambda wc: (-wc[1], wc[0]))
        top = [[w, c] for w, c in ranked if c >= min_count and w not in skip][:keep]
        if top:
            table[prev] = top
    path = out_path = out or f"{CACHE}/pairs/{lang}-{keep}.tsv.gz"
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    lines = [f"{before}\t" + " ".join(f"{w} {c}" for w, c in table[before]) for before in sorted(table)]
    # The words written with a capital, under a name no word can be.
    lines.append(f"{CAPITALS}\t" + " ".join(sorted(caps)))
    data = ("\n".join(lines) + "\n").encode()
    with open(out_path, "wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0, filename="") as f:
        f.write(data)
    return path, len(table), sum(len(v) for v in table.values())


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("lang")
    b.add_argument("--keep", type=int, default=32)
    b.add_argument("--all", action="store_true", help="every sentence, for a release")
    b.add_argument("--out", help="where to write it, for a release")
    s = sub.add_parser("show")
    s.add_argument("lang")
    s.add_argument("word")
    s.add_argument("--keep", type=int, default=32)
    a = ap.parse_args()
    if a.cmd == "build":
        path, words, pairs = build(a.lang, a.keep, part="all" if a.all else "train", out=a.out)
        print(f"{path}: {words:,} words, {pairs:,} pairs, {os.path.getsize(path) / 1024:.0f} KB")
    else:
        with gzip.open(f"{CACHE}/pairs/{a.lang}-{a.keep}.tsv.gz", "rt", encoding="utf-8") as f:
            for line in f:
                before, _, rest = line.rstrip("\n").partition("\t")
                if before == a.word.lower():
                    print(rest)


if __name__ == "__main__":
    main()


# ---- Measuring it -----------------------------------------------------------

def measure(lang, keep=32, sentences_n=1500, backoff=None, seed=7):
    """Keystrokes saved on held-out sentences, with the words before and
    without: before each word, its next-word suggestions; then, letter by
    letter, its completions, ranked with the word before or not. A word in
    the first three is one tap. A word the list lacks costs every letter."""
    import random
    import time
    vocab = P.read_wordlist(f"{CACHE}/words/small_{lang}.msgpack.gz")
    plain = P.Predictor(vocab, lang)
    ctx = P.Predictor(vocab, lang)
    ctx.use_pairs(f"{CACHE}/pairs/{lang}-{keep}.tsv.gz")
    if backoff is not None:
        P.CONTEXT_BACKOFF = backoff
    test = [t for _, t in sentences(lang, "test")]
    rng = random.Random(seed)
    picked = rng.sample(test, min(sentences_n, len(test)))
    letters = {"plain": 0, "context": 0}
    keys = {"plain": 0, "context": 0}
    next_hits = 0
    words = 0
    lat = []
    for text in picked:
        before = START
        for w in tokens(text, lang):
            words += 1
            for name, p in (("plain", plain), ("context", ctx)):
                letters[name] += len(w)
                b = before if name == "context" else None
                if b is not None and w in [x.rstrip("'").lower() for x in p.next(b)[:3]]:
                    keys[name] += 1
                    if name == "context":
                        next_hits += 1
                    continue
                need = len(w)
                for k in range(1, len(w)):
                    t = time.perf_counter()
                    found = p.suggest(w[:k], b)
                    if name == "context":
                        lat.append((time.perf_counter() - t) * 1000)
                    if w in [x.lower() for x in found[:3]]:
                        need = k + 1
                        break
                keys[name] += min(need, len(w))
            before = w if w in vocab else None
    lat.sort()
    return {"words": words,
            "plain_saved": round(1 - keys["plain"] / letters["plain"], 4),
            "context_saved": round(1 - keys["context"] / letters["context"], 4),
            "next_word_first3": round(next_hits / words, 4),
            "p95_ms": round(lat[int(len(lat) * 0.95) - 1], 2) if lat else 0}


def measure_swipe(lang, keep=32, sentences_n=400, seed=7, wobble=1.0):
    """Swipe accuracy on held-out sentences, every word swiped in order, with
    the word before as context and without: first, and in the first three."""
    import random
    import bench as B
    vocab = P.read_wordlist(f"{CACHE}/words/small_{lang}.msgpack.gz")
    p = P.Predictor(vocab, lang)
    p.use_pairs(f"{CACHE}/pairs/{lang}-{keep}.tsv.gz")
    rows = B.ROWS["azerty" if lang == "fr" else "qwerty"]
    keys = B.centres(rows)
    s = P.Swipes(p.ranks, p.folds, p)
    s.set_keys({"unit": 1.0, "keys": {c: list(v) for c, v in keys.items()}})
    rng = random.Random(seed)
    test = [t for _, t in sentences(lang, "test")]
    hits = {"plain": [0, 0], "context": [0, 0]}
    n = 0
    for text in rng.sample(test, min(sentences_n, len(test))):
        before = START
        for w in tokens(text, lang):
            f = P.fold(w).replace("'", "")
            if w in p.ranks and len(f) >= 2 and all(c in keys for c in f):
                path = B.finger_path(w, keys, rng, wobble)
                n += 1
                for name, b in (("plain", None), ("context", before)):
                    found = [x.lower() for x in s.decode(path, b)]
                    hits[name][0] += bool(found) and found[0] == w
                    hits[name][1] += w in found[:3]
            before = w if w in p.ranks else None
    return {k: (round(a / n, 4), round(b / n, 4)) for k, (a, b) in hits.items()} | {"swipes": n}
