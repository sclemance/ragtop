import QtQuick

// Ragtop's on-screen keyboard. It draws the keys and decides what each tap
// means; keyboard-helper.py, run by the service, turns that into key events.
// The letter keys are those of the active Hyprland layout, as the helper
// reads them from the keymap (US until it reports). Characters go by what
// they are, not where they sit, so they type correctly in any layout.
Item {
  id: root

  // Service.qml: sendKeys(command), openSettings(), modifierMode, keyLabels.
  required property var service
  required property var theme

  property string page: "letters"
  // Modifiers: "off", "latched" (applies to the next key) or "locked".
  property var mods: ({ "shift": "off", "ctrl": "off", "alt": "off", "super": "off" })
  readonly property bool oneShot: root.service.modifierMode !== "sticky"
  readonly property bool upper: root.mods.shift !== "off"

  // The extra row of desktop keys, then the pages. A key is its character,
  // or one of the named keys below.
  readonly property var topRow: ["esc", "tab", "ctrl", "alt", "super", "left", "up", "down", "right"]
  readonly property var fallbackRows: [
    [["q","Q"],["w","W"],["e","E"],["r","R"],["t","T"],["y","Y"],["u","U"],["i","I"],["o","O"],["p","P"]],
    [["a","A"],["s","S"],["d","D"],["f","F"],["g","G"],["h","H"],["j","J"],["k","K"],["l","L"]],
    [["z","Z"],["x","X"],["c","C"],["v","V"],["b","B"],["n","N"],["m","M"]]
  ]
  readonly property var layoutRows: root.service.keyLabels && root.service.keyLabels.rows.length === 3
    ? root.service.keyLabels.rows : fallbackRows
  readonly property string layoutName: root.service.keyLabels ? root.service.keyLabels.name : ""
  // Each letter's shifted character, e.g. "Ü" for "ü".
  readonly property var shiftOf: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { map[k[0]] = k[1] }) })
    return map
  }
  function letters(row) { return row.map(function(k) { return k[0] }) }

  readonly property var pages: ({
    "letters": [
      letters(layoutRows[0]),
      letters(layoutRows[1]),
      ["shift"].concat(letters(layoutRows[2]), ["backspace"]),
      ["symbols", "settings", "space", ".", "enter"]
    ],
    "symbols": [
      ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
      ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
      ["more", ".", ",", "?", "!", "'", "backspace"],
      ["letters", "settings", "space", ",", "enter"]
    ],
    "more": [
      ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
      ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "`"],
      ["symbols", ".", ",", "?", "!", "'", "backspace"],
      ["letters", "settings", "space", ",", "enter"]
    ]
  })
  readonly property var labels: ({
    "esc": "Esc", "tab": "Tab", "ctrl": "Ctrl", "alt": "Alt", "super": "Super",
    "left": "←", "up": "↑", "down": "↓", "right": "→",
    "shift": "⇧", "backspace": "⌫", "enter": "⏎", "space": "",
    "symbols": "?123", "more": "#+=", "letters": "ABC", "settings": String.fromCodePoint(0xf0493)
  })
  readonly property var widths: ({
    "shift": 1.5, "backspace": 1.5, "symbols": 1.5, "more": 1.5, "letters": 1.5,
    "space": 4.5, "enter": 2
  })
  // Keys sent as key events, by the name xkb gives them.
  readonly property var keysyms: ({
    "esc": "Escape", "tab": "Tab", "left": "Left", "up": "Up", "down": "Down", "right": "Right",
    "backspace": "BackSpace", "enter": "Return", "space": "space"
  })
  // Keys that repeat while held: pressed and released with the finger.
  readonly property var holdable: ["backspace", "left", "up", "down", "right"]

  // Sized so the longest row fits; layouts differ (10 to 12 letter keys).
  readonly property real rowUnits: Math.max(10, layoutRows[0].length, layoutRows[1].length, layoutRows[2].length + 3)
  readonly property real unit: Math.min((width - 2 * theme.padding) / rowUnits, 84)
  readonly property real keyHeight: Math.max(40, Math.min(Math.round(unit * 0.78), 60))
  readonly property real topRowHeight: Math.round(keyHeight * 0.62)

  // Where each key sits: { key, x, y, width, height } for every key of the
  // top row and the current page, rows centred. A key's slot is this
  // rectangle; how it's drawn inside is up to KeyboardKey.qml, and never
  // affects which key a touch means.
  readonly property var slots: {
    var rows = [root.topRow].concat(root.pages[root.page])
    var gap = root.theme.gap
    var out = []
    var y = root.theme.padding
    rows.forEach(function(row, i) {
      // The top row spreads its keys over the full width.
      var widths = row.map(function(k) {
        return i === 0 ? root.unit * root.rowUnits / root.topRow.length : root.unit * (root.widths[k] || 1)
      })
      var h = i === 0 ? root.topRowHeight : root.keyHeight
      var x = (root.width - widths.reduce(function(a, b) { return a + b }, 0)) / 2
      row.forEach(function(k, j) {
        out.push({ key: k, x: x + gap / 2, y: y, width: widths[j] - gap, height: h })
        x += widths[j]
      })
      y += h + gap
    })
    return out
  }
  readonly property real slotsBottom: slots.length > 0
    ? slots[slots.length - 1].y + slots[slots.length - 1].height : 0

  implicitHeight: slotsBottom + theme.padding

  // The key a touch at (x, y) means: the one whose slot is nearest, so a
  // touch in a gap goes to the closer key and the keys at a row's ends
  // reach the keyboard's edges. Measured to the slot's edges, not its
  // centre, so a touch on a wide key like the space bar is always that key.
  function keyAt(x, y) {
    var best = null, bestDist = Infinity
    for (var i = 0; i < slots.length; i++) {
      var s = slots[i]
      var dx = Math.max(s.x - x, 0, x - (s.x + s.width))
      var dy = Math.max(s.y - y, 0, y - (s.y + s.height))
      var d = dx * dx + dy * dy
      if (d < bestDist) { bestDist = d; best = s.key }
    }
    return best
  }

  function label(key) {
    if (key === "space") return layoutName
    if (key in labels) return labels[key]
    return upper ? shifted(key) : key
  }

  function shifted(key) {
    return shiftOf[key] || key.toUpperCase()
  }

  function kind(key) {
    if (key in mods) return mods[key] === "locked" ? "locked" : mods[key] === "latched" ? "latched" : "special"
    if (key === "enter") return "accent"
    return key in labels ? "special" : "normal"
  }

  // Modifiers applied to the next key, as the helper names them.
  function activeMods(includeShift) {
    var names = []
    for (var m in mods) if (mods[m] !== "off" && (includeShift || m !== "shift")) names.push(m)
    return names
  }

  function setMod(name, state) {
    var next = Object.assign({}, mods)
    next[name] = state
    mods = next
  }

  // Latched modifiers are used up by the next key.
  function afterKey() {
    var next = Object.assign({}, mods)
    for (var m in next) if (next[m] === "latched") next[m] = "off"
    mods = next
  }

  function tapModifier(name) {
    var state = mods[name]
    if (!oneShot) {
      setMod(name, state === "off" ? "locked" : "off")
    } else if (state === "off") {
      setMod(name, "latched")
      doubleTap.name = name
      doubleTap.restart()
    } else if (state === "latched" && doubleTap.running && doubleTap.name === name) {
      setMod(name, "locked")  // a quick second tap locks it on
    } else {
      setMod(name, "off")
    }
  }

  Timer { id: doubleTap; interval: 400; property string name: "" }

  function press(key) {
    if (key in mods) { tapModifier(key); return }
    switch (key) {
    case "symbols": case "more": case "letters":
      page = key
      return
    case "settings":
      service.openSettings()
      return
    }
    if (holdable.indexOf(key) !== -1) {
      service.sendKeys(["down", keysyms[key]].concat(activeMods(true)).join(" "))
      return
    }
    if (key in keysyms) {
      service.sendKeys(["key", keysyms[key]].concat(activeMods(true)).join(" "))
    } else {
      // A character: typed as itself unless Ctrl, Alt or Super make it a
      // shortcut, which goes by the key (Ctrl+C, not Ctrl+"C").
      var combo = activeMods(false)
      if (combo.length > 0)
        service.sendKeys(["key", key].concat(activeMods(true)).join(" "))
      else
        service.sendKeys("type " + (upper ? shifted(key) : key))
    }
    afterKey()
  }

  function release(key) {
    if (holdable.indexOf(key) !== -1) {
      service.sendKeys("up " + keysyms[key])
      afterKey()
    }
  }

  // Keys held down by a finger (or the mouse), as touch point id -> key.
  property var held: ({})
  readonly property var heldKeys: {
    var keys = {}
    for (var id in held) keys[held[id]] = true
    return keys
  }

  // Flat unless the style's background is a gradient (see KeyboardTheme).
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: root.theme.backgroundTop }
      GradientStop { position: 1; color: root.theme.background }
    }
  }

  Repeater {
    model: root.slots

    KeyboardKey {
      required property var modelData
      theme: root.theme
      x: modelData.x
      y: modelData.y
      width: modelData.width
      height: modelData.height
      label: root.label(modelData.key)
      kind: root.kind(modelData.key)
      pressed: modelData.key in root.heldKeys
    }
  }

  // One touch layer for the whole keyboard: each finger picks its key when
  // it comes down and keeps it until it lifts, however it moves. Several
  // fingers can be down at once, e.g. the next key tapped before the last
  // is released.
  MultiPointTouchArea {
    anchors.fill: parent
    onPressed: function(points) {
      var next = Object.assign({}, root.held)
      var pressed = []
      points.forEach(function(p) {
        var key = root.keyAt(p.x, p.y)
        if (key === null) return
        next[p.pointId] = key
        pressed.push(key)
      })
      root.held = next
      pressed.forEach(root.press)
    }
    onReleased: function(points) { root.lift(points) }
    onCanceled: function(points) { root.lift(points) }
  }

  function lift(points) {
    var next = Object.assign({}, root.held)
    var lifted = []
    points.forEach(function(p) {
      if (!(p.pointId in next)) return
      lifted.push(next[p.pointId])
      delete next[p.pointId]
    })
    root.held = next
    lifted.forEach(root.release)
  }
}
