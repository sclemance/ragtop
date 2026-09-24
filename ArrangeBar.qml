import QtQuick
import qs.Commons
import qs.Ui

// The controls for arrange mode, along the bottom of the screen in place of
// the keyboard's handle.
//
// Everything here is a thing a finger cannot express by dragging a window
// around. Moving, swapping and resizing happen on the windows themselves,
// so they are not repeated here. What is left is where a window goes
// (workspaces and the scratchpad) and what shape it takes (full width,
// tiled full screen, split, float).
//
// The way out sits in the middle, because it is the one control you need to
// find without looking for it.
Item {
  id: bar

  // Service.qml
  required property var service

  readonly property int pad: Style.space(6)
  readonly property int gap: Style.space(6)

  // Which workspaces to offer, by Omarchy's own rule, and whether a tap
  // sends the window there rather than going there.
  readonly property var workspaces: service.workspaceIds
  readonly property bool sending: service.sendMod !== "off"

  // A control on the strip: its own pill, sized to what it says, so a long
  // Omarchy name is not abbreviated into something nobody recognises.
  component Btn: Rectangle {
    property alias text: btnText.text
    property bool lit: false
    property bool wide: false
    signal tapped()

    width: Math.max(wide ? Style.space(64) : Style.space(40),
                    btnText.implicitWidth + bar.pad * 3)
    height: bar.height - bar.pad * 2
    radius: Style.cornerRadius
    color: lit ? Color.accent : Util.alpha(Color.popups.background, 0.9)
    border.width: Math.max(1, Style.space(1))
    border.color: lit ? Color.accent : Color.popups.border

    Text {
      id: btnText
      anchors.centerIn: parent
      width: parent.width - bar.pad * 2
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: parent.lit ? Color.background : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    TapHandler { onTapped: parent.tapped() }
  }

  // Where a window goes.
  Row {
    anchors.left: parent.left
    anchors.leftMargin: bar.pad
    anchors.verticalCenter: parent.verticalCenter
    spacing: bar.gap

    Btn {
      wide: true
      text: "Send to…"
      lit: bar.sending
      onTapped: bar.service.stepSendMod()
    }
    Repeater {
      model: bar.workspaces
      Btn {
        required property var modelData
        text: (bar.sending ? "→" : "") + modelData
        lit: !bar.sending && modelData === bar.service.focusedWorkspace
        onTapped: bar.service.takeWorkspace(modelData)
      }
    }
    Btn {
      wide: true
      text: (bar.sending ? "→" : "") + "Scratchpad"
      lit: !bar.sending && bar.service.focusedWorkspace < 0
      onTapped: bar.service.takeScratchpad()
    }
  }

  // The way out, in the middle where it can be found without hunting.
  Rectangle {
    anchors.centerIn: parent
    width: finishText.implicitWidth + Style.space(28)
    height: bar.height - bar.pad * 2
    radius: height / 2
    color: Color.accent
    opacity: finishTap.pressed ? 0.6 : 1

    Text {
      id: finishText
      anchors.centerIn: parent
      text: "Finish arranging"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    TapHandler {
      id: finishTap
      onTapped: bar.service.closeArrange(true)
    }
  }

  // What shape a window takes. Omarchy's own names, since there is room.
  Row {
    anchors.right: parent.right
    anchors.rightMargin: bar.pad
    anchors.verticalCenter: parent.verticalCenter
    spacing: bar.gap

    Btn { wide: true; text: "Full width"; onTapped: bar.service.runWindowAction("wide") }
    Btn { wide: true; text: "Tiled full screen"; onTapped: bar.service.runWindowAction("tiled") }
    Btn { wide: true; text: "Split"; onTapped: bar.service.runWindowAction("split") }
    Btn { wide: true; text: "Float"; onTapped: bar.service.runWindowAction("float") }
  }
}
