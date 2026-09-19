# Ragtop

Tablet mode for convertible laptops running [Omarchy](https://github.com/omacom/omarchy) 4.

Fold the screen back, like a ragtop's roof, and Ragtop switches your desktop
into a touch-friendly mode: the screen rotates with the device, an on-screen
keyboard themed like the rest of Omarchy is one tap away, and the things that
normally need a keyboard shortcut or a mouse (moving windows between tiles,
closing them, typing into the Omarchy menu) work by touch. Fold it back and
everything returns to normal.

## Features

- **Follows the hinge.** Ragtop reads the hardware tablet-mode switch, so
  tablet features appear only while folded. The switch is auto-detected
  whichever driver provides it.
- **Auto-rotation with a lock.** Screen and touch input rotate with the device
  (via `iio-sensor-proxy`). A bar button locks the orientation; the lock is
  remembered, and released automatically when you fold back to laptop mode.
- **An on-screen keyboard that fits Omarchy.** Drawn by the Omarchy shell in
  your theme's colours and font, and restyled the moment you switch themes. Its
  background can be see-through, matching the bar's transparency by default.
- **The keys a desktop needs.** A slim extra row has Esc, Tab, Ctrl, Alt, Super
  and arrow keys. Modifiers are one-shot: tap Ctrl, then C, for Ctrl+C. Your
  Hyprland SUPER shortcuts work from it: tap Super, then Return, to open a
  terminal.
- **Your layout, any character.** The letter keys follow your active Hyprland
  layout (QWERTZ, AZERTY, Cyrillic, Dvorak…), and characters your layout
  can't type (é on a US layout, emoji) still arrive.
- **Settings one tap away.** A gear key next to the space bar opens Ragtop's
  settings.
- **Window shortcuts panel.** Omarchy windows have no title bars and moving or
  resizing them needs SUPER plus a mouse, so a bar button opens a touch panel
  for focus, swap, close, fullscreen, float, split, pop out, resize, move to
  workspace 1–5, scratchpad and window cycling. Each button runs the same
  action as Omarchy's own keybinding.
- **Type into Omarchy's overlays by touch, if you want to.** The Omarchy menu,
  emoji picker, clipboard picker and polkit password prompt normally close when
  you tap the on-screen keyboard. Ragtop can fix that in tablet mode, bring
  the keyboard up with them, and keep them clear of it. It's off until you turn
  it on, one overlay at a time (see [Omarchy's overlays](#omarchys-overlays)).
- **Unlock without unfolding, if you want to.** The lock screen hides every
  other window, the on-screen keyboard included, so Ragtop can give it a
  keyboard of its own in tablet mode. Also off until you turn it on.
- **Settings in the Omarchy menu,** under Setup › Tablet.

## Requirements

- Omarchy 4 (Hyprland 0.56+, the Omarchy shell).
- A convertible whose kernel driver reports a tablet-mode switch
  (`lenovo-ymc`, `intel-vbtn`, `intel-hid`, `asus-wmi`, `hp-wmi`,
  `thinkpad_acpi` and others), and an accelerometer for rotation.
- Two packages Omarchy doesn't install, both from the official repositories:
  `iio-sensor-proxy` (rotation) and `python-pywayland` (the keyboard). Ragtop
  also uses `python-gobject`, `git` and `fcitx5`, which come with Omarchy;
  fcitx5 is how it notices text fields (see [Using it](#using-it)).
- Read access to the tablet-mode switch. If you don't have it, the installer
  offers to fix it (see [Tablet-mode detection](#tablet-mode-detection)).

## Tested hardware — feedback wanted

Ragtop has so far been tested on one machine:

| Device | Tablet-mode driver | Status |
| --- | --- | --- |
| Lenovo 300w Yoga Gen 4 | `lenovo-ymc` | Works |

Nothing in Ragtop is written for that model: the tablet-mode switch is
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
~/.config/omarchy/plugins/sclemance.ragtop/install.sh
```

Or clone it anywhere and run `./install.sh`; it links the checkout into
Omarchy's plugin folder.

If you enable Ragtop without running the installer, or something it set up
goes missing later, Ragtop shows a "Ragtop needs setup" notification
after the shell starts. Click it to run the installer in a terminal.

The installer can be re-run safely. Options:

| Option | Effect |
| --- | --- |
| `--no-restart` | Don't restart the Omarchy shell at the end. |

### What the installer changes

Ragtop keeps as much as possible inside its own folder, but a few things
have to live elsewhere. The installer:

1. Links the plugin into `~/.config/omarchy/plugins/` and adds it to the bar.
2. Adds Ragtop's settings to the Omarchy menu, as a marked block at the
   top of `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
3. Only if you can't read the tablet-mode switch, and only after asking:
   installs a udev rule, asking for your password (see [Tablet-mode detection](#tablet-mode-detection)).

Each of these is undone by the uninstaller. The installer doesn't touch
Omarchy's overlays; that's up to you (below). While running, Ragtop keeps
generated files in `~/.local/state/ragtop` and its settings in
`~/.config/ragtop`.

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
switch to a window that takes typing, like a terminal. Ragtop learns about
this from fcitx5, the input method Omarchy already runs, by registering as its
on-screen keyboard while in tablet mode. It doesn't hide the keyboard when you
leave a text field: fcitx5's "hide" also fires on every keystroke from the
on-screen keyboard, so the two can't be told apart. Use the handle.
Apps that don't talk to an input method (some Electron and Chromium apps)
won't bring it up. To turn this off, tap **Setup › Tablet › Auto Keyboard** in
the Omarchy menu.

If you've turned on touch typing for them, the keyboard also comes up on its own
when you open the Omarchy menu, the emoji or clipboard picker, or a password
prompt, and goes away when you close it.

## The keyboard

Ragtop's keyboard is drawn by the Omarchy shell, so it follows your theme's
colours and font, and the Transparency setting, without restarting. It has:

- **An extra row** of Esc, Tab, Ctrl, Alt, Super and the arrow keys. Held
  arrows and Backspace repeat.
- **One-shot modifiers:** tap Ctrl, then C, for Ctrl+C; the Ctrl turns off by
  itself. Tap a modifier twice to lock it on. Or pick Sticky under
  Setup › Tablet › Modifier Keys to have them stay on until tapped again.
- **Your layout's letters:** the letter keys follow the active Hyprland
  layout, and the space bar shows its name.
- **Any character** your layout can't type still arrives, and every key types
  what it shows whatever your Hyprland layout is.
- A settings key that opens Setup › Tablet directly.

`keyboard-helper.py` sends the keys: it registers a Wayland virtual keyboard
with the same keymap as your physical keyboard, which is also why your SUPER
shortcuts work from it. For keybindings or scripts:

```bash
omarchy-shell ragtop toggleKeyboard    # also showKeyboard, hideKeyboard
```

## Omarchy's overlays

Omarchy's menu, pickers and polkit prompt are full-screen surfaces that take
*exclusive* keyboard focus, and Hyprland sends every touch to such a surface
before checking anything stacked above it. So a tap on the on-screen keyboard
lands on the overlay and closes it. This can't be fixed from the keyboard's
side.

Ragtop can replace them with clones (made with Omarchy's own
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
./ragtop overlay toggle menu        # or: enable, disable; menu, emojis, clipboard, polkit, lock
./ragtop overlay status             # which are on, and in sync with Omarchy?
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

### The lock screen

The lock screen is different: while it's up, Hyprland shows nothing else at
all, so no on-screen keyboard can appear over it. Its clone (**Lock Screen**
in the same menu) keeps Omarchy's lock screen as it is and adds a keyboard of
its own along the bottom, in tablet mode only: letters with Shift (tap twice
for Caps), and two pages of digits and symbols. The keys edit the password the
same way typing does, and Omarchy checks it as usual. The keyboard itself is
`LockKeyboard.qml` in Ragtop's folder, which the clone loads.

The screen doesn't rotate while it's locked, with or without this: Omarchy's
lock screen isn't redrawn for a rotated display, although touches would be
rotated, so taps would land in the wrong place. The lock screen keeps the
orientation it was locked in, and the screen catches up when you unlock.

The same points apply as for the password prompt, since this is where you type
your login password: the clone and the keyboard live in your user-writable
config. Keys light up when tapped, as on any on-screen keyboard, so mind who's
watching. Try it the first time with the laptop unfolded and Tablet Mode set to
Always On, so the physical keyboard is there if anything goes wrong.

## Settings

Ragtop's settings are in the Omarchy menu under **Setup › Tablet**, which
the gear key on the on-screen keyboard opens directly:

| Setting | Default | Where |
| --- | --- | --- |
| Tablet mode: Automatic (follow the hinge), Always On or Always Off | Automatic | Setup › Tablet › Tablet Mode |
| Keyboard modifiers: One-Shot (next key only; tap twice to lock) or Sticky (until tapped again) | One-Shot | Setup › Tablet › Modifier Keys |
| Keyboard comes up on text fields | on | Setup › Tablet › Auto Keyboard |
| Keyboard background transparency: Match Bar, or Opaque, Low, Medium, High or Full to override it | Match Bar | Setup › Tablet › Transparency |
| Touch typing in each overlay, and the lock screen's keyboard | off | Setup › Tablet › System Overlays (see [Omarchy's overlays](#omarchys-overlays)) |

Match Bar follows Style › Bar › Transparency: a solid bar gives a solid
keyboard background, a transparent bar a fully clear one. The keys themselves
always stay solid. The handle along the bottom follows the bar the same way.

From a terminal, `./ragtop <setting> ...` does the same as the menu rows:
`tablet-mode set auto|on|off`, `auto-show toggle` (or `enable`, `disable`),
`modifiers set oneshot|sticky` and
`transparency set auto|opaque|low|medium|high|full`. Settings other than the
overlays are kept in
`~/.config/ragtop/settings.conf`, and changes apply straight away.

A couple more live in Ragtop's bar entry in `~/.config/omarchy/shell.json`:

| Setting | Default | Meaning |
| --- | --- | --- |
| `tabletSwitchDevice` | blank | Input device to read the tablet-mode switch from. Blank means auto-detect. |
| `rotationLocked` | `false` | Saved by the padlock button. |

## Tablet-mode detection

Ragtop picks the input device that advertises the standard tablet-mode
switch (`SW_TABLET_MODE`) and watches it, so a fold registers immediately.
If none exists yet, it
keeps looking every 10 seconds, which covers keyboards that attach later.

If your device has no usable switch, or you want the touch controls with the
keyboard attached, set **Setup › Tablet › Tablet Mode** to **Always On**.
Always On and Always Off stop Ragtop reading the switch at all.

If tablet mode is never detected:

- Check the installer's "Looking for a tablet-mode switch" output. No device
  means your driver doesn't report the switch; setting `tabletSwitchDevice`
  won't help then.
- A device that isn't readable is usually owned by the `input` group. Rather
  than joining that group, which would let any program you run read every
  keyboard, the installer offers to install
  `/etc/udev/rules.d/70-ragtop-tablet-switch.rules`:

  ```
  SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", ENV{ID_INPUT_KEY}!="1", TAG+="uaccess"
  ```

  It gives the user logged in at the machine read access to switch devices
  only (tablet mode, lid, headphone jack), never keyboards, and takes effect
  without logging out. The uninstaller removes it.
- Rotation is separate: it needs `iio-sensor-proxy` to see your accelerometer
  with the right orientation, which is handled by your distribution's hardware
  database, not Ragtop.

## Troubleshooting

- **Changes to Ragtop's code don't take effect.** Run
  `omarchy-restart-shell`. Omarchy's plugin reload (`omarchy-shell shell
  rescanPlugins`) can keep running previously compiled code.
- **The bar icons are missing.** Look for a load error:
  `quickshell log -r '*=true' /run/user/$UID/quickshell/by-pid/$(pgrep -f 'quickshell.*omarchy/shell')/log.qslog | grep 'sclemance.ragtop failed'`
- **The keyboard doesn't type.** Check that `python-pywayland` is installed:
  the setup notification says so if it isn't.

## Uninstall

```bash
./install.sh uninstall
```

This removes any overlay clones you turned on, Ragtop's rows in the Omarchy
menu, the switch access rule, Ragtop's settings and generated files, and the
plugin itself (or unlinks it, if it was linked from a checkout).

## Credits and licensing

- The on-demand focus fix for Omarchy's overlays follows
  [Gimbal](https://github.com/mechanicsunlocked/gimbal) (MIT), a tablet mode
  for the Framework Laptop 12.
- `protocols/virtual-keyboard-unstable-v1.xml` is the Wayland virtual keyboard
  protocol (MIT). Its Python bindings are generated on your machine on first run.
- Clones of Omarchy's overlays are made on your machine from Omarchy's
  MIT-licensed source.
- Ragtop itself is released under the [MIT License](LICENSE).
