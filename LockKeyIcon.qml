import QtQuick
import QtQuick.Shapes

// An icon on a lock screen key, drawn rather than typed, so it doesn't
// depend on the font carrying a glyph and scales exactly with the key.
//
// Deliberately its own copy of the desktop keyboard's KeyIcon.qml, as the
// lock screen keyboard is: it draws only the three keys that screen has
// (Shift, Backspace, Enter), and nothing added to the desktop keyboard's
// icons reaches the lock screen unless it's added here too.
//
// Coordinates are a 0..1 box, scaled to `unit`, so every icon keeps its
// proportions at any key size.
Item {
  id: icon

  // "shift", "backspace" or "enter".
  property string name: ""
  property color color: "white"
  // Filled rather than outlined: Shift while Caps is locked on.
  property bool filled: false

  // Enter's arrow runs twice as wide as it is tall; the rest are square.
  readonly property real aspect: name === "enter" ? 2 : 1
  implicitWidth: height * aspect
  readonly property real unit: Math.min(width / aspect, height)
  readonly property real stroke: Math.max(1, unit * (name === "enter" ? 0.12 : 0.09))

  // Named px/py: x and y would shadow the item's own position properties.
  function px(v) { return (width - unit * aspect) / 2 + v * unit * aspect }
  function py(v) { return (height - unit) / 2 + v * unit }
  function at(hx, vy) { return px(hx).toFixed(2) + " " + py(vy).toFixed(2) + " " }
  function move(hx, vy) { return "M " + at(hx, vy) }
  function line(hx, vy) { return "L " + at(hx, vy) }

  // A hollow arrow pointing up, as a shift key has.
  function shiftPath() {
    return move(0.5, 0.12) + line(0.88, 0.5) + line(0.68, 0.5) + line(0.68, 0.86)
      + line(0.32, 0.86) + line(0.32, 0.5) + line(0.12, 0.5) + "Z"
  }

  // The backspace key's arrow-headed box, with a cross inside.
  function backspacePath() {
    return move(0.34, 0.2) + line(0.9, 0.2) + line(0.9, 0.8) + line(0.34, 0.8) + line(0.1, 0.5) + "Z "
      + move(0.48, 0.38) + line(0.72, 0.62) + move(0.72, 0.38) + line(0.48, 0.62)
  }

  // The return arrow: down the right, then a long run left into an
  // arrowhead. The head's arms are kept square, not stretched by `aspect`.
  function enterPath() {
    var tip = 0.12, arm = 0.18 / aspect
    return move(0.9, 0.14) + line(0.9, 0.62) + line(tip, 0.62) + " "
      + move(tip + arm, 0.44) + line(tip, 0.62) + line(tip + arm, 0.8)
  }

  readonly property string strokedPath: name === "shift" ? shiftPath()
    : name === "backspace" ? backspacePath()
    : name === "enter" ? enterPath()
    : ""

  Shape {
    anchors.fill: parent
    visible: icon.strokedPath !== ""
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      // Shift fills in when Caps is locked; the open shapes stay outlines.
      fillColor: icon.filled && icon.name === "shift" ? icon.color : "transparent"
      strokeColor: icon.color
      strokeWidth: icon.stroke
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: icon.strokedPath }
    }
  }
}
