# Architecture

What Ragtop is made of and how the pieces reach the machine. README.md says
what it does and how to use it. This says how it works.

Written against Omarchy 4.0.0.alpha, Hyprland 0.56.2 and Quickshell 0.3.1.

## Where it runs

Ragtop is an Omarchy plugin, which means it is QML loaded into Omarchy's own
Quickshell process. It is not a program of its own and it has no process of
its own. `manifest.json` declares two entry points:

- `service` is `Service.qml`, loaded once at shell start and never visible.
  It owns every piece of state and every child process.
- `barWidget` is `BarWidget.qml`, the tile on the Omarchy bar.

Everything on screen is a Wayland layer surface created by the service. The
bar widget is a button, not a window.

Because it lives in the shell's process, a QML error in Ragtop can take the
whole shell down. That is not theoretical. Naming an `id` `layer`, or
shadowing a final property like `left`, fails at load with a message that
names neither the file nor Ragtop. Always check `ragtop health` after a
reload rather than trusting that the screen still looks right.

Code changes do not take effect through the file watcher, because the plugin
directory is a symlink into the repo and the watcher does not follow it.
`omarchy-shell shell rescanPlugins` can keep stale compiled QML. Use
`omarchy-restart-shell`. The tell that a restart really happened is the
`raises` counter in `ragtop health` going back to zero.

## The pieces

| File | What it is |
| --- | --- |
| `Service.qml` | The whole service. State, child processes, every layer surface, the IPC socket. |
| `BarWidget.qml` | The bar tile. Opens arrange mode, shows rotation lock. |
| `Keyboard.qml` | The on-screen keyboard: layouts, pages, which key a touch means. |
| `KeyboardKey.qml` | How one key is drawn. Nothing else. |
| `KeyboardTheme.qml` | Reads the look settings and resolves them into colours, sizes and corners. |
| `KeyboardSurface.qml` | The shared backdrop and top border, used by the keyboard and the picker strip. |
| `KeyIcon.qml` | Icons Ragtop draws itself as paths rather than taking from a font. |
| `LockKeyboard.qml` | A second, standalone keyboard for the lock screen. See below for why it is separate. |
| `LockKeyIcon.qml` | The same idea for the lock screen. |
| `ArrangeLayer.qml` | The transparent layer over real windows. Move, swap and resize by finger. |
| `ArrangeBar.qml` | The control strip along the bottom while arranging. |
| `ToolsPanel.qml` | The settings panel that comes up over the keyboard. |
| `PickerNav.qml` | A navigation strip for Omarchy's image picker. |
| `SetupWizard.qml` | First-run setup, in the shell rather than the terminal. |
| `keyboard-helper.py` | Types characters. A Wayland virtual keyboard. |
| `fcitx-osk-bridge.py` | Listens for "an app wants text input" and says so. |
| `tablet-switch.py` | Watches the fold switch. |
| `find-tablet-switch.py` | Finds which device that is. |
| `ragtop` | The command line tool. Settings, themes, overlays, diagnostics. |
| `install.sh` | Installs the parts that live outside the plugin folder. |
| `overlay-clones.sh` | Clones and patches Omarchy's full screen overlays. |
| `udev-rule.sh` | The rule that makes the fold switch readable. |
| `menu-block.sh` | Ragtop's rows in the Omarchy menu. |
| `setup-check.sh`, `setup-apply.sh` | What the wizard reads and what it writes. |

## Surfaces on screen

Every surface is a Quickshell `PanelWindow`, which is a Wayland layer
surface. There are six.

| Namespace | Layer | Exclusion | What it is |
| --- | --- | --- | --- |
| `ragtop-keyboard` | Top | Auto | The keyboard. Reserves its own height. |
| `ragtop-keyboard-handle` | Top | Auto | The grab handle when the keyboard is down. |
| `ragtop-tools` | Top | Normal | The settings panel. |
| `ragtop-picker-nav` | Top | Auto | The image picker strip. |
| `ragtop-arrange` | Top | Ignore | The arrange overlay. Reserves nothing. |
| `ragtop-screensaver-catcher` | Overlay | Ignore | Swallows the first tap that dismisses the screensaver. |

Two things decide what a touch hits.

**Stacking** is set by Hyprland layer rules, applied once at startup by
`hyprctl eval`:

```
ragtop-tools            order  1
ragtop-keyboard-handle  order -1
ragtop-picker-nav       order -2
ragtop-keyboard         order -3
```

**Input masks** decide where a surface takes touches at all. Every surface
sets `mask: Region { item: ... }` pointing at whatever it actually draws.
Outside that region touches fall through to whatever is underneath. This is
why the arrange overlay can cover the screen and still let you reach the bar
and the keyboard handle. Layer ordering was tried first for that and it put
the overlay on top of both.

`ExclusionMode.Auto` means the surface reserves its height and Hyprland
moves tiled windows out of the way. `Ignore` means it floats over them.
That difference matters more than it looks: when the keyboard's exclusive
zone changes, every window relayouts, and **Hyprland emits no event for it**.

## Talking to Hyprland

Two directions, two mechanisms.

**Out** is `hyprctl`. Hyprland 0.56 refuses `hyprctl keyword` with
"keyword can't work with non-legacy parsers", and it fails quietly, so
everything goes through the Lua dispatch API:

```
hyprctl dispatch 'hl.dsp.window.swap({ window = "address:0x...", target = "address:0x..." })'
hyprctl eval 'hl.config({ input = { kb_layout = "de" } })'
```

`hyprctl eval` returns `ok` whatever the Lua did, and swallows anything the
Lua prints, so it cannot be used to read values back.

Reading state is `hyprctl -j clients`, `-j monitors`, `-j activewindow`,
`getoption`.

Every address that reaches a dispatch is checked against
`/^0x[0-9a-f]+$/` first, and every workspace id is parsed as an integer and
range checked, because these strings are being interpolated into a Lua
expression.

**In** is Quickshell's `Hyprland` singleton and its `onRawEvent`. Ragtop
listens for window and workspace events, `activespecial`, `configreloaded`
and layout changes.

Two traps worth knowing. `hyprctl` prints addresses as `0x589cf9091790` and
Hyprland's **events** print them as `589cf9091790` with no prefix, so one
side has to be normalised or nothing ever matches. And a Hyprland config
reload drops the runtime monitor transform, so rotation has to reapply
itself on `configreloaded`.

## The fold switch

A convertible reports being folded as an evdev switch event, `EV_SW` code
`SW_TABLET_MODE`. `tablet-switch.py` opens the device, reads its current
state with an ioctl so it is right from the first moment rather than from
the first change, then blocks reading events and prints a line per change.

`find-tablet-switch.py` picks the device. The bar widget also takes an
explicit device path in its settings for machines where detection is wrong.

The device is only readable because of a udev rule that `udev-rule.sh`
installs:

```
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", ENV{ID_INPUT_KEY}!="1", TAG+="uaccess"
```

`uaccess` makes logind grant the seat's active user an ACL on the device.
The alternative is putting the user in the `input` group, which grants every
input device including keyboards, so the rule is deliberately narrower. It
excludes devices that also report keys, so it does not hand out a keyboard.

Tablet mode is also written to `$XDG_RUNTIME_DIR/ragtop-mode`, which is how
the patched overlay clones know to behave differently without talking to
Ragtop.

## The accelerometer

Rotation reads `monitor-sensor --accel` from iio-sensor-proxy and applies
the transform itself:

| Orientation | Transform |
| --- | --- |
| normal | 0 |
| left-up | 1 |
| bottom-up | 2 |
| right-up | 3 |

`monitor-sensor` asks iio-sensor-proxy to claim the accelerometer over
D-Bus. That call can hang. When it does, `monitor-sensor` gives up and
exits, and an eager restart makes it worse rather than better: measured on a
Lenovo 300w Yoga, a fresh process every 23 seconds all day with rotation
dead the whole time, and the same claim answering in 0.23 seconds after 40
seconds of quiet. Ragtop's own retry was what kept it dead.

So the sensor has a backoff of 3s, 30s, 2m, 5m, held as a deadline rather
than an armed timer, and it says once what stopped working.

## Typing

`keyboard-helper.py` is a Wayland client in its own right. It connects to
the compositor with pywayland, binds `zwp_virtual_keyboard_manager_v1` from
the bundled protocol XML in `protocols/`, and becomes a keyboard.

It does not send the key that sits where a letter is printed. It sends the
character. The layout is compiled with `xkbcli compile-keymap` from
Hyprland's own `kb_*` options, and characters are looked up in it. Anything
the layout cannot type is bound temporarily to a spare keycode at or below
255 that carries no symbol, reused least recently first.

The service talks to it over stdin, one line per command: `type`, `up`,
`reload`, `quit`. The helper prints back a `labels` line of JSON describing
the active layout, its rows, the levels each key carries and the extra
symbols it has. That is what the on-screen keyboard draws, which is why the
keyboard shows the letters your layout actually types.

Constraints found the hard way and worth not rediscovering:

- Build the keymap from Hyprland's config, not from the Wayland keymap dump.
  The dump returns whichever keyboard typed last.
- fcitx5 reads a device's keymap only when it first sees the device, so a
  changed keymap needs a **new** virtual keyboard rather than a re-upload.
- Keycodes above 255 never reach clients.
- pywayland segfaults during interpreter teardown, so the helper exits with
  `os._exit(0)`, wrapped, because on shell restart stdout is a broken pipe
  and a raised flush would skip it.

## Raising the keyboard by itself

Ragtop does not watch for focused text fields. fcitx5 already does, because
every keystroke passes through it and it implements text-input-v3 under
waylandim.

`fcitx-osk-bridge.py` claims the D-Bus name
`org.fcitx.Fcitx5.VirtualKeyboard` and implements the interface fcitx5 calls
when an application wants text input. When that call arrives the bridge
prints `show` and the service raises the keyboard.

The bridge watches for fcitx5 appearing on the bus with
`Gio.bus_watch_name_on_connection`. Without that, a fcitx5 restart left the
bridge registered but never called again, and the keyboard silently stopped
raising itself until the shell restarted.

`ragtop health` reports a `raises` counter, which is the honest way to tell
whether this path is alive.

## The overlay clones

Omarchy's full screen overlays take keyboard focus exclusively. Hyprland
routes every touch to a layer surface with exclusive focus before hit
testing anything above it, so with a stock overlay a tap on the on-screen
keyboard lands on the overlay and closes it.

`overlay-clones.sh` clones the menu, emoji picker, clipboard picker, polkit
prompt, image picker and lock screen, and patches each one to take focus on
demand instead, and to respect reserved space so it sits above the keyboard.
The patch is conditional on `$XDG_RUNTIME_DIR/ragtop-mode`, so in laptop
mode each clone behaves exactly like the original. The focus approach comes
from Gimbal (MIT).

A clone stops receiving Omarchy's updates, so `sync` re-clones and re-patches
any whose built-in has changed, and `install` registers it as an Omarchy
post-update hook. The polkit and lock clones keep their authentication
capability because Omarchy stamps a clone with its source's capabilities via
`clonedFrom`.

**The lock screen is different.** A session lock hides every other surface,
the keyboard included, so there is no way to put Ragtop's keyboard over it.
The lock clone instead loads `LockKeyboard.qml` directly. That is why there
is a second keyboard implementation rather than a shared one: it runs inside
the lock screen's own QML, not in the shell.

That duplication is a real cost. `LockKeyboard.qml` carries its own copy of
the key drawing, and a change to how keys look has to be made twice. When
the two drifted, the lock screen quietly kept the old behaviour.

## Settings, themes and the CLI

Settings are flat `key=value` lines in `~/.config/ragtop/settings.conf`.
The service reads the file and the `ragtop` CLI writes it.

A theme is a directory under `themes/` holding a `ragtop.toml`. Applying one
is a whitelist copy, not a merge: the CLI validates each key against a table
of allowed values, writes what survives, and **clears every look key the
theme did not name**. A theme is a whole look rather than a patch, so
switching themes cannot leave part of the last one behind.

That validation exists in three places and all three have to agree:

1. `ragtop` (Python), which decides what may be written at all.
2. `Service.qml`, which reads the settings into the live theme.
3. `LockKeyboard.qml`, which reads them again for the lock screen.

The CLI drops unknown keys silently and on purpose, so a value the CLI has
not been taught never reaches QML and the keyboard renders the fallback with
no error anywhere explaining why. Anything added to one of the three has to
be added to all three, and in the CLI to both the whitelist and the list of
keys an apply clears.

The CLI also carries `ragtop diagnostics`, which gathers what a bug report
needs and deliberately leaves out home directory paths, the host name and
the user name, since it is meant to be pasted into a public issue.

## Background processes

Four things run as child processes and each can die while everything on
screen still looks right:

- `keyboard-helper.py`
- `fcitx-osk-bridge.py`
- `tablet-switch.py`
- `monitor-sensor`

They share one retry policy: backoff of 3s, 15s, 60s, 5m, a run of ten
seconds counts as good and resets the count, and the user is told once at
the second consecutive failure rather than every time. The sensor has its
own longer backoff for the reason above.

`ragtop health` exists because of this. It returns the state of each of
them, and it is the only honest answer to "is it working".

## IPC

`IpcHandler` with target `ragtop`, reachable as
`omarchy-shell ragtop <function>`. Every function takes **no arguments**, so
nothing on the socket can be handed a value to act on:

```
showKeyboard  hideKeyboard  toggleKeyboard  keyboardVisible
toggleControls  growKeyboard  shrinkKeyboard
cycleRotation  rotationState
toggleArrange  openSetup  closeSetup  health
```

A temporary probe function is the standard way to test something that needs
touch or needs to be seen. Add it, use it, remove it before committing.

## Dependencies

`install.sh` refuses to run without `omarchy`, `omarchy-shell`, `hyprctl`
and `gdbus`, since there is no Ragtop without Omarchy 4 and Hyprland. It
then checks four packages and names the packages rather than the commands,
because "monitor-sensor is missing" is not something anybody can act on:

| Package | For |
| --- | --- |
| `iio-sensor-proxy` | `monitor-sensor`, which is rotation |
| `python-pywayland` | the keyboard helper's Wayland client |
| `python-gobject` | the fcitx5 bridge's D-Bus |
| `git` | cloning the overlays |

Not checked, because they come with the system it needs anyway:

- `xkbcli-compile-keymap` and `xkbcli-how-to-type`, taken from
  `/usr/lib/xkbcommon` by path rather than from `PATH`.
- fcitx5 under waylandim, for raising the keyboard on focus. Ragtop works
  without it, minus auto-show.

Rotation, auto-show and the fold switch each degrade on their own. A missing
piece disables that feature and reports itself in `health`, rather than
stopping the rest.

## What shaped the design

Five things that came out of building it, worth holding on to.

**State changes with no event to notice it by.** The keyboard's exclusive
zone relayouts every window and Hyprland says nothing. Arrange mode's own
resizes move the windows it is drawing over. Screen rotation moves
everything. Special workspaces did have an event, `activespecial`, and the
bug was not listening for it. Anything reading geometry needs a settle pass,
not a single read.

**One rule, one place.** Where a rule was written twice it drifted, and the
drift was always invisible until something specific broke. Hit testing and
paint order ranked windows differently, so a floating window inside a
focused tile could not be tapped at all. Three theme whitelists had to agree
and two of them knew about a new value. A settings key added beside a table
instead of into it was never cleared. Prefer one function both callers use
over two that happen to match today.

**Touches go by the slot, not by what is drawn.** A key's touch area is its
rectangle whatever shape the theme draws in it, so a shape can never make a
key harder to hit. Arrange mode inverts this deliberately: there the windows
themselves are the controls, so what you touch has to be what you get, and
nothing reaches past what is on top.

**Validate before dispatching.** Addresses and workspace ids are
interpolated into Lua. They are checked by pattern and by range first, every
time.

**Measure it.** Sign conventions, whether a dispatcher accepts a floating
window, how long a hung D-Bus call takes to recover. Several assumptions in
this file were wrong the first time and were only settled by running the
thing and reading the numbers.
