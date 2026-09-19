import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// On-screen keyboard for Omarchy's lock screen in tablet mode. The lock
// screen is a session lock, which hides every other surface, the on-screen
// keyboard included, so Ragtop's patched clone of it (overlay-clones.sh) loads
// this inside it and sets `view` to its LockView. Keys edit the password through
// LockView's own signals, the path typing takes, so checking it is untouched.
//
// Deliberately separate from Keyboard.qml: it shares no code with it, so
// nothing added to the desktop keyboard reaches the lock screen unless it's
// added here too. It only edits the password text: no key events, no helper,
// no modifiers other than Shift. It copies the desktop keyboard's key shapes
// and proportions, in the lock screen's own colours (Color.lock).
Item {
  id: root

  property var view: null
  readonly property bool typing: view !== null && view.inputEnabled && !view.authenticatingPassword

  property string page: "letters"
  property bool shift: false
  property bool capsLock: false
  readonly property bool upper: shift || capsLock

  // The active layout's letter keys, which Ragtop's service writes when its
  // keyboard helper reads them from the keymap, so these keys type what the
  // physical keyboard would. Checked before use; US if missing or malformed.
  readonly property var usRows: [
    [["q","Q"],["w","W"],["e","E"],["r","R"],["t","T"],["y","Y"],["u","U"],["i","I"],["o","O"],["p","P"]],
    [["a","A"],["s","S"],["d","D"],["f","F"],["g","G"],["h","H"],["j","J"],["k","K"],["l","L"]],
    [["z","Z"],["x","X"],["c","C"],["v","V"],["b","B"],["n","N"],["m","M"]]
  ]
  property var layoutRows: usRows
  property string layoutName: ""

  function validLayout(layout) {
    if (!layout || !Array.isArray(layout.rows) || layout.rows.length !== 3) return false
    return layout.rows.every(function(row) {
      return Array.isArray(row) && row.length > 0 && row.length <= 13 && row.every(function(k) {
        return Array.isArray(k) && k.length === 2 && k.every(function(c) {
          return typeof c === "string" && c.length >= 1 && c.length <= 2 && c.trim() === c
        })
      })
    })
  }

  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ragtop-layout.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var layout = null
      try { layout = JSON.parse(text()) } catch (e) {}
      var ok = root.validLayout(layout)
      root.layoutRows = ok ? layout.rows : root.usRows
      root.layoutName = ok && typeof layout.name === "string" ? layout.name.slice(0, 40) : ""
    }
    onLoadFailed: { root.layoutRows = root.usRows; root.layoutName = "" }
  }

  // Each letter's shifted character, e.g. "Ü" for "ü".
  readonly property var shiftOf: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { map[k[0]] = k[1] }) })
    return map
  }
  function letters(row) { return row.map(function(k) { return k[0] }) }

  // Rows of keys; a key is its text, or one of the named keys below. Widths
  // are in units of a letter key.
  readonly property var pages: ({
    "letters": [
      letters(layoutRows[0]),
      letters(layoutRows[1]),
      ["shift"].concat(letters(layoutRows[2]), ["backspace"]),
      ["symbols", "space", ".", "enter"]
    ],
    "symbols": [
      ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
      ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
      ["more", ".", ",", "?", "!", "'", "backspace"],
      ["letters", "space", ",", "enter"]
    ],
    "more": [
      ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
      ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "`"],
      ["symbols", ".", ",", "?", "!", "'", "backspace"],
      ["letters", "space", ",", "enter"]
    ]
  })
  readonly property var labels: ({
    "shift": "⇧", "backspace": "⌫", "enter": "⏎",
    "symbols": "?123", "more": "#+=", "letters": "ABC"
  })
  readonly property var widths: ({
    "shift": 1.5, "backspace": 1.5, "symbols": 1.5, "more": 1.5, "letters": 1.5,
    "space": 5.5, "enter": 2
  })

  // Sized as the desktop keyboard is, so the longest row fits.
  readonly property int gap: 6
  readonly property int padding: 8
  readonly property real rowUnits: Math.max(10, layoutRows[0].length, layoutRows[1].length, layoutRows[2].length + 3)
  readonly property real unit: Math.min((width - 2 * padding) / rowUnits, 84)
  readonly property real keyHeight: Math.max(40, Math.min(Math.round(unit * 0.78), 60))

  // The desktop keyboard's key fills, made from the lock screen's colours.
  readonly property color keyColor: Qt.tint(Color.lock.background, Util.alpha(Color.lock.text, 0.10))
  readonly property color specialKeyColor: Qt.tint(Color.lock.background, Util.alpha(Color.lock.text, 0.05))
  readonly property color keyBorder: Util.alpha(Color.lock.text, 0.12)
  readonly property real keyRadius: Math.max(Style.cornerRadius, 6)

  implicitHeight: rows.implicitHeight + 2 * padding + 12
  opacity: typing ? 1 : 0.5

  function label(key) {
    if (key === "space") return root.layoutName
    if (key in labels) return labels[key]
    return upper ? shifted(key) : key
  }

  function shifted(key) {
    return shiftOf[key] || key.toUpperCase()
  }

  function type(text) {
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
      root.type(root.upper ? root.shifted(key) : key)
    }
  }

  Timer { id: shiftTap; interval: 400 }

  Column {
    id: rows
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.padding + 12
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
            readonly property bool accent: modelData === "enter" || (modelData === "shift" && root.capsLock)
            readonly property bool latched: modelData === "shift" && root.shift
            readonly property bool special: modelData in root.labels || modelData === "space"
            width: root.unit * (root.widths[modelData] || 1) - root.gap
            height: root.keyHeight
            radius: root.keyRadius
            border.width: 1
            border.color: root.keyBorder
            color: area.pressed ? Color.lock.selection
              : accent ? Color.lock.borderActive
              : latched ? Color.lock.selection
              : special ? root.specialKeyColor
              : root.keyColor

            Text {
              anchors.centerIn: parent
              text: root.label(key.modelData)
              color: key.accent ? Color.background : Color.lock.text
              font.family: Style.font.family
              // Short labels (a letter) larger than words like "?123".
              font.pixelSize: Math.round(Math.min(key.height * 0.42, 26) * (text.length > 1 ? 0.75 : 1.25))
            }

            MouseArea {
              id: area
              // Half the gap on every side, so neighbouring keys meet in the
              // middle of the gap and a tap there isn't lost.
              anchors.fill: parent
              anchors.margins: -root.gap / 2
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
