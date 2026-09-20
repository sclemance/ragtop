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

  readonly property string shape: theme.keyShape
  readonly property bool outlined: theme.keyFill === "outline"
  readonly property bool marked: kind === "accent" || kind === "locked" || kind === "latched"
  readonly property color fill: pressed ? theme.pressedKey
    : kind === "accent" || kind === "locked" ? theme.lockedKey
    : kind === "latched" ? theme.latchedKey
    : kind === "special" ? theme.specialKey
    : theme.key
  readonly property color labelColor: kind === "accent" || kind === "locked" ? theme.accentText
    : kind === "special" ? theme.specialText
    : theme.text

  // A raised key's face sits above its side and sinks into it when pressed.
  readonly property real depth: Math.min(theme.keyDepth, height / 4)
  // The face, where the label goes: the whole key but for a keycap's side.
  readonly property real faceY: pressed ? depth * 0.6 : 0
  readonly property real faceHeight: height - depth

  // Angular keys are drawn as a chamfered box; the same path serves the
  // face and the side, so a raised angular key keeps its cut corners.
  readonly property real chamfer: Math.min(theme.keyChamfer, width / 3, height / 3)
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
    border.width: key.theme.keyBorderWidth
    border.color: key.outlined ? key.theme.outline : key.theme.keyBorder
  }

  // Angular: the corners cut off.
  Shape {
    visible: key.shape === "angular"
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: key.fill
      strokeColor: key.outlined ? key.theme.outline : key.theme.keyBorder
      strokeWidth: key.theme.keyBorderWidth
      joinStyle: ShapePath.MiterJoin
      PathSvg { path: key.chamferPath(key.faceY, key.faceHeight) }
    }
  }

  // The label's size on Omarchy's scales, kept inside the key.
  readonly property int labelPixelSize: Math.min(
    labelKind === "icon" || labelKind === "drawn" ? theme.iconSize
      : labelKind === "word" ? theme.wordSize
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
    font.family: key.theme.fontFamily
    font.pixelSize: key.labelPixelSize
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
