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

  // Angular keys are drawn as a chamfered box; the same path serves the
  // face and the side, so a raised angular key keeps its cut corners.
  readonly property real chamfer: Math.min(theme.keyChamfer, width / 3, height / 3)

  // How far the corner eats into the face where the hint sits. A pill's
  // radius is half the key, so its corner is nowhere near the corner of the
  // box and a hint placed by the box alone ends up on the curve. Roughly the
  // horizontal reach of the arc where the hint's own line crosses it.
  readonly property real cornerInset: shape === "angular"
    ? chamfer * 0.5
    : (shape === "pill" ? faceHeight / 2 : theme.keyRadius) * 0.3
  function chamferPath(top, boxHeight) {
    var c = chamfer, w = width, bottom = top + boxHeight
    return "M " + c + " " + top + " L " + (w - c) + " " + top
      + " L " + w + " " + (top + c) + " L " + w + " " + (bottom - c)
      + " L " + (w - c) + " " + bottom + " L " + c + " " + bottom
      + " L 0 " + (bottom - c) + " L 0 " + (top + c) + " Z"
  }

  // A raised key's side, which only ever shows below the face: it starts
  // where the face does, so a pressed key shows nothing above it.
  Rectangle {
    visible: key.depth > 0 && key.shape !== "angular"
    y: key.faceY
    width: key.width
    height: key.height - key.faceY
    radius: key.shape === "pill" ? height / 2 : key.theme.keyRadius
    color: key.theme.keySide
  }

  Shape {
    visible: key.depth > 0 && key.shape === "angular"
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: key.theme.keySide
      strokeWidth: 0
      strokeColor: "transparent"
      PathSvg { path: key.chamferPath(key.faceY, key.height - key.faceY) }
    }
  }

  // The face, in every shape but Angular: a rectangle with its own corners.
  Rectangle {
    visible: key.shape !== "angular"
    y: key.faceY
    width: key.width
    height: key.faceHeight
    radius: key.shape === "pill" ? height / 2 : key.theme.keyRadius
    color: key.fill
    border.width: key.edgeWidth
    border.color: key.edgeColor
  }

  // Angular: the corners cut off.
  Shape {
    visible: key.shape === "angular"
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: key.fill
      strokeColor: key.edgeColor
      strokeWidth: key.edgeWidth
      joinStyle: ShapePath.MiterJoin
      PathSvg { path: key.chamferPath(key.faceY, key.faceHeight) }
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
    spacing: Math.max(3, Math.round(key.theme.gap / 2))

    KeyIcon {
      anchors.verticalCenter: parent.verticalCenter
      height: Math.round(key.labelPixelSize * 1.05)
      name: key.icon
      color: key.labelColor
      filled: key.kind === "locked"
    }
    Text {
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
