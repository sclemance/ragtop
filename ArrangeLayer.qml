import QtQuick
import qs.Commons
import qs.Ui

// The inside of arrange mode: an outline around every window on the
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

  function windowAt(px, py) {
    // Last first, so an overlapping floating window wins over the tile it
    // is sitting on, which is the order they are drawn in.
    for (var i = surface.windows.length - 1; i >= 0; i--) {
      var w = surface.windows[i]
      if (px >= w.x && px < w.x + w.w && py >= w.y && py < w.y + w.h) return w.address
    }
    return ""
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
  Item {
    id: activeArea
    visible: false
    readonly property bool empty: surface.windows.length === 0
    readonly property real minX: empty ? doneButton.x
      : Math.min(doneButton.x, surface.windowBounds.x)
    readonly property real minY: empty ? doneButton.y
      : Math.min(doneButton.y, surface.windowBounds.y)
    readonly property real maxX: empty ? doneButton.x + doneButton.width
      : Math.max(doneButton.x + doneButton.width,
                 surface.windowBounds.x + surface.windowBounds.width)
    readonly property real maxY: empty ? doneButton.y + doneButton.height
      : Math.max(doneButton.y + doneButton.height,
                 surface.windowBounds.y + surface.windowBounds.height)
    x: minX
    y: minY
    width: maxX - minX
    height: maxY - minY
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

  Repeater {
    model: surface.windows

    Item {
      id: frame
      required property var modelData
      x: modelData.x
      y: modelData.y
      width: modelData.w
      height: modelData.h

      // Picked up: this outline stops being drawn here, because it is the
      // thing now under the finger. One object, one place, rather than an
      // after-image left behind to be explained.
      readonly property bool lifted: surface.dragFrom === modelData.address
      visible: !lifted

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Style.cornerRadius
        // The focused one is drawn heavier rather than in another colour,
        // so floating still reads as floating whether or not it has focus.
        border.width: frame.dropTarget || frame.modelData.focused
          ? surface.edge * 2 : surface.edge
        border.color: frame.modelData.floating ? Color.urgent : Color.accent
        opacity: frame.dropTarget || frame.modelData.focused ? 1 : 0.65
      }

      // Where this one would land. A wash rather than a fill: you are
      // dropping onto a window, and you should still be able to see which.
      readonly property bool dropTarget: surface.dragFrom !== ""
        && surface.dragOver === modelData.address
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
      PointHandler {
        id: finger
        property real downX: 0
        property real downY: 0

        onActiveChanged: {
          if (active) {
            finger.downX = point.scenePosition.x
            finger.downY = point.scenePosition.y
            liftTimer.restart()
            return
          }
          liftTimer.stop()
          if (surface.dragFrom === frame.modelData.address) {
            var to = surface.dragOver
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
            surface.service.focusWindow(frame.modelData.address)
        }

        onPointChanged: {
          if (!active || surface.dragFrom !== frame.modelData.address) return
          surface.dragX = point.scenePosition.x
          surface.dragY = point.scenePosition.y
          surface.dragOver = surface.windowAt(point.scenePosition.x,
                                              point.scenePosition.y)
        }
      }
      Timer {
        id: liftTimer
        interval: surface.holdMs
        onTriggered: {
          surface.dragFrom = frame.modelData.address
          surface.dragOver = frame.modelData.address
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
        text: frame.modelData.name
      }
      Chip {
        x: frame.width - width - surface.edge * 2
        y: surface.edge * 2
        maxWidth: frame.width / 2 - surface.edge * 3
        text: frame.modelData.w + "\u00d7" + frame.modelData.h
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
    visible: src !== null && surface.dragX >= 0
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

  // The way out. Large, always in the same place, and the only thing on this
  // surface that takes a touch. The bar and the keyboard's handle stay live
  // underneath, so this is the most obvious way back rather than the only
  // one, and the idle timer is a third.
  Rectangle {
    id: doneButton
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(28)
    width: Math.max(Style.space(160), doneLabel.implicitWidth + Style.space(48))
    height: Style.space(52)
    radius: Style.cornerRadius
    color: Color.accent

    Text {
      id: doneLabel
      anchors.centerIn: parent
      text: "Done"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    TapHandler {
      onTapped: surface.service.closeArrange(true)
    }
  }

  // What this is, said once, because a screen full of outlines needs to
  // explain itself before someone decides something has gone wrong.
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: doneButton.top
    anchors.bottomMargin: Style.space(10)
    text: surface.windows.length === 0
      ? "No windows on this workspace"
      : "Arranging " + surface.windows.length
        + (surface.windows.length === 1 ? " window" : " windows")
    color: Color.popups.text
    opacity: 0.75
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
}
