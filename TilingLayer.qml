import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// The inside of tiling mode: an outline around every window on the
// workspace, and a way out.
//
// Nothing here is drawn solid. The reason to do this over the real windows
// rather than over a scaled map of them is that their content stays visible
// and reflows while you work, and you cannot judge whether a split is right
// for a terminal through a panel sitting on top of it. So: a border, a small
// name in a corner, and otherwise the desktop as it is.
//
// Phase one shows where the windows are and gets out of the way again.
// Dragging comes later.
Item {
  // Not `layer`: every Item already has one of those, as a grouped property
  // for render effects, and an id of that name is silently shadowed by it.
  // Every reference here read as undefined and the borders fell back to a
  // hairline while the name chips vanished altogether.
  id: surface

  // Service.qml
  required property var service
  // [{ address, x, y, w, h, name, floating }] in this surface's coordinates.
  required property var windows

  readonly property int edge: Math.max(2, Style.space(2))
  readonly property int chipPad: Style.space(6)
  // Long enough that a tap is not mistaken for a hold, short enough that
  // holding does not feel like waiting. The keyboard uses 420 for its
  // accents, which have a popup to justify the pause; this only has to say
  // "picked up".
  readonly property int holdMs: 280
  // One number for the shrink and the ghost, so what you pick up and what
  // you carry are the same size.
  readonly property real liftScale: 0.94
  // Below this there is no room for an edge between two corners, so the
  // corners have that side to themselves.
  readonly property int edgeMin: Style.space(24)
  readonly property int tapSlop: Style.space(16)

  // What the window is masked to: the only part of the screen this takes
  // touches on. Everything outside falls through to whatever is underneath,
  // so the bar and the keyboard's handle stay usable while this is up,
  // without depending on layer ordering to arrange that.
  //
  // It is the windows and the way out, and nothing else. One rectangle
  // around both rather than a region per window: the tiles already cover
  // that area between them, and a single shape cannot end up with a seam
  // down the middle of it that swallows a tap.
  readonly property Item touchArea: activeArea

  // A drag in progress: the window it started on, and the one the finger is
  // over now. Both are addresses, empty when nothing is being dragged.
  property string dragFrom: ""
  property string dragOver: ""

  // Where the finger is while carrying something, so the ghost can follow
  // it. Negative until a drag starts.
  property real dragX: -1
  property real dragY: -1

  function windowByAddress(address) {
    for (var i = 0; i < surface.windows.length; i++) {
      if (surface.windows[i].address === address) return surface.windows[i]
    }
    return null
  }

  // The tile across a given edge, if there is one. Tiles are separated by
  // the layout's gap, so "touching" allows for it.
  function neighbour(w, side) {
    var slack = Style.space(40)
    for (var i = 0; i < surface.windows.length; i++) {
      var o = surface.windows[i]
      if (o.address === w.address || o.floating) continue
      if (side === "r" && Math.abs(o.x - (w.x + w.w)) <= slack
          && o.y < w.y + w.h && o.y + o.h > w.y) return o
      if (side === "b" && Math.abs(o.y - (w.y + w.h)) <= slack
          && o.x < w.x + w.w && o.x + o.w > w.x) return o
    }
    return null
  }

  // Which window to name so that the boundary you grabbed is the one that
  // moves. Measured: a relative resize moves the split on the named
  // window's LEFT (or above it), falling back to the other side when there
  // is none. So a left or top edge names the tile itself, and a right or
  // bottom edge names its neighbour, which has that same boundary on its
  // left or above it.
  function resizeTarget(w, edge) {
    if (edge === -1) return w.address
    var o = surface.neighbour(w, edge === 1 ? "r" : "b")
    return o ? o.address : ""
  }

  // How the screen stacks a window, high on top. Floating always sits over
  // tiled, and focus only orders within its own class.
  //
  // Focus must not lift a tile over a floating window. It reads like the
  // obvious rule and it deadlocks: the tap resolves to the focused tile,
  // so the floating window over it never gains focus, so it never outranks
  // the tile, so it can never be selected at all. A floating window fully
  // inside a focused tile was unreachable.
  function stackRank(w) {
    return (w.floating ? 2 : 0) + (w.focused ? 1 : 0)
  }

  // Which window a point belongs to, in the order they are stacked rather
  // than the order they are listed. A floating window sits over the tiles
  // on screen, so a tap inside it means that window and not the tile it
  // happens to cover.
  //
  // Handlers here take no exclusive grab, so every frame under the touch is
  // offered the point and each one asks this whether it is the one meant.
  // That makes this the only thing deciding what a tap selects, and it has
  // to agree with what is drawn on top or a window becomes untappable.
  //
  // Ties go to the smaller window, which only two floating windows can
  // reach because tiles do not overlap. It is the one more likely to be on
  // top and meant, and being independent of focus it cannot deadlock the
  // way ranking by focus did.
  function windowAt(px, py) {
    var best = "", bestRank = -1, bestArea = Infinity
    for (var i = 0; i < surface.windows.length; i++) {
      var w = surface.windows[i]
      if (px < w.x || px >= w.x + w.w || py < w.y || py >= w.y + w.h) continue
      var rank = surface.stackRank(w)
      var area = w.w * w.h
      if (rank > bestRank || (rank === bestRank && area < bestArea)) {
        bestRank = rank
        bestArea = area
        best = w.address
      }
    }
    return best
  }

  readonly property rect windowBounds: {
    if (surface.windows.length === 0) return Qt.rect(0, 0, 0, 0)
    var l = Infinity, t = Infinity, r = -Infinity, b = -Infinity
    for (var i = 0; i < surface.windows.length; i++) {
      var w = surface.windows[i]
      l = Math.min(l, w.x)
      t = Math.min(t, w.y)
      r = Math.max(r, w.x + w.w)
      b = Math.max(b, w.y + w.h)
    }
    return Qt.rect(l, t, r - l, b - t)
  }

  // Not `left` and `top` for these: every Item already has those as final
  // anchor lines and QML refuses to shadow them, which takes the whole
  // service down with it. The same trap as naming an id `layer`.
  // Just the windows now. With nothing else on this layer to touch, an
  // empty workspace means an empty mask, and the handle below is the way
  // out either way.
  Item {
    id: activeArea
    visible: false
    x: surface.windowBounds.x
    y: surface.windowBounds.y
    width: surface.windowBounds.width
    height: surface.windowBounds.height
  }

  // A label on its own background, so it stays readable over whatever the
  // window happens to be showing behind it. The text is measured first and
  // the chip is sized from it, never the other way round.
  component Chip: Rectangle {
    property alias text: chipText.text
    property real maxWidth: 200

    width: chipText.width + surface.chipPad * 2
    height: chipText.implicitHeight + surface.chipPad
    radius: Style.cornerRadius
    // The fill carries the transparency rather than the whole chip, so the
    // border and the text stay solid and the panel reads as an object
    // sitting on the window instead of a smudge over it.
    color: Util.alpha(Color.popups.background, 0.88)
    border.width: Math.max(1, Style.space(1))
    border.color: Color.popups.border
    visible: chipText.text !== ""

    Text {
      id: chipText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, Math.max(0, parent.maxWidth))
      elide: Text.ElideRight
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Rows are updated in place, never replaced. Assigning a fresh array to a
  // Repeater rebuilds every delegate, which destroys the handle a finger is
  // in the middle of dragging: the grab is lost, the drag's reference point
  // resets, and what is left is a few tiny jumps in whichever direction the
  // noise went. Measured at three rebuilds in one short drag.
  ListModel { id: windowModel }

  function syncWindows() {
    var ws = surface.windows
    var i
    if (windowModel.count !== ws.length) {
      windowModel.clear()
      for (i = 0; i < ws.length; i++) windowModel.append(ws[i])
      return
    }
    for (i = 0; i < ws.length; i++) {
      if (windowModel.get(i).address !== ws[i].address) {
        windowModel.clear()
        for (var j = 0; j < ws.length; j++) windowModel.append(ws[j])
        return
      }
    }
    for (i = 0; i < ws.length; i++) {
      var row = windowModel.get(i)
      if (row.x !== ws[i].x) windowModel.setProperty(i, "x", ws[i].x)
      if (row.y !== ws[i].y) windowModel.setProperty(i, "y", ws[i].y)
      if (row.w !== ws[i].w) windowModel.setProperty(i, "w", ws[i].w)
      if (row.h !== ws[i].h) windowModel.setProperty(i, "h", ws[i].h)
      if (row.name !== ws[i].name) windowModel.setProperty(i, "name", ws[i].name)
      if (row.floating !== ws[i].floating) windowModel.setProperty(i, "floating", ws[i].floating)
      if (row.focused !== ws[i].focused) windowModel.setProperty(i, "focused", ws[i].focused)
    }
  }
  onWindowsChanged: surface.syncWindows()
  Component.onCompleted: surface.syncWindows()

  Repeater {
    model: windowModel

    Item {
      id: frame
      // `model`, not the roles themselves: a role called x would otherwise
      // collide with the Item's own x.
      required property var model
      x: model.x
      y: model.y
      width: model.w
      height: model.h
      // Stacked the way the screen stacks them, so an outline and its
      // handles are never underneath another window's. The same ranking
      // that decides what a tap selects, from the one function, because
      // when these two disagreed the window drawn on top was not the one
      // being tapped.
      z: surface.stackRank(model)

      // Picked up: a tile's outline stops being drawn here, because it is
      // the thing now under the finger. One object, one place, rather than
      // an after-image left behind to be explained.
      //
      // A floating window needs none of that. It goes where you put it, so
      // its outline simply travels with it and the ghost would be a second
      // copy of something already moving.
      readonly property bool lifted: surface.dragFrom === model.address
      visible: !(lifted && !model.floating)

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Style.cornerRadius
        // The focused one is drawn heavier rather than in another colour,
        // so floating still reads as floating whether or not it has focus.
        border.width: frame.dropTarget || frame.model.focused
          ? surface.edge * 2 : surface.edge
        border.color: frame.model.floating ? Color.urgent : Color.accent
        opacity: frame.dropTarget || frame.model.focused ? 1 : 0.65
      }

      // Where this one would land. A wash rather than a fill: you are
      // dropping onto a window, and you should still be able to see which.
      readonly property bool dropTarget: surface.dragFrom !== ""
        && surface.dragOver === model.address
        && surface.dragOver !== surface.dragFrom
      Rectangle {
        anchors.fill: parent
        anchors.margins: surface.edge
        radius: Style.cornerRadius
        visible: frame.dropTarget
        color: Util.alpha(Color.accent, 0.16)
      }

      // A tap focuses, a hold picks up. Waiting for movement to decide meant
      // nothing happened until the finger had already travelled, so the
      // pickup arrived late and felt like a miss. Holding says what you
      // meant before you have moved at all, which is what the keyboard's
      // own hold does for the accents.
      //
      // A PointHandler rather than a DragHandler and a TapHandler together:
      // it reports the finger without taking an exclusive grab, so press,
      // move and release all arrive here in one place and in order.
      // Where this window can be resized from: a square in each corner for
      // both axes at once, and a bar between them for that edge alone. On a
      // tiled window an edge says exactly which split is moving, which is
      // the part a finger cannot otherwise express without a cursor.
      //
      // ex and ey name the edge this handle moves: -1 left or top, 1 right
      // or bottom, 0 not live on that axis.
      // Measured: resizing a tiled window by +100 moved the split between
      // it and its neighbour 100 to the right, whichever of the two was
      // named. So a relative resize means "move my split that way", not
      // "make me bigger", and the delta is simply where the finger went.
      // A per-handle sign was the first attempt and it inverted every edge
      // on one side of the screen.
      // Full size for as long as the tile can hold it, and only then
      // smaller. Sizing these as a fraction of the tile made them shrink
      // long before they had to, so the only thing that takes them below
      // the maximum is not fitting: two corners plus a little can never be
      // wider than the side they sit on.
      readonly property int hs: Math.max(32, Math.min(96,
        width / 2.4, height / 2.4))
      readonly property real eb: Math.max(14, hs * 0.42)
      readonly property bool wideEnough: width - 2 * hs >= surface.edgeMin
      readonly property bool tallEnough: height - 2 * hs >= surface.edgeMin
      readonly property bool showHandles: model.focused && surface.dragFrom === ""
      // A function of the index, not an array. An array property rebuilt on
      // every width change hands the Repeater a new model, which rebuilds
      // every delegate, which destroys the DragHandler the finger is
      // holding. That is the same fault as the window list one level up,
      // and it is why a resize drag died after a step or two. The Repeater's
      // model is the number 8 and never changes; the geometry inside each
      // delegate re-evaluates in place.
      function handleSpec(i) {
        switch (i) {
        case 0: return { hx: 0, hy: 0, hw: hs, hh: hs, ex: -1, ey: -1, on: true }
        case 1: return { hx: width - hs, hy: 0, hw: hs, hh: hs, ex: 1, ey: -1, on: true }
        case 2: return { hx: 0, hy: height - hs, hw: hs, hh: hs, ex: -1, ey: 1, on: true }
        case 3: return { hx: width - hs, hy: height - hs, hw: hs, hh: hs, ex: 1, ey: 1, on: true }
        case 4: return { hx: hs, hy: 0, hw: width - 2 * hs, hh: eb, ex: 0, ey: -1, on: wideEnough }
        case 5: return { hx: hs, hy: height - eb, hw: width - 2 * hs, hh: eb, ex: 0, ey: 1, on: wideEnough }
        case 6: return { hx: 0, hy: hs, hw: eb, hh: height - 2 * hs, ex: -1, ey: 0, on: tallEnough }
        default: return { hx: width - eb, hy: hs, hw: eb, hh: height - 2 * hs, ex: 1, ey: 0, on: tallEnough }
        }
      }

      // A press that lands on a handle belongs to the handle. Both handlers
      // see the same finger, since neither takes an exclusive grab, so the
      // body has to stand aside rather than be told to.
      function onHandle(lx, ly) {
        if (!showHandles) return false
        for (var i = 0; i < 8; i++) {
          var h = handleSpec(i)
          if (!h.on) continue
          if (lx >= h.hx && lx < h.hx + h.hw && ly >= h.hy && ly < h.hy + h.hh) return true
        }
        return false
      }

      Repeater {
        model: 8
        Rectangle {
          id: handle
          required property int index
          readonly property var spec: frame.handleSpec(index)
          visible: frame.showHandles && spec.on
          x: spec.hx
          y: spec.hy
          width: spec.hw
          height: spec.hh
          // Rounded on the corner squares, sharp on the edge bars. A bar
          // stands for the whole split it moves, and a rounded end reads as
          // a thing with a length of its own rather than as the edge it is.
          // Specs 0 to 3 are the corners, 4 to 7 the bars.
          radius: index < 4 ? Style.space(3) : 0
          // The corner facing into the window is rounded harder than the
          // three sitting against its edges, so a square reads as tucked
          // into the corner rather than stuck onto it. It is the one
          // diagonally opposite the window corner the square occupies, so
          // 0 is top left and wants its bottom right, and so on round.
          // The bars have no inside corner and keep radius, which is 0.
          readonly property real inner: Style.space(9)
          topLeftRadius: index === 3 ? inner : radius
          topRightRadius: index === 2 ? inner : radius
          bottomLeftRadius: index === 1 ? inner : radius
          bottomRightRadius: index === 0 ? inner : radius
          color: grip.active ? Color.accent : Util.alpha(Color.accent, 0.55)

          // A double headed arrow across the corner, saying which way this
          // one drags before you touch it. Both heads because both
          // directions are live: on a tiled window a corner moves two
          // splits, either way.
          //
          // Corners only. A bar is long and thin and its arrow would have
          // to point across the thin axis, which does not survive a small
          // tile, and by the time you have read one corner the bars explain
          // themselves.
          //
          // Opposite corners share an axis, so there are two shapes rather
          // than four: 0 and 3 run top left to bottom right, 1 and 2 the
          // other way. `parent` does not resolve inside a ShapePath, hence
          // the id above.
          //
          // No handlers on any of this. It is drawn inside the grip and
          // must never take a point away from it.
          function arrowPath() {
            var w = handle.width, h = handle.height
            var m = Math.min(w, h) * 0.28, b = Math.min(w, h) * 0.2
            var down = handle.index === 0 || handle.index === 3
            var x1 = down ? m : w - m, y1 = m
            var x2 = down ? w - m : m, y2 = h - m
            var dx = down ? 1 : -1
            return "M " + x1 + " " + y1 + " L " + x2 + " " + y2
              + " M " + x1 + " " + y1 + " L " + (x1 + b * dx) + " " + y1
              + " M " + x1 + " " + y1 + " L " + x1 + " " + (y1 + b)
              + " M " + x2 + " " + y2 + " L " + (x2 - b * dx) + " " + y2
              + " M " + x2 + " " + y2 + " L " + x2 + " " + (y2 - b)
          }

          Shape {
            anchors.fill: parent
            visible: handle.index < 4
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              strokeColor: Color.background
              strokeWidth: Math.max(2, Math.min(handle.width, handle.height) * 0.09)
              fillColor: "transparent"
              capStyle: ShapePath.RoundCap
              joinStyle: ShapePath.RoundJoin
              PathSvg { path: handle.arrowPath() }
            }
          }

          // DragHandler, not PointHandler: the handle moves as the window
          // resizes, and a PointHandler stops the moment its own item is no
          // longer under the finger. One small step and the grab was gone.
          // A DragHandler keeps the point until it is released.
          DragHandler {
            id: grip
            target: null
            property real lastX: 0
            property real lastY: 0
            // A floating window is dragged against where it started, not
            // step by step, so rounding cannot accumulate over a long drag.
            property real startX: 0
            property real startY: 0
            property var startRect: null

            onActiveChanged: {
              if (!active) return
              grip.lastX = centroid.scenePosition.x
              grip.lastY = centroid.scenePosition.y
              grip.startX = grip.lastX
              grip.startY = grip.lastY
              var w0 = surface.windowByAddress(frame.model.address)
              grip.startRect = w0 && w0.floating
                ? { x: w0.x, y: w0.y, w: w0.w, h: w0.h } : null
            }
            onCentroidChanged: {
              if (!active) return
              var nx = centroid.scenePosition.x
              var ny = centroid.scenePosition.y
              var w = surface.windowByAddress(frame.model.address)
              if (grip.startRect) {
                // Floating: move the grabbed edge and leave the other
                // three where they are.
                var r = grip.startRect
                var tdx = nx - grip.startX
                var tdy = ny - grip.startY
                var x0 = r.x, y0 = r.y, x1 = r.x + r.w, y1 = r.y + r.h
                if (parent.spec.ex === -1) x0 += tdx
                else if (parent.spec.ex === 1) x1 += tdx
                if (parent.spec.ey === -1) y0 += tdy
                else if (parent.spec.ey === 1) y1 += tdy
                var minw = Style.space(120), minh = Style.space(80)
                if (x1 - x0 < minw) { if (parent.spec.ex === -1) x0 = x1 - minw; else x1 = x0 + minw }
                if (y1 - y0 < minh) { if (parent.spec.ey === -1) y0 = y1 - minh; else y1 = y0 + minh }
                surface.service.setWindowGeom(frame.model.address, x0, y0, x1 - x0, y1 - y0)
                grip.lastX = nx
                grip.lastY = ny
                return
              }
              if (w) {
                // Each axis is dispatched on whichever tile owns that
                // boundary, so a corner can name two different windows.
                var dx = nx - grip.lastX
                var dy = ny - grip.lastY
                if (parent.spec.ex !== 0 && dx !== 0) {
                  var tx = surface.resizeTarget(w, parent.spec.ex)
                  if (tx !== "") surface.service.resizeWindow(tx, dx, 0)
                }
                if (parent.spec.ey !== 0 && dy !== 0) {
                  var ty = surface.resizeTarget(w, parent.spec.ey)
                  if (ty !== "") surface.service.resizeWindow(ty, 0, dy)
                }
              }
              grip.lastX = nx
              grip.lastY = ny
            }
          }
        }
      }

      PointHandler {
        id: finger
        property real downX: 0
        property real downY: 0
        property bool ignoring: false
        property var startRect: null

        onActiveChanged: {
          if (active) {
            finger.downX = point.scenePosition.x
            finger.downY = point.scenePosition.y
            // A handle's finger is not the body's finger.
            //
            // Nor is a finger that belongs to a window stacked above this
            // one. Handlers here take no exclusive grab, so every frame
            // under the touch sees it, and without this a floating window
            // being resized also dragged the tile behind it.
            if (frame.onHandle(point.position.x, point.position.y)
                || surface.windowAt(point.scenePosition.x,
                                    point.scenePosition.y) !== frame.model.address) {
              finger.ignoring = true
              return
            }
            finger.ignoring = false
            var w0 = surface.windowByAddress(frame.model.address)
            finger.startRect = w0 && w0.floating
              ? { x: w0.x, y: w0.y, w: w0.w, h: w0.h } : null
            liftTimer.restart()
            return
          }
          if (finger.ignoring) return
          liftTimer.stop()
          if (surface.dragFrom === frame.model.address) {
            var to = finger.startRect ? "" : surface.dragOver
            var from = surface.dragFrom
            surface.dragFrom = ""
            surface.dragOver = ""
            surface.dragX = -1
            surface.dragY = -1
            if (to !== "" && to !== from) surface.service.swapWindows(from, to)
            return
          }
          // Never picked up, and the finger stayed put: that was a tap.
          if (Math.abs(point.scenePosition.x - finger.downX)
              + Math.abs(point.scenePosition.y - finger.downY) < surface.tapSlop)
            surface.service.focusWindow(frame.model.address)
        }

        onPointChanged: {
          if (!active || surface.dragFrom !== frame.model.address) return
          surface.dragX = point.scenePosition.x
          surface.dragY = point.scenePosition.y
          // Floating windows go where you put them. A tile has no free
          // position, so for those the drag is a search for something to
          // swap with instead.
          if (finger.startRect) {
            var r = finger.startRect
            surface.service.setWindowGeom(frame.model.address,
              r.x + (point.scenePosition.x - finger.downX),
              r.y + (point.scenePosition.y - finger.downY), r.w, r.h)
            return
          }
          // Whatever is on top, floating included. Measured: swapping a
          // tiled window with a floating one exchanges them, the float
          // taking the tile's place in the tree at full size and the tile
          // becoming floating where the float was. Skipping floats here
          // was a guess that they had no place in a swap, and all it did
          // was make the one useful thing you can do with a float in this
          // mode impossible.
          surface.dragOver = surface.windowAt(point.scenePosition.x,
                                              point.scenePosition.y)
        }
      }
      Timer {
        id: liftTimer
        interval: surface.holdMs
        onTriggered: {
          surface.dragFrom = frame.model.address
          surface.dragOver = frame.model.address
          surface.dragX = finger.point.scenePosition.x
          surface.dragY = finger.point.scenePosition.y
        }
      }

      // Which window this is on the left, how big it is on the right. Both
      // small enough to sit in a corner rather than on the part of the
      // window you are judging, and each capped at half the width so a long
      // title cannot run into the size.
      Chip {
        x: surface.edge * 2
        y: surface.edge * 2
        maxWidth: frame.width / 2 - surface.edge * 3
        text: frame.model.name
      }
      Chip {
        x: frame.width - width - surface.edge * 2
        y: surface.edge * 2
        maxWidth: frame.width / 2 - surface.edge * 3
        text: frame.model.w + "\u00d7" + frame.model.h
      }
    }
  }

  // A small copy of what you are carrying, under the finger. Without it a
  // drag looks like nothing is happening until a border is crossed, so
  // there is no reason to believe dragging does anything at all. It is an
  // outline rather than a solid, like everything else here, and the finger
  // sits in the hole in the middle of it.
  Item {
    id: ghost
    readonly property var src: surface.windowByAddress(surface.dragFrom)
    visible: src !== null && !src.floating && surface.dragX >= 0
    // The size it shrank to, so what leaves the outline and what follows the
    // finger are plainly the same object.
    width: src ? src.w * surface.liftScale : 0
    height: src ? src.h * surface.liftScale : 0
    x: surface.dragX - width / 2
    y: surface.dragY - height / 2
    // Comes in at the window's own size and settles to the carried one, so
    // the pickup is still a movement rather than a swap of one box for
    // another.
    scale: visible ? 1 : 1 / surface.liftScale
    Behavior on scale { NumberAnimation { duration: 110 } }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.popups.background, 0.4)
      border.width: surface.edge * 2
      border.color: Color.accent
    }
    // At the top, where the hand carrying it is not.
    Chip {
      x: surface.edge * 2
      y: surface.edge * 2
      maxWidth: ghost.width - surface.edge * 4 - surface.chipPad * 2
      text: ghost.src ? ghost.src.name : ""
    }
  }

}
