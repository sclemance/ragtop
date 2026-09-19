import QtQuick
import QtQuick.Shapes

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
  property bool pressed: false

  readonly property string shape: theme.keyShape
  readonly property bool marked: kind === "accent" || kind === "locked" || kind === "latched"
  readonly property color fill: pressed ? theme.pressedKey
    : kind === "accent" || kind === "locked" ? theme.lockedKey
    : kind === "latched" ? theme.latchedKey
    : kind === "special" ? theme.specialKey
    : theme.key
  readonly property color labelColor: kind === "accent" || kind === "locked" ? theme.accentText : theme.text

  // Keycap: the face sits above the key's side and sinks when pressed.
  readonly property real depth: shape === "keycap" ? Math.min(theme.keyDepth, height / 4) : 0
  // The face, where the label goes: the whole key but for a keycap's side.
  readonly property real faceY: pressed ? depth * 0.6 : 0
  readonly property real faceHeight: height - depth

  // Keycap: the key's side, showing below the face.
  Rectangle {
    visible: key.shape === "keycap"
    anchors.fill: parent
    radius: key.theme.keyRadius
    color: Qt.darker(key.fill, 1.6)
  }

  // Every shape but Angular: a rectangle with its own corners and fill.
  Rectangle {
    visible: key.shape !== "angular"
    y: key.faceY
    width: key.width
    height: key.faceHeight
    radius: key.shape === "rectangle" ? 0
      : key.shape === "pill" ? height / 2
      : key.theme.keyRadius
    // Outline keys are just their edges unless pressed or marked.
    color: key.shape === "outline" && !key.pressed && !key.marked ? "transparent" : key.fill
    border.width: key.theme.keyBorderWidth
    border.color: key.shape === "outline" ? key.theme.outline : key.theme.keyBorder
  }

  // Angular: the corners cut off.
  Shape {
    id: angular
    visible: key.shape === "angular"
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    readonly property real c: Math.min(key.theme.keyChamfer, key.width / 3, key.height / 3)

    ShapePath {
      fillColor: key.fill
      strokeColor: key.theme.keyBorder
      strokeWidth: key.theme.keyBorderWidth
      joinStyle: ShapePath.MiterJoin
      PathPolyline {
        path: [
          Qt.point(angular.c, 0), Qt.point(key.width - angular.c, 0),
          Qt.point(key.width, angular.c), Qt.point(key.width, key.height - angular.c),
          Qt.point(key.width - angular.c, key.height), Qt.point(angular.c, key.height),
          Qt.point(0, key.height - angular.c), Qt.point(0, angular.c), Qt.point(angular.c, 0)
        ]
      }
    }
  }

  Text {
    y: key.faceY
    width: key.width
    height: key.faceHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: key.label
    color: key.labelColor
    font.family: key.theme.fontFamily
    // Short labels (a letter, an arrow) larger than words like "Esc".
    font.pixelSize: Math.round(Math.min(key.faceHeight * 0.42, 26) * key.theme.labelScale
      * (text.length > 1 ? 0.75 : key.theme.fontScale))
  }
}
