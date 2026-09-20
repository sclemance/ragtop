import QtQuick

// Touch controls for Omarchy's preview-carousel pickers: the theme picker
// and the background picker, both its image picker (layer
// omarchy-image-selector).
//
// The carousel is driven by Left, Right, Return and Escape. Its slices can
// be tapped, but the one that matters is the big preview in the middle, and
// stepping to the next theme means hitting a narrow slice beside it, with
// the scrim — which cancels the picker — all around. The keyboard would do
// the job, except it covers the very preview the picker exists to show. So
// Ragtop puts those four keys in a strip along the bottom instead, sent
// through the same helper the keyboard uses, and draws it from the
// keyboard's own theme so the two read as one panel.
//
// Only shown while the picker runs as a Ragtop clone: a stock picker takes
// every touch on the screen (see overlay-clones.sh), so the strip's own
// taps would never reach it.
Item {
  id: root

  // Service.qml: sendKeys(command).
  required property var service
  required property var theme

  // Prev and Next repeat while held, as the keyboard's arrows do; Select and
  // Cancel are taps. `pad` puts air before a button, keeping the one that
  // throws the picker away from the three that work it.
  readonly property var buttons: [
    { name: "prev", keysym: "Left", label: "", icon: "left", kind: "special", units: 1.6, hold: true, pad: 0 },
    { name: "select", keysym: "Return", label: "Select", icon: "", kind: "accent", units: 3, hold: false, pad: 0 },
    { name: "next", keysym: "Right", label: "", icon: "right", kind: "special", units: 1.6, hold: true, pad: 0 },
    { name: "cancel", keysym: "Escape", label: "Cancel", icon: "", kind: "special", units: 3, hold: false, pad: 1.2 }
  ]

  // Sized like the keyboard's keys, so the strip is the keyboard's bottom
  // row in every respect but what it sends.
  readonly property real totalUnits: buttons.reduce(function(a, b) { return a + b.units + b.pad }, 0)
  readonly property real unit: Math.min((width - 2 * theme.padding) / totalUnits, Math.round(84 * theme.keyScale))
  readonly property real keyHeight: Math.max(Math.round(36 * theme.keyScale),
    Math.min(Math.round(unit * 0.78), Math.round(60 * theme.keyScale)))
  readonly property real topPadding: theme.padding + theme.edgeFade + theme.edgeBorder

  implicitHeight: topPadding + keyHeight + theme.padding

  // Where each button sits, centred as a row; the same shape as the
  // keyboard's slots so KeyboardKey can be dropped straight in.
  readonly property var slots: {
    var gap = root.theme.gap
    var out = []
    var x = (root.width - root.unit * root.totalUnits) / 2
    root.buttons.forEach(function(b) {
      x += b.pad * root.unit
      out.push({ button: b, x: x + gap / 2, y: root.topPadding,
                 width: b.units * root.unit - gap, height: root.keyHeight })
      x += b.units * root.unit
    })
    return out
  }

  function press(button) {
    if (button.hold) service.sendKeys("down " + button.keysym)
    else service.sendKeys("key " + button.keysym)
  }

  function release(button) {
    if (button.hold) service.sendKeys("up " + button.keysym)
  }

  // The background and top edge, shared with the keyboard.
  KeyboardSurface {
    anchors.fill: parent
    theme: root.theme
  }

  Repeater {
    model: root.slots

    Item {
      id: slot
      required property var modelData
      x: modelData.x
      y: modelData.y
      width: modelData.width
      height: modelData.height

      KeyboardKey {
        anchors.fill: parent
        theme: root.theme
        label: slot.modelData.button.label
        kind: slot.modelData.button.kind
        labelKind: slot.modelData.button.icon !== "" ? "drawn" : "word"
        icon: slot.modelData.button.icon
        pressed: touch.pressed
      }

      // Each button's touch area is widened by half a gap, so the gaps
      // between them belong to the nearer button and nothing is dead.
      MouseArea {
        id: touch
        x: -root.theme.gap / 2
        y: -root.theme.gap / 2
        width: parent.width + root.theme.gap
        height: parent.height + root.theme.gap
        onPressed: root.press(slot.modelData.button)
        onReleased: root.release(slot.modelData.button)
        onCanceled: root.release(slot.modelData.button)
      }
    }
  }
}
