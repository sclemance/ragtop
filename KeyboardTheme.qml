import QtQuick
import qs.Commons
import "KeyContrast.js" as KeyContrast
import "GlowColors.js" as GlowColors

// Everything about how Ragtop's keyboard looks, in one place, so a style can
// change it without touching the keyboard's logic.
//
// Omarchy's theme owns the values: colours (Color), type scale and spacing
// (Style), borders (Border). The settings under Setup › Tablet only say how
// to use them, how the keys are filled, how roomy they are and how big
// their labels read, so switching Omarchy themes restyles the keyboard too.
// A setting can still pin an off-theme colour or size outright. Those stop
// following the theme, and only those.
QtObject {
  id: theme

  // The keyboard's look, from Setup › Tablet (see Service.qml's `look`).
  property var look: ({ shape: "omarchy", relief: "flat", fill: "solid", size: "normal",
                        keyTransparency: "opaque", labels: "normal", depth: 4, chamfer: 8,
                        keyColor: "", labelColor: "", keyFillAlpha: "auto",
                        borderWidth: "auto", radius: "auto", corners: "auto" })

  // "dark" or "light" (an opaque key sitting darker or lighter than the
  // keyboard's background), "auto" (whichever of those the theme has room
  // for) or "outline" (no fill, carried by its edge).
  // Both filled kinds are fully opaque, so Key Transparency is the only
  // thing that makes a key see-through.
  readonly property string keyFill: look.fill
  // How big the keys are: the theme's percentage, times the user's nudge,
  // held inside what a keyboard can actually be. Spacing follows the result
  // rather than a name, so a theme asking for 130 is roomy without having to
  // say so.
  // What the user's step does to the theme's size. The service works it out,
  // so there is one table rather than one per keyboard.
  readonly property real sizeNudge: look.sizeNudge || 1
  readonly property string density: keyScale < 0.95 ? "compact"
    : keyScale > 1.08 ? "roomy" : "normal"
  readonly property string labels: look.labels
  readonly property bool strongContrast: look.contrast === "strong"
  readonly property bool backlit: look.backlight === "accent"
  readonly property bool ripple: backlit && look.animateBacklight === true && look.backlightMotion === "ripple"
  readonly property bool sculpted: look.keycapProfile === "sculpted" && raised && cornersAllRound
  readonly property bool pudding: (backlit || sculpted) && look.keycapMaterial === "pudding" && raised && cornersAllRound
  readonly property bool transparentCap: sculpted && (look.keycapMaterial === "frosted" || look.keycapMaterial === "translucent")
  readonly property bool shineThrough: backlit && look.shineThrough !== false && !transparentCap
  readonly property real wallOpacity: look.wallOpacity === undefined ? 0.5 : look.wallOpacity / 100
  property var glowPalette: ({})
  readonly property var glowColors: GlowColors.choose(glowPalette, accent, Color.foreground, Color.background)
  readonly property color glowColor: glowColors.base
  readonly property color rippleColor: role(look.backlightPressColor, glowColors.press)
  readonly property real rippleWhiteMix: GlowColors.waveWhiteMix(glowColor, rippleColor, glowColors.dark)
  readonly property real hintOpacity: strongContrast ? 1 : 0.5

  function readableText(preferred, face) {
    return KeyContrast.readableText(preferred, Qt.tint(solidBase, face))
  }

  function pressFill(base) { return KeyContrast.pressedFill(base, pressedOverlay) }

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
  // colours, and the keys are controls, so they take its control states.
  // There is no background behind the keys, ever: the keyboard reserves its
  // own room, so what is behind it is the wallpaper, and a panel over that
  // did nothing but hide it. `surface` is still the colour the keys are
  // measured against, lighter or darker, as the panel's would have been.
  property color surface: Color.popups.background
  property color text: role(look.labelColor, Color.popups.text)
  property color accent: Color.accent
  property color accentText: Color.background


  // How see-through the keys are, as the theme asked: the wallpaper shows
  // through, blurred if the theme asks for blur (Service.qml, applyBlur,
  // which blurs only what is at least partly opaque, so only the keys).
  readonly property real keyOpacity: 1 - look.keyTransparency / 100
  function seeThrough(c) { return Qt.rgba(c.r, c.g, c.b, c.a * keyOpacity) }

  // A key sits darker or lighter than its panel. The palette has roles
  // rather than a ramp, so each direction first tries the theme's own
  // colours. Where the panel already is that colour (a dark theme has
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
  // rest, which is no way to ship a theme.
  readonly property color autoKey: Math.abs(luminance(lightKey) - luminance(solidBase))
    >= Math.abs(luminance(darkKey) - luminance(solidBase)) ? lightKey : darkKey

  // Omarchy's normal control fill goes over the top, so a key still wears
  // the theme's own control tint.
  readonly property color themeKey: Style.normalFillFor(text, Color.accent, Color.urgent)
  readonly property color keyBase: look.keyFillAlpha !== "auto"
    ? Util.alpha(role(look.keyColor, text), look.keyFillAlpha)
    : keyFill === "outline" ? "transparent"
    : Qt.tint(role(look.keyColor, keyFill === "dark" ? darkKey
                                : keyFill === "surface" ? solidBase
                                : keyFill === "light" ? lightKey : autoKey), themeKey)
  property color key: seeThrough(keyBase)
  readonly property color pressedOverlay: Style.pressedFillFor(text, Color.accent, Color.urgent)
  property color pressedKey: pressFill(key)
  property color latchedKey: seeThrough(Qt.tint(specialBase, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)))
  property color lockedKey: seeThrough(Color.accent)
  // A key that produces no character sits a step further from the panel than
  // the letters do, so the letters read as one block and the rest read as
  // the keys that act on them. Stepped the same way the keys themselves step
  // off the panel: tint toward the theme's own roles rather than multiply a
  // value, since multiplying leaves pure black and pure white where they
  // were, and keep whichever direction measurably moves further. The base's
  // own alpha is put back, so these keys are no more solid than the letters
  // at any Key Transparency.
  // Darker than the letters, whatever the palette. Qt.darker only drops the
  // value, so the hue and saturation are the theme's own and nothing has to
  // be mixed in. Tinting toward the darker role was tried and is wrong here:
  // on a dark theme the darker role IS nearly the panel the keys sit on, and
  // a key that starts 19/255 above it barely moves.
  //
  // The one thing darker must not do is sink a key into the panel, which is
  // exactly the case on a dark theme where the letters are lifted only a
  // little above it. So where the keys sit above the panel, the step stops
  // halfway down to it. Where they sit below it, as on a light theme, darker
  // moves away from the panel and needs no floor. The base's alpha is put
  // back, so these keys are no more solid than the letters at any Key
  // Transparency.
  // Which way, and whether at all, is the Ragtop theme's to say (special-keys).
  // Off leaves them the letters' own shade, where the quieter label is the
  // only thing setting them apart, which is how the keyboard looked before.
  readonly property string specialStep: look.specialKeys
  readonly property color specialBase: {
    if (keyBase.a === 0 || specialStep === "off") return keyBase
    var up = specialStep === "lighter"
    var target = up ? Qt.lighter(keyBase, 1.45) : Qt.darker(keyBase, 1.45)
    // A step must not take a key into the panel it sits on. Going down, that
    // is a risk where the keys are already above the panel, as a dark theme
    // has them. Going up, where they are below it. Either way the step stops
    // halfway rather than crossing.
    if (up === (luminance(keyBase) < luminance(solidBase))) {
      var halfway = Qt.tint(keyBase, Util.alpha(solidBase, 0.5))
      if (up ? luminance(target) > luminance(halfway) : luminance(target) < luminance(halfway))
        target = halfway
    }
    return Qt.rgba(target.r, target.g, target.b, keyBase.a)
  }
  // Keys that aren't characters (Esc, Shift, ?123…) carry a quieter label.
  property color specialKey: seeThrough(specialBase)
  property color specialText: strongContrast ? text : Util.alpha(text, 0.66)

  // A raised key's side is part of the key, not a wash over the background:
  // the face's own colour in shadow, with a little accent so it reads as an
  // edge, and it fades with the key so a see-through key stays one object.
  // An outline key has no face colour to shade, so there it stays a wash.
  //
  // Shadow is a step towards black, which is what a keycap's side is, but a
  // face that is already nearly black has no shadow left in it. Measured
  // across Omarchy's themes, a dark key's side came out less than 3% of
  // luminance from its face on 14 of 22 of them, and on vantablack the two
  // were identical: a keycap with no side at all. So where there isn't room
  // to step down, the side steps up instead. An edge that can't be seen
  // isn't an edge.
  property real sideShadow: 0.25    // towards black, where the face has room
  property real sideLift: 0.09      // towards white, where it hasn't
  property real sideMinStep: 0.035  // the least difference that still reads as an edge
  property real sideAccent: 0.12    // enough accent that the edge belongs to the theme
  property real outlineSideAccent: 0.35
  property real sideStrength: 0.3

  function shaded(c) {
    var down = Qt.tint(c, Qt.rgba(0, 0, 0, sideShadow))
    return Math.abs(luminance(down) - luminance(c)) >= sideMinStep
      ? down : Qt.tint(c, Qt.rgba(1, 1, 1, sideLift))
  }
  readonly property color sideBase: keyFill === "outline"
    ? Util.alpha(Qt.tint(text, Util.alpha(Color.accent, outlineSideAccent)), sideStrength)
    : Qt.tint(shaded(keyBase), Util.alpha(Color.accent, sideAccent))
  property color keySide: seeThrough(sideBase)

  // Key borders, from the same control states.
  property var keyBorderSpec: Border.controlSpec("normal", text, Color.accent, Color.urgent)
  property color keyBorder: strongContrast ? Util.alpha(text, 0.8) : Border.color(keyBorderSpec)
  property real keyBorderWidth: keyFill === "outline" ? Math.max(1, keyBorderWidthAsked) : keyBorderWidthAsked
  // An outline key is its edge, so it always keeps one, whatever width
  // the theme asked for: zero included.
  property real keyBorderWidthAsked: look.borderWidth !== "auto"
    ? Style.space(look.borderWidth) : Border.top(keyBorderSpec)
  // The Outline shape's edges, which carry the key on their own.
  property color outline: Util.alpha(text, 0.45)

  // "omarchy" (the theme's own corner rounding, as windows have),
  // "rounded", "pill", "angular" or "bevel". A Ragtop theme can pin a
  // radius instead, or name the corners one by one.
  property string keyShape: look.shape

  // Each corner in turn, clockwise from the top left.
  //
  // A named shape is nothing more than a set of these. Angular is four cut
  // corners and rounded is four round ones, so rather than every silhouette
  // needing a name and a branch of its own, a theme can write `corners`
  // and have the one that suits it. Bevel is the pair that gets a name
  // because it is the one worth having by default: cut on one diagonal,
  // round on the other.
  readonly property var keyCorners: {
    if (look.corners !== "auto") return String(look.corners).split(" ")
    if (keyShape === "angular") return ["cut", "cut", "cut", "cut"]
    if (keyShape === "bevel") return ["cut", "round", "cut", "round"]
    return ["round", "round", "round", "round"]
  }
  // Four round corners is a rectangle, which is cheaper to draw and is what
  // most themes are, so it stays the common path and everything else takes
  // the outline.
  readonly property bool cornersAllRound: keyCorners[0] === "round"
    && keyCorners[1] === "round" && keyCorners[2] === "round"
    && keyCorners[3] === "round"
  // Raised keys stand on a side, as a keycap does, whatever their shape.
  readonly property bool raised: look.relief === "raised"
  property real keyRadius: look.radius !== "auto" ? Style.space(look.radius)
    : keyShape === "omarchy" ? Style.cornerRadius
    : keyShape === "angular" ? 0
    : keyShape === "bevel" ? Style.space(8)
    : Style.space(8)
  property real keyDepth: raised ? Style.space(look.depth) : 0
  // A side can't take more than this much of the key, or the face has
  // nowhere left to sit. Pressing sinks the face most of the way into it.
  property real maxDepthFraction: 0.25
  property real pressSink: sculpted ? 0.55 : backlit && !pudding ? 1 : 0.6
  property real keyChamfer: Style.space(look.chamfer)

  // Density steps through Omarchy's spacing tokens and scales the keys.
  property int gap: density === "compact" ? Style.spacing.sm : density === "roomy" ? Style.spacing.lg : Style.spacing.md
  property int padding: density === "compact" ? Style.spacing.md : density === "roomy" ? Style.spacing.xl : Style.spacing.lg
  property real keyScale: Math.max(0.6, Math.min(1.6, look.size / 100 * sizeNudge))

  // Visual room for underlighting inside an unchanged touch slot. Sculpted
  // already has a skirt around its inset face, so it needs much less here.
  function capInsetFor(w, h) {
    return sculpted ? Math.min(0.75 * keyScale, w * 0.02, h * 0.02)
      : backlit ? Math.min(2.5, w * 0.07, h * 0.07) : 0
  }

  property string fontFamily: Style.font.family
  // Labels step on Omarchy's type scale, a character reading large, a word
  // like "Esc" small and an icon on its own icon scale, and they grow with the
  // keys, so Key Size moves the labels with them.
  function labelPx(size) { return Math.max(8, Math.round(size * keyScale)) }
  property int labelSize: labelPx(labels === "small" ? Style.font.heading
    : labels === "large" ? Style.font.displayLarge : Style.font.display)
  property int wordSize: labelPx(labels === "small" ? Style.font.bodySmall
    : labels === "large" ? Style.font.heading : Style.font.title)
  property int iconSize: labelPx(labels === "small" ? Style.font.iconSmall
    : labels === "large" ? Style.font.display : Style.font.iconLarge)
}
