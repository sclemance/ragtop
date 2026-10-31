# Changelog

## 0.48.0 — Unreleased

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
