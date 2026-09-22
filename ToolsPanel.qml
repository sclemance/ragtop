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

  readonly property color faceOn: panel.theme.lockedKey
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
      spacing: 10

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
          MouseArea { anchors.fill: parent; onClicked: panel.service.stepTheme(-1) }
        }
        Rectangle {
          width: 342; height: 44; radius: 12
          color: panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          Text {
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
          MouseArea { anchors.fill: parent; onClicked: panel.service.stepTheme(1) }
        }
      }

      Row {
        spacing: 8

        // Rotation lock. The bar widget keeps it, so this asks rather than sets.
        Rectangle {
          width: 52; height: 52; radius: 12
          color: panel.service.rotationLocked ? panel.faceOn : panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          KeyIcon {
            anchors.centerIn: parent
            height: 26
            name: "rotate"
            color: panel.service.rotationLocked ? panel.theme.accentText : panel.theme.text
          }
          MouseArea { anchors.fill: parent; onClicked: panel.service.toggleRotationLock() }
        }

        // Key size, the whole ladder at once rather than a step at a time.
        Item {
          id: sizeSlider
          width: 298
          height: 52
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

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            text: {
              var name = panel.service.sizeSteps[sizeSlider.shown] || ""
              return name.charAt(0).toUpperCase() + name.slice(1)
            }
            color: panel.theme.specialText
            font.family: panel.theme.fontFamily
            font.pixelSize: 13
          }
          Rectangle { y: 34; x: 14; width: sizeSlider.span; height: 4; radius: 2
                      color: panel.faceOff }
          Repeater {
            model: sizeSlider.steps
            Rectangle {
              required property int index
              width: 6; height: 6; radius: 3; y: 33
              x: 11 + index * sizeSlider.stepWidth
              color: panel.theme.specialText
            }
          }
          Rectangle {
            width: 28; height: 28; radius: 14; y: 22
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

        // Everything else is rare enough to be worth a menu.
        Rectangle {
          width: 84; height: 52; radius: 12
          color: panel.faceOff
          border.width: Math.max(1, panel.theme.keyBorderWidth)
          border.color: panel.theme.keyBorder
          Text {
            anchors.centerIn: parent
            text: "Settings"
            color: panel.theme.specialText
            font.family: panel.theme.fontFamily
            font.pixelSize: 14
          }
          MouseArea {
            anchors.fill: parent
            onClicked: { panel.dismissed(); panel.service.openSettings() }
          }
        }
      }

      // Whether the keyboard comes up by itself on a text field. A box with
      // a sentence beside it, because "Auto" on a key says nothing about
      // what is automatic. The moment you want this off is the moment it has
      // appeared over what you were reading, which is a bad moment to be
      // several taps deep in a menu.
      Item {
        width: 446
        height: 30

        Rectangle {
          id: autoBox
          y: 2
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
          anchors.verticalCenter: autoBox.verticalCenter
          x: 38
          text: "Auto-expand keyboard on text fields"
          color: panel.theme.text
          font.family: panel.theme.fontFamily
          font.pixelSize: 15
        }
        // The sentence is part of the control, not a caption beside it.
        MouseArea { anchors.fill: parent; onClicked: panel.service.toggleAutoShow() }
      }
    }
  }
}
