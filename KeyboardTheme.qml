import QtQuick
import qs.Commons

// Everything about how Ragtop's keyboard looks, in one place, so a theme can
// change it without touching the keyboard's logic. Bound to Omarchy's theme
// colours and font, so it follows theme switches live.
QtObject {
  // Background opacity, from Setup › Tablet › Transparency (0 = fully clear).
  property real backgroundOpacity: 1

  property color background: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, backgroundOpacity)
  property color text: Color.foreground
  property color accent: Color.accent
  property color accentText: Color.background

  // Key fills, as tints of the background towards the text colour, so they
  // hold up on light and dark themes alike.
  property color key: Qt.tint(Color.background, Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10))
  property color specialKey: Qt.tint(Color.background, Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
  property color pressedKey: Qt.tint(Color.background, Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.28))
  // A modifier that applies to the next key only, and one locked on.
  property color latchedKey: Qt.tint(key, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45))
  property color lockedKey: Color.accent
  property color keyBorder: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

  property real keyRadius: Math.max(Style.cornerRadius, 6)
  property int keyBorderWidth: 1
  property int gap: 6
  property int padding: 8

  property string fontFamily: Style.font.family
  property real fontScale: 1.25
}
