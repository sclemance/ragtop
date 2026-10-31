import QtQuick

// A stand-in for KeyboardKey.qml, which draws through Omarchy's qs.Ui and
// so cannot load here. The strip test checks which item a touch means, not
// how a key looks, so this takes the properties and draws nothing.
Item {
  property var theme
  property string label: ""
  property string labelKind: "char"
  property string kind: "normal"
  property bool pressed: false
  readonly property real depth: Math.min(theme.keyDepth, height * theme.maxDepthFraction)
  readonly property real faceHeight: height - depth
  readonly property real faceY: pressed ? depth * theme.pressSink : 0
}
