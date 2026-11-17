# Changelog

## 0.49.0 - 2026-11-17

- Validate theme directory names before listing them and shell-quote them in menu commands. Crafted names can no longer execute commands when Omarchy evaluates the menu. Adding or refreshing the menu replaces unsafe rows written by older versions.
- Add Spanish, Portuguese, Italian and German word suggestions and swipe vocabulary, with language-specific handling of accents, apostrophes and spelling. Their word lists and pairs download only when requested and are checked against pinned SHA-256 hashes.
- Use Omarchy's Commons.Color explicitly so theme colours keep working with Qt 6.12. Add the released Omarchy 4.5.0 overlay fixtures and compatibility tests.
- Remove trailing spaces added to Japanese candidates by Mozc 3.35 while preserving candidates that consist only of spaces.
- Treat symlinks and other special files in overlay clones as user edits. Checking a clone no longer risks writing through a copied symlink.
- Leave the lock clone in place while the session is locked or its lock state cannot be determined. A deferred update is retried at the next sync while unlocked.
- Clear typed state when focus moves to another window and keep it untrusted until the newest numbered field query answers. Old or unanswered queries cannot restore the previous field's state.
- Shell-escape command names offered in terminal completion, including names containing equals signs.
- Read Hyprland's blur response correctly and leave unknown state alone.
- Count full Unicode characters in the typed record and stop trusting cursor edits across combining characters or joined emoji. Read key-size settings back after writes so the controls follow the value that was saved.
- Correct the suggested English forms of tie and die to tying and dying.

## 0.48.3 — 2026-11-08

- `bench/touch-trace.py`, the sudo diagnostic, gives up root as soon as the touchscreen is open and writes its log as the user who ran it. The log is never opened through a link, only a regular file of theirs is used, and it is made private on every run. It no longer runs as plain root, and it takes only a `/dev/input/eventN` touchscreen.

## 0.48.2 — 2026-11-01

- What was typed is kept when the focused window's title changes. Hyprland repeats its window event on every title change (Claude Code's spinner, shells on each prompt), and Ragtop had taken each one for another window and forgotten the line.
- Where Ragtop never sees a line begin, as in a terminal running a program or after typing on another keyboard, the first word it types is now kept and named by BackSpace. A word begun on another keyboard and finished here is named by the letters typed here.
- The keyboard is spaced like a window. A keycap's or strip button's edge sits as far below the window above as one window sits below another, and the side keys line up with the windows' edges, following Hyprland's gaps, Super+Shift+Backspace included. Nothing is closer to an edge than the keys are to each other. The strip's end buttons line up with the keys.
- touch-trace also logs field focus, the bridge's reports and every reset of the typed record, as events and ids, never text.

## 0.48.1 — 2026-10-31

- Check for updates saves the fetched manifest to a temporary file and reads its version from there, rather than piping the download. Behaviour is unchanged; the marketplace's security baseline misread the old line.

## 0.48.0 — 2026-10-31

- Overlay focus follows Keyboard availability, including Always On in laptop mode.
- Locale-independent clone tracking recognizes existing approved copies without discarding edit protection.
- Prepare overlay additions, removals and refreshes before publishing them in batches. Serialize concurrent overlay jobs and keep rollback copies of the newest two batches only. A batch that never published is removed, and removing one of Ragtop's own clones no longer leaves an Omarchy backup of it behind.
- Tell a locked session apart from one whose lock state could not be read when overlays are chosen.
- A failed overlay step in the installer no longer stops the install part-way: Ragtop is installed, the reason is shown, and the next run offers the overlays again.
- Overlays that went through without the hooks that keep them in step are reported as exactly that, by the installer, Setup and `ragtop overlay`. Startup sync and a rerun of the installer, `--no-restart` included, put the hooks back. `ragtop overlay enable/disable` no longer announces a change that failed.
- Preserve rapid settings taps; add display confirmation, Typing Memory explanations, language-download recovery and accurate size checks.
- Stop uninstall if overlay cleanup fails.
- Omarchy's own Remove no longer strands the overlay clones: a copy kept outside Ragtop removes its unedited clones and hooks once Ragtop is gone, and names any clone you edited. Menu rows, the switch rule and settings still need `./install.sh uninstall`.
- Clear queued typed text when switching Typing Memory to Nothing and avoid retaining it after the keyboard hides.
- Add Mechanical backlight and keycap options, Focus and Chiclet styling; retire standalone Slab, Glow and Pudding Shine Through themes.
- Use Omarchy styling and palette for the lock keyboard; improve its password-entry layout and Always On visibility.
- Align lock-screen long-press choices, selection and cancellation with desktop behaviour; bound popup width, restore punctuation holds, and avoid splitting supplementary Unicode characters on Backspace.
- Swipe no longer rebuilds its word paths when the keyboard reports the same key positions again, such as on returning from the symbols page.
- Terminal command and file suggestions run in a separate helper, so a slow folder or manual-page lookup cannot hold up word suggestions or a swipe. Command descriptions arrive after the names.
- Mechanical keycaps build only the surface for the material in use; they look exactly the same.
- Make layout changes reliable when switching back before displayed labels update.
- Add Omarchy to prediction/swipe vocabulary; improve tour timing and suggestion-strip presentation.
- Refresh marketplace artwork and search description.

The guided settings wizard remains deferred. Suggestions, swipe and CJK input remain beta.
