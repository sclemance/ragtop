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
and shell. No new typed-text cache or logs are created. Field changes, unknown
focus, leaving the prompt and keyboard hiding drop request text while preserving
the command cache. An id-only barrier for an outstanding request prevents focus
churn from queuing extra lookups. A worker reset drops pending description updates.
The worker stops when suggestions are disabled, typing memory leaves Full, a secret
field is entered or the keyboard becomes unavailable. It announces readiness before
receiving work, and reaps its metadata child on EOF, SIGTERM or metadata timeout.

## Verification

`bash tests/run predictor terminal-helper terminal-lifecycle completion-queue typing-memory`
passes. The tests include:

- real worker responses while metadata is held at a barrier, plus independent
  word-predictor response during that delay;
- metadata update ids, missing tools, five-second timeout and child cleanup;
- source-extracted Service queue tests for rapid prefixes, stale results,
  context/language/field changes and clearing retained text;
- real QML Process startup, stable PID through focus/hide/unknown-field changes,
  privacy/feature shutdown, rapid close/reopen, crash recovery and stale retry safety;
- worker resets preserve cached command metadata, empty prompts return no guesses;
- existing prediction/ranking, command/file escaping and typing-memory checks.

On the development Intel N100, one isolated process trial measured 102 ms
startup, 109 ms first command lookup, 0.44 ms median warm request/response
(30 queries), and about 20 MiB RSS. These are local samples, not latency
promises; cold filesystem and system load matter. The previous in-predictor
first command lookup measured about 350 ms. The additional helper has a
memory cost persists after first use until a privacy/feature shutdown; ordinary
focus changes and hide/show reuse the warm worker. The principal guarantee is that
terminal work no longer serializes word and swipe work. Touch-to-text latency
and large/network-mounted directories were not benchmarked.
