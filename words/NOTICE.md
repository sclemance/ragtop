# The English word list

Ragtop's word suggestions read `small_en.msgpack.gz` from
[wordfreq](https://github.com/rspeer/wordfreq) 3.2, by Robyn Speer, as
wordfreq publishes it. It is not part of Ragtop and not in its repository.
`ragtop words install` downloads it, checks it against a fixed SHA-256, and
keeps it unmodified in `~/.local/share/ragtop/words/en/`, with a copy of this
notice beside it.

wordfreq's data files may be redistributed under the Creative Commons
Attribution-ShareAlike 4.0 license
(<https://creativecommons.org/licenses/by-sa/4.0/>). Ragtop itself stays
under its MIT licence: it reads the file and does not include it.

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
