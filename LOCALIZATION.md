# Localization

## Why care

Because in 2026, localization isn't as hard as it used to be, and Linux is for
everyone, not just English speakers.

The machinery is already on the disk. A stock Omarchy machine carries 250
locale directories and the catalogs to go with them: pacman speaks 43
languages on it, systemd 53, GTK 117. Every one of those projects solved this
with tools that ship in the base system. What's missing in Omarchy's case
isn't technology, it's a decision, and a decision can arrive any time, which
is exactly why a plugin written today shouldn't make it harder to act on.

So this is not a file about translating Ragtop. It is about not standing in
the way of the day someone does.

Omarchy decided in October 2026: **"Omarchy in 50 languages"**
([omarchy#15326](https://github.com/omacom/omarchy/pull/15326), merged into
`quattro` on 2026-10-14, in 4.5.0-rc1). Ragtop follows it.

## How Ragtop does it

- **The language is Omarchy's.** *Setup › Language*, or
  `omarchy language <code>`, writes `~/.config/omarchy/language`; Ragtop
  reads the same file and watches it, so switching Omarchy's language
  switches Ragtop's too, at once. No file, as on Omarchy before 4.5, is
  English.
- **The catalogs are Ragtop's, in Omarchy's form.** Omarchy's `I18n` reads
  only Omarchy's own catalogs and has no hook for a plugin's, and its menu
  catalog applies only to Omarchy's own rows. So Ragtop keeps its own, in
  `i18n/<code>/`, shaped exactly as Omarchy's are, so they can move the day
  a plugin hook appears:
  - `shell.json`: everything drawn on screen, the controls, the tour, the
    setup wizard, the strip's offers, the picker strip, the bar's tooltips,
    and the service's notifications. Read by `Service.qml`, `t(key, ...)`
    and `tn(key, count, ...)`.
  - `cli.json`: the `ragtop` command's notifications, the installer's
    words, the overlay clones' and the setup check's. Read by `i18n.sh`'s
    `t`, sourced by each script, the counterpart of Omarchy's
    `omarchy-i18n`.
  - `menu.json`: the *Setup › Tablet* rows, in Omarchy's menu-catalog shape
    (`{"<row id>": {"label": ...}}`). `menu-block.sh` writes the rows in the
    language set, and the service rewrites them when it changes. Theme
    names are names, and stay as the themes give them.
- **Keys are dotted names** (`tour.swipe.body`), as Omarchy's are; values
  carry `%1`, `%2` placeholders a translation may reorder, and plurals are
  `{"one": ..., "other": ...}`. English is the source of truth and the
  fallback for any key a language lacks; the key itself shows only where
  neither has it, which `tests/i18n-test.sh` rules out.
- **Terminal error messages stay English**, as Omarchy's own command-line
  output does. What a person reads on the desktop, and the installer, is
  translated.
- **Languages** use Omarchy's codes (`fr`, `de`, `es-MX`, `pt-BR`...). The
  first are English, French, German, Spanish, Italian and Portuguese (see
  the README's language support); each needs a native speaker's review
  before it ships.

## For translators

Copy `i18n/en/` to `i18n/<code>/` and translate the values, not the keys.
Keep every `%1`, `%2`; move them where your grammar wants. Keep `[y/N]` in
the installer's two questions exactly: the answer is read as y. Keep
"Ragtop" as it is (below). Keep menu labels short, about 15 characters,
before the ✓ pushes them off the row. Then run `tests/i18n-test.sh`, which
says what is missing, extra or mismatched.

## The name stays Ragtop

**Ragtop is never translated**, in any language: it is a name, as Omarchy is,
and a name a person may search for. Catalogs carry it as written, and a
translation that needs a word for "the keyboard" uses one of its own beside
it, never in place of it.

What is checked instead is whether the name itself reads badly. "Ragtop" is
English slang for a convertible with a fabric roof, from 1954, and no
dictionary or slang source found lists it as offensive. Its nearest
neighbours are not so clean: "rag" alone is mildly disparaging (a poor
newspaper), and English has slurs built on "rag-" (raghead), which the name
is not but might be heard near. Other languages have not been checked by
anyone who speaks them, so every language's review answers one more
question: does "Ragtop", left as it is, sound like anything offensive, crude
or unfortunate there? Recorded in the table below before a language ships.

| Language | Name reviewed by | Finding |
| --- | --- | --- |
| English | — | no known problem (dictionaries, Green's Dictionary of Slang) |
| French | not yet | catalogs drafted 2026-10-26, awaiting a native speaker's review of them and of the name |

## Rule 1: prose and protocol are different things

The most expensive lesson in the upstream thread is that translating an
Omarchy string breaks things **silently**. `omarchy-dns` prints `Custom`, and
the menu decides which DNS provider is selected by comparing against that
word. Translate it and the menu shows nothing selected, with no error
anywhere. Translating the shipped keybinding descriptions destroys the chord
merges and reorders most of the rendered rows, again with nothing failing.

So: a string that something else reads back is **protocol**. It is English
because ASCII is a convenient alphabet, not because it is a language, and it
must never be translated. Ragtop's protocol strings, all of them:

| Where | What |
| --- | --- |
| `$XDG_RUNTIME_DIR/ragtop-mode` | `tablet` / `laptop`, compared in `Service.qml` and in every overlay clone's patch |
| `settings.conf` | keys and values (`auto`, `on`, `off`, `opaque`, `oneshot`, `raised`…), written by `ragtop`, read by `Service.qml` |
| `install.conf` | `overlays=` and its space-separated overlay names |
| `keyboard-helper.py` stdin/stdout | the commands (`type`, `key`, `down`, `up`, `hold`, `release`, `reload`, `quit`) and the replies `ok`, `error: …`, `labels <json>` |
| `fcitx-osk-bridge.py` stdout | `show` |
| `overlay-clones.sh status` | `<name>: installed…`, parsed by `install.sh`'s offer and printed by `ragtop overlay status` |
| `overlay-clones.sh tappable` | the overlay names it prints, one per line, read by `Service.qml` |
| `overlay-clones.sh`, `setup-check.sh` | the marker strings they grep for: `id: ragtopMode`, `// Ragtop: tablet settings.` |
| IPC and layers | the `ragtop` IPC target, its function names, and the `ragtop-keyboard`, `ragtop-keyboard-handle`, `ragtop-picker-nav`, `ragtop-screensaver-catcher` layer namespaces |
| `ragtop-layout.json`, `ragtop-style.json` | field names and values |

Ragtop is in good shape here, mostly by accident of taste: the menu's
`checked` commands (`ragtop shape is pill`) answer with an **exit code**
rather than a printed word, which is the pattern to keep. The one place
Ragtop parses printed prose is `overlay-clones.sh status`, and it belongs to
Ragtop on both sides.

It also depends on two protocol strings it does **not** own. `monitor-sensor`
printing `normal` / `left-up` / `bottom-up` / `right-up`, and
`omarchy-shell lock isLocked` answering `true`. Both would be someone else's
regression, but Ragtop would be where it showed up.

## Rule 2: whole sentences, never fragments

Don't invent a scheme; Ragtop's is Omarchy's (above): dotted keys, `%1`
placeholders, English as the fallback. And every string is a whole sentence,
or a whole label: never one built by putting a word into a sentence in code,
"The " + name + " is on", since other languages put the word elsewhere and
inflect it. Where a sentence has to name something, the name is a `%1`, and
the name itself comes from the catalog too (the overlays' names, a
language's name). Where a value is a setting rather than a word (small,
normal, large), each value gets its own sentence. Converting Ragtop found
five of these and turned each into whole sentences: the overlay
notifications, the key-label notice, Shift's state and "This is ..." in the
tour, and the setup wizard's summary.

## What is already language-agnostic

Most of the keyboard doesn't need translating, because it isn't words:

- **The letters** are the active Hyprland layout's own, read from the keymap
  (`keyboard-helper.py`, `XkbLabels`): QWERTZ, AZERTY, Cyrillic, Dvorak.
- **The symbol pages** pick up the symbols that layout carries (§ and ° on a
  German keyboard, ¡ and ¿ on a Spanish one, № and ₽ on a Russian one).
- **Accents** are a long press away, with the layout's own letters first, so
  the letters AZERTY keeps off its letter rows are reachable.
- **The key glyphs**, Shift, Backspace, Enter, the arrows and the settings
  cog, are drawn vectors (`KeyIcon.qml`), not font glyphs and not words.

## The English that is left, and what it's worth

| | |
| --- | --- |
| `Esc`, `Tab`, `Ctrl`, `Alt`, `Super` | Leave them. Physical keyboards print these in English in most of the world, and a translated `Ctrl` would be less recognisable, not more |
| `?123`, `#+=` | Symbols, effectively |
| **`ABC`** | The one genuinely Latin-centric label: the key back to the letters page says `ABC` whatever script you type. GBoard shows `АБВ` on Cyrillic. Ragtop already knows the layout's letters, so this could be derived rather than translated |
| The space bar's layout name | Done: the keymap spells it `German`, and it goes through xkeyboard-config's catalog to reach `Deutsch` (see above) |
| `Select`, `Cancel` on the picker strip | Two words, the only prose drawn on a Ragtop surface |
| Menu labels and notifications | The bulk of it, and the part a language pack would reach first |

Menu labels have a budget of roughly **15 characters** before the ✓ pushes
them off the end of the row, worth remembering since most languages run
longer than English.

## If you want to help

The useful contribution today is not a Ragtop translation, since there is
nothing
to plug it into. It is upstream: [omarchy#7284](https://github.com/omacom/omarchy/issues/7284)
is where the decision will be made, and a language pack for
[omarchy-language](https://github.com/sbelcl/omarchy-language) is what reaches
a user's desktop this week.

When a layer does land, Ragtop's domain will be its plugin id,
`sclemance.ragtop`.
