import QtQuick

// One key of Ragtop's keyboard. Only how a key looks and reports touches
// lives here; what it does is up to Keyboard.qml. Swapping this component
// is how key shapes and effects can change.
Rectangle {
  id: key

  required property var theme
  property string label: ""
  // "normal", "special", "accent", "latched" or "locked".
  property string kind: "normal"
  property alias pressed: area.pressed

  signal keyPressed()
  signal keyReleased()

  radius: theme.keyRadius
  border.width: theme.keyBorderWidth
  border.color: theme.keyBorder
  color: pressed ? theme.pressedKey
    : kind === "accent" || kind === "locked" ? theme.lockedKey
    : kind === "latched" ? theme.latchedKey
    : kind === "special" ? theme.specialKey
    : theme.key

  Text {
    anchors.centerIn: parent
    text: key.label
    color: key.kind === "accent" || key.kind === "locked" ? key.theme.accentText : key.theme.text
    font.family: key.theme.fontFamily
    // Short labels (a letter, an arrow) larger than words like "Esc".
    font.pixelSize: Math.round(Math.min(key.height * 0.42, 26) * (text.length > 1 ? 0.75 : key.theme.fontScale))
  }

  MouseArea {
    id: area
    anchors.fill: parent
    onPressed: key.keyPressed()
    onReleased: key.keyReleased()
    onCanceled: key.keyReleased()
  }
}
