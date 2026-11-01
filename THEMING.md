# Theming the keyboard

A Ragtop theme sets the keyboard's **form**. Its colours keep coming from
your Omarchy theme, which is why any Ragtop theme looks right on any Omarchy
one, and why there is no palette in here.

## What a theme is

A directory with a `ragtop.toml` in it.

```
~/.config/ragtop/themes/mytheme/ragtop.toml   your own
<plugin>/themes/mytheme/ragtop.toml           the ones that ship
```

Yours are looked at first, so a theme of your own named `glass` shadows the
one that ships without touching it. The directory name is what you type at
`ragtop theme apply`, and it has to match `^[a-z0-9-]{1,32}$`. The `name`
field inside is the label people see.

```
ragtop theme list
ragtop theme apply spaceship
```

Nine ship: `omarchy`, `soft`, `chiclet`, `focus`, `mechanical`,
`typewriter`, `glass`, `industrial`, `spaceship`.

## The smallest theme that works

```toml
name = "Mine"
shape = "rounded"
```

Every field is optional. What you leave out takes its default, **not**
whatever the last theme set. Applying a theme writes the whole look and
clears every look field the theme did not name, so themes cannot leave
pieces of themselves behind in each other.

## Shape

`shape` picks a silhouette:

| Shape | Corners |
| --- | --- |
| `omarchy` | round, at your Omarchy theme's own corner radius |
| `rounded` | round, at a fixed radius |
| `pill` | round, at half the key's height |
| `angular` | all four cut |
| `bevel` | cut on one diagonal, round on the other |

A shape name is shorthand for a set of four corners and nothing more. If
none of them is what you want, name the corners yourself.

## Corners

`corners` takes four words, **clockwise from the top left**: top left, top
right, bottom right, bottom left. Each is `round`, `cut` or `square`.

```toml
corners = "cut round cut round"
```

It overrides whatever `shape` would have set. `corners = "auto"`, or leaving
it out, uses the shape's own.

| corners | what you get |
| --- | --- |
| `round round round round` | `rounded` |
| `cut cut cut cut` | `angular` |
| `cut round cut round` | `bevel` |
| `cut round round round` | one corner notched |
| `square square square square` | a plain slab |
| `cut cut round round` | a keycap taper |

A round corner uses `radius`. A cut one uses `chamfer`. A square one takes
nothing.

All four round is drawn as a rectangle, which is cheaper. Anything else is
drawn as an outline path. That is invisible from a theme except that a
`pill` drawn with mixed corners uses `radius` rather than half the key
height, because half the key height only makes sense when every corner has
it.

If your four words are not four known words, they are ignored in full and
the shape's corners stand. There is no half-applied corner set.

### One thing worth knowing before you cut the top right

A keycap prints what AltGr types in its **top right** corner, and Ragtop
does the same. The space that hint gets is measured from whichever corner
style landed there, so a cut corner there pushes the hint inward.

That is a preference and not a rule. Checked against `fr(ergol)`, which
carries superscripts on its third level and is about the worst case there
is, a cut top right was close but fine. Look at your own font and key size
and decide. `spaceship` runs its diagonal so the top right stays round, and
says so in its own file.

## Relief

```toml
relief = "raised"
depth = 6
```

`flat` is a face and nothing else. `raised` stands the key on a side, like a
keycap, and pressing sinks the face into it. `depth` is how far the side
shows, 0 to 10, and it is capped at a quarter of the key's height so the
face always has somewhere to sit.

A raised key draws its side with the same corners as its face, so a bevelled
key stays bevelled all the way down.

## Fill and colour

```toml
fill = "auto"
```

| `fill` | The key |
| --- | --- |
| `auto` | follows whether your Omarchy theme is dark or light |
| `dark` | sits darker than the background |
| `light` | sits lighter than it |
| `surface` | uses the Omarchy popup surface with its normal control tint |
| `outline` | is its edge, with no fill at all |

`key-fill-alpha` (0 to 1) overrides how strong that fill is.
`border-width` (0 to 4) sets the edge. An `outline` key always keeps at
least a hairline whatever you set, because an outline key with no edge is
not there.

To leave the Omarchy palette for one part of the look:

```toml
key-color = "accent"
label-color = "#ffcc00"
```

Both take `foreground`, `background`, `accent`, `urgent`, or a hex colour
of 6 or 8 digits. Only what you set stops following your Omarchy theme.

`contrast = "strong"` opts into full-strength modifier labels and corner
hints, stronger borders, and labels checked against their key face in each
state. It keeps the preferred palette colour when its contrast is at least
4.5:1; otherwise it uses black or white. Use opaque fills for predictable
results: wallpaper behind transparent keys cannot be measured here.
The default, `"normal"`, preserves the usual label and border treatment.
Focus uses `"strong"`; other themes can opt in independently.

Pressing a filled key tints its existing face while retaining its opacity.
An outline key still gains the shell's translucent press fill.

## What is behind the keys

```toml
key-transparency = 15
blur = false
```

There is no background behind the keys, and nothing to set for one. This
is an opinionated change, made in 0.48.0, in line with Omarchy's design:
the keyboard reserves its own room, so what is behind it is the wallpaper,
and a panel over that only hid it. `background`, `transparency`, `edge` and
`edge-fade` are gone; a theme that still names them has them ignored, and
`ragtop migrate` drops them from your settings.

`key-transparency` is how see-through the keys are, 0 solid to 100 gone.
`blur` asks the compositor to blur what is behind the keys, and only the
keys, since it blurs only what is at least partly opaque. It costs something
to draw, so it is off unless a theme asks. It takes a TOML boolean or the
strings `"on"` and `"off"`, since both read naturally in a file. The themes
Ragtop ships keep the keys mostly solid; a fully see-through keyboard is
there to make in a theme of your own.

## Labels and size

```toml
labels = "large"
size = 115
special-keys = "darker"
```

`labels` steps the text on Omarchy's own type scale: `small`, `normal`,
`large`. A label is capped at 62% of the key's face whatever you ask, so a
large label on a small key shrinks rather than spills.

`size` is the key size as a percentage of the usual, 60 to 160. It is a
theme's opinion. The reader's own **Size Adjust** multiplies it rather than
replacing it, so how big the keys are for someone's eyes survives changing
theme.

`special-keys` is how keys that type nothing sit against the letters:
`darker`, `lighter` or `off`.

## Every field

| Field | Values | Default |
| --- | --- | --- |
| `name` | the label people see | the directory name |
| `shape` | `omarchy`, `rounded`, `pill`, `angular`, `bevel` | `omarchy` |
| `corners` | four of `round`, `cut`, `square`, or `auto` | `auto` |
| `radius` | round corner radius, 0 to 30 | the shape's own |
| `chamfer` | cut corner depth, 0 to 20 | 8 |
| `relief` | `flat`, `raised` | `flat` |
| `depth` | raised key side, 0 to 10 | 4 |
| `fill` | `auto`, `dark`, `light`, `surface`, `outline` | `light` |
| `contrast` | `normal`, `strong` | `normal` |
| `backlight` | `off`, `accent` | `off` |
| `backlight-motion` | `off`, `ripple` (desktop main keys only) | `ripple`, gated by user preference |
| `backlight-press-color` | `foreground`, `background`, `accent`, `urgent`, `#hex` | palette complement |
| `keycap-material` | `solid`, `pudding`, `frosted`, `translucent` (clear faces require the Sculpted profile) | `solid` |
| `keycap-profile` | `standard`, `sculpted` (raised, rounded caps) | `standard` |
| `wall-opacity` | 0 transparent to 100 opaque (Pudding sides only) | 50 |
| `key-fill-alpha` | 0 to 1 | auto |
| `border-width` | 0 to 4 | auto |
| `key-color` | `foreground`, `background`, `accent`, `urgent`, `#hex` | follows Omarchy |
| `label-color` | the same | follows Omarchy |
| `key-transparency` | 0 solid to 100 gone | 0 |
| `blur` | `true`, `false`, or `"on"`, `"off"` | `false` |
| `labels` | `small`, `normal`, `large` | `normal` |
| `size` | 60 to 160 | 100 |
| `special-keys` | `darker`, `lighter`, `off` | `darker` |

Anything outside these names, or outside these values, is **dropped without
a word**. That is deliberate, because a theme is a file and it does not get
to write arbitrary settings. It does mean a typo in a field name is silent,
and what you get is the default rather than an error. If a theme is not
doing what you wrote, check the spelling first.

## The shipped themes, as worked examples

**Omarchy** is the plain one: your Omarchy theme's corner radius, flat, and
`fill = "light"`. It exists so there is a way back.

**Soft** and **Glass** are the same rounded, flat key doing different things
with the wallpaper behind it. Soft's keys are 15% see-through. Glass's are
30%, with `blur = true`, so what shows through is softened.

**Chiclet** is `rounded` at `radius = 4` and raised at `depth = 6`, solid,
with a thin edge and darker modifiers. Its visible side and sinking press
give it the familiar form of a physical keyboard, with normal-size legends
and room for secondary hints. Its face is flat; nothing here draws a
dished one.

**Typewriter** is `pill` and raised at `depth = 8`, which on a near square
key reads as a round typewriter key, with `labels = "large"` and `size =
115` asking for keys a little bigger than usual.

**Focus** is flat and opaque, with `radius = 6`, large labels and a 2-unit
border. Its `surface` fill follows the Omarchy surface, and `contrast =
"strong"` keeps modifier labels and corner hints at full strength and checks
label contrast in normal, pressed and selected states. Size stays at 100.

## Backlit themes

`backlight = "accent"` declares a backlit theme. Desktop backlighting supports
raised, opaque caps with round corners; flat, transparent and cut-corner
caps omit the halo. Mechanical offers Plain, Pudding, Frosted and Translucent
materials independently of lighting behaviour.

Backlighting uses a centred light shaped to each cap's footprint.
Pressing lowers the cap and changes
its light to the complementary palette colour, keeping the cap's fill unchanged.
Underlighting and illuminated legends share a colour. Letter/word legends, drawn icons and
corner hints use the existing brightening (18% white) and faint luminous
rim (22% light colour); locked modifiers retain contrasting legends.

**Mechanical** defaults to opaque plastic walls and a shallow perspective profile
(`keycap-profile = "sculpted"`, `keycap-material = "solid"`). Its centred face has a shallow curved top edge and a gently bowed lower
edge over a broader skirt, following the supplied SVG reference. Both sides
and the front wall are visible. Static gradients suggest a dished surface.
The 8-unit depth compresses by 55% on press, leaving a visible solid skirt.
Letters, icons and corner hints shine through, and light escapes underneath;
the walls are opaque and do not change colour with the backlight. The theme
does not request backdrop blur. Label placement follows the inset face.
Sculpted uses a smaller outer light inset (at most 0.75 units times the size
scale), keeping the outer gaps compact. Its side inset is bounded by 6 units,
8.5% of cap width and 17% of face height. The face ends up to 3 units higher
(7% of face height on small caps), exposing a deeper front wall. Legends
follow the inset face. Key slots and touch targets stay rectangular and unchanged.

The profile loads a small vector renderer only when selected. Its geometry
changes on depression, not on ripple frames. It requires rounded, raised,
keys; incompatible shapes use the standard profile. Backlighting can be off.
The lock keyboard uses its existing conservative rendering instead.

Mechanical's gear controls separate material and lighting from the Sculpted
profile. No profile selector is shown while there is only one option.

| Control | Behaviour |
|---------|-----------|
| Backlight | Master light switch; cap shape and material remain visible when off. |
| Plain | Opaque plastic face and walls, the original Sculpted appearance. |
| Pudding | Opaque face; walls at 50% opacity, illuminated when backlit, with backdrop blur. |
| Frosted | Entire cap at 50% opacity with backdrop blur; opaque, contrasting glyphs. |
| Translucent | Entire cap at 50% opacity without backdrop blur; opaque, contrasting glyphs. |
| Shine-through glyphs | Available with backlight on and Plain/Pudding; letters, SVG icons and hints share the light. |
| Lighting effects | Existing ripple animation preference. Off keeps steady light and immediate press colour. |

Frosted and Pudding still use compositor blur when lighting effects or the
backlight are off. Clear surfaces adjoin rather than stacking transparent
fills; they do not create per-key capture textures. The underlight itself
also obscures some background. Actual readability depends on what is behind
a translucent keyboard.

`mechanical-backlight` and `mechanical-shine-through` default on;
`mechanical-material` defaults to `plain`. These saved user preferences are
independent of theme files and survive theme changes. Disabled controls do
not erase their values. Lighting effects reuse `backlight-animation`, whose
existing value is retained (off by default). These overrides apply only to
the selected Mechanical theme, not tour previews or other themes.

```sh
ragtop mechanical-backlight disable
ragtop mechanical-material set frosted
ragtop mechanical-shine-through enable
ragtop backlight-animation disable
```

The former `sculpted` theme selection migrates to `mechanical` without
resetting other settings. `ragtop theme apply sculpted` remains an alias;
a user-authored theme named `sculpted` keeps its own identity. The theme list
shows Mechanical once. `sculpted` remains the profile's internal name.

The resting light follows the bright palette counterpart nearest Omarchy's
accent, or the accent itself if no counterpart is close. Dim colours on
dark themes are lifted towards white. Modern named colours and older ANSI
`color1`–`color14` palettes are supported. The active `colors.toml` is watched,
and `theme.name` reattaches the watch when Omarchy replaces the theme
directory. Palette selection runs on theme changes, never animation frames.
Resting lighting stays at 100% intensity. Presses use a bright palette colour
near the opposite hue; selection accounts for the existing white brightness
and legend tints and discounts nearly neutral candidates. Named and legacy
ANSI palettes are supported. Sparse or monochrome palettes fall back to an
authored foreground, then white if none is available.
`backlight-press-color` can override the automatic choice.

The travelling wave blends towards that complementary colour while dimming
neighbouring keys towards 50%, then returns to the resting colour and
100%. A held key stays fully lit in the press colour; its release changes
colour without dimming. Underlight, walls, legend cores and rims share the
brightness wave, applied after the legend's white tint. Material opacity
and the solid cap colour stay unchanged. Percentages scale RGB intensity,
not measured display luminance.

On dark themes the wave mixes in just enough white to keep its sampled
colour transition above a trial relative-luminance floor of 0.18. This
softens the dip for darker complements; bright-enough colours receive no
extra tint. The lift tapers to zero as the wave settles and does not affect
resting or held-key colours. It is calculated once per palette or explicit
press-colour change, with no per-frame luminance analysis. The floor is an
appearance heuristic, not a text-contrast guarantee.
Light themes retain their palette hue without the dark-theme brightness
lift; these materials are designed primarily for dark themes.

### Animation preference

**Animate backlight** appears in the gear panel for backlit themes only.
It defaults to off, giving immediate complementary colour on press and
restoration on release, at full brightness throughout. This creates no ripple
helpers or animation timers. The setting is a user preference, preserved
when applying any theme:

```sh
ragtop backlight-animation enable
ragtop backlight-animation disable
```

With animation enabled, the default `backlight-motion = "ripple"` transitions
the pressed light in 90 ms and sends a wave up to 2.4 key pitches away.
Neighbours dip towards 50% with the complementary colour and the brightness
floor above, delayed by 65 ms per pitch, with a 90 ms dip and 300 ms recovery.
Each key replaces its prior wave; held keys resist incoming waves. Hiding
the keyboard destroys the helpers. Static frosting/blur still has a
compositor cost with animation disabled. A theme may explicitly set
`backlight-motion = "off"` to suppress ripple animation.

Suggestions and held-key cards use the flat Omarchy default look at the
keyboard's size scale, independently of its cap theme: no raised profile,
backlight, glow or ripple. Alternate characters, language/layout choices,
held-word forms and erase-preview cards share this supporting-control look.
The suggestion list retains its scrolling clip; without luminous keys inside
it, the clip no longer cuts off candidate-key halos. The lock keyboard always
uses flat Omarchy keys with normal legends and no backlighting or effects.
Desktop halos use Qt RectangularShadow (Qt 6.9+), with no key-content captures
or animated blur geometry.

**Industrial** is `angular` and raised at `depth = 6`, with `chamfer = 12`
and `labels = "large"`. Four cut corners on a solid key.

**Spaceship** is `bevel` at `chamfer = 18`, raised at `depth = 4`, with keys
10% see-through. It is the one that uses `corners` explicitly, and its file
explains why its diagonal runs the way it does.

## Where the look is actually kept

Applying a theme writes flat `key=value` lines into
`~/.config/ragtop/settings.conf`, alongside settings that are not part of
the look. Tablet mode, auto-show, Size Adjust and the animation preference are never
touched by a theme.

You can change one field from the keyboard's own settings panel without
writing a theme at all. That writes to the same file, and applying a theme
afterwards overwrites it.

## Testing a theme

```
ragtop theme apply mytheme
```

takes effect immediately, with no restart. If it does not, the value was
dropped, and the two usual reasons are a misspelled field and a value
outside its range.

The lock keyboard always uses the flat **Omarchy** appearance in `Color.lock`
colours. Desktop theme shape, fill, transparency, type scale, materials and
lighting do not apply. `LockKeyboard.qml` reads only the user's checked
`sizeNudge` from the runtime style file; it uses a fixed 100% base size and
ignores old theme fields. Layout and alternate characters remain available.
Theme previews and tests do not require locking the live session.
