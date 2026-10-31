import QtQuick
import QtQuick.Effects

// A stationary light beneath the opaque keycap. RectangularShadow draws
// this shape directly, without capturing and blurring the key's contents.
// The owner hides it on press; neither geometry nor blur is animated.
RectangularShadow {
  required property color accent
  required property real rounding
  required property real gap
  property real strength: 0.7
  radius: rounding
  color: Qt.rgba(accent.r, accent.g, accent.b, strength)
  blur: Math.max(4, gap * 1.4)
  spread: 1
}
