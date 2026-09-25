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

  // "settings", "shift", "backspace", "enter", "rotate", "keyboard",
  // "windows", "omarchy", "check", "float", "wide", "tiled", "split",
  // "left", "up", "down", "right".
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

  // Two arcs chasing each other round a circle, each ending in a head: the
  // rotation glyph. Drawn with SVG arcs rather than the straight-line
  // helpers, so the points are worked out here in the same 0..1 box.
  function rotatePath() {
    var r = 0.3
    function pt(deg) {
      var a = deg * Math.PI / 180
      return [0.5 + r * Math.cos(a), 0.5 - r * Math.sin(a)]
    }
    function arcTo(deg) {
      var p = pt(deg)
      return "A " + (r * unit).toFixed(2) + " " + (r * unit).toFixed(2) + " 0 0 1 " + at(p[0], p[1])
    }
    function head(deg, away) {
      // A short two-line head at the arc's end, turned to follow it.
      var p = pt(deg), a = deg * Math.PI / 180, w = 0.11
      var tx = Math.sin(a) * (away ? 1 : -1), ty = Math.cos(a) * (away ? 1 : -1)
      var nx = Math.cos(a), ny = -Math.sin(a)
      return move(p[0] + (tx + nx) * w, p[1] + (ty + ny) * w)
        + line(p[0], p[1])
        + line(p[0] + (tx - nx) * w, p[1] + (ty - ny) * w)
    }
    var top = pt(160), bottom = pt(340)
    return move(top[0], top[1]) + arcTo(20) + head(20, false)
      + move(bottom[0], bottom[1]) + arcTo(200) + head(200, false)
  }

  // A tick.
  // Omarchy's own square mark, the one in /usr/share/pixmaps/omarchy.png,
  // on the Super key the way a physical keyboard puts the system's logo
  // there. It is drawn rather than loaded for the same reason every other
  // icon here is: it needs no file on disk, it takes the key's colour, and
  // it is exact at any size. The mark is built entirely from blocks on a
  // 15 by 15 grid, so these thirteen rectangles are the whole of it, read
  // off the image rather than traced by eye.
  readonly property var omarchyRects: [
      [0, 0, 15, 1],
      [0, 1, 1, 14],
      [7, 1, 1, 2],
      [14, 1, 1, 14],
      [2, 2, 5, 1],
      [11, 2, 2, 1],
      [2, 3, 1, 10],
      [12, 3, 1, 10],
      [1, 7, 1, 1],
      [3, 12, 9, 1],
      [7, 13, 1, 2],
      [1, 14, 6, 1],
      [9, 14, 5, 1]
  ]
  function omarchyPath() {
    var path = ""
    for (var i = 0; i < icon.omarchyRects.length; i++) {
      var r = icon.omarchyRects[i]
      var x0 = r[0] / 15, y0 = r[1] / 15
      var x1 = (r[0] + r[2]) / 15, y1 = (r[1] + r[3]) / 15
      path += move(x0, y0) + line(x1, y0) + line(x1, y1) + line(x0, y1) + "Z "
    }
    return path
  }

  // A tiled layout: one pane on the left, two stacked on the right. It is
  // the shape of what tiling mode rearranges, which reads faster than
  // any word would at this size.
  function windowsPath() {
    return move(0.1, 0.22) + line(0.9, 0.22) + line(0.9, 0.78)
      + line(0.1, 0.78) + line(0.1, 0.22)
      + move(0.48, 0.22) + line(0.48, 0.78)
      + move(0.48, 0.5) + line(0.9, 0.5)
  }

  // A keyboard: the case, a row of keys and a space bar. At the size this is
  // drawn the keys are dots rather than squares, since anything with a shape
  // of its own turns to mush by 20 pixels.
  function keyboardPath() {
    var path = move(0.08, 0.28) + line(0.92, 0.28) + line(0.92, 0.72)
      + line(0.08, 0.72) + line(0.08, 0.28)
    var xs = [0.25, 0.42, 0.58, 0.75]
    for (var i = 0; i < xs.length; i++) {
      path += move(xs[i], 0.42) + line(xs[i] + 0.02, 0.42)
    }
    return path + move(0.34, 0.60) + line(0.66, 0.60)
  }

  function checkPath() {
    return move(0.2, 0.52) + line(0.42, 0.74) + line(0.8, 0.28)
  }

  // A plain arrow pointing left; `arrowTurn` turns it the other ways.
  function arrowPath() {
    return move(0.88, 0.5) + line(0.16, 0.5) + " " + move(0.42, 0.26) + line(0.16, 0.5) + line(0.42, 0.74)
  }

  // A floating window: one pane lifted off another. The standard windowed
  // mark, so it reads without a label beside it.
  function floatPath() {
    return move(0.34, 0.16) + line(0.9, 0.16) + line(0.9, 0.62)
      + move(0.1, 0.38) + line(0.66, 0.38) + line(0.66, 0.84)
      + line(0.1, 0.84) + line(0.1, 0.38)
  }

  // Full width: a pane with the sides pushed out to the edges it is going
  // to reach.
  function widePath() {
    return move(0.26, 0.24) + line(0.74, 0.24) + line(0.74, 0.76)
      + line(0.26, 0.76) + line(0.26, 0.24)
      + move(0.16, 0.5) + line(0.02, 0.5)
      + move(0.07, 0.42) + line(0.02, 0.5) + line(0.07, 0.58)
      + move(0.84, 0.5) + line(0.98, 0.5)
      + move(0.93, 0.42) + line(0.98, 0.5) + line(0.93, 0.58)
  }

  // Tiled full screen: four corners opening outwards, which is what a
  // full-screen mark looks like everywhere else.
  function tiledPath() {
    return move(0.1, 0.34) + line(0.1, 0.1) + line(0.34, 0.1)
      + move(0.66, 0.1) + line(0.9, 0.1) + line(0.9, 0.34)
      + move(0.9, 0.66) + line(0.9, 0.9) + line(0.66, 0.9)
      + move(0.34, 0.9) + line(0.1, 0.9) + line(0.1, 0.66)
  }

  // Split: one pane divided, with the divider turned, which is what the
  // toggle does to the next window opened beside this one.
  function splitPath() {
    return move(0.1, 0.16) + line(0.9, 0.16) + line(0.9, 0.84)
      + line(0.1, 0.84) + line(0.1, 0.16)
      + move(0.5, 0.16) + line(0.5, 0.84)
      + move(0.34, 0.5) + line(0.2, 0.5)
      + move(0.66, 0.5) + line(0.8, 0.5)
  }

  readonly property string strokedPath: name === "shift" ? shiftPath()
    : name === "backspace" ? backspacePath()
    : name === "enter" ? enterPath()
    : name === "rotate" ? rotatePath()
    : name === "keyboard" ? keyboardPath()
    : name === "windows" ? windowsPath()
    : name === "check" ? checkPath()
    : name === "float" ? floatPath()
    : name === "wide" ? widePath()
    : name === "tiled" ? tiledPath()
    : name === "split" ? splitPath()
    : isArrow ? arrowPath()
    : ""

  // The gear and Omarchy's mark are filled shapes; the rest are strokes.
  readonly property string filledPath: name === "settings" ? gearPath()
    : name === "omarchy" ? omarchyPath() : ""

  Shape {
    anchors.fill: parent
    visible: icon.filledPath !== ""
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: icon.color
      fillRule: ShapePath.OddEvenFill
      strokeWidth: 0
      strokeColor: "transparent"
      PathSvg { path: icon.filledPath }
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
