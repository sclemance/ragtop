import QtQuick

// How one key of Ragtop's keyboard looks, and nothing else: Keyboard.qml
// places it in its slot, decides which key a touch means and sets its
// state. Swapping this component is how key shapes and effects can change;
// whatever it draws, touches go by the slot, so a shape can't make a key
// harder to hit.
Rectangle {
  id: key

  required property var theme
  property string label: ""
  // "normal", "special", "accent", "latched" or "locked".
  property string kind: "normal"
  property bool pressed: false

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
}
