import QtQuick
import qs.Commons

// Everything about how Ragtop's keyboard looks, in one place, so a theme can
// change it without touching the keyboard's logic. Colours follow Omarchy's
// theme live; shapes, measurements and the background come from the keyboard
// style (styles/, checked by Service.qml's cleanStyle before it's set here).
QtObject {
  // Background opacity, from Setup › Tablet › Transparency (0 = fully clear).
  property real backgroundOpacity: 1

  // The checked keyboard style; see Service.qml's cleanStyle for each field.
  property var style: ({ shape: "rounded", radius: "auto", border: 1, gap: 6, labelScale: 1,
                         depth: 4, chamfer: 8, background: "tint" })

  // "tint" (a flat colour), "blur" (the same, with what's behind blurred by
  // Hyprland) or "gradient" (towards the accent colour at the top).
  property string backgroundStyle: style.background
  property color background: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, backgroundOpacity)
  property color gradientTop: Qt.tint(Color.background, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18))
  property color backgroundTop: backgroundStyle === "gradient"
    ? Qt.rgba(gradientTop.r, gradientTop.g, gradientTop.b, backgroundOpacity)
    : background
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
  // The Outline shape's edges, which carry the key on their own.
  property color outline: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.45)

  // "rounded", "rectangle", "pill", "outline", "keycap" or "angular".
  property string keyShape: style.shape
  property real keyRadius: style.radius === "auto" ? Math.max(Style.cornerRadius, 6) : style.radius
  property real keyBorderWidth: style.border
  // Keycap: how far the key's side shows below its face. Angular: how much
  // of each corner is cut off.
  property real keyDepth: style.depth
  property real keyChamfer: style.chamfer
  property int gap: style.gap
  property int padding: 8

  property string fontFamily: Style.font.family
  property real fontScale: 1.25
  property real labelScale: style.labelScale
}
