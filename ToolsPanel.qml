import QtQuick

// Ragtop's own controls: the inside of a tile that is a window of its own.
// It is drawn in pixels and its window is anchored only to the top of the
// screen at a fixed size, so nothing the keyboard does can move or resize it.
// That matters more than it sounds: while this window shared an edge with the
// keyboard, every step of the size slider relaid it out mid-drag and took the
// touch grab with it, which made the slider unusable.
//
// What is here is what you change while holding the machine, with the
// keyboard still drawn underneath so you can see what each change does.
Item {
  id: panel

  required property var service
  required property var theme

  signal dismissed()

  readonly property color faceOff: panel.theme.specialKey

  Rectangle {
    id: card
    anchors.fill: parent
    radius: 16
    color: panel.theme.solidBase
    border.width: Math.max(1, panel.theme.keyBorderWidth)
    border.color: panel.theme.accent

    Column {
      anchors.centerIn: parent
      spacing: 14

      // Tap targets here are TapHandlers rather than MouseAreas. MouseArea's
      // onClicked needs Qt to synthesise a mouse press and release out of a
      // touch, and the first touch on a surface that has not been touched
      // yet is lost somewhere in that synthesis, so the first tap on a panel
      // that has only just opened does nothing. The keyboard never had the
      // problem because it reads touch points directly, which is what a
      // TapHandler does too. The size slider below stays a MouseArea: it is
      // a drag, not a tap, and its handling is already tuned for that.
      //
      // The theme, stepped rather than listed: the keyboard behind redraws
      // as you go, which is a better way to choose one than reading names.
      Row {
        spacing: 8
        Rectangle {
          width: 44; height: 44; radius: 12
          color: panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          KeyIcon { anchors.centerIn: parent; height: 20; name: "left"; color: panel.theme.text }
          TapHandler { onTapped: panel.service.stepTheme(-1) }
        }
        Rectangle {
          width: 444; height: 44; radius: 12
          color: panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          Text {
            // Never rich text. A window title, a layout name and an error
            // string all arrive from outside, and AutoText would sniff markup
            // in them and render it, which for Qt includes fetching a remote
            // image named in an img tag.
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: {
              var name = panel.service.currentTheme
              return name.charAt(0).toUpperCase() + name.slice(1)
            }
            color: panel.theme.text
            font.family: panel.theme.fontFamily
            font.pixelSize: 16
          }
        }
        Rectangle {
          width: 44; height: 44; radius: 12
          color: panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          KeyIcon { anchors.centerIn: parent; height: 20; name: "right"; color: panel.theme.text }
          TapHandler { onTapped: panel.service.stepTheme(1) }
        }
      }

      // Screen rotation, named rather than implied. Automatic follows the
      // machine: it turns in tablet mode and holds still in laptop mode.
      // Three exclusive states, so radios rather than three buttons that
      // each look like something you do.
      Row {
        spacing: 14
        KeyIcon {
          anchors.verticalCenter: parent.verticalCenter
          height: 20
          name: "rotate"
          color: panel.theme.specialText
        }
        Text {
          // Never rich text. A window title, a layout name and an error
          // string all arrive from outside, and AutoText would sniff markup
          // in them and render it, which for Qt includes fetching a remote
          // image named in an img tag.
          textFormat: Text.PlainText
          width: 150
          anchors.verticalCenter: parent.verticalCenter
          text: "Screen Rotation"
          color: panel.theme.text
          font.family: panel.theme.fontFamily
          font.pixelSize: 15
        }
        Repeater {
          model: [{ mode: "locked", label: "Locked" },
                  { mode: "unlocked", label: "Unlocked" },
                  { mode: "auto", label: "Automatic" }]
          Item {
            id: radio
            required property var modelData
            readonly property bool on: panel.service.rotationMode === modelData.mode
            width: dot.width + 6 + optionLabel.width
            height: 44

            Rectangle {
              id: dot
              anchors.verticalCenter: parent.verticalCenter
              width: 22; height: 22; radius: 11
              color: "transparent"
              border.width: Math.max(1, panel.theme.keyBorderWidth)
              border.color: parent.on ? panel.theme.accent : panel.theme.keyBorder
              Rectangle {
                anchors.centerIn: parent
                width: 12; height: 12; radius: 6
                color: panel.theme.accent
                visible: dot.parent.on
              }
            }
            Text {
              // Never rich text. A window title, a layout name and an error
              // string all arrive from outside, and AutoText would sniff markup
              // in them and render it, which for Qt includes fetching a remote
              // image named in an img tag.
              textFormat: Text.PlainText
              id: optionLabel
              anchors.verticalCenter: parent.verticalCenter
              x: dot.width + 6
              text: parent.modelData.label
              color: panel.theme.text
              font.family: panel.theme.fontFamily
              font.pixelSize: 15
            }
            // The label belongs to the radio, as the sentence does below.
            TapHandler {
              onTapped: panel.service.setRotationMode(radio.modelData.mode)
            }
          }
        }
      }

      // Key size, on a line of its own and saying which step it is on. The
      // icon and the label width match the row above, so the two read as a
      // pair rather than as two rows that happen to be near each other.
      Row {
        spacing: 14
        KeyIcon {
          anchors.verticalCenter: parent.verticalCenter
          height: 20
          name: "keyboard"
          color: panel.theme.specialText
        }
        Text {
          // Never rich text. A window title, a layout name and an error
          // string all arrive from outside, and AutoText would sniff markup
          // in them and render it, which for Qt includes fetching a remote
          // image named in an img tag.
          textFormat: Text.PlainText
          id: sizeLabel
          width: 150
          anchors.verticalCenter: parent.verticalCenter
          text: "Keyboard Size"
          color: panel.theme.text
          font.family: panel.theme.fontFamily
          font.pixelSize: 15
        }

        Item {
          id: sizeSlider
          width: 350
          height: 44
          readonly property int steps: panel.service.sizeSteps.length
          readonly property int index: Math.max(0,
            panel.service.sizeSteps.indexOf(panel.service.look.sizeAdjust))
          readonly property real span: width - 28
          readonly property real stepWidth: span / (steps - 1)
          // Where the finger has put it, while a finger is on it. The settled
          // value comes back through settings.conf, which is quick but not
          // instant, and a handle that waits for it stutters under the thumb.
          property int dragIndex: -1
          readonly property int shown: dragIndex >= 0 ? dragIndex : index
          // The finger's answer stands until the settled one agrees with it,
          // so a write still in flight cannot look like a spring back.
          onIndexChanged: if (dragIndex === index) dragIndex = -1

          Rectangle { y: 20; x: 14; width: sizeSlider.span; height: 4; radius: 2
                      color: panel.faceOff }
          Repeater {
            model: sizeSlider.steps
            Rectangle {
              required property int index
              width: 6; height: 6; radius: 3; y: 19
              x: 11 + index * sizeSlider.stepWidth
              color: panel.theme.specialText
            }
          }
          Rectangle {
            width: 28; height: 28; radius: 14; y: 8
            x: sizeSlider.shown * sizeSlider.stepWidth
            color: panel.theme.accent
            border.width: 1
            border.color: panel.theme.accentText
            Behavior on x { NumberAnimation { duration: 90 } }
          }
          MouseArea {
            anchors.fill: parent
            preventStealing: true
            // A step is only given up once the finger is well past the middle
            // of the gap, so a wobble at a boundary cannot flip it back and
            // forth. A long drag still crosses several at once.
            function at(mx) {
              var pos = (mx - 14) / sizeSlider.stepWidth
              var current = sizeSlider.dragIndex
              var want = (current < 0 || Math.abs(pos - current) > 0.6) ? Math.round(pos) : current
              return Math.max(0, Math.min(sizeSlider.steps - 1, want))
            }
            function moveTo(i) {
              if (i === sizeSlider.dragIndex) return
              sizeSlider.dragIndex = i
              panel.service.setSize(i)
            }
            onPressed: function(m) { moveTo(at(m.x)) }
            onPositionChanged: function(m) { if (pressed) moveTo(at(m.x)) }
            onReleased: function(m) { moveTo(at(m.x)) }
            onCanceled: sizeSlider.dragIndex = -1
          }
        }
      }

      // Whether the keyboard comes up by itself on a text field, and the way
      // through to everything that does not belong on a surface you hold.
      Item {
        width: 548
        height: 44

        Rectangle {
          id: autoBox
          y: 9
          width: 26; height: 26; radius: 7
          color: panel.service.autoShowEnabled ? panel.theme.accent : "transparent"
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.service.autoShowEnabled ? panel.theme.accent : panel.theme.keyBorder
          KeyIcon {
            anchors.centerIn: parent
            height: 16
            name: "check"
            color: panel.theme.accentText
            visible: panel.service.autoShowEnabled
          }
        }
        Text {
          // Never rich text. A window title, a layout name and an error
          // string all arrive from outside, and AutoText would sniff markup
          // in them and render it, which for Qt includes fetching a remote
          // image named in an img tag.
          textFormat: Text.PlainText
          id: autoLabel
          anchors.verticalCenter: autoBox.verticalCenter
          x: 38
          text: "Auto-expand keyboard on text fields"
          color: panel.theme.text
          font.family: panel.theme.fontFamily
          font.pixelSize: 15
        }
        // The sentence is part of the control, not a caption beside it.
        Item {
          width: autoLabel.x + autoLabel.width
          height: parent.height
          TapHandler { onTapped: panel.service.toggleAutoShow() }
        }

        Rectangle {
          anchors.right: parent.right
          y: 0
          width: 84; height: 44; radius: 12
          color: panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          Text {
            // Never rich text. A window title, a layout name and an error
            // string all arrive from outside, and AutoText would sniff markup
            // in them and render it, which for Qt includes fetching a remote
            // image named in an img tag.
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "Settings"
            color: panel.theme.specialText
            font.family: panel.theme.fontFamily
            font.pixelSize: 14
          }
          TapHandler {
            onTapped: { panel.dismissed(); panel.service.openSettings() }
          }
        }
      }
    }
  }
}
