import QtQuick
import qs.Commons

// On-screen keyboard for Omarchy's lock screen in tablet mode. The lock
// screen is a session lock, which hides every other surface, the on-screen
// keyboard included, so Ragtop's patched clone of it (overlay-clones.sh) loads this
// inside it and sets `view` to its LockView. Keys edit the password through
// LockView's own signals, the path typing takes, so checking it is untouched.
Item {
  id: root

  property var view: null
  readonly property bool typing: view !== null && view.inputEnabled && !view.authenticatingPassword

  property string page: "letters"
  property bool shift: false
  property bool capsLock: false
  readonly property bool upper: shift || capsLock

  // Rows of keys; a key is its text, or one of the named keys below. Widths
  // are in units of a letter key.
  readonly property var pages: ({
    "letters": [
      ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
      ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
      ["shift", "z", "x", "c", "v", "b", "n", "m", "backspace"],
      ["symbols", "space", "enter"]
    ],
    "symbols": [
      ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
      ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
      ["more", ".", ",", "?", "!", "'", "backspace"],
      ["letters", "space", "enter"]
    ],
    "more": [
      ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
      ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "`"],
      ["symbols", ".", ",", "?", "!", "'", "backspace"],
      ["letters", "space", "enter"]
    ]
  })
  readonly property var labels: ({
    "shift": "⇧", "backspace": "⌫", "enter": "⏎", "space": "",
    "symbols": "?123", "more": "#+=", "letters": "ABC"
  })
  readonly property var widths: ({
    "shift": 1.5, "backspace": 1.5, "symbols": 1.5, "more": 1.5, "letters": 1.5,
    "space": 6, "enter": 2.5
  })

  readonly property real unit: Math.min(width / 10, 76)
  readonly property real keyHeight: Math.min(Math.round(unit * 0.9), 58)
  readonly property int gap: 6

  implicitHeight: rows.implicitHeight + 2 * gap + 12
  opacity: typing ? 1 : 0.5

  function label(key) {
    if (key in labels) return labels[key]
    return upper ? key.toUpperCase() : key
  }

  function type(text) {
    if (!root.typing) return
    root.view.wakeRequested()
    root.view.passwordTextEdited(root.view.passwordText + text)
    if (root.shift) root.shift = false
  }

  function press(key) {
    if (!root.typing) return
    root.view.wakeRequested()
    switch (key) {
    case "shift":
      // A second tap soon after the first locks capitals on.
      if (root.capsLock) { root.capsLock = false; root.shift = false }
      else if (root.shift && shiftTap.running) { root.capsLock = true; root.shift = false }
      else { root.shift = !root.shift; shiftTap.restart() }
      break
    case "backspace":
      root.view.passwordTextEdited(root.view.passwordText.slice(0, -1))
      break
    case "enter":
      // As the password field's own Enter does.
      var submitted = root.view.passwordText
      root.view.passwordTextEdited("")
      if (submitted.length > 0) root.view.submitPassword(submitted)
      root.shift = false
      break
    case "space":
      root.type(" ")
      break
    case "symbols":
    case "more":
    case "letters":
      root.page = key
      break
    default:
      root.type(root.upper ? key.toUpperCase() : key)
    }
  }

  Timer { id: shiftTap; interval: 400 }

  Column {
    id: rows
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.gap + 12
    spacing: root.gap

    Repeater {
      model: root.pages[root.page]

      Row {
        required property var modelData
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.gap

        Repeater {
          model: parent.modelData

          Rectangle {
            id: key
            required property string modelData
            readonly property bool accent: modelData === "enter"
            readonly property bool active: (modelData === "shift" && (root.shift || root.capsLock))
            width: root.unit * (root.widths[modelData] || 1) - root.gap
            height: root.keyHeight
            radius: Style.cornerRadius
            color: area.pressed ? Color.lock.selection
              : accent ? Color.lock.borderActive
              : active ? Color.lock.selection
              : Color.lock.background
            border.width: 1
            border.color: Util.alpha(Color.lock.border, 0.25)

            Text {
              anchors.centerIn: parent
              text: root.label(key.modelData)
              color: key.accent ? Color.background : Color.lock.text
              font.family: Style.font.family
              font.pixelSize: text.length > 1 ? Style.font.heading : Math.round(Style.font.heading * 1.25)
              font.underline: key.modelData === "shift" && root.capsLock
            }

            MouseArea {
              id: area
              anchors.fill: parent
              onPressed: root.press(key.modelData)
              // Holding backspace keeps deleting.
              onPressAndHold: if (key.modelData === "backspace") repeat.start()
              onReleased: repeat.stop()
              onCanceled: repeat.stop()
            }

            Timer {
              id: repeat
              interval: 80
              repeat: true
              onTriggered: root.press("backspace")
            }
          }
        }
      }
    }
  }
}
