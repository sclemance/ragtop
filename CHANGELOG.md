# Changelog

## 0.48.0 — Unreleased

- Overlay focus follows Keyboard availability, including Always On in laptop mode.
- Locale-independent clone tracking recognizes existing approved copies without discarding edit protection.
- Prepare overlay additions, removals and refreshes before publishing them in batches. Serialize concurrent overlay jobs and keep rollback copies of the newest two batches only. A batch that never published is removed, and removing one of Ragtop's own clones no longer leaves an Omarchy backup of it behind.
- Tell a locked session apart from one whose lock state could not be read when overlays are chosen.
- A failed overlay step in the installer no longer stops the install part-way: Ragtop is installed, the reason is shown, and the next run offers the overlays again.
- Preserve rapid settings taps; add display confirmation, Typing Memory explanations, language-download recovery and accurate size checks.
- Stop uninstall if overlay cleanup fails. Native Omarchy Remove still requires running Ragtop's uninstaller first.
- Clear queued typed text when switching Typing Memory to Nothing and avoid retaining it after the keyboard hides.
- Add Mechanical backlight and keycap options, Focus and Chiclet styling; retire standalone Slab, Glow and Pudding Shine Through themes.
- Use Omarchy styling and palette for the lock keyboard; improve its password-entry layout and Always On visibility.
- Align lock-screen long-press choices, selection and cancellation with desktop behaviour; bound popup width, restore punctuation holds, and avoid splitting supplementary Unicode characters on Backspace.
- Make layout changes reliable when switching back before displayed labels update.
- Add Omarchy to prediction/swipe vocabulary; improve tour timing and suggestion-strip presentation.
- Refresh marketplace artwork and search description.

The guided settings wizard remains deferred. Suggestions, swipe and CJK input remain beta.
