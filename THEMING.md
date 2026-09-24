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

Six ship: `omarchy`, `soft`, `typewriter`, `glass`, `industrial`,
`spaceship`.

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

## The background behind the keys

```toml
background = "tint"
transparency = 30
key-transparency = 15
edge = "fade"
edge-fade = 16
blur = false
```

`background` is `tint` or `gradient`. `transparency` is the backdrop over
your desktop and `key-transparency` is the keys over that backdrop, both
0 solid to 100 gone. `edge` is how the backdrop ends: `border`, `fade` or
`none`, with `edge-fade` the pixels a fade takes.

`blur` asks the compositor to blur what is behind the keyboard. It costs
something to draw, so it is off unless a theme asks. It takes a TOML boolean
or the strings `"on"` and `"off"`, since both read naturally in a file.

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
| `fill` | `auto`, `dark`, `light`, `outline` | `light` |
| `key-fill-alpha` | 0 to 1 | auto |
| `border-width` | 0 to 4 | auto |
| `key-color` | `foreground`, `background`, `accent`, `urgent`, `#hex` | follows Omarchy |
| `label-color` | the same | follows Omarchy |
| `background` | `tint`, `gradient` | `tint` |
| `transparency` | 0 solid to 100 gone | 0 |
| `key-transparency` | 0 solid to 100 gone | 0 |
| `edge` | `border`, `fade`, `none` | `none` |
| `edge-fade` | 0 to 24 | 8 |
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

**Omarchy** is the plain one. Your Omarchy theme's corner radius, flat, no
edge. It exists so there is a way back.

**Soft** and **Glass** are the same shape doing different things with the
backdrop. Soft is a gradient at 30 with a 16px fade. Glass is a tint at 50
with keys at 30 on top of it, so the desktop comes through twice.

**Typewriter** is `pill` and raised, which on a near square key reads as a
round typewriter key.

**Industrial** is `angular` and raised with `chamfer = 12`, `labels =
"large"` and a border. Four cut corners and a heavy edge.

**Spaceship** is `bevel` at `chamfer = 18`, raised, gradient, with a border.
It is the one that uses `corners` explicitly, and its file explains why its
diagonal runs the way it does.

## Where the look is actually kept

Applying a theme writes flat `key=value` lines into
`~/.config/ragtop/settings.conf`, alongside settings that are not part of
the look. Tablet mode, auto-show and Size Adjust are never touched by a
theme.

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

The lock screen reads the same theme through its own copy of the parser, in
`LockKeyboard.qml`, so check it there too by locking the screen. The two
parsers are separate code and have drifted before, which is exactly the kind
of thing a theme notices first.
