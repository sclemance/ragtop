import QtQuick

// One reusable animation per cap, not a growing list of waves. The same
// amount drives colour and neighbour dimming; shadow geometry stays fixed.
Item {
  id: ripple
  property bool active: false
  property bool pressed: false
  property color baseColor: "transparent"
  property color pressColor: "transparent"
  property real floorWhiteMix: 0
  property real amount: 0
  property bool neighbourWave: false
  readonly property real brightness: pressed || !neighbourWave ? 1 : 1 - 0.5 * amount
  readonly property real whiteMix: pressed || !neighbourWave ? 0 : floorWhiteMix * amount
  readonly property color color: Qt.rgba(
    baseColor.r + (pressColor.r - baseColor.r) * amount,
    baseColor.g + (pressColor.g - baseColor.g) * amount,
    baseColor.b + (pressColor.b - baseColor.b) * amount, baseColor.a)
  readonly property bool running: wave.running || rise.running || fall.running

  function stop() { wave.stop(); rise.stop(); fall.stop() }
  function reset() { stop(); amount = 0; neighbourWave = false }
  // Loading the helper while a key is already held must preserve its pressed
  // light, even when QML initializes the colour bindings after `pressed`.
  function settle() { reset(); if (active && pressed) amount = 1 }
  function pulse(distance) {
    if (!active || pressed || !isFinite(distance) || distance < 0 || distance > 2.4) return
    stop()
    neighbourWave = true
    arrival.duration = Math.round(distance * 65)
    // Distance delays arrival; every neighbour reaches the full press colour.
    crest.to = 1
    wave.start()
  }
  function updatePress() {
    if (!active) { reset(); return }
    stop()
    neighbourWave = false
    if (pressed) rise.start()
    else fall.start()
  }
  onPressedChanged: updatePress()
  onActiveChanged: settle()
  onBaseColorChanged: settle()
  onPressColorChanged: settle()
  Component.onCompleted: settle()

  SequentialAnimation {
    id: wave
    PauseAnimation { id: arrival }
    NumberAnimation { id: crest; target: ripple; property: "amount"; duration: 90; easing.type: Easing.InOutQuad }
    NumberAnimation { target: ripple; property: "amount"; to: 0; duration: 300; easing.type: Easing.OutQuad }
  }
  NumberAnimation { id: rise; target: ripple; property: "amount"; to: 1; duration: 90; easing.type: Easing.InOutQuad }
  NumberAnimation { id: fall; target: ripple; property: "amount"; to: 0; duration: 300; easing.type: Easing.OutQuad }
}
