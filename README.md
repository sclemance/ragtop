# Ragtop

**Made for convertibles, works for tablets, built for Omarchy.**

Fold the screen back, like a ragtop's roof — or take the keyboard off, which
the hardware reports the same way — and Ragtop switches your
[Omarchy 4](https://github.com/omacom/omarchy) desktop into a touch-friendly
mode: the screen rotates with the device, an on-screen keyboard themed like
the rest of Omarchy is one tap away, and the things that normally need a
keyboard shortcut or a mouse (moving windows between tiles, closing them,
typing into the Omarchy menu) work by touch. Put it back and everything
returns to normal.

## How it looks

The keyboard takes its colours from your Omarchy theme and its letters from
your Hyprland layout, so it matches whatever you already run. The look is
yours to change (see [Presets](#presets)).

| | | |
| --- | --- | --- |
| ![Glass preset on Tokyo Night, German layout](screenshots/glass-tokyo-night.jpg) | ![Typewriter preset on Catppuccin Latte, French layout](screenshots/typewriter-catppuccin-latte.jpg) | ![The lock screen's keyboard on Rose Pine](screenshots/lock-screen-rose-pine.jpg) |
| **Glass** on Tokyo Night — see-through keys over a blurred desktop, QWERTZ | **Typewriter** on Catppuccin Latte — raised keycaps, AZERTY with its short bottom row filled out | **The lock screen's own keyboard**, in the lock screen's palette |

Held upright, the same keyboard fills the width it is given:

| | |
| --- | --- |
| ![Holding a letter for its accents](screenshots/portrait-accents-osaka-jade.jpg) | ![The nav strip under the background picker](screenshots/portrait-picker-nav.jpg) |
| Hold a letter for its accents — the only way to reach é on some layouts | Choosing a background by touch, with the picker's own strip |

## Which tablets?

A convertible is a convertible whether its keyboard folds away or comes off.
Both report the same thing — a kernel tablet-mode switch — and Ragtop follows
either without knowing which it is looking at. That is now two machines: a
hinge that folds, and a slate that detaches.

| Kind | How it goes | |
| --- | --- | --- |
| **Convertible, hinged** — the screen folds back (Lenovo Yoga, HP x360, Dell 2-in-1) | Folding it past the point of no return flips the switch, and Ragtop follows. | Tested — Lenovo 300w Yoga Gen 4 |
| **Convertible, detachable** — the keyboard comes off (Surface-style, ThinkPad X12) | Detaching flips the same switch, so it behaves exactly as a hinge does. Ragtop keeps looking while no switch is there, so attaching a keyboard later is picked up too. | Tested — Surface Book 2 |
| **Slate** — no keyboard at all | Nothing to switch, and nothing needed: set **Tablet Mode › Always On** once and Ragtop stays in tablet mode for good. Setup saying it found no switch is the right answer here, not a fault. | Untested — reports welcome |

The only thing any of this decides is *how Ragtop learns it is in tablet
mode*. Everything after that — rotation, the keyboard, the handle, the
overlays, the lock screen — is the same on all three and needs a touchscreen
and nothing else.

### What it costs to have less

Nothing here is all-or-nothing. Each missing piece takes away exactly one
thing:

| Missing | What stops | What still works |
| --- | --- | --- |
| A tablet-mode switch, or read access to one | Tablet mode switching by itself | Everything, once **Tablet Mode › Always On** is set: the keyboard, rotation, the handle, the overlays |
| An accelerometer, or `iio-sensor-proxy` | The screen following the device; the rotation-lock button has nothing to lock | The keyboard, the handle, tablet mode, the overlays |
| `python-pywayland` | The keyboard sends no keys | Rotation, tablet mode, the shortcuts panel, the picker strip |
| `python-gobject` or fcitx5 | The keyboard coming up on its own at a text field | Bringing it up from the handle, and everything else |
| A touchscreen | Touch, obviously — but the keys, the handle and the panels all take a mouse | Rotation and tablet-mode switching, which is most of what a non-touch convertible wants |

A plain laptop with none of the above is not a failure case either: Ragtop
stays out of the way, the bar icons never appear, and nothing reserves screen
space until tablet mode turns on.

## Features

- **Follows the hardware.** Ragtop reads the tablet-mode switch, so tablet
  features appear when you fold the screen back — or when you take the
  keyboard off, which a detachable reports the same way. The switch is
  auto-detected whichever driver provides it.
- **Auto-rotation with a lock.** Screen and touch input rotate with the device
  (via `iio-sensor-proxy`). A bar button locks the orientation; the lock is
  remembered, and released automatically on the way back to laptop mode.
- **An on-screen keyboard that fits Omarchy.** Drawn by the Omarchy shell in
  your theme's colours and font, and restyled the moment you switch themes. Its
  background can be see-through, matching the bar's transparency by default.
- **The keys a desktop needs.** A slim extra row has Esc, Tab, Ctrl, Alt, Super
  and arrow keys. Modifiers are one-shot: tap Ctrl, then C, for Ctrl+C. Your
  Hyprland SUPER shortcuts work from it: tap Super, then Return, to open a
  terminal.
- **Your layout, any character.** The letter keys and the symbol pages follow
  your active Hyprland layout (QWERTZ, AZERTY, Cyrillic, Dvorak…), accents
  are a long press away, and characters your layout can't type (é on a US
  layout, emoji) still arrive.
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
- **Unlock without putting it back together, if you want to.** The lock screen hides every
  other window, the on-screen keyboard included, so Ragtop can give it a
  keyboard of its own in tablet mode. Also off until you turn it on.
- **Settings in the Omarchy menu,** under Setup › Tablet.

## Requirements

Only one thing is actually required: **Omarchy 4** (Hyprland 0.56+, the
Omarchy shell). Everything else buys a piece of Ragtop, and Ragtop runs
without any of it — it just does less, and the setup steps say which less.

| For | You need | Without it |
| --- | --- | --- |
| The on-screen keyboard | `python-pywayland` (official repositories) | No keys are sent; everything else still works |
| Rotation following the device | `iio-sensor-proxy` (official repositories), and an accelerometer | The screen stays where it is; rotation lock is moot |
| The keyboard coming up on text fields | `python-gobject`, and fcitx5 (which Omarchy ships) | Bring it up yourself with the handle |
| **Automatic** tablet mode | A kernel driver that reports a tablet-mode switch (`lenovo-ymc`, `intel-vbtn`, `intel-hid`, `asus-wmi`, `hp-wmi`, `thinkpad_acpi`…), and read access to it | Set **Tablet Mode › Always On** and Ragtop stays in tablet mode — which is the right answer on a slate anyway |
| Touch typing in Omarchy's overlays | `git`, to copy them | They behave as they ship |

Read access to the switch is a udev rule the setup offers to install, with
your password, through Omarchy's own prompt (see
[Tablet-mode detection](#tablet-mode-detection)). It is worth having on a
convertible and pointless on a slate.

## Tested hardware — feedback wanted

Ragtop has been tested on these:

| Device | Shape | Status |
| --- | --- | --- |
| Lenovo 300w Yoga Gen 4 | Convertible | Works. Folding switches modes, rotation follows the device |
| Microsoft Surface Book 2 | Detachable | Tablet mode and rotation work: **detaching the slate turns the keyboard on exactly as folding a hinge does**, reattaching turns it off, and rotation is correct. Touch itself doesn't work on this machine — see below |

Nothing in Ragtop is written for either model: the tablet-mode switch is
auto-detected, and rotation comes from the standard accelerometer stack.

**On a Surface, touch is the machine's problem, not Ragtop's.** Surface
hardware needs the [linux-surface](https://github.com/linux-surface/linux-surface)
kernel and firmware before its touchscreen works at all; a stock kernel gives
you a machine that detaches, rotates and runs Ragtop, with nothing to touch it
with. Worth knowing before you conclude the plugin is broken: check whether a
touch device exists at all with `hyprctl devices | grep -i touch`. **If you have a machine we haven't listed, please try it and open an issue**,
whether it works or not. Two machines is not a sample. There is a
[hardware report form](https://github.com/sclemance/ragtop/issues/new?template=hardware-report.yml)
that asks for exactly this.

What is most useful to hear about, roughly in order:

1. **Tablet mode.** Does folding or detaching turn it on, and does undoing
   that turn it off? Include what setup printed under "Looking for a
   tablet-mode switch" — and say so if it found none, because a machine with
   no switch is a useful data point too.
2. **Rotation.** Does the screen follow the device, the right way round, and
   do taps land where things are drawn? Getting the picture right but the
   touch rotated is a distinct and interesting failure.
3. **Everything else, in real use.** The keyboard coming up on a text field,
   SUPER shortcuts from it, the handle, the window shortcuts, the lock
   screen, the overlays if you turned any on. Tell us what you were doing,
   not only what broke.

Plus your device model, and anything that didn't work along with what you
expected instead.

Reports for detachables (tablets with a keyboard cover) are especially
welcome, since some signal the keyboard being detached differently.

## Install

```bash
omarchy plugin add https://github.com/sclemance/ragtop.git --enable
```

That is the whole of it: Ragtop notices it hasn't been set up and opens its
setup in the shell, which is where the rest happens.

Two packages come from Arch's own repositories and Ragtop can't install them
for you — the setup names them, and this is the line:

```bash
sudo pacman -S --needed iio-sensor-proxy python-pywayland
```

If you'd rather do it in a terminal, or you're working on a checkout of your
own, `./install.sh` does the same things and links the checkout into Omarchy's
plugin folder. It takes `--yes`, `--no-restart`, `--overlays` and
`--no-overlays` for unattended runs.

### Setup without a terminal

The first time Ragtop runs on a machine nothing has been set up on, it opens
**setup in the shell** instead: a short series of steps that says what it is
about to touch, checks the packages it needs, offers the switch access rule
through Omarchy's own password prompt, and lets you pick which of Omarchy's
overlays to patch — each with a switch, and one that turns them all on.

It writes exactly what `install.sh` writes, through the same scripts, so a
machine set up either way ends up the same. Re-open it any time from
**Setup › Tablet › Run Setup**, or with `./ragtop setup`; it reflects what is
already on the machine, so you can use it to turn overlays on and off later.

The one thing it cannot do is install packages: it names what is missing, says
what each is for, and hands you the `pacman` line. If something Ragtop set up
goes missing later, a "Ragtop needs setup" notification says what, and opens
the same steps.

The installer can be re-run safely. Options:

| Option | Effect |
| --- | --- |
| `--no-restart` | Don't restart the Omarchy shell at the end. |
| `--yes` | Don't ask anything; take the offer. Touch typing in Omarchy's overlays is the exception — it replaces part of Omarchy, so it stays off unless you ask for it. |
| `--no-udev` | Leave the switch access rule alone, installing or removing. |
| `--overlays` | Turn touch typing on in all of [Omarchy's overlays](#omarchys-overlays), without asking. |
| `--no-overlays` | Leave it off, without asking. |

### What the installer changes

Ragtop keeps as much as possible inside its own folder, but a few things
have to live elsewhere. The installer:

1. Links the plugin into `~/.config/omarchy/plugins/` and adds it to the bar.
2. Adds Ragtop's settings to the Omarchy menu, as a marked block at the
   top of `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
3. Only if you can't read the tablet-mode switch, and only after asking:
   installs a udev rule, asking for your password through Omarchy's polkit
   prompt (see [Tablet-mode detection](#tablet-mode-detection)). The rule and
   everything that runs as root live in `udev-rule.sh`.
4. Offers, once and answering No by default, to turn on touch typing in all of
   [Omarchy's overlays](#omarchys-overlays) — its menu, pickers, password
   prompt and lock screen. Say no and nothing of Omarchy's is replaced; you
   can turn them on one at a time later.

Each of these is undone by the uninstaller, which removes the overlay clones
whether the installer or the menu turned them on. While running, Ragtop keeps
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
it; with the bar at the bottom, the handle sits just above the bar. While the
keyboard is open, the handle fades to the keyboard's background, so the two
read as one panel.

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

**Tapping the screen ends the screensaver.** Omarchy's screensaver is a
fullscreen terminal that quits when it reads a key, which a touchscreen never
sends it, so folded up there was no way to dismiss it but to open the laptop
and press a key. In tablet mode Ragtop covers it with a transparent catcher
and turns a tap into that key press. It's specific to Omarchy's own
screensaver (the `org.omarchy.screensaver` window), and only to one that
starts while the shell is running.

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
- **Hold a letter for its accents:** e gives é è ê ë, c gives ç, s gives ß.
  Slide onto the one you want and let go; let go where you started for the
  plain letter, or slide off the popup to take nothing. The letters your own
  layout carries come first — on AZERTY, which keeps é, è, ç and à on its
  number row where the letter rows can't reach them, this is the only way to
  type them.
- **Your layout's symbols:** the two symbol pages carry the same punctuation
  whatever you type in, and pick up what your layout adds on top — § and ° on
  a German keyboard, ¡ and ¿ on a Spanish one, № and ₽ on a Russian one, ₹ on
  an Indian one. Up to four go in the free slots on the pages' third rows; a
  US layout adds nothing, so its pages look exactly as they always did.
- **Any character** your layout can't type still arrives, and every key types
  what it shows whatever your Hyprland layout is.
- A settings key that opens Setup › Tablet directly.

`keyboard-helper.py` sends the keys: it registers a Wayland virtual keyboard
with the same keymap as your physical keyboard, which is also why your SUPER
shortcuts work from it. For keybindings or scripts:

```bash
omarchy-shell ragtop toggleKeyboard    # also showKeyboard, hideKeyboard
```

### The keyboard's look

Ragtop follows your Omarchy theme: colours, type scale, spacing and borders
all come from the theme's own tokens, so switching themes restyles the
keyboard with it. The settings only say *how* to use them, and each one is a
row in the Omarchy menu under **Setup › Tablet**:

| Row | Choices |
| --- | --- |
| Preset | A saved look; picking one writes the rows below |
| Key Shape | Omarchy (the theme's own corner rounding), Rounded, Pill, Angular |
| Key Relief | Flat, or Raised: the key stands on a side, like a keycap |
| Key Fill | Dark or Light (an opaque key sitting darker or lighter than the keyboard), Automatic (whichever of those your theme has room for — a dark theme has little below its background, a light one little above it, so a fixed choice reads strongly on some themes and barely at all on others), or Outline (no fill, carried by its edge) |
| Key Size | Compact, Normal, Large — the labels scale with the keys |
| Key Transparency | Opaque, Low, Medium, High, Full. What shows through is the keyboard's background, so the desktop only shows if that's see-through too |
| Background | Tint or Gradient |
| BG Transparency | The keyboard's background: Match Bar, Opaque, Low, Medium, High, Full |
| Edge | Border, Fade or None, for the keyboard's top edge |

Whatever a key looks like, a touch goes to the nearest key, so no shape
makes keys harder to hit.

**Edge** sets how the keyboard's top edge meets the desktop. Border gives it
the same border your tiled windows have, taken from the Omarchy theme itself
(the shell's own active-window border spec), so it follows a theme switch
live, gradients included. Fade fades the background out over `edge-fade`
pixels. None leaves a hard edge.

### Presets

A preset is a small JSON file of those same settings, never code. Applying
one **writes its values into your settings**, so afterwards every menu row
shows what the keyboard is actually doing — a preset is a starting point,
not a layer that overrides you.

Ragtop's are in `presets/` (Omarchy, Soft, Typewriter, Glass); put your own
in `~/.config/ragtop/presets/<name>.json` and apply it from the menu or with
`./ragtop preset apply <name>`:

```json
{
  "name": "Chunky",
  "shape": "rounded",
  "relief": "raised",
  "fill": "light",
  "size": "large",
  "background": "tint",
  "transparency": "opaque",
  "edge": "border",
  "labels": "large",
  "depth": 6
}
```

Besides the menu rows, a preset can set the details that don't deserve one:

| Field | Values | Default |
| --- | --- | --- |
| `labels` | label size on Omarchy's type scale: `small`, `normal`, `large` | `normal` |
| `depth` | Raised keys: how far the key's side shows, 0–10 | 4 |
| `chamfer` | Angular: how much of each corner is cut, 0–20 | 8 |
| `edge-fade` | pixels the background fades over with Edge set to Fade, 0–24 | 8 |
| `blur` | blur what's behind the keyboard (see below) | `false` |

To leave the theme behind for one part of the look, a preset can also set
these outright. Only what you set stops following the theme:

| Field | Values |
| --- | --- |
| `key-color`, `label-color` | a palette role (`foreground`, `background`, `accent`, `urgent`) or a hex colour |
| `key-fill-alpha` | 0–1, how strong the key fill is |
| `border-width` | 0–4 |
| `radius` | corner radius in pixels, 0–30 |

Anything missing, unknown or out of range is ignored, so a stray file can't
break the keyboard. All of this lands in `~/.config/ragtop/settings.conf`,
which you can also edit directly.

**Blur** is Hyprland's, and Omarchy ships with it turned off. A preset with
`"blur": true` turns it on at runtime, for Ragtop's keyboard and its handle
only: Hyprland is told to leave every window unblurred, so your see-through
terminals stay as they are. Turning blur off again restores it, and nothing
is written to your Hyprland config, so `hyprctl reload` clears it either
way. If you have blur on yourself, Ragtop leaves your setup alone and just
blurs behind its keyboard.

The lock screen's keyboard takes the shape, fill and measurements too,
checked again by its own code, but never the colours or the background.

## Omarchy's overlays

Omarchy's menu, pickers and polkit prompt are full-screen surfaces that take
*exclusive* keyboard focus, and Hyprland sends every touch to such a surface
before checking anything stacked above it. So a tap on the on-screen keyboard
lands on the overlay and closes it. This can't be fixed from the keyboard's
side.

The theme and background pickers (both Omarchy's image picker) have the same
problem and one of their own: see [The theme and background pickers](#the-theme-and-background-pickers).

Ragtop can replace them with clones (made with Omarchy's own
`omarchy plugin clone`) that change two lines, and only in tablet mode: they
take focus *on demand*, which still gets focus when they open and still
receives typed keys, and they respect the keyboard's reserved space so they
sit above it. In laptop mode they behave exactly as shipped; on-demand focus
there could let a window under the mouse on another monitor take focus away.

Replacing part of Omarchy is your call, so each clone is off until you turn it
on. The installer offers all of them once, with the trade-off below and No as
the default answer. Afterwards, in the Omarchy menu, go to
**Setup › Tablet › System Overlays** and
tap an overlay to turn it on or off (✓ means on). The shell restarts to load
the change. From a terminal, the same thing is:

```bash
./ragtop overlay toggle menu        # or: enable, disable; menu, emojis, clipboard,
                                    # polkit, image-picker, lock
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

### The theme and background pickers

Both are Omarchy's image picker (**Image Picker** in the same menu), and it
isn't a keyboard problem: it shows a carousel of previews, and the keyboard
covers the very preview you're choosing by. So Ragtop keeps the keyboard off
it and, with the clone on, puts the four keys the carousel actually listens
to in a strip along the bottom instead:

```
   [ ◀ ]   [ Select ]   [ ▶ ]      [ Cancel ]
```

◀ and ▶ step through the images and repeat if you hold them; Select applies
the one in the middle; Cancel closes without changing anything. The strip is
drawn from the keyboard's own theme and reserves its space, so the carousel
sits above it. The keyboard handle stays, so you can still bring the keyboard
up to type a filter where the picker takes one.

Without the clone Ragtop can only get out of the way: a stock picker takes
every touch on the screen, so the strip's own taps would never reach it, and
even a tap on the keyboard would land on the picker and throw it away. So
whether or not you turn the clone on, while a picker is open the keyboard
stays down and the handle goes with it, leaving the carousel's own slices to
tap: tap one to select it, tap the middle one again to apply.

One cost specific to this clone: Omarchy warms the picker's thumbnails
through an IPC call that names the built-in plugin directly, so with any
clone in place that warm-up does nothing and the first open is slower. The
picker itself opens, works and closes normally.

### The lock screen

The lock screen is different: while it's up, Hyprland shows nothing else at
all, so no on-screen keyboard can appear over it. Its clone (**Lock Screen**
in the same menu) keeps Omarchy's lock screen as it is and adds a keyboard of
its own along the bottom, in tablet mode only: your layout's letters with
Shift (tap twice for Caps), and two pages of digits and symbols, which pick
up your layout's own symbols the same way the desktop keyboard's do. Holding
a letter offers its accents there too — a password is typed in characters,
and on some layouts é or ß is only reachable that way. Its popup sits on a card of
its own, opaque whatever your Key Transparency setting is, so the letter you
are picking stays legible against the keys it covers. The keys edit
the password the same way typing does, and Omarchy checks it as usual. The
keyboard itself is `LockKeyboard.qml` in Ragtop's folder, which the clone
loads.

It's shaped like the desktop keyboard but drawn in the lock screen's own
colours, and it's deliberately a separate, self-contained file: it shares no
code with the desktop keyboard, sends no key events and has no Ctrl, Alt or
Super, so nothing added to the desktop keyboard reaches the lock screen by
accident, and there's one short file to review. It learns your layout's letters
and symbols from `$XDG_RUNTIME_DIR/ragtop-layout.json`, which Ragtop's service
writes, and falls back to US if that's missing or malformed. What it takes
from there is data, never code, and it re-checks all of it by its own rules:
a symbol has to be one printable character or it's dropped.

The screen doesn't rotate while it's locked, with or without this: Omarchy's
lock screen isn't redrawn for a rotated display, although touches would be
rotated, so taps would land in the wrong place. The lock screen keeps the
orientation it was locked in, and the screen catches up when you unlock.

The same points apply as for the password prompt, since this is where you type
your login password: the clone and the keyboard live in your user-writable
config. Keys light up when tapped, as on any on-screen keyboard, so mind who's
watching. Try it the first time in laptop mode with Tablet Mode set to
Always On, so the physical keyboard is there if anything goes wrong.

## Settings

Ragtop's settings are in the Omarchy menu under **Setup › Tablet**, which
the gear key on the on-screen keyboard opens directly:

| Setting | Default | Where |
| --- | --- | --- |
| Tablet mode: Automatic (follow the hardware — folding or detaching), Always On or Always Off | Automatic | Setup › Tablet › Tablet Mode |
| Keyboard modifiers: One-Shot (next key only; tap twice to lock) or Sticky (until tapped again) | One-Shot | Setup › Tablet › Modifier Keys |
| Keyboard comes up on text fields | on | Setup › Tablet › Auto Keyboard |
| A saved look, which writes the rows below (see [Presets](#presets)) | Omarchy | Setup › Tablet › Preset |
| Key shape: Omarchy, Rounded, Pill or Angular | Omarchy | Setup › Tablet › Key Shape |
| Key relief: Flat or Raised | Flat | Setup › Tablet › Key Relief |
| Keys: Automatic (whichever way your theme has room for), Dark, Light or Outline | Light | Setup › Tablet › Key Fill |
| Key size: Compact, Normal or Large | Normal | Setup › Tablet › Key Size |
| Keyboard background: Tint or Gradient | Tint | Setup › Tablet › Background |
| Keyboard top edge: Border (your Hyprland window border), Fade or None | None | Setup › Tablet › Edge |
| Keyboard background transparency: Match Bar, or Opaque, Low, Medium, High or Full to override it | Match Bar | Setup › Tablet › BG Transparency |
| Key transparency: Opaque, Low, Medium, High or Full | Opaque | Setup › Tablet › Key Transparency |
| Touch typing in each overlay, the picker nav strip, and the lock screen's keyboard | off | Setup › Tablet › System Overlays (see [Omarchy's overlays](#omarchys-overlays)) |

Match Bar follows Style › Bar › Transparency: a solid bar gives a solid
keyboard background, a transparent bar a fully clear one. The keys themselves
always stay solid. The handle along the bottom follows the bar the same way
while the keyboard is closed, and the keyboard while it's open.

From a terminal, `./ragtop <setting> ...` does the same as the menu rows:
`tablet-mode set auto|on|off`, `auto-show toggle` (or `enable`, `disable`),
`modifiers set oneshot|sticky`, `background set tint|gradient`, `edge set border|fade|none`,
`shape set omarchy|rounded|pill|angular`, `relief set flat|raised`,
`fill set dark|light|outline`, `key-transparency set opaque|low|medium|high|full`,
`size set compact|normal|large`, `preset apply <name>` (`preset list` shows
them) and
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

## Language

Ragtop is English-only, and so is Omarchy: the shell has no translation layer
yet, and the proposals for one are still open. That's worth fixing one day —
in 2026 localization isn't as hard as it used to be, and Linux is for
everyone, not just English speakers — so the point for now is to not get in
the way of it. [LOCALIZATION.md](LOCALIZATION.md)
records where that stands, which of Ragtop's strings are prose and which are
protocol that must never be translated, and what would change here once a
standard settles.

The keyboard itself is mostly language-agnostic already — its letters, symbols
and accents come from your active Hyprland layout, and its key glyphs are
drawn rather than written.

## Versioning and updates

`omarchy plugin update sclemance.ragtop` fast-forwards this checkout to the
default branch: it shows you the diff first, validates the manifest
afterwards, and rolls back if that fails. There are no release channels —
whatever is on the branch is what you get — so the branch is kept shippable
and every push is, in effect, a release.

The version in `manifest.json` is required — `omarchy plugin validate` refuses
a manifest without one — but Omarchy itself never shows it: not in
`omarchy plugin list`, not in its JSON. So it is here for people, in the
release tags and in bug reports. Ragtop is **in beta**: it runs two machines every day, but the settings are
still moving and it wants strangers to break it. Bugs and hardware reports
are the point of this stage; feature ideas are welcome once it is boring. The version is **0.x while
that is true**,
and says so honestly: the settings file, the `ragtop` command and the rest
are still moving. The first published release is 1.0.0, tagged, and from
then on:

| | |
| --- | --- |
| **patch** | a fix |
| **minor** | a new capability, or a changed default |
| **major** | a break in something you can build a habit or a script on: the keys and values in `settings.conf`, the `ragtop` verbs, the `setup.tablet.*` menu ids, the layer namespaces, the `ragtop` IPC target and its functions, the files in `$XDG_RUNTIME_DIR`, and the installer's flags |

Everything else — the QML, how a key is drawn, what the helper prints to
itself — is Ragtop's own business and can change in a patch.

## Credits and licensing

- The on-demand focus fix for Omarchy's overlays follows
  [Gimbal](https://github.com/mechanicsunlocked/gimbal) (MIT), a tablet mode
  for the Framework Laptop 12.
- `protocols/virtual-keyboard-unstable-v1.xml` is the Wayland virtual keyboard
  protocol (MIT). Its Python bindings are generated on your machine on first run.
- Clones of Omarchy's overlays are made on your machine from Omarchy's
  MIT-licensed source.
- Ragtop itself is released under the [MIT License](LICENSE).
