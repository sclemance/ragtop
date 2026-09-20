# Localization

Ragtop is English-only, deliberately, and will stay that way until Omarchy
decides how it wants to do this. That is not a shrug: there are things a
plugin has to get right *before* a translation layer exists, because they are
much harder to retrofit than to preserve. This file records where things
stand upstream, what Ragtop already does right, and the two rules to keep
following.

Last checked against upstream: **2026-09-20**, Omarchy 4.0.0.alpha.

## Ragtop's position

A distribution this size will end up with a localization standard; it would be
strange if it didn't. Ragtop's plan is to adopt whichever one emerges rather
than to invent a ninth:

- **Omarchy's own, first.** If the shell grows a translation layer, Ragtop
  uses it, whatever shape it takes.
- **A third-party standard only if no distro one appears**, and only once the
  dust has settled — a convention with several live implementations and users,
  not a proposal.
- **Until then, nothing.** No homegrown layer, no string-id scheme, no
  half-adopted catalog format. The cost of waiting is that Ragtop reads in
  English; the cost of guessing wrong is a rewrite plus a migration for
  everyone who translated anything.

What that leaves to do now is keep the code *convertible*, which is what the
two rules below are for.

## Where Omarchy stands

Omarchy is English by design. The installer asks for a keyboard layout and
nothing else, so `LANG` stays `en_US.UTF-8` until someone changes it by hand.
The shell's `qs.Commons` has no `I18n` singleton, and there is no hook for one
plugin to reach another plugin's strings.

The **manual and website are** translated — `omacom/omarchy-site` carries
around thirty locales under `src/i18n/`. The operating system's own interface
is not.

Everything proposed for the shell is open, and none of it has a word from a
code owner on it:

| | |
| --- | --- |
| [omarchy#7284](https://github.com/omacom/omarchy/issues/7284) | The feature request |
| [omarchy#8765](https://github.com/omacom/omarchy/pull/8765) | The leading proposal: a `qs.Commons.I18n` singleton, a Qt-free model, and a Bash counterpart. Catalogs keyed by **plugin id**, entries keyed on `(msgctxt, English msgid)` as gettext does, language packs shipping **as plugins** |
| [omarchy#10051](https://github.com/omacom/omarchy/pull/10051) | The rival: a compiled Qt translations module |
| [omarchy#12345](https://github.com/omacom/omarchy/issues/12345) | A community adjudication with measurements. Adopts #8765 with amendments, declines #10051 on cost |
| [omarchy#10949](https://github.com/omacom/omarchy/pull/10949), [#10955](https://github.com/omacom/omarchy/pull/10955) | Asking for a language at setup; reading day and month names from the locale |

Today the practical answer for a user who wants a translated desktop is the
[omarchy-language](https://github.com/sbelcl/omarchy-language) plugin. It sets
the locale, and it translates **the Omarchy menu and nothing else**, because
the menu is the only part of the shell that is data rather than code.

### What that means for Ragtop's menu rows

That plugin rewrites rows read from Omarchy's own
`default/omarchy/omarchy-menu.jsonc` into a marked
`// >>> omarchy-language begin` block in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, and preserves everything
outside that block verbatim.

Ragtop writes its own marked block into the same file (`install.sh`,
`menu_block`). The two coexist: it does not read Ragtop's rows, and Ragtop
does not touch its block. The consequence is simply that on a translated
desktop, **Setup › Tablet stays English** while the rest of the menu does not.
Nothing breaks; it just looks like what it is, an untranslated guest.

Two details of that mechanism are worth knowing if this is ever revisited:

- An override has to re-declare the **whole row**. The shell's comment
  promises a per-key merge, but `parseMenuJsonc` normalizes each entry to a
  full object with empty-string defaults first, so `{"label": "…"}` alone
  produces a row with no icon and no action.
- Its tables key on **English strings, not row ids**, so a row that uses a
  word already in the table translates itself. Ragtop's labels (`Key Shape`,
  `Auto Keyboard`, `System Overlays`…) are not in anyone's table.

## What the rest of Linux does

Arch has no framework for this, because it has no interface of its own to
translate — it ships the plumbing and every package brings its own catalog:
`/etc/locale.gen` → `locale-gen` → `/etc/locale.conf`, `localectl`, and
`/usr/share/locale`. That last one is not empty on an Omarchy machine. On the
laptop this was written on, with only `en_US.UTF-8` generated: **250 locale
directories**, pacman translated into 43 languages, systemd 53,
xkeyboard-config 46, GTK 117, `iso_3166-1` 159.

The ecosystem's answer, in layers:

1. **GNU gettext** is the standard — `.pot`/`.po`/`.mo`, keyed on the English
   source string, looked up through `LANGUAGE`/`LC_MESSAGES`. Everything
   above uses it, and it covers **shell scripts** too (`gettext.sh`,
   `eval_gettext`). `gettext`, `msgfmt` and `xgettext` are already installed.
2. **Qt and QML** use `qsTr()` with `.ts`/`.qm`, built by `lupdate` and
   `lrelease` (`qt6-tools`, not installed by default here). This is the fork
   Omarchy is stuck at: [#12345](https://github.com/omacom/omarchy/issues/12345)
   measured that no working gettext→Qt catalog bridge exists, which is why
   [#8765](https://github.com/omacom/omarchy/pull/8765) builds a QML catalog
   by hand instead of reusing the ecosystem's.
3. **Data files** are localized by suffixed keys, not by a runtime:
   `Name=Files` / `Name[de]=Dateien`, as `.desktop` and AppStream do. That is
   the closest thing to a standard for a data-driven menu like Omarchy's
   JSONC, and it needs no translation layer at all.
4. **Names of things** — languages, countries, keyboard layouts — are already
   translated by `iso-codes` and `xkeyboard-config`. Never retype them.

Two consequences for Ragtop, one taken and one not:

- **The space bar's layout name is localized** (`keyboard-helper.py`,
  `localized_layout_name`). The keymap spells it `German`; the name goes
  through xkeyboard-config's own catalog, so a German desktop reads
  `Deutsch`, a French one `Allemand`, a Japanese one `ドイツ語`. No table of
  Ragtop's own, nothing to keep up to date, and it works today whatever
  upstream decides. With an English session it returns what it was given.
- **Ragtop's Bash half could use gettext now** — the `ragtop` CLI's
  notifications, the installer's prose — with no dependency on the unresolved
  QML question. It doesn't, because a half-translated plugin is worse than an
  English one, but that half is unblocked whenever the rest is.

## Rule 1: prose and protocol are different things

The most expensive lesson in the upstream thread is that translating an
Omarchy string breaks things **silently**. `omarchy-dns` prints `Custom`, and
the menu decides which DNS provider is selected by comparing against that
word; translate it and the menu shows nothing selected, with no error
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
| `overlay-clones.sh`, `setup-check.sh` | the marker strings they grep for: `id: ragtopMode`, `// Ragtop: tablet settings.` |
| IPC and layers | the `ragtop` IPC target, its function names, and the `ragtop-keyboard`, `ragtop-keyboard-handle`, `ragtop-picker-nav`, `ragtop-screensaver-catcher` layer namespaces |
| `ragtop-layout.json`, `ragtop-style.json` | field names and values |

Ragtop is in good shape here, mostly by accident of taste: the menu's
`checked` commands (`ragtop shape is pill`) answer with an **exit code**
rather than a printed word, which is the pattern to keep. The one place
Ragtop parses printed prose is `overlay-clones.sh status`, and it belongs to
Ragtop on both sides.

It also depends on two protocol strings it does **not** own — `monitor-sensor`
printing `normal` / `left-up` / `bottom-up` / `right-up`, and
`omarchy-shell lock isLocked` answering `true`. Both would be someone else's
regression, but Ragtop would be where it showed up.

## Rule 2: key on the English string

If a translation layer lands, don't invent a scheme. Both live approaches key
on the English source string — the menu tables above, and #8765's
`(msgctxt, msgid)` pairs. Ragtop's prose is already written as plain English
sentences in one place each, so converting it later is mechanical:

- **Menu labels** — `install.sh`, in `menu_block`'s `rows` table.
- **Notifications** — `ragtop`'s `notify` calls and `choice_notice`, plus
  `overlay-clones.sh`'s `notify`.
- **Installer output** — `say`, `warn` and the offer text in `install.sh`.
- **Setup check** — `setup-check.sh`'s notification.
- **In the interface itself** — remarkably little; see below.

Keep it that way: no string built by concatenating fragments, and no prose
that another script reads back.

## What is already language-agnostic

Most of the keyboard doesn't need translating, because it isn't words:

- **The letters** are the active Hyprland layout's own, read from the keymap
  (`keyboard-helper.py`, `XkbLabels`) — QWERTZ, AZERTY, Cyrillic, Dvorak.
- **The symbol pages** pick up the symbols that layout carries (§ and ° on a
  German keyboard, ¡ and ¿ on a Spanish one, № and ₽ on a Russian one).
- **Accents** are a long press away, with the layout's own letters first, so
  the letters AZERTY keeps off its letter rows are reachable.
- **The key glyphs** — Shift, Backspace, Enter, the arrows, the settings cog —
  are drawn vectors (`KeyIcon.qml`), not font glyphs and not words.

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
them off the end of the row — worth remembering, since most languages run
longer than English.

## If you want to help

The useful contribution today is not a Ragtop translation — there is nothing
to plug it into. It is upstream: [omarchy#7284](https://github.com/omacom/omarchy/issues/7284)
is where the decision will be made, and a language pack for
[omarchy-language](https://github.com/sbelcl/omarchy-language) is what reaches
a user's desktop this week.

When a layer does land, Ragtop's domain will be its plugin id,
`sclemance.ragtop`.
