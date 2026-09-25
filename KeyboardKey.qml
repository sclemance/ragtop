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
  property string labelKind: "char"
  // The drawn icon's name, for labelKind "drawn" (see KeyIcon.qml).
  property string icon: ""
  property bool pressed: false
  // A second character printed small in a corner, the way a keycap prints
  // what AltGr types on it. Empty on a key that has nothing there.
  property string hint: ""
  // Draw the fill at full strength whatever Key Transparency says. The
  // setting is there to let the desktop show through the keyboard; behind a
  // key in a long-press popup is the popup's own panel, so being see-through
  // there would only muddy the letter.
  property bool opaque: false

  readonly property string shape: theme.keyShape
  readonly property bool outlined: theme.keyFill === "outline"
  readonly property color tinted: pressed ? theme.pressedKey
    : kind === "locked" ? theme.lockedKey
    : kind === "latched" ? theme.latchedKey
    : kind === "special" || kind === "accent" ? theme.specialKey
    : theme.key
  readonly property color fill: opaque && tinted.a > 0
    ? Qt.rgba(tinted.r, tinted.g, tinted.b, 1) : tinted
  readonly property color labelColor: kind === "locked" ? theme.accentText
    : kind === "accent" ? theme.accent
    : kind === "special" ? theme.specialText
    : theme.text

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

  // Which corner is drawn how, clockwise from the top left. A shape name
  // is only ever shorthand for one of these sets, so there is no shape to
  // special-case here: either all four are round, which a rectangle draws,
  // or the outline below does it.
  readonly property var corners: theme.keyCorners
  readonly property bool boxy: theme.cornersAllRound
  readonly property real chamfer: Math.min(theme.keyChamfer, width / 3, height / 3)

  // How far the corner eats into the face where the hint sits, which is the
  // top right one. A pill's radius is half the key, so its corner is nowhere
  // near the corner of the box and a hint placed by the box alone ends up on
  // the curve. Roughly the horizontal reach of the arc where the hint's own
  // line crosses it.
  readonly property real cornerInset: corners[1] === "cut"
    ? chamfer * 0.5
    : corners[1] === "square" ? 0
    : (shape === "pill" ? faceHeight / 2 : theme.keyRadius) * 0.3

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

  // A raised key's side, which only ever shows below the face: it starts
  // where the face does, so a pressed key shows nothing above it.
  Rectangle {
    visible: key.depth > 0 && key.boxy
    y: key.faceY
    width: key.width
    height: key.height - key.faceY
    radius: key.shape === "pill" ? height / 2 : key.theme.keyRadius
    color: key.theme.keySide
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
    visible: key.boxy
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

  // The label's size on Omarchy's scales, kept inside the key.
  readonly property int labelPixelSize: Math.min(
    labelKind === "icon" || labelKind === "drawn" ? theme.iconSize
      : labelKind === "word" || labelKind === "markword" ? theme.wordSize
      : theme.labelSize,
    Math.round(faceHeight * 0.62))

  // A glyph goes through Omarchy's own glyph renderer, which corrects the
  // centring of icon glyphs; plain text doesn't need it.
  OpticalGlyph {
    visible: key.labelKind === "icon"
    y: key.faceY
    width: key.width
    height: key.faceHeight
    text: key.labelKind === "icon" ? key.label : ""
    color: key.labelColor
    fontFamily: key.theme.fontFamily
    fontSize: key.labelPixelSize
  }

  Text {
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
    visible: key.labelKind === "char" || key.labelKind === "word"
    y: key.faceY
    width: key.width
    height: key.faceHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: key.label
    color: key.labelColor
    elide: Text.ElideRight
    font.family: key.theme.fontFamily
    font.pixelSize: key.labelPixelSize
  }

  Text {
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
    visible: key.hint !== ""
    y: key.faceY + Math.round(key.theme.gap / 2 + key.cornerInset / 2)
    width: key.width - Math.round(key.theme.gap / 2 + key.cornerInset)
    horizontalAlignment: Text.AlignRight
    text: key.hint
    color: key.labelColor
    // Quieter than the label it sits beside: it says what the key can also
    // do, and should not compete with what it does now.
    opacity: 0.5
    font.family: key.theme.fontFamily
    font.pixelSize: Math.max(9, Math.round(key.labelPixelSize * 0.52))
  }

  // A mark and its name together, for a key whose symbol nobody has on
  // their hardware to learn it from. The pair is centred as one thing, so
  // the key still reads as a single label rather than two.
  Row {
    visible: key.labelKind === "markword"
    y: key.faceY
    height: key.faceHeight
    x: Math.max(0, (key.width - implicitWidth) / 2)
    spacing: Math.max(7, key.theme.gap)

    KeyIcon {
      anchors.verticalCenter: parent.verticalCenter
      height: Math.round(key.labelPixelSize * 1.05)
      name: key.icon
      color: key.labelColor
      filled: key.kind === "locked"
    }
    Text {
      // Never rich text. A window title, a layout name and an error
      // string all arrive from outside, and AutoText would sniff markup
      // in them and render it, which for Qt includes fetching a remote
      // image named in an img tag.
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: key.label
      color: key.labelColor
      font.family: key.theme.fontFamily
      font.pixelSize: key.labelPixelSize
    }
  }

  KeyIcon {
    visible: key.labelKind === "drawn"
    y: key.faceY + (key.faceHeight - height) / 2
    x: (key.width - width) / 2
    height: Math.round(key.labelPixelSize * 1.2)
    // Wider than tall for icons that ask for it, e.g. Enter's long arrow.
    width: Math.min(implicitWidth, key.width - key.theme.gap)
    name: key.icon
    color: key.labelColor
    filled: key.kind === "locked"
  }
}
