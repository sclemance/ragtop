# Architecture

What Ragtop is made of and how the pieces reach the machine. README.md says
what it does and how to use it. This says how it works.

Written against Omarchy 4.0.4, Hyprland 0.56.2 and Quickshell 0.3.1.

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
| `BarWidget.qml` | The bar tile. Opens tiling mode, shows rotation lock. |
| `Keyboard.qml` | The on-screen keyboard: layouts, pages, which key a touch means. |
| `KeyboardKey.qml` | How one key is drawn. Nothing else. |
| `KeyboardTheme.qml` | Reads the look settings and resolves them into colours, sizes and corners. |
| `KeyboardSurface.qml` | The shared backdrop and top border, used by the keyboard and the picker strip. |
| `SuggestionStrip.qml` | The band above the keys with an input method's choices. Draws, and says which item a touch means. |
| `KeyIcon.qml` | Icons Ragtop draws itself as paths rather than taking from a font. |
| `LockKeyboard.qml` | A second, standalone keyboard for the lock screen. See below for why it is separate. |
| `LockKeyIcon.qml` | The same idea for the lock screen. |
| `TilingLayer.qml` | The transparent layer over real windows. Move, swap and resize by finger. |
| `TilingBar.qml` | The control strip along the bottom while tiling. |
| `ToolsPanel.qml` | The settings panel that comes up over the keyboard. |
| `PickerNav.qml` | A navigation strip for Omarchy's image picker. |
| `SetupWizard.qml` | First-run setup, in the shell rather than the terminal. |
| `keyboard-helper.py` | Types characters. A Wayland virtual keyboard. |
| `fcitx-osk-bridge.py` | Ragtop's side of fcitx5: "an app wants text input", which input method is on, and its choices. |
| `predictor.py` | Word suggestions and swipe decoding, against wordfreq's English list. |
| `words/NOTICE.md` | The word list's credits and licence, copied beside it on download. |
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
| `ragtop-tiling` | Top | Ignore | The tiling overlay. Reserves nothing. |
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
why the tiling overlay can cover the screen and still let you reach the bar
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
Lua prints. **`hyprctl repl` does not**, and returns what the Lua returns:

```
hyprctl repl 'return 1+1'          -> 2
hyprctl eval  'return 1+1'         -> ok
```

Worth knowing, because "you cannot read a value back out of Lua" is true of
one of them and false of the tool sitting next to it, and believing it of
both leads to working around a problem that is not there.

Reading state is `hyprctl -j clients`, `-j monitors`, `-j activewindow`,
`getoption`. The Lua API has its own getters that Ragtop does not use,
including `get_windows`, `get_workspace_windows`, `get_monitors`,
`get_layers` and `is_key_down`. The JSON is well understood and works, so
there is no reason to move, but the second route exists.

**What is not available at all: the layout tree.** Dwindle is a binary tree
and an edge between two tiles belongs to a branch rather than to either
window, which is why resizing a boundary between two groups moves the whole
group. Showing that to a user would need to know the tree, and nothing
exposes it. `hyprctl` has no tree command, `clients` carries no parent,
sibling or node field, and the Lua `HL.Window` object answers `nil` to
`parent`, `sibling`, `node` and `children` while `w.layout` is only
`{name = "dwindle"}`. It could be inferred from geometry, and it is
deliberately not: an inference that is usually right reads as a bug on the
case where it is wrong, and that case is exactly when someone is already
confused. It needs a change in Hyprland or it stays undone.

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

A claim that never lands has two causes and only one of them is a fault. The
daemon can be wedged, which a restart clears, or the machine can have no
accelerometer at all, which a restart cannot help and which is the normal
state of a kiosk or a desk touchscreen. Ragtop used to treat them as one
thing, because the only question it asked was whether `monitor-sensor` is
installed, and it told both of them to run
`systemctl restart iio-sensor-proxy`.

It asks instead. `net.hadess.SensorProxy.HasAccelerometer` is a boolean on
the daemon's own D-Bus interface, read with `busctl get-property`, and it is
the authority on whether there is hardware. Absence has to be proved: only a
definite false suppresses the fault, so a daemon too broken to answer its own
property is still reported, which it should be. The answer decides three
things, the notification, the `sensor` line in Diagnostics, and whether the
bar carries a rotation button at all.

## Typing

`keyboard-helper.py` is a Wayland client in its own right. It connects to
the compositor with pywayland, binds `zwp_virtual_keyboard_manager_v1` from
the bundled protocol XML in `protocols/`, and becomes a keyboard.

It does not send the key that sits where a letter is printed. It sends the
character. The layout is compiled with `xkbcli compile-keymap` from
Hyprland's own `kb_*` options, and characters are looked up in it. Anything
the layout cannot type is bound temporarily to a spare keycode at or below
255 that carries no symbol, reused least recently first.

The service talks to it over stdin, one line per command: `type`, `key`,
`down`, `up`, `hold`, `release`, `route`, `reload`, `quit`. The helper prints back a `labels` line of JSON describing
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

The bridge is also how input methods reach the keyboard (below), so it runs
while either auto-show or input methods are on.

## Input methods

Chinese, Japanese and Korean are typed through fcitx5's composing engines,
Mozc, Pinyin, Hangul and the like. fcitx5 shows an engine's choices in a
popup by the text, and on a touch screen that popup is no use: tested on the
Yoga, it vanishes when touched. So Ragtop shows them itself, in
`SuggestionStrip.qml` above the keys.

fcitx5 hands them over through its virtual keyboard addon, the same
D-Bus interface the bridge already claims for auto-show. It calls the
holder of `org.fcitx.Fcitx5.VirtualKeyboard` with:

| Call | Signature | Means |
| --- | --- | --- |
| `NotifyIMActivated` | `s` | this engine is now on in the focused field, or that field gained focus |
| `NotifyIMDeactivated` | `s` | it is off, or the field lost focus |
| `NotifyIMListChanged` | | the user's group changed |
| `UpdateCandidateArea` | `as b b i i` | the choices, has a previous page, has a next page, page, highlighted one |
| `UpdatePreeditArea`, `UpdatePreeditCaret` | `s`, `i` | the word being written. Unused: the application draws it in the field |

and the keyboard answers through `/virtualkeyboard`,
`org.fcitx.Fcitx5.VirtualKeyboardBackend1`: `SelectCandidate(i)`,
`PrevPage`, `NextPage` and `ProcessKeyEvent(uuubu)`.

**The catch, and why the keys change route.** fcitx5 sends the choices only
while it is in on-screen keyboard mode, and any key from a keyboard device
ends that mode, the on-screen keyboard's own Wayland keys included. That is
the "hide" the bridge has always had to re-arm after. Measured: with keys
going the Wayland way, the first key sends `HideVirtualKeyboard` and not one
`UpdateCandidateArea` follows. Keys sent through `ProcessKeyEvent` are the
on-screen keyboard's by definition, so the mode holds.

So the helper has two routes. `route fcitx` sends each key through
`ProcessKeyEvent`, with its real keysym, xkb keycode (evdev's plus 8) and
modifier state. A key fcitx5 does not use, it passes on to the application
itself through its own virtual keyboard, which is why the keycode matters.
`route wayland` is the helper as it always was. The service picks the route:
fcitx while the focused field has a composing engine on and input methods
are enabled, Wayland otherwise. A plain layout never changes route.

Three things stay on the Wayland route whatever it is:

- **Shortcuts.** A key with Ctrl, Alt or Super goes as a Wayland key, so
  Hyprland's bindings see it exactly as before.
- **A character the layout cannot type.** It needs the helper's spare-key
  trick, which only exists on the Wayland side.
- **Anything fcitx5 refuses.** A failed call falls back rather than losing
  the key.

**Knowing which engine is on.** fcitx5 says so on focus, by
`NotifyIMActivated`, and keeps the choice per application, so focus moving to
a terminal reports its plain layout. It does not say so after an arm,
though, and an arm follows every Wayland-route key. So after each arm the
bridge asks, with `Controller1.CurrentInputMethod`. Measured on a private
fcitx5: focus out sends `NotifyIMDeactivated` then `Hide`, focus in sends
`NotifyIMActivated` then `Show`, a second application gaining focus sends
its own engine.

**Never auto-start fcitx5.** Every call to `org.fcitx.Fcitx5` from the
bridge, the helper and the tests carries `NO_AUTO_START`. D-Bus starts a
fcitx5 for a call to the name when nobody holds it, and one started that way
runs outside Omarchy's `omarchy-fcitx5` service. Found the hard way: a call
during a restart of the service left a second fcitx5 holding the name and
the service crash-looping behind it.

**The strip** belongs to no input method. `Service.qml` holds `suggestions`,
`{ source, items: [{ text, note }], prev, next, cursor }`, and answers
`chooseSuggestion` and `pageSuggestions` by asking whichever source filled
it. fcitx5 is the only source today. Word prediction or swipe would be
others. The strip keeps its place while an engine is on, items or not, so
the keyboard is one height through a sentence. Touches on it go through the
keyboard's one touch layer like every key's: a finger that moves scrolls,
one that lifts where it landed chooses.

The space bar names the engine while one is on ("あ Mozc"), and the card a
hold on it opens lists fcitx5's engines after Hyprland's layouts.
`ragtop input-methods disable` turns all of it off, and keys go the Wayland
way with fcitx5 drawing its own popup, as before.

## Word suggestions and swipe

`predictor.py` is a child process like the helper, run while either is
turned on. It reads wordfreq's `small_en.msgpack.gz` as wordfreq publishes
it. The data is CC-BY-SA 4.0 and its author asks that it not be converted
into a plain list that sheds the attribution, so it is never converted: a
forty-line reader for the subset of MessagePack the file uses reads it in
place, and `ragtop words install` fetches it from the v3.2 tag, checks a
pinned SHA-256, and puts `words/NOTICE.md` beside it. Nothing of wordfreq's
is in the repository, and the tests build their own small list in the same
format.

**Where the word comes from.** Ragtop has no view of the text being edited,
only of the keys it sends, so `Service.qml` follows the word in `sendKeys`,
the one place every key passes. A letter extends it, BackSpace shortens it,
anything else starts again, and so do a focus change (the bridge's `show`)
and the keyboard going away. A tap in the text moves the cursor without a
key, which is the case this cannot see; starting again at the next non-letter
keeps the damage to one word. Taking a suggestion sends one BackSpace per
letter and then the word and a space, which works in any application, input
method support or not.

**Four rules found on the Yoga, each a bug before it was a rule:**

- *An empty list clears only its own source.* The bridge reports "no
  candidates" after every key on a plain layout, and that wiped the word
  suggestions a moment after each appeared.
- *Answers are matched to their question.* Replies come back a moment after
  each key, in order. One that arrives after the word has changed (a quick
  space) is dropped; taking it deleted nothing and glued the word on, "a" +
  "test" as "atest". A suggestion is not taken with no word in progress.
- *A swipe after tapped letters puts a space first.* "a" can only be tapped.
- *An automatic space moves past punctuation.* The space a swipe or a
  suggestion adds goes after a `. , ! ? ; :` typed straight after it, so
  "test, " and not "test ,". A space typed by hand is never moved.

**Completion and correction.** Words starting with what was typed, ranked by
wordfreq's centibel bucket. From three letters, words one edit away too, at a
penalty, and a changed letter is only a slip when the two keys are neighbours
on the active layout's rows, which the service sends (`rows`). A shorter
correction waits until nothing completes the word: otherwise "hel" offered
"he", which is so common it beat every real completion.

**Swipes** follow SHARK2. Keyboard.qml sends each letter key's centre in its
own coordinates (`keys`) and, when a finger has drawn across the letters,
the path (`swipe`). Candidates are the words whose first and last keys are
near where the path began and ended and every one of whose keys the path
passes near. Each is scored on five things: the mean distance between the
path and the word's ideal path, both resampled to 32 points (location); the
same after both are centred and scaled (shape); the difference in their
lengths; how far the path's ends are from the word's first and last keys;
and how common the word is. The weights came from a simulation, every one of
160 common words drawn through its key centres with a random wobble of up to
half a key: 95 to 98 percent come first and all of them come in the first
three, at about 20 ms each. The misses are mostly pairs no path can tell
apart, to and too, its and it's, which is what the runners-up in the strip
are for. The simulation is not a hand, so the weights are a start rather than
an answer.

Speed is decided by points, not by words. The simulation drew six points
between keys, and a real finger reports far more: on the Yoga, a slower
swipe of a longer word took 400 to 600 ms to settle. How near the path
comes to each key is the same for every candidate, so it is worked out once
per swipe, and the keyboard keeps a point only once the finger has moved a
tenth of a key. A 120-point path went from 330 ms at worst to 45, with the
same words chosen. While a finger draws, the strip shows the guess so far
(`peek`, answered as `peeked` so it is never taken for a finished word),
one guess at a time, each taking the path as it is when the last returns.
BackSpace straight after a swipe takes the word and its space back in one,
keeping a space the swipe put in front.

**What turns them off.** A layout whose xkb name is not English (the helper
now reports `code` in its labels, since the name is translated), a CJK
engine, and Omarchy's polkit prompt, the one password field Ragtop can see.

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

Omarchy has written the overlays two ways. On 4.0.4 each is a `PanelWindow`
in its entry file. At `7cc6a55` the menu and the three pickers are instances
of `OverlayWindow`, a component in `qs.Ui`. Either way the surface maps when
the overlay opens and unmaps when it closes, which is what the service's
`openlayer` and `closelayer` handling goes by. The patcher tells the two
apart by the entry file and refuses anything that is neither.

For the second kind the clone gets `RagtopOverlayWindow.qml`, a copy of the
shared component with the patch in it, and the entry file is changed only to
name that type and pass it tablet mode. `.ragtop-base` gains a third line,
the hash of the `OverlayWindow.qml` the copy was made from. That hash is
what makes the copy part of the clone: `sync` compares it with Omarchy's
file, and a clone only counts as Ragtop's own if taking the patch back out
of the copy leaves exactly the file that was hashed.

The copy differs from the per-window patch in two ways:

- **Focus.** Hyprland gives an on-demand layer the keyboard when it maps and
  not when an already mapped one starts asking, and the image picker maps
  before its images have loaded and only then asks. So in tablet mode the
  copy asks exclusively for 75 ms each time it starts wanting the keyboard,
  then drops to on demand, as Omarchy's `KeyboardPanel` does.
- **Being seen.** `OverlayWindow` keeps its content transparent until the
  surface is the size of the whole screen and has the screen's scale. Out of
  reserved space the surface is never that size, so in tablet mode the copy
  waits for the scale alone. Without this the overlay would open invisible.

The copy adds an `onBackingWindowVisibleChanged` handler, so a source that
already has one is refused rather than copied into a window with two.

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
toggleTiling  openSetup  closeSetup  health
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

## Tests

```
tests/run                    # everything
tests/run overlay-clones     # one file: tests/overlay-clones-test.sh
```

Needs `bash`, `python3`, `jq` and `quickshell`. The tests cover the overlay
clones, which is the part of Ragtop that breaks when Omarchy changes and
cannot be checked by looking.

Nothing in them touches the machine they run on. Each test gets a throwaway
`HOME` and `XDG_RUNTIME_DIR` and an environment built from nothing, so there
is no `WAYLAND_DISPLAY` or Hyprland socket to find. `omarchy plugin clone`
and `remove` are stood in for by `tests/stub-bin/omarchy`, which does to the
filesystem what the real ones do and leaves out the running shell.

| File | What it runs |
| --- | --- |
| `overlay-clones-test.sh` | The real `overlay-clones.sh` against copies of two Omarchy trees in `tests/fixtures`: 4.0.4 and `7cc6a55`. Install, status, sync, remove, edited clones, failed patches, moving between the two, shapes it must refuse. |
| `input-methods-test.sh` | The real bridge and the helper's fcitx route against a private fcitx5 with Mozc, Pinyin and Hangul, on a bus of its own: 日本語, 你好 and 한글 typed and chosen, shortcuts kept off the route. Skipped where the engines are not installed. |
| `predictor-test.sh` | `predictor.py` against a made-up list in wordfreq's format: ranking, capitals, corrections by neighbouring keys, and swipes drawn through QWERTY with a fixed miss at every key. |
| `suggestion-strip-test.sh` | `SuggestionStrip.qml` loaded offscreen: which item a touch means, at the arrows and scrolled. |
| `overlay-window-test.sh` | The window the patcher generates for a clone, loaded by quickshell offscreen: what it asks for closed and open, in laptop and tablet mode, and when it lets its content be seen. |

The QML tests stop where the compositor starts. A `PanelWindow` cannot exist
without one, so the generated window is loaded with `PanelWindow`, the
`WlrLayershell` attached object and the `Hyprland` singleton swapped for
stand-ins that only record what they are told
(`tests/qml/FakePanelWindow.qml`). They prove what a clone asks
Hyprland for. Where focus then goes, and what a touch then hits, still has
to be tried by hand on a tablet.

The fixtures are Omarchy's own files, unmodified, under its MIT licence
(`tests/fixtures/LICENSE.omarchy`). `emojis.json` is left out for its size;
the patcher only ever hashes it. When Omarchy changes an overlay, add the new
tree beside the others rather than replacing one: the old shapes are still
on people's machines. The one exception so far is the tree from `81145eb`,
whose shared window stayed mapped between opens. Omarchy dropped that design
ten days later (#14458) and no release ever carried it, so its fixture and
the code for it are gone.

## What shaped the design

Five things that came out of building it, worth holding on to.

**State changes with no event to notice it by.** The keyboard's exclusive
zone relayouts every window and Hyprland says nothing. Tiling mode's own
resizes move the windows it is drawing over. Screen rotation moves
everything. Special workspaces did have an event, `activespecial`, and the
bug was not listening for it.

Two more turned up after this file was first written, and both were
Hyprland dispatches that change geometry silently. Measured on the event
socket, `window.swap` emits no `movewindow` and no `resizewindow`, and it
does not change focus either. `layout("togglesplit")` emits nothing at all.
The first made tiling mode swap the wrong window, because `windowAt` reads
the same rectangles the outlines are drawn from, so a stale one resolves a
drop to whichever window used to be in that spot. The second left the
outlines around the old shape.

The rule that comes out of it: **an action that moves something says so
itself**, rather than waiting for an event that may not come. Every one of
these was fixed by having the dispatching function trigger the re-read.
Where an action seemed to work, it was usually relying on a side effect,
tapping a window refreshed the model only because focusing emits
`activewindow`.

To find out whether a dispatch is silent, watch `.socket2.sock` through it:

```
socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
```

Filter for `movewindow` and `resizewindow`. Ignore `windowtitle` and
`activewindow`, which any terminal generates constantly on its own.

Anything reading geometry needs a settle pass, not a single read.

**One rule, one place.** Where a rule was written twice it drifted, and the
drift was always invisible until something specific broke. Hit testing and
paint order ranked windows differently, so a floating window inside a
focused tile could not be tapped at all. Three theme whitelists had to agree
and two of them knew about a new value. A settings key added beside a table
instead of into it was never cleared. Prefer one function both callers use
over two that happen to match today.

**A group is one tile.** Omarchy tabs windows together with SUPER+G, and
Hyprland then reports every member at the same geometry with `hidden` false
on all of them. Anything drawing per window draws them stacked. Measured:
swapping one member with another tile moves the whole group intact, so the
members are interchangeable as handles and the fix is to keep one row per
group rather than to work out which tab is visible. Nothing exposes which
tab that is, so the one kept is the most recently focused, which only
affects a label.

**Touches go by the slot, not by what is drawn.** A key's touch area is its
rectangle whatever shape the theme draws in it, so a shape can never make a
key harder to hit. Tiling mode inverts this deliberately: there the windows
themselves are the controls, so what you touch has to be what you get, and
nothing reaches past what is on top.

**Validate before dispatching.** Addresses and workspace ids are
interpolated into Lua. They are checked by pattern and by range first, every
time.

**Measure it.** Sign conventions, whether a dispatcher accepts a floating
window, how long a hung D-Bus call takes to recover. Several assumptions in
this file were wrong the first time and were only settled by running the
thing and reading the numbers.
