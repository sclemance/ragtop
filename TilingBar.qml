import QtQuick
import qs.Commons
import qs.Ui

// The controls for tiling mode, along the bottom of the screen in place of
// the keyboard's handle.
//
// Everything here is a thing a finger cannot express by dragging a window
// around. Moving, swapping and resizing happen on the windows themselves,
// so they are not repeated here. What is left is where a window goes
// (workspaces and the scratchpad) and what shape it takes.
//
// Turned on its side there is little more than half the width and nearly
// twice the height, so it uses the axis it has: one row across when there
// is room, two rows when there is not. Nothing is hidden behind a scroll or
// a carousel, because the job of the workspace group is to say where you are
// and where you can go, and a control you have to go looking for cannot.
Item {
  id: bar

  // Service.qml
  required property var service

  // One row while everything fits on one, two rows when it does not.
  //
  // Measured with the icons in: one row needs about 980px, so the old 900
  // would have overflowed between 900 and 980. Icons made each shape button
  // wider, not narrower, and the threshold had to follow them.
  readonly property bool tight: width < Style.space(1020)

  // Words dropped in favour of the icon alone, which is a last resort. In
  // portrait the shapes row needs about 450px and gets 768, so there is room
  // for the words and they stay. This is for a narrower screen or a much
  // larger font, not for the ordinary rotated layout. A finger still gets a
  // full-size target either way, because what goes is the word.
  readonly property bool cramped: width < Style.space(520)
  readonly property int pad: Style.space(6)
  readonly property int gap: tight ? Style.space(4) : Style.space(6)
  readonly property int rowH: tight ? Style.space(38) : Style.space(44)

  // What the strip has to be for the layout it is in. The window reads this
  // rather than assuming, so a second row is paid for in height only when
  // there is a second row.
  readonly property int neededHeight: tight ? rowH * 2 + pad * 3 : rowH + pad * 2

  readonly property var workspaces: service.workspaceIds
  readonly property bool sending: service.sendMod !== "off"

  // A control on the strip: its own pill, sized to what it says. Labels
  // shorten rather than elide when the room runs out, since half a word is
  // worse than a shorter one.
  //
  // A control that has an icon shows the icon and the word together while
  // there is room, and drops to the icon alone when there is not. A finger
  // needs the target to stay the size it was, so what goes is the word and
  // never the button.
  component Btn: Rectangle {
    id: btn
    property alias text: btnText.text
    property bool lit: false
    property bool wide: false
    // A KeyIcon name, or "" for a control that is only a word.
    property string icon: ""
    // Greyed and untappable, for a control that has nothing to act on.
    // Better than a button that appears to do nothing, or one whose light
    // flickers because the state behind it is being suspended.
    property bool off: false
    readonly property bool iconOnly: icon !== "" && bar.cramped
    signal tapped()

    // Never narrower than a finger, whatever is inside it.
    width: Math.max(iconOnly ? bar.rowH : (wide ? Style.space(60) : Style.space(36)),
                    row.implicitWidth + bar.pad * 3)
    height: bar.rowH
    radius: Style.cornerRadius
    color: lit ? Color.accent : Util.alpha(Color.popups.background, 0.9)
    border.width: Math.max(1, Style.space(1))
    border.color: lit ? Color.accent : Color.popups.border
    opacity: off ? 0.35 : 1

    Row {
      id: row
      anchors.centerIn: parent
      spacing: btn.iconOnly || btn.icon === "" ? 0 : Style.space(5)

      KeyIcon {
        anchors.verticalCenter: parent.verticalCenter
        visible: btn.icon !== ""
        name: btn.icon
        height: Math.round(bar.rowH * 0.46)
        color: btn.lit ? Color.background : Color.popups.text
      }
      Text {
        // Never rich text. A window title, a layout name and an error
        // string all arrive from outside, and AutoText would sniff markup
        // in them and render it, which for Qt includes fetching a remote
        // image named in an img tag.
        textFormat: Text.PlainText
        id: btnText
        anchors.verticalCenter: parent.verticalCenter
        visible: !btn.iconOnly
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: btn.lit ? Color.background : Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    TapHandler { enabled: !btn.off; onTapped: btn.tapped() }
  }

  // Where a window goes.
  component Places: Row {
    spacing: bar.gap

    Btn {
      wide: true
      text: bar.tight ? "Send…" : "Send to…"
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
      text: (bar.sending ? "→" : "") + (bar.tight ? "Scratch" : "Scratchpad")
      lit: !bar.sending && bar.service.specialShown
      onTapped: bar.service.takeScratchpad()
    }
  }

  // What shape a window takes. Omarchy's own names where they fit.
  //
  // Each of these is a toggle, so each says whether it is already on rather
  // than offering a verb with no state behind it. Hyprland keeps two
  // independent fullscreen axes: `full` is the internal one that maximized
  // sets, `fullClient` is the one Omarchy's tiled toggle drives, where 2
  // means on. Measured: every combination of the two is legal, so both can
  // be lit at once and neither needs to clear the other.
  //
  // Split lights for nothing. It flips the split of the dwindle node this
  // window sits in rather than changing the window, so there is no state on
  // the window to show.
  readonly property var focused: service.tilingFocused

  component Shapes: Row {
    spacing: bar.gap

    // Maximized sets internal and client both to 1, and it survives a float
    // toggle, so it is live whether the window is tiled or floating. Only
    // 1 lights it: 2 is true fullscreen, which Ragtop never asks for.
    Btn {
      wide: true; icon: "wide"; text: "Full width"
      lit: bar.focused !== null && bar.focused.full === 1
      onTapped: bar.service.runWindowAction("wide")
    }
    // Off while the window floats, because there is no tile for it to fill.
    // Measured: Hyprland suspends client 2 the moment a window floats and
    // puts it back when it tiles again, so left enabled this light flickers
    // on every float toggle while appearing to mean something.
    Btn {
      wide: true; icon: "tiled"
      text: bar.tight ? "Full screen" : "Tiled full screen"
      lit: bar.focused !== null && bar.focused.fullClient === 2
      off: bar.focused !== null && bar.focused.floating
      onTapped: bar.service.runWindowAction("tiled")
    }
    // Off while the window floats for the same reason. Split turns the
    // divider of the dwindle node this window sits in, and a floating
    // window sits in none.
    Btn {
      wide: true; icon: "split"; text: "Split"
      off: bar.focused !== null && bar.focused.floating
      onTapped: bar.service.runWindowAction("split")
    }
    Btn {
      wide: true; icon: "float"; text: "Float"
      lit: bar.focused !== null && bar.focused.floating
      onTapped: bar.service.runWindowAction("float")
    }
  }

  // The way out. Accent filled wherever it lands, since that is what makes
  // it findable without hunting, rather than where it happens to sit.
  component Finish: Rectangle {
    width: finishText.implicitWidth + Style.space(28)
    height: bar.rowH
    radius: height / 2
    color: Color.accent
    opacity: finishTap.pressed ? 0.6 : 1

    Text {
      // Never rich text. A window title, a layout name and an error
      // string all arrive from outside, and AutoText would sniff markup
      // in them and render it, which for Qt includes fetching a remote
      // image named in an img tag.
      textFormat: Text.PlainText
      id: finishText
      anchors.centerIn: parent
      text: bar.tight ? "Finish" : "Finish tiling"
      color: Color.background
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Style.font.bodySmall
    }

    TapHandler {
      id: finishTap
      onTapped: bar.service.closeTiling(true)
    }
  }

  // Wide: one row, places left, shapes right, the way out in the middle.
  Item {
    anchors.fill: parent
    visible: !bar.tight

    Places {
      anchors.left: parent.left
      anchors.leftMargin: bar.pad
      anchors.verticalCenter: parent.verticalCenter
    }
    Finish { anchors.centerIn: parent }
    Shapes {
      anchors.right: parent.right
      anchors.rightMargin: bar.pad
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Narrow: two rows, where a window goes above what shape it takes, with
  // the way out at the end of the second.
  Column {
    anchors.centerIn: parent
    visible: bar.tight
    spacing: bar.pad

    Places { anchors.horizontalCenter: parent.horizontalCenter }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: bar.gap
      Shapes {}
      Finish {}
    }
  }
}
