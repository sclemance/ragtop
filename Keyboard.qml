import QtQuick

// Ragtop's on-screen keyboard. It draws the keys and decides what each tap
// means; keyboard-helper.py, run by the service, turns that into key events.
// The letter keys are those of the active Hyprland layout, as the helper
// reads them from the keymap (US until it reports), and the symbol pages
// pick up the symbols that layout carries. Characters go by what they are,
// not where they sit, so they type correctly in any layout.
Item {
  id: root

  // Service.qml: sendKeys(command), openSettings(), keyLabels.
  required property var service
  required property var theme

  property string page: "letters"

  // Modifiers: "off", "latched" (applies to the next key) or "locked".
  property var mods: ({ "shift": "off", "ctrl": "off", "alt": "off", "super": "off", "altgr": "off" })
  readonly property bool upper: root.mods.shift !== "off"
  readonly property bool altgrOn: root.mods.altgr !== "off"

  // The extra row of desktop keys, then the pages. A key is its character,
  // or one of the named keys below.
  // AltGr is only there on a layout that puts something on its third level.
  // On a plain US layout there is nothing to reach, so the key would do
  // nothing and the row is better without it.
  readonly property var topRow: ["esc", "tab", "ctrl", "alt", "super"]
    .concat(root.hasLevel3 ? ["altgr"] : [], ["left", "up", "down", "right"], ["windows"])
  readonly property var fallbackRows: [
    [["q","Q"],["w","W"],["e","E"],["r","R"],["t","T"],["y","Y"],["u","U"],["i","I"],["o","O"],["p","P"]],
    [["a","A"],["s","S"],["d","D"],["f","F"],["g","G"],["h","H"],["j","J"],["k","K"],["l","L"]],
    [["z","Z"],["x","X"],["c","C"],["v","V"],["b","B"],["n","N"],["m","M"]]
  ]
  readonly property var layoutRows: root.service.keyLabels && root.service.keyLabels.rows.length === 3
    ? root.service.keyLabels.rows : fallbackRows
  readonly property string layoutName: root.service.keyLabels ? root.service.keyLabels.name : ""
  // Every layout Hyprland has configured, in its order, and which one is on.
  // A hold on the space bar offers the others. Ragtop does not keep a layout
  // of its own, so with one configured there is nothing to offer.
  readonly property var layoutList: root.service.keyLabels && Array.isArray(root.service.keyLabels.layouts)
    ? root.service.keyLabels.layouts : []
  readonly property int activeLayout: root.service.keyLabels && root.service.keyLabels.active >= 0
    ? root.service.keyLabels.active : 0
  // Each letter's shifted character, e.g. "Ü" for "ü".
  readonly property var shiftOf: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { map[k[0]] = k[1] }) })
    return map
  }
  function letters(row) { return row.map(function(k) { return k[0] }) }

  // What AltGr and AltGr with Shift type on each letter key, where the
  // layout has anything there: @ and Ω on a German q, æ and Æ on a French a.
  // The helper reports them as the third and fourth character of the key
  // (see keyboard-helper.py), empty where the level is unused.
  readonly property var level3Of: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { if (k[2]) map[k[0]] = k[2] }) })
    return map
  }
  readonly property var level4Of: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { if (k[3]) map[k[0]] = k[3] }) })
    return map
  }
  readonly property bool hasLevel3: Object.keys(root.level3Of).length > 0

  // The symbol pages, which are the same whatever the layout: every
  // character here types in any of them, because the helper types by
  // character rather than by key.
  readonly property var symbolRows: [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
  ]
  readonly property var moreRows: [
    ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
    ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "`"]
  ]
  readonly property var punctuation: [".", ",", "?", "!", "'"]

  // What the active layout puts on its keys that the pages above don't
  // have: § and ° on a German keyboard, ¡ and ¿ on a Spanish one, № and ₽
  // on a Russian one, nothing at all on a US one. The helper reports them
  // (see keyboard-helper.py); the four that fit go in the two free slots on
  // each page's third row, which is why those rows are a key short.
  readonly property var layoutSymbols: root.service.keyLabels && root.service.keyLabels.symbols
    ? root.service.keyLabels.symbols : []
  readonly property var pageCharacters: symbolRows[0].concat(symbolRows[1], moreRows[0], moreRows[1], punctuation)
  readonly property var extraSymbols: layoutSymbols.filter(function(c) {
    return typeof c === "string" && c.length === 1 && root.pageCharacters.indexOf(c) === -1
  }).slice(0, 4)

  readonly property var pages: ({
    "letters": [
      letters(layoutRows[0]),
      letters(layoutRows[1]),
      ["shift"].concat(letters(layoutRows[2]), ["backspace"]),
      ["symbols", "settings", "space", ".", "enter"]
    ],
    "symbols": [
      symbolRows[0],
      symbolRows[1],
      ["more"].concat(punctuation, extraSymbols.slice(0, 2), ["backspace"]),
      ["letters", "settings", "space", ",", "enter"]
    ],
    "more": [
      moreRows[0],
      moreRows[1],
      ["symbols"].concat(punctuation, extraSymbols.slice(2, 4), ["backspace"]),
      ["letters", "settings", "space", ",", "enter"]
    ],
  })
  // The key back to the letters page names the script, not a language: the
  // layout's own first three letters, so A B C on a Latin layout and А Б В
  // on a Cyrillic one. Sorting by code point gets there without a table —
  // each script's letters are a contiguous run, and the ASCII ones sort
  // ahead of the accented letters a Latin layout adds. Scripts without case
  // are unchanged by toUpperCase, which is what they want.
  readonly property string lettersLabel: {
    var all = []
    root.layoutRows.forEach(function(row) {
      row.forEach(function(k) { if (all.indexOf(k[0]) === -1) all.push(k[0]) })
    })
    all.sort()
    return all.length >= 3 ? all.slice(0, 3).join("").toUpperCase() : "ABC"
  }

  readonly property var labels: ({
    "esc": "Esc", "tab": "Tab", "ctrl": "Ctrl", "alt": "Alt", "super": "Super", "altgr": "AltGr",
    "left": "", "up": "", "down": "", "right": "",
    "shift": "", "backspace": "", "enter": "", "space": "",
    "symbols": "?123", "more": "#+=", "letters": root.lettersLabel, "settings": "",
    "windows": ""
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
  // Keys Ragtop draws an icon for (KeyIcon.qml) instead of a label, so they
  // don't depend on the font carrying a glyph and scale with the keys.
  readonly property var iconKeys: ["left", "up", "down", "right", "shift", "backspace",
                                   "enter", "settings", "windows"]
  // The focus arrows are the same four arrows, drawn under another name.
  readonly property var iconNames: ({
    // Super carries the system's mark, the way it does on a keyboard you
    // can touch.
    "super": "omarchy"
  })
  function iconFor(key) {
    if (key in root.iconNames) return root.iconNames[key]
    return root.iconKeys.indexOf(key) !== -1 ? key : ""
  }
  function labelKind(key) {
    // Super is the key every Omarchy binding is written around, and the mark
    // is on nobody's hardware to learn it from, so it carries both.
    if (key === "super") return "markword"
    if (root.iconFor(key) !== "") return "drawn"
    return root.label(key).length > 1 ? "word" : "char"
  }

  // Keys that must not act until the finger lifts, because acting takes the
  // keyboard off the screen. A surface that unmaps while a touch is still
  // down leaves that touch with nowhere to end, and the next touch-down
  // anywhere is swallowed putting it right: the first tap on whatever
  // replaced the keyboard does nothing. Measured, with a counter on the far
  // side: the touch never arrived at all.
  //
  // This is the same reason a key with variants types on release. That one
  // waits so a hold can become a popup, this one waits so the finger has
  // somewhere to lift from.
  readonly property var liftKeys: ["windows"]

  // Keys that repeat while held: pressed and released with the finger.
  readonly property var holdable: ["backspace", "left", "up", "down", "right"]

  // Hold a letter to reach the characters that belong to it, as every phone
  // keyboard does. Ragtop needs it more than most: the letter rows are the
  // three rows of a physical keyboard, and a layout can keep letters
  // elsewhere — AZERTY has é, è, ç and à on its number row — so without
  // this a French user can't type them at all.
  readonly property var variantTable: ({
    "a": ["à", "â", "á", "ä", "ã", "å", "æ"],
    "c": ["ç", "ć", "č"],
    "d": ["ð", "đ"],
    "e": ["é", "è", "ê", "ë", "ę", "ē"],
    "g": ["ğ"],
    "i": ["î", "ï", "ì", "í", "ī", "ı"],
    "l": ["ł"],
    "n": ["ñ", "ń", "ň"],
    "o": ["ô", "ö", "ò", "ó", "õ", "ø", "œ"],
    "r": ["ř"],
    "s": ["ß", "š", "ś", "ş"],
    "t": ["ţ", "þ"],
    "u": ["û", "ü", "ù", "ú", "ū"],
    "y": ["ÿ", "ý"],
    "z": ["ž", "ź", "ż"]
  })
  // Letters that don't decompose to the key they belong under.
  readonly property var variantBase: ({
    "ß": "s", "æ": "a", "ø": "o", "œ": "o", "ł": "l", "đ": "d", "ð": "d",
    "ı": "i", "ŋ": "n", "þ": "t", "ħ": "h", "ĸ": "k"
  })
  // Letters the active layout types that its letter rows don't carry, from
  // the helper: they go first behind their own base letter, ahead of the
  // table's, since they're the ones that layout's user actually wants.
  readonly property var layoutLetters: root.service.keyLabels && root.service.keyLabels.letters
    ? root.service.keyLabels.letters : []
  readonly property var variantsOf: {
    var map = {}
    for (var base in root.variantTable) map[base] = root.variantTable[base].slice()
    var own = {}
    root.layoutLetters.forEach(function(c) {
      if (typeof c !== "string" || c.length < 1) return
      var lower = c.toLowerCase()
      var base = root.variantBase[lower] || lower.normalize("NFD")[0]
      // The letter it decomposes to, whatever the script: ё belongs behind
      // Cyrillic е as é does behind e. Anything that decomposes to itself
      // is no letter's variant — µ, º and ª come through the keymap as
      // letters but belong to nothing.
      if (base.length !== 1 || base === lower || base.toLowerCase() === base.toUpperCase()) return
      if (!(base in own)) own[base] = []
      if (own[base].indexOf(lower) === -1) own[base].push(lower)
    })
    // The layout's own come first, in the order it has them, then the rest
    // of the table.
    for (var b in own) {
      map[b] = own[b].concat((map[b] || []).filter(function(c) { return own[b].indexOf(c) === -1 }))
    }
    return map
  }

  // What a hold on this key offers: the key itself first, then its
  // variants, in the case the keyboard is currently typing.
  function variantsFor(key) {
    var list = root.variantsOf[key]
    if (!list || list.length === 0) return []
    return [key].concat(list).slice(0, 9).map(function(c) { return root.upper ? c.toUpperCase() : c })
  }

  // What a hold on a key offers: the characters behind a letter, or the
  // layouts behind the space bar. Fewer than two and there is nothing to
  // show, so the key types on the way down as usual.
  function holdItems(key) {
    if (key === "space") return root.layoutList.length > 1 ? root.layoutList : []
    return root.variantsFor(key)
  }


  // Wide enough for the longest word in a list, measured rather than
  // guessed: layout names are proportional text and vary a lot in length.
  TextMetrics {
    id: wordMetrics
    font.family: root.theme.fontFamily
    font.pixelSize: root.theme.wordSize
  }
  function wordCell(items) {
    var widest = 0
    for (var i = 0; i < items.length; i++) {
      wordMetrics.text = items[i]
      widest = Math.max(widest, wordMetrics.width)
    }
    return Math.ceil(widest) + 3 * root.theme.gap
  }

  // Sized so the longest row fits. Layouts differ, 10 to 12 letter keys.
  readonly property real rowUnits: Math.max(10, layoutRows[0].length, layoutRows[1].length, layoutRows[2].length + 3)
  readonly property real unit: Math.min((width - 2 * theme.padding) / rowUnits, Math.round(84 * theme.keyScale))
  // Height follows the size setting, not the width a key happens to get. On
  // a narrow screen the width is spent long before the ladder runs out, so
  // pinning height to it made Larger and Largest render identically to
  // Regular. The cap against `unit` only stops a key becoming a tall ribbon.
  readonly property real keyHeight: Math.max(30,
    Math.min(Math.round(60 * theme.keyScale), Math.round(unit * 1.4)))
  readonly property real topRowHeight: Math.round(keyHeight * 0.62)

  // Where each key sits: { key, x, y, width, height } for every key of the
  // top row and the current page, rows centred. A key's slot is this
  // rectangle; how it's drawn inside is up to KeyboardKey.qml, and never
  // affects which key a touch means.
  // A soft or bordered top edge (Setup › Tablet › Edge) gets its own space
  // above the keys, so it's clear of the first row.
  readonly property real topPadding: root.theme.padding + root.theme.edgeFade + root.theme.edgeBorder

  // Keys that hold a width of their own on the top row, whatever else is
  // sharing it. The windows toggle keeps one place and one size on every
  // page, which is what makes it read as a switch rather than another key,
  // the way the gear does on the row below. Super takes more than its share
  // because it carries a mark and a word, and because it is the key every
  // Omarchy binding is written around.
  readonly property var topRowFixed: ({ "windows": 1, "super": 1.5 })

  // A row that comes up short is stretched to the keyboard's width by its
  // own stretchy keys, rather than floating in the middle with a gap at
  // either end: the space bar on the bottom row, and the wide keys at both
  // ends of a third row (Shift and Backspace, or a page key and Backspace).
  // Rows of plain keys — the letters, the digits — are left alone and stay
  // centred, so the keys keep one size.
  //
  // The letter rows only come up short on some layouts — French's bottom row
  // is six keys (w x c v b n; m sits above it) against eleven on the row
  // above, so its Shift and Backspace grow to reach the edges — while the
  // symbol pages' third row is short everywhere, and its page key and
  // Backspace take the slack on any layout.
  function stretch(row, widths) {
    var slack = root.unit * root.rowUnits - widths.reduce(function(a, b) { return a + b }, 0)
    if (slack <= 1) return widths
    var space = row.indexOf("space")
    if (space !== -1) {
      widths[space] += slack
    } else if (row.length > 1 && (row[0] in root.widths) && (row[row.length - 1] in root.widths)) {
      widths[0] += slack / 2
      widths[widths.length - 1] += slack / 2
    }
    return widths
  }

  readonly property var slots: {
    var rows = [root.topRow].concat(root.pages[root.page])
    var gap = root.theme.gap
    var out = []
    var y = root.topPadding
    rows.forEach(function(row, i) {
      // The top row spreads its keys over the full width, less whatever the
      // windows toggle holds at the end of it.
      var fixedUnits = 0, sharers = 0
      if (i === 0) {
        row.forEach(function(k) {
          if (k in root.topRowFixed) fixedUnits += root.topRowFixed[k]
          else sharers++
        })
      }
      var share = sharers > 0
        ? root.unit * (root.rowUnits - fixedUnits) / sharers
        : root.unit * root.rowUnits / row.length
      var widths = row.map(function(k) {
        if (i !== 0) return root.unit * (root.widths[k] || 1)
        return k in root.topRowFixed ? root.unit * root.topRowFixed[k] : share
      })
      if (i > 0) widths = root.stretch(row, widths)
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

  // How far the keys reach across. On a wide screen the keyboard spans the
  // whole width while the keys stay a comfortable size, leaving a margin
  // either side of the keys that is not aimed at the keyboard.
  readonly property real keysLeft: slots.reduce(function(a, s) { return Math.min(a, s.x) }, root.width)
  readonly property real keysRight: slots.reduce(function(a, s) { return Math.max(a, s.x + s.width) }, 0)

  Item {
    id: keysBounds
    x: Math.max(0, root.keysLeft - root.theme.gap)
    width: Math.min(root.width - x, root.keysRight - root.keysLeft + 2 * root.theme.gap)
    y: 0
    height: root.height
  }
  // What the surface takes touches on (the service masks it to this): you
  // can only touch through the keyboard where it isn't there. With a drawn
  // background the whole surface takes them, so a tap in the margins does
  // nothing rather than reaching a window the background hides; when the
  // background is fully clear there is nothing to hide, and the margins
  // pass taps through — tapping away from a menu closes it.
  readonly property Item touchArea: root.theme.backgroundVisible ? root : keysBounds

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
    // Only near a key: a touch well past the ends of the rows isn't aimed
    // at the keyboard at all.
    return bestDist <= Math.pow(root.unit * 0.75, 2) ? best : null
  }

  function label(key) {
    if (key === "space") return layoutName
    if (key in labels) return labels[key]
    return root.charFor(key)
  }

  function shifted(key) {
    return shiftOf[key] || key.toUpperCase()
  }

  // The character a key types with the modifiers as they are. A cap shows
  // this, so what is written on a key is always what tapping it gives you.
  // A key with nothing on its third level types its own character, the way
  // it would with AltGr held on a physical keyboard that has nothing there.
  function charFor(key) {
    if (root.altgrOn) {
      var deep = root.upper ? (root.level4Of[key] || root.level3Of[key]) : root.level3Of[key]
      if (deep) return deep
    }
    return root.upper ? root.shifted(key) : key
  }

  // How a key is coloured, which follows what it does: a key that produces a
  // character is drawn as a letter, and one that acts on the next key or on
  // the keyboard itself is drawn apart from them.
  function kind(key) {
    if (key === "settings" && root.service.toolsOpen) return "locked"
    // Super is the key Omarchy is built around, so at rest it is drawn the
    // way Enter is rather than as another grey modifier. Armed, it drops
    // back to the latched and locked colours, because what it is doing then
    // matters more than how important it is.
    if (key === "super")
      return mods["super"] === "locked" ? "locked"
        : mods["super"] === "latched" ? "latched" : "accent"
    if (key in mods) return mods[key] === "locked" ? "locked" : mods[key] === "latched" ? "latched" : "special"
    if (key === "enter") return "accent"
    // The space bar goes with them rather than with the letters, though it
    // does type a character: it is part of the frame around the letters, it
    // carries the layout's name instead of a legend, and no one hunts for it.
    return key in labels ? "special" : "normal"
  }

  // Modifiers applied to the next key, as the helper names them. AltGr is
  // not one of them: it chooses which character a key types (charFor), and
  // that character is then typed as itself, so a layout's third level works
  // the same whether or not the character has a key of its own.
  function activeMods(includeShift) {
    var names = []
    for (var m in mods)
      if (m !== "altgr" && mods[m] !== "off" && (includeShift || m !== "shift")) names.push(m)
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

  // Off, then latched for the next key, then locked, then off again. The
  // second tap locks however long it comes after the first, because a latch
  // only lives until the next key is sent (afterKey), and a tap on another
  // modifier is not a key. So "tapped again while still latched" says all a
  // timer used to say, without asking anyone to be quick about it: Super,
  // Shift, Super locks Super, and the B that follows launches the browser,
  // drops the latched Shift and leaves Super on.
  function tapModifier(name) {
    var state = mods[name]
    if (state === "off") {
      setMod(name, "latched")
    } else if (state === "latched") {
      setMod(name, "locked")
    } else {
      setMod(name, "off")
    }
  }

  function press(key) {
    if (key in mods) { tapModifier(key); return }
    if (key === "windows") {
      // Straight into tiling, rather than to a page of keys that say the
      // same things. It waits for the finger to lift because it takes the
      // keyboard off the screen: see liftKeys.
      root.service.openTiling()
      return
    }
    switch (key) {
    case "symbols": case "more": case "letters":
      page = key
      return
    case "settings":
      // Ragtop's controls come up over the keyboard rather than in place of
      // it, so the keys stay under them while you change how they look. The
      // gear stays where it is and reads as held down while they are open.
      root.service.toolsOpen = !root.service.toolsOpen
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
        service.sendKeys("type " + root.charFor(key))
    }
    afterKey()
  }

  function release(key) {
    if (root.liftKeys.indexOf(key) !== -1) {
      root.press(key)
      return
    }
    if (holdable.indexOf(key) !== -1) {
      service.sendKeys("up " + keysyms[key])
      afterKey()
    }
  }

  // A hold in progress: the finger that started it and the key under it,
  // until the timer turns it into a popup or the finger lifts and it turns
  // out to have been a tap.
  property int pendingPoint: -1
  property string pendingKey: ""
  property real pendingX: 0
  property real pendingY: 0
  Timer { id: holdTimer; interval: 420; onTriggered: root.openPopup() }

  // The open popup: { key, items, pointId, index, x, y, cellWidth,
  // cellHeight }, or null. It's a plain object, so changing it means
  // replacing it. Only one at a time, as on a phone.
  property var popup: null

  // As high as a popup can sit: where the card it is drawn on begins at the
  // same place the keys do. The card reaches theme.gap past the popup on
  // every side, so a popup at the very top of the keyboard puts the card's
  // top border outside the surface, where it is cut off. The extra row is
  // shorter than a letter key, so a popup for the top letter row always
  // asks to go higher than the keyboard reaches and always lands here.
  readonly property real popupTop: root.topPadding + root.theme.gap

  function startHold(point, key) {
    root.pendingPoint = point.pointId
    root.pendingKey = key
    root.pendingX = point.x
    root.pendingY = point.y
    holdTimer.restart()
  }

  function endHold() {
    holdTimer.stop()
    root.pendingPoint = -1
    root.pendingKey = ""
  }

  // The popup sits above its key, its first cell over the key so the finger
  // starts on the letter it's already holding, and it slides along the row
  // to stay on the keyboard. Where it can't fit at all it's centred.
  function openPopup() {
    var key = root.pendingKey
    var items = root.holdItems(key)
    if (items.length < 2 || root.pendingPoint === -1) return
    var layouts = key === "space"
    var slot = null
    for (var i = 0; i < root.slots.length; i++) if (root.slots[i].key === key) { slot = root.slots[i]; break }
    if (!slot) return
    var room = root.width - 2 * root.theme.padding
    var cell = layouts ? Math.min(root.wordCell(items), room / items.length)
      : Math.max(slot.width + root.theme.gap, root.unit * 0.92)
    var total = items.length * cell
    // Characters start their first cell over the key being held, so the
    // finger is already on the one it holds. Layout names are a list rather
    // than a row of keys, so they sit centred on the space bar.
    var from = layouts ? slot.x + (slot.width - total) / 2 : slot.x
    var x = total > room ? (root.width - total) / 2
      : Math.min(Math.max(from, root.theme.padding), root.width - root.theme.padding - total)
    root.popup = { key: key, kind: layouts ? "layouts" : "chars",
                   items: items, pointId: root.pendingPoint, index: 0,
                   x: x, y: Math.max(root.popupTop, slot.y - slot.height - root.theme.gap),
                   cellWidth: cell, cellHeight: slot.height }
    root.selectAt(root.pendingX, root.pendingY)
  }

  // Which cell the finger is on. Sliding well below the popup takes
  // nothing, the way letting go somewhere else cancels on a phone.
  function selectAt(x, y) {
    var p = root.popup
    if (!p) return
    var index = -1
    // Characters reach a cell from the key below, since the popup's first
    // cell sits over the key being held and the finger is already on it.
    // Layouts are centred on the space bar instead and none of them is the
    // one you are on, so nothing is chosen until the finger is actually on
    // the card. Otherwise holding space and lifting would change the
    // system's layout without the finger ever moving.
    var within = p.kind === "layouts"
      ? (y >= p.y && y <= p.y + p.cellHeight)
      : y < p.y + p.cellHeight + root.keyHeight
    if (within) {
      index = Math.max(0, Math.min(p.items.length - 1, Math.floor((x - p.x) / p.cellWidth)))
    }
    if (index === p.index) return
    var next = Object.assign({}, p)
    next.index = index
    root.popup = next
  }

  function choosePopup() {
    var p = root.popup
    root.popup = null
    root.endHold()
    if (!p || p.index < 0) return
    if (p.kind === "layouts") {
      if (p.index !== root.activeLayout) root.service.switchLayout(p.index)
      return
    }
    root.service.sendKeys("type " + p.items[p.index])
    root.afterKey()
  }

  // Keys held down by a finger (or the mouse), as touch point id -> key.
  property var held: ({})
  readonly property var heldKeys: {
    var keys = {}
    for (var id in held) keys[held[id]] = true
    return keys
  }

  // The background and top edge, shared with the picker nav strip.
  KeyboardSurface {
    anchors.fill: parent
    theme: root.theme
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
      hint: root.altgrOn ? "" : (root.level3Of[modelData.key] || "")
      kind: root.kind(modelData.key)
      labelKind: root.labelKind(modelData.key)
      icon: root.iconFor(modelData.key)
      pressed: modelData.key in root.heldKeys
    }
  }

  // The popup, drawn over the rows above its key. It takes no touches of
  // its own: the finger that opened it is still down on the keyboard's own
  // touch layer, which follows it (see selectAt).
  Item {
    id: popupLayer
    visible: root.popup !== null
    z: 10
    x: root.popup ? root.popup.x : 0
    y: root.popup ? root.popup.y : 0
    width: root.popup ? root.popup.items.length * root.popup.cellWidth : 0
    height: root.popup ? root.popup.cellHeight : 0

    // Its own panel, opaque whatever the keyboard's transparency, and edged
    // in the theme's accent so it reads as something floating over the keys
    // rather than another row of them.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -root.theme.gap
      radius: root.theme.keyRadius + root.theme.gap / 2
      color: root.theme.solidBase
      border.width: Math.max(1, root.theme.keyBorderWidth)
      border.color: root.theme.accent
    }

    Repeater {
      model: root.popup ? root.popup.items : []

      KeyboardKey {
        required property int index
        required property string modelData
        theme: root.theme
        x: index * (root.popup ? root.popup.cellWidth : 0) + root.theme.gap / 2
        width: (root.popup ? root.popup.cellWidth : 0) - root.theme.gap
        height: parent.height
        label: modelData
        labelKind: root.popup && root.popup.kind === "layouts" ? "word" : "char"
        // The cell under the finger is filled, not merely edged: it is
        // usually half covered by that finger. "accent" no longer fills,
        // since Enter took it and became an edge, so this takes "locked".
        kind: root.popup && index === root.popup.index ? "locked"
          : root.popup && root.popup.kind === "layouts" && index === root.activeLayout ? "special"
          : "normal"
        opaque: true
      }
    }
  }

  // One touch layer for the whole keyboard: each finger picks its key when
  // it comes down and keeps it until it lifts, however it moves. Several
  // fingers can be down at once, e.g. the next key tapped before the last
  // is released.
  MultiPointTouchArea {
    anchors.fill: parent
    onPressed: function(points) {
      // While the controls are up, a touch on the keyboard puts them away
      // rather than typing. That is the tap-outside-to-dismiss, done from the
      // surface the finger is already on instead of a sheet over everything,
      // which would take the tile's own touches with it. Decided once for the
      // whole event: inside the loop, the first finger closed them and the
      // second read them as already closed and typed a letter.
      if (root.service.toolsOpen) {
        root.service.toolsOpen = false
        return
      }
      var next = Object.assign({}, root.held)
      var pressed = []
      points.forEach(function(p) {
        // While a popup is open the other fingers wait their turn. A pending
        // space hold is not one to wait for, since space has already typed.
        if (root.popup !== null
            || (root.pendingPoint !== -1 && root.pendingKey !== "space")) return
        var key = root.keyAt(p.x, p.y)
        if (key === null) return
        next[p.pointId] = key
        // A key with variants types on release instead, so a hold can turn
        // into a popup rather than a letter that's already been typed. The
        // space bar is not one of those. It types on the way down as it
        // always has, and its hold runs alongside, because a thumb resting
        // on space must not swallow the letter rolling in after it.
        if (root.holdItems(key).length > 1) root.startHold(p, key)
        if (root.liftKeys.indexOf(key) === -1
            && (key === "space" || root.holdItems(key).length <= 1)) pressed.push(key)
      })
      root.held = next
      pressed.forEach(root.press)
    }
    onUpdated: function(points) { points.forEach(root.moved) }
    onReleased: function(points) { root.lift(points) }
    onCanceled: function(points) { root.lift(points) }
  }

  function moved(point) {
    if (root.popup !== null && point.pointId === root.popup.pointId) {
      root.selectAt(point.x, point.y)
      return
    }
    // A finger that wanders off the key it came down on was never holding
    // it: the key still types when it lifts, as it always has.
    if (point.pointId !== root.pendingPoint) return
    if (Math.abs(point.x - root.pendingX) + Math.abs(point.y - root.pendingY) > root.unit * 0.4)
      holdTimer.stop()
  }

  function lift(points) {
    var next = Object.assign({}, root.held)
    var lifted = []
    points.forEach(function(p) {
      if (root.popup !== null && p.pointId === root.popup.pointId) {
        root.choosePopup()
      } else if (p.pointId === root.pendingPoint) {
        var key = root.pendingKey
        root.endHold()
        if (key !== "space") root.press(key)  // a tap after all, and space already did
      } else if (p.pointId in next) {
        lifted.push(next[p.pointId])
      }
      delete next[p.pointId]
    })
    root.held = next
    lifted.forEach(root.release)
  }
}
