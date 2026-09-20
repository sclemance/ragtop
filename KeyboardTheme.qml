import QtQuick
import qs.Commons

// Everything about how Ragtop's keyboard looks, in one place, so a style can
// change it without touching the keyboard's logic.
//
// Omarchy's theme owns the values: colours (Color), type scale and spacing
// (Style), borders (Border). The settings under Setup › Tablet only say how
// to use them — how the keys are filled, how roomy they are, how big their
// labels read — so switching Omarchy themes restyles the keyboard too. A
// setting can still pin an off-theme colour or size outright; those stop
// following the theme, and only those.
QtObject {
  id: theme

  // Background opacity, from Setup › Tablet › Transparency (0 = fully clear).
  property real backgroundOpacity: 1
  // The keyboard's look, from Setup › Tablet (see Service.qml's `look`).
  property var look: ({ shape: "omarchy", relief: "flat", fill: "solid", size: "normal", background: "tint",
                        keyTransparency: "opaque", edge: "none", labels: "normal", depth: 4, chamfer: 8, edgeFade: 8,
                        keyColor: "", labelColor: "", keyFillAlpha: "auto",
                        borderWidth: "auto", radius: "auto" })

  // "dark" or "light" (an opaque key sitting darker or lighter than the
  // keyboard's background), "auto" (whichever of those the theme has room
  // for) or "outline" (no fill, carried by its edge).
  // Both filled kinds are fully opaque, so Key Transparency is the only
  // thing that makes a key see-through.
  readonly property string keyFill: look.fill
  readonly property string density: look.size
  readonly property string labels: look.labels

  // A look's off-theme colour: a palette role or a hex colour, "" to follow
  // the theme.
  function role(name, fallback) {
    switch (String(name)) {
    case "foreground": return Color.foreground
    case "background": return Color.background
    case "accent": return Color.accent
    case "urgent": return Color.urgent
    case "": case "auto": case "undefined": return fallback
    default: return /^#[0-9a-fA-F]{6,8}$/.test(name) ? name : fallback
    }
  }

  // The keyboard is a popup-like surface, so it takes Omarchy's popup
  // colours; the keys are controls, so they take its control states.
  property color surface: Color.popups.background
  property color text: role(look.labelColor, Color.popups.text)
  property color accent: Color.accent
  property color accentText: Color.background

  // "tint" (a flat colour), "blur" (the same, with what's behind blurred by
  // Hyprland) or "gradient" (towards the accent colour at the top).
  property string backgroundStyle: look.background
  property color background: Qt.rgba(surface.r, surface.g, surface.b, surface.a * backgroundOpacity)
  property color gradientTop: Qt.tint(surface, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18))
  property color backgroundTop: backgroundStyle === "gradient"
    ? Qt.rgba(gradientTop.r, gradientTop.g, gradientTop.b, surface.a * backgroundOpacity)
    : background

  // How the keyboard's top edge meets the desktop (Setup › Tablet › Edge):
  // "border" (Omarchy's own active window border), "fade" (the background
  // fading out over the style's edgeFade pixels) or "none" (a hard edge).
  readonly property string edgeStyle: look.edge
  property var borderSpec: Border.hyprlandActiveSpec(Color.accent, 2)
  property color borderColor: Border.color(borderSpec)
  // Two or more colours when the theme's border is a gradient.
  property var borderColors: borderSpec.gradient && borderSpec.gradient.enabled
    ? borderSpec.gradient.colors : [borderColor]
  property real edgeFade: edgeStyle === "fade" ? look.edgeFade : 0
  property real edgeBorder: edgeStyle === "border" ? Math.max(0, Border.top(borderSpec)) : 0
  property color backgroundClear: Qt.rgba(backgroundTop.r, backgroundTop.g, backgroundTop.b, 0)

  // Whether the background is actually drawn. Fully clear (Setup › Tablet ›
  // BG Transparency › Full) hides nothing, so taps off the keys can reach
  // what is behind the keyboard; any visible background does hide it, and
  // then the keyboard keeps those taps to itself.
  readonly property bool backgroundVisible: Math.max(background.a, backgroundTop.a) > 0.01

  // How see-through the keys are (Setup › Tablet › Key Transparency). What
  // shows through is the keyboard's own background; the desktop only shows
  // if that is see-through too.
  readonly property real keyOpacity:
    ({ "opaque": 1, "low": 0.85, "medium": 0.7, "high": 0.5, "full": 0 })[look.keyTransparency]
  function seeThrough(c) { return Qt.rgba(c.r, c.g, c.b, c.a * keyOpacity) }

  // A key sits darker or lighter than its panel. The palette has roles
  // rather than a ramp, so each direction first tries the theme's own
  // colours; where the panel already is that colour (a dark theme has
  // nothing darker than its background), it steps from the panel itself.
  // The step with the most contrast wins, and the key's border carries it
  // when a theme leaves little headroom either way.
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  readonly property color solidBase: Qt.rgba(surface.r, surface.g, surface.b, 1)
  readonly property color lighterRole: luminance(Color.foreground) > luminance(Color.background)
    ? Color.foreground : Color.background
  readonly property color darkerRole: luminance(Color.foreground) > luminance(Color.background)
    ? Color.background : Color.foreground

  function stepped(role, factorColor) {
    var mixed = Qt.tint(solidBase, Util.alpha(role, 0.14))
    return Math.abs(luminance(mixed) - luminance(solidBase))
      >= Math.abs(luminance(factorColor) - luminance(solidBase)) ? mixed : factorColor
  }
  readonly property color lightKey: stepped(lighterRole, Qt.lighter(solidBase, 1.3))
  readonly property color darkKey: stepped(darkerRole, Qt.darker(solidBase, 1.35))
  // "auto" takes whichever direction the theme has room for. A dark theme
  // has little below its background and a light one little above it, so a
  // fixed choice is strong on half the themes and nearly invisible on the
  // rest — which is no way to ship a preset.
  readonly property color autoKey: Math.abs(luminance(lightKey) - luminance(solidBase))
    >= Math.abs(luminance(darkKey) - luminance(solidBase)) ? lightKey : darkKey

  // Omarchy's normal control fill goes over the top, so a key still wears
  // the theme's own control tint.
  readonly property color themeKey: Style.normalFillFor(text, Color.accent, Color.urgent)
  readonly property color keyBase: look.keyFillAlpha !== "auto"
    ? Util.alpha(role(look.keyColor, text), look.keyFillAlpha)
    : keyFill === "outline" ? "transparent"
    : Qt.tint(role(look.keyColor, keyFill === "dark" ? darkKey
                                : keyFill === "light" ? lightKey : autoKey), themeKey)
  property color key: seeThrough(keyBase)
  property color pressedKey: Style.pressedFillFor(text, Color.accent, Color.urgent)
  property color latchedKey: seeThrough(Qt.tint(keyBase, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)))
  property color lockedKey: seeThrough(Color.accent)
  // Keys that aren't characters (Esc, Shift, ?123…) carry a quieter label.
  property color specialKey: key
  property color specialText: Util.alpha(text, 0.66)

  // A raised key's side is part of the key, not a wash over the background:
  // the face's own colour in shadow, with a little accent so it reads as an
  // edge, and it fades with the key so a see-through key stays one object.
  // An outline key has no face colour to shade, so there it stays a wash.
  property real sideStrength: 0.3
  readonly property color sideBase: keyFill === "outline"
    ? Util.alpha(Qt.tint(text, Util.alpha(Color.accent, 0.35)), sideStrength)
    : Qt.tint(Qt.darker(keyBase, 1.35), Util.alpha(Color.accent, 0.12))
  property color keySide: seeThrough(sideBase)

  // Key borders, from the same control states.
  property var keyBorderSpec: Border.controlSpec("normal", text, Color.accent, Color.urgent)
  property color keyBorder: Border.color(keyBorderSpec)
  property real keyBorderWidth: look.borderWidth !== "auto" ? Style.space(look.borderWidth)
    // An outline key is its edge, so it always keeps one.
    : keyFill === "outline" ? Math.max(1, Border.top(keyBorderSpec))
    : Border.top(keyBorderSpec)
  // The Outline shape's edges, which carry the key on their own.
  property color outline: Util.alpha(text, 0.45)

  // "omarchy" (the theme's own corner rounding, as windows have),
  // "rounded", "pill" or "angular"; a preset can pin a radius instead.
  property string keyShape: look.shape
  // Raised keys stand on a side, as a keycap does, whatever their shape.
  readonly property bool raised: look.relief === "raised"
  property real keyRadius: look.radius !== "auto" ? Style.space(look.radius)
    : keyShape === "omarchy" ? Style.cornerRadius
    : keyShape === "angular" ? 0
    : Style.space(8)
  property real keyDepth: raised ? Style.space(look.depth) : 0
  property real keyChamfer: Style.space(look.chamfer)

  // Density steps through Omarchy's spacing tokens and scales the keys.
  property int gap: density === "compact" ? Style.spacing.sm : density === "roomy" ? Style.spacing.lg : Style.spacing.md
  property int padding: density === "compact" ? Style.spacing.md : density === "roomy" ? Style.spacing.xl : Style.spacing.lg
  property real keyScale: density === "compact" ? 0.88 : density === "roomy" ? 1.15 : 1

  property string fontFamily: Style.font.family
  // Labels step on Omarchy's type scale — a character reads large, a word
  // like "Esc" small, an icon on its own icon scale — and grow with the
  // keys, so Key Size moves the labels with them.
  function labelPx(size) { return Math.max(8, Math.round(size * keyScale)) }
  property int labelSize: labelPx(labels === "small" ? Style.font.heading
    : labels === "large" ? Style.font.displayLarge : Style.font.display)
  property int wordSize: labelPx(labels === "small" ? Style.font.bodySmall
    : labels === "large" ? Style.font.heading : Style.font.title)
  property int iconSize: labelPx(labels === "small" ? Style.font.iconSmall
    : labels === "large" ? Style.font.display : Style.font.iconLarge)
}
