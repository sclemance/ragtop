# Terminal completion isolation and bounded requests

Terminal completion now runs in a lazy `terminal-helper.py` process. It
imports the existing command/file parser without loading word dictionaries.
PATH enumeration uses directory entries and skips duplicate PATH components.
Command names are sent immediately; `apropos` notes are loaded asynchronously
and update only the still-current request. Slow filesystem/metadata work
cannot occupy the word/swipe predictor.

Both ordinary and terminal completion allow one request in flight plus the
latest pending request. Field/language/context checks reject obsolete word
results; terminal replies carry ids and are checked against field, line, cwd
and shell. No new typed-text cache or logs are created. The terminal worker
stops when the keyboard is hidden, the field changes or privacy/feature gates
close. It announces readiness before receiving work, and reaps its metadata
child on EOF, SIGTERM or metadata timeout.

## Verification

`bash tests/run predictor terminal-helper terminal-lifecycle completion-queue typing-memory`
passes. The tests include:

- real worker responses while metadata is held at a barrier, plus independent
  word-predictor response during that delay;
- metadata update ids, missing tools, five-second timeout and child cleanup;
- source-extracted Service queue tests for rapid prefixes, stale results,
  context/language/field changes and clearing retained text;
- real QML Process startup, stop/reopen, crash/retry, hidden-keyboard gating;
- existing prediction/ranking, command/file escaping and typing-memory checks.

On the development Intel N100, one isolated process trial measured 102 ms
startup, 109 ms first command lookup, 0.44 ms median warm request/response
(30 queries), and about 20 MiB RSS. These are local samples, not latency
promises; cold filesystem and system load matter. The previous in-predictor
first command lookup measured about 350 ms. The additional helper has a
memory/startup cost, paid only while used; the principal guarantee is that
terminal work no longer serializes word and swipe work. Touch-to-text latency
and large/network-mounted directories were not benchmarked.
