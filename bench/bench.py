#!/usr/bin/env python3
"""How fast and how good Ragtop's predictions are, per language and per word
list, so a change of data or engine is decided by numbers.

    bench/bench.py fetch                 the data, into ~/.cache/ragtop-bench
    bench/bench.py run <lang> <list> [--rows qwerty|azerty] [--json]
    bench/bench.py compare <lang> ...     run each list named and print a table

<list> is a wordfreq list file, or small or large for the cached ones.

Nothing here ships with Ragtop or runs on a user's machine. The data it
reads stays in the cache, outside the repository: wordfreq's lists are
CC-BY-SA, the texts are Project Gutenberg's, and none of it is ours to
redistribute in a commit.

What it measures, each on text the word lists were not built from:

  load        time to read a list and build the predictor and swipe decoder,
              and the memory that takes (each run is its own process)
  coverage    how many of the text's words the list has at all
  completion  per keystroke: is the word in the strip's first three yet,
              and how long suggest() took; keystroke savings is the share of
              letters a tap on the strip spared
  correction  one letter swapped for a key beside it: is the word in the
              first three, and how long it took
  swipe       a path through the word's keys, wobbled the way a finger is,
              decoded: first, first three, and how long, for words as often
              as they are written and, as "rare", for distinct words evenly

Random choices are seeded, so two runs of one list agree, and two lists are
measured on the same words.
"""
import argparse
import json
import math
import os
import random
import re
import resource
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import predictor as P  # noqa: E402

CACHE = os.path.expanduser("~/.cache/ragtop-bench")
WORDFREQ = "https://raw.githubusercontent.com/rspeer/wordfreq/v3.2/wordfreq/data"
# Public domain novels, one per language, as held-out text: Project
# Gutenberg's own numbers.
TEXTS = {"en": 1661, "fr": 17989}
ROWS = {
    "qwerty": ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
    "azerty": ["azertyuiop", "qsdfghjklm", "wxcvbn"],
}
# How far each row starts in from the left, in keys, as on a real board.
STAGGER = [0.0, 0.25, 0.75]
SEED = 7
TOP = 3


def fetch():
    os.makedirs(f"{CACHE}/words", exist_ok=True)
    os.makedirs(f"{CACHE}/text", exist_ok=True)
    for lang in TEXTS:
        for size in ("small", "large"):
            out = f"{CACHE}/words/{size}_{lang}.msgpack.gz"
            if not os.path.exists(out):
                subprocess.run(["curl", "-fsSL", "--max-time", "120", "-o", out,
                                f"{WORDFREQ}/{size}_{lang}.msgpack.gz"], check=True)
        out = f"{CACHE}/text/{lang}.txt"
        if not os.path.exists(out):
            n = TEXTS[lang]
            subprocess.run(["curl", "-fsSL", "--max-time", "120", "-o", out,
                            f"https://www.gutenberg.org/cache/epub/{n}/pg{n}.txt"], check=True)


def words_of(lang):
    """The text's words, in order, lower case, its Gutenberg wrapping cut."""
    text = open(f"{CACHE}/text/{lang}.txt", encoding="utf-8-sig").read()
    start = text.find("*** START")
    end = text.find("*** END")
    if start != -1:
        text = text[text.index("\n", start):end if end != -1 else None]
    text = text.replace("’", "'")
    return [w.lower() for w in re.findall(r"[^\W\d_]+(?:'[^\W\d_]+)*", text)]


def centres(rows):
    return {c: (STAGGER[r] + i + 0.5, r + 0.5) for r, row in enumerate(rows) for i, c in enumerate(row)}


def finger_path(word, keys, rng, wobble=1.0):
    """A swipe through the word's keys: each key aimed at and missed a little,
    the line between them drawn every tenth of a key and never quite still.
    wobble scales how far off: 0.7 a careful finger, 1.4 a hurried one."""
    stops = []
    for c in P.fold(word):
        if c == "'":
            continue
        p = keys[c]
        if not stops or stops[-1][0] != c:
            stops.append((c, (p[0] + rng.gauss(0, 0.22 * wobble), p[1] + rng.gauss(0, 0.18 * wobble))))
    out = []
    for (_, a), (_, b) in zip(stops, stops[1:]):
        n = max(2, int(math.dist(a, b) / 0.1))
        for i in range(n):
            t = i / n
            out.append([a[0] + (b[0] - a[0]) * t + rng.gauss(0, 0.03),
                        a[1] + (b[1] - a[1]) * t + rng.gauss(0, 0.03)])
    out.append(list(stops[-1][1]))
    return out


def timed(fn, *args):
    t = time.perf_counter()
    out = fn(*args)
    return out, (time.perf_counter() - t) * 1000


def spread(ms):
    if not ms:
        return {}
    ms = sorted(ms)
    return {"median_ms": round(statistics.median(ms), 3),
            "p95_ms": round(ms[int(len(ms) * 0.95) - 1], 3),
            "max_ms": round(ms[-1], 3), "n": len(ms)}


def run(lang, path, rows_name, samples):
    rss0 = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    rows = ROWS[rows_name]
    keys = centres(rows)
    t = time.perf_counter()
    ranks = P.read_wordlist(path)
    pred = P.Predictor(ranks, lang)
    pred.set_rows([list(r) for r in rows])
    swipes = P.Swipes(pred.ranks, pred.folds)
    swipes.set_keys({"unit": 1.0, "keys": {c: list(p) for c, p in keys.items()}})
    load_ms = (time.perf_counter() - t) * 1000
    rss = (resource.getrusage(resource.RUSAGE_SELF).ru_maxrss - rss0) / 1024

    text = words_of(lang)
    rng = random.Random(SEED)
    known = [w for w in text if w in pred.ranks]
    result = {"lang": lang, "list": os.path.basename(path), "words": len(pred.ranks),
              "load_ms": round(load_ms), "memory_mb": round(rss, 1),
              "coverage": round(len(known) / len(text), 4)}

    # Completion, over every word of a sample of running text, known or not:
    # an unknown word is one the strip never offers, and costs every letter.
    picks = [text[i] for i in sorted(rng.sample(range(len(text)), samples["complete"]))]
    letters = saved_keys = 0
    lat = []
    for w in picks:
        needed = len(w)
        for k in range(1, len(w)):
            found, ms = timed(pred.suggest, w[:k])
            lat.append(ms)
            if w in [x.lower() for x in found[:TOP]]:
                needed = k + 1   # the letters so far, and a tap
                break
        letters += len(w)
        saved_keys += len(w) - min(needed, len(w))
    result["completion"] = {"keystroke_savings": round(saved_keys / letters, 4), **spread(lat)}

    # Corrections: one letter for a key beside it, a typo that is not itself
    # a word.
    near = P.neighbours([list(r) for r in rows])
    pool = [w for w in set(known) if len(w) >= 4 and all(c in near for c in P.fold(w))]
    pool.sort()
    hits1 = hits3 = 0
    lat = []
    tried = 0
    for w in rng.sample(pool, min(samples["correct"], len(pool))):
        f = P.fold(w)
        i = rng.randrange(len(f))
        typo = f[:i] + rng.choice(sorted(near[f[i]])) + f[i + 1:]
        if typo in pred.ranks:
            continue
        found, ms = timed(pred.suggest, typo)
        found = [x.lower() for x in found]
        tried += 1
        hits1 += bool(found) and found[0] == w
        hits3 += w in found[:TOP]
        lat.append(ms)
    result["correction"] = {"top1": round(hits1 / max(1, tried), 4),
                            "top3": round(hits3 / max(1, tried), 4), **spread(lat)}

    # Swipes, over words the decoder could spell on this board, two ways.
    # As written: positions in the running text, so the words come up as
    # often as people write them, which is what a swipe meets. Rare words:
    # distinct words picked evenly, which is mostly words seldom written and
    # says how the decoder copes when frequency cannot help. The first is
    # the one to judge by; judged by the second alone, frequency looked like
    # it was hurting, and weighing it less would have made everyday swipes
    # worse.
    def decodable(w):
        f = P.fold(w).replace("'", "")
        return len(f) >= 2 and all(c in keys for c in f)

    def swipe_on(words):
        hits1 = hits3 = 0
        lat = []
        for w in words:
            found, ms = timed(swipes.decode, finger_path(w, keys, rng))
            found = [x.lower() for x in found]
            hits1 += bool(found) and found[0] == w
            hits3 += w in found[:TOP]
            lat.append(ms)
        return {"top1": round(hits1 / max(1, len(words)), 4),
                "top3": round(hits3 / max(1, len(words)), 4), **spread(lat)}

    written = []
    while len(written) < samples["swipe"]:
        w = text[rng.randrange(len(text))]
        if w in pred.ranks and decodable(w):
            written.append(w)
    result["swipe"] = swipe_on(written)
    pool = sorted(w for w in set(known) if decodable(w) and len(P.fold(w)) >= 3)
    result["swipe_rare"] = swipe_on(rng.sample(pool, min(samples["swipe"], len(pool))))
    return result


def list_path(lang, name):
    return name if os.path.exists(name) else f"{CACHE}/words/{name}_{lang}.msgpack.gz"


def table(results):
    cols = [("list", lambda r: r["list"].replace(".msgpack.gz", "")),
            ("words", lambda r: f"{r['words']:,}"),
            ("load", lambda r: f"{r['load_ms']} ms"),
            ("memory", lambda r: f"{r['memory_mb']} MB"),
            ("coverage", lambda r: f"{r['coverage']:.1%}"),
            ("saved", lambda r: f"{r['completion']['keystroke_savings']:.1%}"),
            ("type p95", lambda r: f"{r['completion']['p95_ms']} ms"),
            ("fix top3", lambda r: f"{r['correction']['top3']:.1%}"),
            ("fix p95", lambda r: f"{r['correction']['p95_ms']} ms"),
            ("swipe 1/3", lambda r: f"{r['swipe']['top1']:.0%}/{r['swipe']['top3']:.0%}"),
            ("rare 1/3", lambda r: f"{r['swipe_rare']['top1']:.0%}/{r['swipe_rare']['top3']:.0%}"),
            ("swipe p95", lambda r: f"{max(r['swipe']['p95_ms'], r['swipe_rare']['p95_ms'])} ms")]
    cells = [[name for name, _ in cols]] + [[f(r) for _, f in cols] for r in results]
    widths = [max(len(row[i]) for row in cells) for i in range(len(cols))]
    for row in cells:
        print("  ".join(c.ljust(w) for c, w in zip(row, widths)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("fetch")
    for name in ("run", "compare"):
        p = sub.add_parser(name)
        p.add_argument("lang")
        p.add_argument("lists", nargs="+" if name == "compare" else 1)
        p.add_argument("--rows", default=None, choices=sorted(ROWS))
        p.add_argument("--complete", type=int, default=1500)
        p.add_argument("--correct", type=int, default=400)
        p.add_argument("--swipe", type=int, default=300)
        p.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if a.cmd == "fetch":
        fetch()
        return
    rows = a.rows or ("azerty" if a.lang == "fr" else "qwerty")
    samples = {"complete": a.complete, "correct": a.correct, "swipe": a.swipe}
    if a.cmd == "run":
        r = run(a.lang, list_path(a.lang, a.lists[0]), rows, samples)
        print(json.dumps(r) if a.json else json.dumps(r, indent=2))
        return
    # Each list in a process of its own, so memory is that list's alone.
    results = []
    for name in a.lists:
        out = subprocess.run([sys.executable, __file__, "run", a.lang, name, "--rows", rows,
                              "--complete", str(a.complete), "--correct", str(a.correct),
                              "--swipe", str(a.swipe), "--json"],
                             capture_output=True, text=True, check=True).stdout
        results.append(json.loads(out))
    if a.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"{a.lang}, {rows}")
        table(results)


if __name__ == "__main__":
    main()
