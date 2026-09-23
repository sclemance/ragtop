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

  // What the window is masked to: the only part of the screen this takes
  // touches on. Everything outside it falls through to whatever is
  // underneath, which in phase one is everything, since nothing but the way
  // out is interactive yet. The bar and the keyboard's handle stay usable
  // for free, and there is no way for this mode to strand a machine.
  readonly property Item touchArea: doneButton

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

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Style.cornerRadius
        border.width: surface.edge
        border.color: frame.modelData.floating ? Color.urgent : Color.accent
        opacity: 0.9
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
