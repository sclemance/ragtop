import QtQuick
import QtQuick.Shapes
import qs.Ui

// How one key of Ragtop's keyboard looks, and nothing else: Keyboard.qml
// places it in its slot, decides which key a touch means and sets its
// state. Whatever it draws, touches go by the slot, so a shape can't make a
// key harder to hit. The shape comes from the keyboard style
// (theme.keyShape).
Item {
  id: key

  required property var theme
  property string label: ""
  // "normal", "special", "accent", "latched" or "locked".
  property string kind: "normal"
  // "char" (a letter), "word" (Esc, ?123), "icon" (a glyph) or "drawn" (an
  // icon Ragtop draws itself), which picks how the label is rendered and
  // its size on Omarchy's scales.
  //
  // There was a fifth, "markword", a mark and its name side by side, for the
  // Super key while it sat on the extra row and carried both. Super is on the
  // bottom row now with the mark alone, so it draws like any other icon key.
  property string labelKind: "char"
  // The drawn icon's name, for labelKind "drawn" (see KeyIcon.qml).
  property string icon: ""
  property bool pressed: false
  // A second character printed small in a corner, the way a keycap prints
  // what AltGr types on it. Empty on a key that has nothing there.
  property string hint: ""
  // The same on the top left, for the character the symbol pages put in
  // this key's place. Two legends because they are two different things
  // behind the key, and a keycap that carries several prints them apart
  // rather than running them together.
  property string hintLeft: ""
  // A drawn icon in the right hint's place, for a key whose hold reaches
  // something no character can name: the gear in Super's corner. It takes
  // that corner instead of `hint`, never as well, since one corner cannot
  // print two things.
  property string hintIcon: ""
  // Draw the fill at full strength whatever Key Transparency says. The
  // setting is there to let the desktop show through the keyboard. Behind a
  // key in a long-press popup is the popup's own panel, so being see-through
  // there would only muddy the letter.
  property bool opaque: false
  // The clear space around the drawn cap can exceed the layout's gap.
  property real glowGap: theme.gap
  // Enabled only on the main desktop board; popup/strip/lock stay static.
  property bool rippleEnabled: false
  readonly property real backlightBrightness: rippleLoader.item ? rippleLoader.item.brightness : 1
  readonly property color lightSourceColor: rippleLoader.item ? rippleLoader.item.color
    : pressed && theme.backlit ? theme.rippleColor : theme.glowColor
  function lightAtBrightness(color) {
    var dim = Qt.rgba(color.r * backlightBrightness, color.g * backlightBrightness,
                      color.b * backlightBrightness, color.a)
    return rippleLoader.item && rippleLoader.item.whiteMix > 0
      ? Qt.tint(dim, Qt.rgba(1, 1, 1, rippleLoader.item.whiteMix)) : dim
  }
  readonly property color backlightColor: lightAtBrightness(lightSourceColor)
  readonly property bool pudding: theme.pudding === true && (backlit || sculpted)
  readonly property bool sculpted: theme.sculpted === true && boxy && depth > 0
  readonly property bool transparentCap: sculpted && theme.transparentCap === true
  readonly property bool illuminated: theme.shineThrough === undefined ? theme.backlit === true : theme.shineThrough
  // Clear caps still need to distinguish latched/locked modifiers from a
  // normal cap. Their glyph contrast follows the same material colour.
  readonly property color materialLight: transparentCap && (kind === "locked" || kind === "latched")
    ? restingFill : backlit ? backlightColor : theme.keySide
  readonly property color wallColor: pudding
    ? Qt.rgba(backlightColor.r, backlightColor.g, backlightColor.b, theme.wallOpacity)
    : sculpted ? theme.keySide : backlit ? backlightColor : theme.keySide
  function pulseGlow(distance) {
    if (rippleLoader.item) rippleLoader.item.pulse(distance)
  }

  readonly property string shape: theme.keyShape
  readonly property bool outlined: theme.keyFill === "outline"
  readonly property color restingFill: kind === "locked" ? theme.lockedKey
    : kind === "latched" ? theme.latchedKey
    : kind === "special" || kind === "accent" ? theme.specialKey
    : theme.key
  // Backlit caps signal a press by sinking and changing their light colour.
  readonly property color tinted: pressed && !theme.backlit && !sculpted ? theme.pressFill(restingFill) : restingFill
  readonly property color fill: opaque && tinted.a > 0
    ? Qt.rgba(tinted.r, tinted.g, tinted.b, 1) : tinted
  readonly property color preferredLabelColor: kind === "locked" ? theme.accentText
    : kind === "accent" ? theme.accent
    : kind === "special" ? theme.specialText
    : theme.text
  readonly property color labelColor: transparentCap
    ? theme.readableText(preferredLabelColor, Qt.rgba(materialLight.r, materialLight.g, materialLight.b, 1))
    : theme.strongContrast ? theme.readableText(preferredLabelColor, fill) : preferredLabelColor
  readonly property color shineColor: illuminated && kind !== "locked"
    ? lightAtBrightness(Qt.tint(Qt.rgba(lightSourceColor.r, lightSourceColor.g, lightSourceColor.b, 1),
              Qt.rgba(1, 1, 1, 0.18))) : labelColor
  readonly property color legendGlow: illuminated && kind !== "locked"
    ? Qt.rgba(backlightColor.r, backlightColor.g, backlightColor.b, 0.22) : "transparent"

  // An accent edge is what marks Enter now that it is not filled. Any style
  // can set a border width of zero, so this one insists on a hairline.
  readonly property color edgeColor: kind === "accent" ? theme.accent
    : outlined ? theme.outline : theme.keyBorder
  readonly property real edgeWidth: kind === "accent"
    ? Math.max(1, theme.keyBorderWidth) : theme.keyBorderWidth

  // A raised key's face sits above its side and sinks into it when pressed.
  readonly property real depth: Math.min(theme.keyDepth, height * theme.maxDepthFraction)
  // The face, where the label goes: the whole key but for a keycap's side.
  readonly property real faceY: pressed ? depth * theme.pressSink : 0
  readonly property real faceHeight: height - depth
  readonly property real legendInset: sculpted ? Math.min(6, width * 0.085, faceHeight * 0.17) : 0
  readonly property real legendHeight: faceHeight - (sculpted ? Math.min(3, faceHeight * 0.07) : 0)
  readonly property real legendShift: 0
  readonly property bool backlit: theme.backlit === true && boxy && depth > 0 && fill.a >= 0.99

  // Which corner is drawn how, clockwise from the top left. A shape name
  // is only ever shorthand for one of these sets, so there is no shape to
  // special-case here: either all four are round, which a rectangle draws,
  // or the outline below does it.
  readonly property var corners: theme.keyCorners
  readonly property bool boxy: theme.cornersAllRound
  readonly property real chamfer: Math.min(theme.keyChamfer, width / 3, height / 3)

  // How far a corner eats into the face where a hint sits. A pill's radius
  // is half the key, so its corner is nowhere near the corner of the box
  // and a hint placed by the box alone ends up on the curve. Roughly the
  // horizontal reach of the arc where the hint's own line crosses it.
  function insetOf(corner) {
    return corner === "cut" ? chamfer * 0.5
      : corner === "square" ? 0
      : (shape === "pill" ? faceHeight / 2 : theme.keyRadius) * 0.3
  }
  // Clockwise from the top left, so 0 is the left hint's corner and 1 the
  // right one's.
  readonly property real cornerInset: insetOf(corners[1])
  readonly property real cornerInsetLeft: insetOf(corners[0])

  // The key's outline with each corner drawn the way its style asks. The
  // same path serves the face and the side, so a raised key keeps whatever
  // corners it has.
  //
  // A square corner is a cut of no length, so both ends of it land on the
  // same point and the straight line that draws a cut draws a square too.
  // That is why there are two cases here and not three.
  function cornerPath(top, boxHeight) {
    var w = width, bottom = top + boxHeight
    var r = Math.min(theme.keyRadius, w / 2, boxHeight / 2)
    var c = Math.min(chamfer, w / 3, boxHeight / 3)
    function reach(k) {
      return key.corners[k] === "round" ? r : key.corners[k] === "cut" ? c : 0
    }
    function turn(k, x, y) {
      return key.corners[k] === "round"
        ? " A " + r + " " + r + " 0 0 1 " + x + " " + y
        : " L " + x + " " + y
    }
    var tl = reach(0), tr = reach(1), br = reach(2), bl = reach(3)
    return "M " + tl + " " + top
      + " L " + (w - tr) + " " + top + turn(1, w, top + tr)
      + " L " + w + " " + (bottom - br) + turn(2, w - br, bottom)
      + " L " + bl + " " + bottom + turn(3, 0, bottom - bl)
      + " L 0 " + (top + tl) + turn(0, tl, top)
      + " Z"
  }

  Loader {
    anchors.fill: parent
    active: key.backlit
    sourceComponent: KeyGlow {
      accent: key.backlightColor
      rounding: key.shape === "pill" ? key.height / 2 : key.theme.keyRadius
      gap: key.glowGap
      // Leave a visible background contribution through the frosted walls.
      // The underlight adds occlusion to their own 50% material opacity.
      strength: key.pudding || key.transparentCap ? 0.55 : 0.95
      blur: Math.max(6, key.glowGap * 1.8)
    }
  }

  Loader {
    id: rippleLoader
    active: key.backlit && key.rippleEnabled && key.visible
    sourceComponent: GlowRipple {
      active: key.visible && key.rippleEnabled
      pressed: key.pressed
      baseColor: key.theme.glowColor
      pressColor: key.theme.rippleColor
      floorWhiteMix: key.theme.rippleWhiteMix
    }
  }

  // A raised key's side, which only ever shows below the face: it starts
  // where the face does, so a pressed key shows nothing above it.
  Rectangle {
    visible: key.depth > 0 && key.boxy && !key.sculpted
    y: key.faceY
    width: key.width
    height: key.height - key.faceY
    radius: key.shape === "pill" ? height / 2 : key.theme.keyRadius
    objectName: "keySide"
    color: key.wallColor
  }

  Shape {
    visible: key.depth > 0 && !key.boxy
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: key.theme.keySide
      strokeWidth: 0
      strokeColor: "transparent"
      PathSvg { path: key.cornerPath(key.faceY, key.height - key.faceY) }
    }
  }

  // The face, when every corner is round: a rectangle with its own radius.
  Rectangle {
    visible: key.boxy && !key.sculpted
    y: key.faceY
    width: key.width
    height: key.faceHeight
    radius: key.shape === "pill" ? height / 2 : key.theme.keyRadius
    color: key.fill
    border.width: key.edgeWidth
    border.color: key.edgeColor
  }

  // Anything else: the corners drawn one by one.
  Shape {
    visible: !key.boxy
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: key.fill
      strokeColor: key.edgeColor
      strokeWidth: key.edgeWidth
      joinStyle: ShapePath.MiterJoin
      PathSvg { path: key.cornerPath(key.faceY, key.faceHeight) }
    }
  }

  Loader {
    objectName: "sculptedCap"
    anchors.fill: parent
    active: key.sculpted
    sourceComponent: SculptedKeycap {
      faceColor: key.fill
      material: key.theme.look.keycapMaterial || "solid"
      lightColor: key.materialLight
      materialOpacity: key.theme.wallOpacity
      edgeColor: key.edgeColor
      edgeWidth: key.edgeWidth
      faceY: key.faceY
      faceHeight: key.faceHeight
      rounding: key.theme.keyRadius
    }
  }

  // The label's size on Omarchy's scales, kept inside the key.
  readonly property int labelPixelSize: Math.min(
    labelKind === "icon" || labelKind === "drawn" ? theme.iconSize
      : labelKind === "word" ? theme.wordSize
      : theme.labelSize,
    Math.round(faceHeight * 0.62))

  // A glyph goes through Omarchy's own glyph renderer, which corrects the
  // centring of icon glyphs. Plain text doesn't need it.
  OpticalGlyph {
    visible: key.labelKind === "icon"
    x: key.legendInset + key.legendShift
    y: key.faceY
    width: key.width - 2 * key.legendInset
    height: key.legendHeight
    text: key.labelKind === "icon" ? key.label : ""
    color: key.shineColor
    fontFamily: key.theme.fontFamily
    fontSize: key.labelPixelSize
  }

  Text {
    id: legend
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
    visible: key.labelKind === "char" || key.labelKind === "word"
    readonly property bool illuminated: key.illuminated
    x: key.legendInset + key.legendShift
    y: key.faceY
    width: key.width - 2 * key.legendInset
    height: key.legendHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: key.label
    // Opaque shine-through lettering, with a small luminous rim. No
    // background sampling, transparency or per-letter blur texture.
    // A locked modifier keeps its contrasting legend over the accent fill.
    color: key.shineColor
    style: illuminated ? Text.Outline : Text.Normal
    styleColor: key.legendGlow
    elide: Text.ElideRight
    font.family: key.theme.fontFamily
    font.pixelSize: key.labelPixelSize
    font.bold: illuminated
  }

  Text {
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
    visible: key.hint !== "" && key.hintIcon === ""
    readonly property bool illuminated: key.illuminated
    y: key.faceY + Math.round(key.theme.gap / 2 + key.cornerInset / 2)
    width: key.width - Math.round(key.theme.gap / 2 + key.cornerInset) - key.legendInset + key.legendShift
    horizontalAlignment: Text.AlignRight
    text: key.hint
    color: key.shineColor
    // Quieter than the label it sits beside: it says what the key can also
    // do, and should not compete with what it does now.
    opacity: illuminated || key.transparentCap ? 1 : key.theme.hintOpacity
    style: illuminated ? Text.Outline : Text.Normal
    styleColor: key.legendGlow
    font.family: key.theme.fontFamily
    font.pixelSize: Math.max(9, Math.round(key.labelPixelSize * 0.52))
    font.bold: illuminated
  }

  Text {
    // Outside strings reach this one too: see the note above.
    textFormat: Text.PlainText
    visible: key.hintLeft !== ""
    readonly property bool illuminated: key.illuminated
    x: Math.round(key.theme.gap / 2 + key.cornerInsetLeft) + key.legendInset + key.legendShift
    y: key.faceY + Math.round(key.theme.gap / 2 + key.cornerInsetLeft / 2)
    horizontalAlignment: Text.AlignLeft
    text: key.hintLeft
    color: key.shineColor
    opacity: illuminated || key.transparentCap ? 1 : key.theme.hintOpacity
    style: illuminated ? Text.Outline : Text.Normal
    styleColor: key.legendGlow
    font.family: key.theme.fontFamily
    font.pixelSize: Math.max(9, Math.round(key.labelPixelSize * 0.52))
    font.bold: illuminated
  }

  // The right hint as a drawn icon. Same corner and the same quietness as the
  // text it stands in for, but drawn a little larger than a character would
  // be at that size. A letter is one stroke and reads at any size. The gear
  // is a ring with teeth and a hole through it, and below about ten pixels
  // the hole fills in and the whole thing reads as a smudge.
  //
  // The floor is what does the work at the usual key sizes, where the icon
  // scale is capped. The fraction takes over once the keys are big enough
  // for it to matter. Neither may outgrow the label beside it, which is what the
  // cap is for: at the smallest key size the floor alone would have put an
  // eleven pixel gear next to a ten pixel mark, and a legend that big is no
  // longer a legend.
  KeyIcon {
    visible: key.hintIcon !== ""
    height: Math.min(key.labelPixelSize,
                     Math.max(11, Math.round(key.labelPixelSize * 0.64)))
    x: key.width - Math.round(key.theme.gap / 2 + key.cornerInset) - width - key.legendInset + key.legendShift
    y: key.faceY + Math.round(key.theme.gap / 2 + key.cornerInset / 2)
    name: key.hintIcon
    color: key.shineColor
    glowColor: key.legendGlow
    opacity: key.illuminated || key.transparentCap ? 1 : key.theme.hintOpacity
  }

  KeyIcon {
    visible: key.labelKind === "drawn"
    y: key.faceY + (key.legendHeight - height) / 2
    x: (key.width - width) / 2 + key.legendShift
    height: Math.round(key.labelPixelSize * 1.2)
    // Wider than tall for icons that ask for it, e.g. Enter's long arrow.
    width: Math.min(implicitWidth, key.width - key.theme.gap - 2 * key.legendInset)
    name: key.icon
    color: key.shineColor
    glowColor: key.legendGlow
    filled: key.kind === "locked"
  }
}
