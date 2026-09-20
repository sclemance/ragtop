import QtQuick
import QtQuick.Shapes

// An icon on a key, drawn rather than typed, so it never depends on the
// font having a glyph (Omarchy's font list includes fonts without Nerd Font
// icons) and it scales exactly with the key. Keyboard.qml names the icon;
// KeyboardKey.qml sizes and colours it.
//
// Coordinates are a 0..1 box, scaled to `unit`, so every icon keeps its
// proportions at any key size.
Item {
  id: icon

  // "settings", "shift", "backspace", "enter", "left", "up", "down", "right".
  property string name: ""
  property color color: "white"

  // Enter's arrow runs twice as wide as it is tall; the rest are square.
  readonly property real aspect: name === "enter" ? 2 : 1
  implicitWidth: height * aspect
  readonly property real unit: Math.min(width / aspect, height)
  // Filled rather than outlined, e.g. Shift while it's locked on.
  property bool filled: false

  readonly property real stroke: Math.max(1, unit * (name === "enter" ? 0.12 : 0.09))
  // The arrows are one shape; the key says which way it points.
  readonly property var arrowTurn: ({ "left": 0, "up": 90, "right": 180, "down": 270 })
  readonly property bool isArrow: name in arrowTurn

  // Named px/py: x and y would shadow the item's own position properties.
  function px(v) { return (width - unit * aspect) / 2 + v * unit * aspect }
  function py(v) { return (height - unit) / 2 + v * unit }
  function at(hx, vy) { return px(hx).toFixed(2) + " " + py(vy).toFixed(2) + " " }
  function move(hx, vy) { return "M " + at(hx, vy) }
  function line(hx, vy) { return "L " + at(hx, vy) }

  // A cog: square teeth around a ring, with a hole through the middle.
  function gearPath() {
    var cx = width / 2, cy = height / 2
    var teeth = 8, outer = unit * 0.48, inner = unit * 0.34, hole = unit * 0.15
    var step = Math.PI / (2 * teeth)  // four points per tooth
    var d = ""
    for (var k = 0; k < 4 * teeth; k++) {
      var r = (k % 4 < 2) ? outer : inner
      var a = k * step
      d += (k === 0 ? "M " : "L ") + (cx + r * Math.cos(a)).toFixed(2) + " " + (cy + r * Math.sin(a)).toFixed(2) + " "
    }
    d += "Z "
    // The hole, as its own subpath: with an odd-even fill it cuts through.
    d += "M " + (cx + hole).toFixed(2) + " " + cy.toFixed(2) + " "
    d += "A " + hole.toFixed(2) + " " + hole.toFixed(2) + " 0 1 0 " + (cx - hole).toFixed(2) + " " + cy.toFixed(2) + " "
    d += "A " + hole.toFixed(2) + " " + hole.toFixed(2) + " 0 1 0 " + (cx + hole).toFixed(2) + " " + cy.toFixed(2) + " Z"
    return d
  }

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

  // A plain arrow pointing left; `arrowTurn` turns it the other ways.
  function arrowPath() {
    return move(0.88, 0.5) + line(0.16, 0.5) + " " + move(0.42, 0.26) + line(0.16, 0.5) + line(0.42, 0.74)
  }

  readonly property string strokedPath: name === "shift" ? shiftPath()
    : name === "backspace" ? backspacePath()
    : name === "enter" ? enterPath()
    : isArrow ? arrowPath()
    : ""

  // The gear is a filled shape; the rest are drawn with strokes.
  Shape {
    anchors.fill: parent
    visible: icon.name === "settings"
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: icon.color
      fillRule: ShapePath.OddEvenFill
      strokeWidth: 0
      strokeColor: "transparent"
      PathSvg { path: icon.name === "settings" ? icon.gearPath() : "" }
    }
  }

  Shape {
    anchors.fill: parent
    visible: icon.strokedPath !== ""
    rotation: icon.isArrow ? icon.arrowTurn[icon.name] : 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      // Shift fills in when it's locked on; the open shapes stay outlines.
      fillColor: icon.filled && icon.name === "shift" ? icon.color : "transparent"
      strokeColor: icon.color
      strokeWidth: icon.stroke
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: icon.strokedPath }
    }
  }
}
