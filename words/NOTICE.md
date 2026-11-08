# Ragtop's language data

Word suggestions, swipe and next-word prediction read two files per
language: a word list and a pairs file. English's are here, in `words/en/`,
so English works with nothing to download. The other languages' are
published by Ragtop as assets of its `data-v1` release on GitHub, and
`ragtop words install <lang>` fetches them from there, checks each against a
fixed SHA-256, and keeps them in `~/.local/share/ragtop/words/<lang>/` with a
copy of this notice.

**This data is not under Ragtop's MIT licence.** Ragtop's code is MIT; these
files are under the Creative Commons Attribution-ShareAlike 4.0 license
(<https://creativecommons.org/licenses/by-sa/4.0/>), as below.

## Word lists: `small_<lang>.msgpack.gz`

From [wordfreq](https://github.com/rspeer/wordfreq) 3.2, by Robyn Speer,
exactly as wordfreq publishes them, unmodified. wordfreq's data files may be
redistributed under CC BY-SA 4.0.

## Pairs: `pairs_<lang>.tsv.gz`

Which words follow which, for next-word prediction: a line of text per word,
its commonest followers with how often each followed it. Counted by Ragtop from
the sentences of [Tatoeba](https://tatoeba.org), which are under CC BY 2.0 FR
(<https://creativecommons.org/licenses/by/2.0/fr/>), some CC0, and kept only
for words in the language's wordfreq list, so they are released under CC BY-SA
4.0. Sentences © their Tatoeba contributors.

Made with `bench/pairs.py build <lang> --all --out pairs_<lang>.tsv.gz` in
Ragtop's repository, from Tatoeba's per-language export
(`<code>_sentences.tsv.bz2`), keeping each word's 32 commonest followers seen
at least twice, and leaving out names Tatoeba's sentences use far more than
everyday writing does (Tom, Mary), and listing the words written with a
capital wherever they are (I, Paris). The build is reproducible: the same export
gives the same file. The exports used:

| language | export date | export SHA-256 | pairs SHA-256 |
| --- | --- | --- | --- |
| English (`eng`) | 2026-10-26 | `f634eaaf26623c2a2e170be2dae54b18388479311ae8619d04889df4e5d021f3` | `d653178af315be3a158f14f91f3d6a4c670c62094ec38f6ed0e2fcf7a1cdd3a1` |
| French (`fra`) | 2026-10-26 | `3cbc43eab20185907b3ff4eae8aa60d20b9caf5133076c1c1c013d169cd87a99` | `8979b831a321d52fe33422d394eed08f265f50be8f817b03475afeee5b76c352` |
| Spanish (`spa`) | 2026-11-07 | `7bbafb2af79d50eba3b398ce2756ca1d7f6ad5a63ea01996d7ff63fa22d9fbe7` | `c6aab2f0e1ffbe8af4c15d49ed51460ca44d68f7862056456f16ad9fa43e6b80` |
| Portuguese (`por`) | 2026-11-07 | `651e36e46c973f307634e0d02885a40c5880fb57faedbe4c7c61309db786202e` | `c6ce5b119358e0f5b57066866500d81246671a64c07ffe445dbc796ec1ae9370` |
| Italian (`ita`) | 2026-11-07 | `169bca28530de22a03e37718cad7d2c7ad2a759cd2dd169aad8a88641aca7540` | `1d2f37002e74bd3d5174873fac24164ba2a79151973ae18be61fbef6f917a13c` |
| German (`deu`) | 2026-11-07 | `293e10050e36c7def8c82dea9f94ae1b4086e9ef8b23cc28625957b9fe456354` | `a959ae062cf185ee2527b96333c8b31c99d16371cf8e0935e58fe99071720fe7` |

## wordfreq's sources

wordfreq contains data extracted from Google Books Ngrams
(<http://books.google.com/ngrams>) and Google Books Syntactic Ngrams, used
with acknowledgement of the Google Books Ngram Viewer as the source.

It also contains data derived from these Creative Commons-licensed sources:
the Leeds Internet Corpus, from the University of Leeds Centre for
Translation Studies; Wikipedia, the free encyclopedia; and ParaCrawl, a
multilingual Web crawl. It contains data from OPUS OpenSubtitles 2018, whose
data originates from the OpenSubtitles project
(<http://www.opensubtitles.org/>).

It contains data from the SUBTLEX word lists (SUBTLEX-US, SUBTLEX-UK and
others), created by Marc Brysbaert et al. and freely available at
<http://crr.ugent.be/programs-data/subtitle-frequencies>, distributed in
wordfreq by permission of their authors on the condition that they are
credited and that it remains clear that SUBTLEX is freely available data.

Some of its data was collected from the streaming Twitter API, giving
statistics about commonly used words without displaying or republishing any
Twitter content.

Citation: Robyn Speer. (2022). rspeer/wordfreq: v3.0 (v3.0.2). Zenodo.
<https://doi.org/10.5281/zenodo.7199437>
