# Fliparchy

Tablet mode for convertible laptops running [Omarchy](https://github.com/omacom/omarchy) 4.

Fold the screen back and Fliparchy switches your desktop into a touch-friendly
mode: the screen rotates with the device, an on-screen keyboard themed like the
rest of Omarchy is one tap away, and the things that normally need a keyboard
shortcut or a mouse (moving windows between tiles, closing them, typing into
the Omarchy menu) work by touch. Fold it back and everything returns to normal.

## Features

- **Follows the hinge.** Fliparchy reads the hardware tablet-mode switch, so
  tablet features appear only while folded. The switch is auto-detected
  whichever driver provides it.
- **Auto-rotation with a lock.** Screen and touch input rotate with the device
  (via `iio-sensor-proxy`). A bar button locks the orientation; the lock is
  remembered, and released automatically when you fold back to laptop mode.
- **An on-screen keyboard that fits Omarchy.** [Squeekboard](https://gitlab.gnome.org/World/Phosh/squeekboard),
  styled from your current Omarchy theme's colours and font, restyled
  automatically when you switch themes.
- **The keys a desktop needs.** Every keyboard layout gets a slim extra row with
  Esc, Tab, Ctrl, Alt, Super, Shift and arrow keys, without making the keyboard
  taller. The modifiers are toggles: tap Super, tap Return, tap Super again to
  open a terminal. Your Hyprland SUPER shortcuts work from it.
- **Window shortcuts panel.** Omarchy windows have no title bars and moving or
  resizing them needs SUPER plus a mouse, so a bar button opens a touch panel
  for focus, swap, close, fullscreen, float, split, pop out, resize, move to
  workspace 1–5, scratchpad and window cycling. Each button runs the same
  action as Omarchy's own keybinding.
- **Type into Omarchy's overlays by touch, if you want to.** The Omarchy menu,
  emoji picker, clipboard picker and polkit password prompt normally close when
  you tap the on-screen keyboard. Fliparchy can fix that in tablet mode, bring
  the keyboard up with them, and keep them clear of it. It's off until you turn
  it on, one overlay at a time (see [Omarchy's overlays](#omarchys-overlays)).
- **Settings in the Omarchy menu,** under Setup › Tablet.

## Requirements

- Omarchy 4 (Hyprland 0.56+, the Omarchy shell).
- A convertible whose kernel driver reports a tablet-mode switch
  (`lenovo-ymc`, `intel-vbtn`, `intel-hid`, `asus-wmi`, `hp-wmi`,
  `thinkpad_acpi` and others), and an accelerometer for rotation.
- Packages, all from the official repositories: `squeekboard`, `evtest`,
  `iio-sensor-proxy`, `python-yaml`, `python-gobject` and `git`. Omarchy's `fcitx5` is used to notice
  text fields (see [Using it](#using-it)).
- Read access to the tablet-mode switch. If you don't have it, the installer
  offers to fix it (see [Tablet-mode detection](#tablet-mode-detection)).

## Tested hardware — feedback wanted

Fliparchy has so far been tested on one machine:

| Device | Tablet-mode driver | Status |
| --- | --- | --- |
| Lenovo 300w Yoga Gen 4 | `lenovo-ymc` | Works |

Nothing in Fliparchy is written for that model: the tablet-mode switch is
auto-detected, and rotation comes from the standard accelerometer stack. It
should work on other convertibles whose kernel reports the switch, but that's
untested. **If you have a convertible or detachable we haven't listed, please
try it and open an issue**, whether it works or not. It helps to include:

- your device model,
- the installer's "Looking for a tablet-mode switch" output,
- whether folding shows and hides the bar icons,
- whether the screen and touch input rotate the right way round,
- anything that didn't work, and what you expected.

Reports for detachables (tablets with a keyboard cover) are especially
welcome, since some signal the keyboard being detached differently.

## Install

```bash
omarchy plugin add <repository-url>
~/.config/omarchy/plugins/sclemance.fliparchy/install.sh
```

Or clone it anywhere and run `./install.sh`; it links the checkout into
Omarchy's plugin folder.

If you enable Fliparchy without running the installer, or something it set up
goes missing later, Fliparchy shows a "Fliparchy needs setup" notification
after the shell starts. Click it to run the installer in a terminal.

The installer can be re-run safely. Options:

| Option | Effect |
| --- | --- |
| `--no-restart` | Don't restart the Omarchy shell at the end. |

### What the installer changes

Fliparchy keeps as much as possible inside its own folder, but a few things
have to live elsewhere. The installer:

1. Links the plugin into `~/.config/omarchy/plugins/` and adds it to the bar.
2. Adds one `@import` line to `~/.config/gtk-3.0/gtk.css` for the keyboard's
   theme. It only matches squeekboard's own widgets, so no other app is
   affected.
3. Adds one line to `~/.config/hypr/input.lua` so Hyprland matches keys from
   squeekboard's virtual keyboard by symbol (`resolve_binds_by_sym`). Without
   it, SUPER shortcuts typed on the on-screen keyboard do nothing.
4. Generates keyboard layouts into `~/.local/state/fliparchy/keyboards` (see
   [Licensing](#credits-and-licensing)).
5. Adds Fliparchy's settings to the Omarchy menu, as a marked block at the
   top of `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
6. Adds a hook to `~/.config/omarchy/hooks/post-update.d/` that regenerates
   the layouts after `omarchy update`.
7. Only if you can't read the tablet-mode switch, and only after asking:
   installs a udev rule, asking for your password (see [Tablet-mode detection](#tablet-mode-detection)).

Each of these is undone by the uninstaller. The installer doesn't touch
Omarchy's overlays; that's up to you (below).

## Using it

In tablet mode, two icons appear in the bar:

| Icon | Does |
| --- | --- |
| Grid | Opens the window shortcuts panel. |
| Padlock | Locks or unlocks rotation. Highlighted while locked, and stays in the bar while locked, even in laptop mode. |

A slim handle, coloured like the bar, runs along the bottom of the screen in
tablet mode. Tap it to show the keyboard (it shows a wide ^) and tap it again
to hide it (a wide v). It reserves its own space, so windows never sit under
it; with the bar at the bottom, the handle sits just above the bar.

The keyboard also comes up on its own when you tap into a text field, or
switch to a window that takes typing, like a terminal. Fliparchy learns about
this from fcitx5, the input method Omarchy already runs, by registering as its
on-screen keyboard while in tablet mode. It doesn't hide the keyboard when you
leave a text field: fcitx5's "hide" also fires on every keystroke from the
on-screen keyboard, so the two can't be told apart. Use the handle.
Apps that don't talk to an input method (some Electron and Chromium apps)
won't bring it up.

If you've turned on touch typing for them, the keyboard also comes up on its own
when you open the Omarchy menu, the emoji or clipboard picker, or a password
prompt, and goes away when you close it.

## Omarchy's overlays

Omarchy's menu, pickers and polkit prompt are full-screen surfaces that take
*exclusive* keyboard focus, and Hyprland sends every touch to such a surface
before checking anything stacked above it. So a tap on the on-screen keyboard
lands on the overlay and closes it. This can't be fixed from the keyboard's
side.

Fliparchy can replace them with clones (made with Omarchy's own
`omarchy plugin clone`) that change two lines, and only in tablet mode: they
take focus *on demand*, which still gets focus when they open and still
receives typed keys, and they respect the keyboard's reserved space so they
sit above it. In laptop mode they behave exactly as shipped; on-demand focus
there could let a window under the mouse on another monitor take focus away.

Replacing part of Omarchy is your call, so each clone is off until you turn it
on. In the Omarchy menu, go to **Setup › Tablet › System Overlays** and
tap an overlay to turn it on or off (✓ means on). The shell restarts to load
the change. From a terminal, the same thing is:

```bash
./fliparchy overlay toggle menu        # or: enable, disable; menu, emojis, clipboard, polkit
./fliparchy overlay status             # which are on, and in sync with Omarchy?
```

What turning one on means:

- **It stops getting Omarchy's fixes directly.** A clone is a copy, so once it's
  on, Omarchy's updates to the original don't reach it by themselves. A hook
  re-clones it after every `omarchy update`, but refuses to replace a clone
  you've edited yourself, and tells you so.
- **In tablet mode it doesn't hold the keyboard to itself.** That's the fix,
  but it also means another window could take keyboard focus while the overlay
  is open, for example one under the mouse on a second monitor, and receive
  what you type.
- **The password prompt matters most.** Its clone keeps its authentication role
  (Omarchy passes a clone its original's capabilities), but its code then lives
  in your user-writable config instead of the root-owned system folder, and the
  point above applies to your password. Anything running as you could already
  interfere with your session in other ways, but it's the one to think about
  before turning on.

## Settings

Fliparchy's settings are in the Omarchy menu under **Setup › Tablet**:

| Setting | Default | Where |
| --- | --- | --- |
| Touch typing in each overlay | off | Setup › Tablet › System Overlays (see [Omarchy's overlays](#omarchys-overlays)) |

A couple more live in Fliparchy's bar entry in `~/.config/omarchy/shell.json`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `tabletSwitchDevice` | blank | Input device to read the tablet-mode switch from. Blank means auto-detect. |
| `rotationLocked` | `false` | Saved by the padlock button. |

## Tablet-mode detection

Fliparchy picks the input device that advertises the standard tablet-mode
switch (`SW_TABLET_MODE`) and polls it once a second. If none exists yet, it
keeps looking every 10 seconds, which covers keyboards that attach later.

If tablet mode is never detected:

- Check the installer's "Looking for a tablet-mode switch" output. No device
  means your driver doesn't report the switch; setting `tabletSwitchDevice`
  won't help then.
- A device that isn't readable is usually owned by the `input` group. Rather
  than joining that group, which would let any program you run read every
  keyboard, the installer offers to install
  `/etc/udev/rules.d/70-fliparchy-tablet-switch.rules`:

  ```
  SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", ENV{ID_INPUT_KEY}!="1", TAG+="uaccess"
  ```

  It gives the user logged in at the machine read access to switch devices
  only (tablet mode, lid, headphone jack), never keyboards, and takes effect
  without logging out. The uninstaller removes it.
- Rotation is separate: it needs `iio-sensor-proxy` to see your accelerometer
  with the right orientation, which is handled by your distribution's hardware
  database, not Fliparchy.

## Troubleshooting

- **Changes to Fliparchy's code don't take effect.** Run
  `omarchy-restart-shell`. Omarchy's plugin reload (`omarchy-shell shell
  rescanPlugins`) can keep running previously compiled code.
- **The bar icons are missing.** Look for a load error:
  `quickshell log -r '*=true' /run/user/$UID/quickshell/by-pid/$(pgrep -f 'quickshell.*omarchy/shell')/log.qslog | grep 'sclemance.fliparchy failed'`
- **The extra keyboard row is missing after a squeekboard upgrade.** Run
  `./squeekboard-layouts.py`. The post-update hook normally does this.
- **SUPER shortcuts don't work from the on-screen keyboard.** Check the
  `resolve_binds_by_sym` line is in `~/.config/hypr/input.lua`, then
  `hyprctl reload`.

## Uninstall

```bash
./install.sh uninstall
```

This removes any overlay clones you turned on, Fliparchy's rows in the
Omarchy menu, the config lines and hooks the installer added, the generated files, and the plugin itself (or unlinks it, if it was
linked from a checkout).

## Credits and licensing

- The on-demand focus fix for Omarchy's overlays follows
  [Gimbal](https://github.com/mechanicsunlocked/gimbal) (MIT), a tablet mode
  for the Framework Laptop 12.
- Squeekboard's keyboard layouts are GPL-3.0-or-later. Fliparchy doesn't ship
  modified copies: `squeekboard-layouts.py` downloads the layouts for your
  installed squeekboard version and adds the extra row locally.
- Clones of Omarchy's overlays are made on your machine from Omarchy's
  MIT-licensed source.
- Fliparchy itself is released under the [MIT License](LICENSE).
