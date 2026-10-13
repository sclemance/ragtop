# Fixtures

Omarchy's own files, copied unmodified, for `overlay-clones.sh` to be run
against. They are Omarchy's, under its MIT licence: see `LICENSE.omarchy`.

| Directory | From |
| --- | --- |
| `omarchy-4.0.4` | the `omarchy` 4.0.4-1 package, `/usr/share/omarchy` |
| `omarchy-7cc6a55` | `omacom/omarchy` at commit `7cc6a55f24fab194fdaacddc801a28acb0fe4810` |

Each holds the six plugins Ragtop can clone, from `shell/plugins`, whole
except for `emojis/emojis.json`, which is 108 KB of data the patcher only
ever hashes. `omarchy-7cc6a55` also has `shell/Ui/OverlayWindow.qml`, the
shared window four of its overlays are drawn in. 4.0.4 has no such file.

The tests copy a tree into a sandbox before touching it. Nothing here is
loaded by the shell: Omarchy looks for a plugin's `manifest.json` one level
below `~/.config/omarchy/plugins`, and these are several levels further down.
