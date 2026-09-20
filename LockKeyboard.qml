import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons

// On-screen keyboard for Omarchy's lock screen in tablet mode. The lock
// screen is a session lock, which hides every other surface, the on-screen
// keyboard included, so Ragtop's patched clone of it (overlay-clones.sh) loads
// this inside it and sets `view` to its LockView. Keys edit the password through
// LockView's own signals, the path typing takes, so checking it is untouched.
// From the service it takes only data, never code: the active layout's letters
// and symbols, and the key style's shape and measurements, each re-checked
// here by this file's own rules.
//
// Deliberately separate from Keyboard.qml: it shares no code with it, so
// nothing added to the desktop keyboard reaches the lock screen unless it's
// added here too. It only edits the password text: no key events, no helper,
// no modifiers other than Shift. It copies the desktop keyboard's key shapes
// and proportions, in the lock screen's own colours (Color.lock), and takes
// only the key style's shape and measurements, never its background.
Item {
  id: root

  property var view: null
  readonly property bool typing: view !== null && view.inputEnabled && !view.authenticatingPassword

  property string page: "letters"
  property bool shift: false
  property bool capsLock: false
  readonly property bool upper: shift || capsLock

  // The active layout's letter keys, which Ragtop's service writes when its
  // keyboard helper reads them from the keymap, so these keys type what the
  // physical keyboard would. Checked before use; US if missing or malformed.
  readonly property var usRows: [
    [["q","Q"],["w","W"],["e","E"],["r","R"],["t","T"],["y","Y"],["u","U"],["i","I"],["o","O"],["p","P"]],
    [["a","A"],["s","S"],["d","D"],["f","F"],["g","G"],["h","H"],["j","J"],["k","K"],["l","L"]],
    [["z","Z"],["x","X"],["c","C"],["v","V"],["b","B"],["n","N"],["m","M"]]
  ]
  property var layoutRows: usRows
  property string layoutName: ""
  // The symbols the active layout carries that the pages below don't (§ and
  // ° on a German keyboard, ¡ and ¿ on a Spanish one). Same source, checked
  // by this file's own rules: single printable characters, nothing that
  // could pass for a control or run away with the layout.
  property var layoutSymbols: []

  function cleanSymbols(raw) {
    if (!Array.isArray(raw)) return []
    return raw.filter(function(c) {
      return typeof c === "string" && Array.from(c).length === 1 && c.trim() === c
        && c.charCodeAt(0) >= 0x20 && c.charCodeAt(0) !== 0x7f
    }).slice(0, 24)
  }

  function validLayout(layout) {
    if (!layout || !Array.isArray(layout.rows) || layout.rows.length !== 3) return false
    return layout.rows.every(function(row) {
      return Array.isArray(row) && row.length > 0 && row.length <= 13 && row.every(function(k) {
        return Array.isArray(k) && k.length === 2 && k.every(function(c) {
          return typeof c === "string" && c.length >= 1 && c.length <= 2 && c.trim() === c
        })
      })
    })
  }

  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ragtop-layout.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var layout = null
      try { layout = JSON.parse(text()) } catch (e) {}
      var ok = root.validLayout(layout)
      root.layoutRows = ok ? layout.rows : root.usRows
      root.layoutName = ok && typeof layout.name === "string" ? layout.name.slice(0, 40) : ""
      root.layoutSymbols = ok ? root.cleanSymbols(layout.symbols) : []
      root.layoutLetters = ok ? root.cleanSymbols(layout.letters) : []
    }
    onLoadFailed: {
      root.layoutRows = root.usRows
      root.layoutName = ""
      root.layoutSymbols = []
      root.layoutLetters = []
    }
  }

  // Each letter's shifted character, e.g. "Ü" for "ü".
  readonly property var shiftOf: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { map[k[0]] = k[1] }) })
    return map
  }
  function letters(row) { return row.map(function(k) { return k[0] }) }

  // Rows of keys; a key is its text, or one of the named keys below. Widths
  // are in units of a letter key. The symbol pages are the same in every
  // layout, and the two free slots on each one's third row take what that
  // layout adds (see layoutSymbols): a password is typed in characters, so
  // the ones your keyboard carries have to be reachable here too.
  readonly property var symbolRows: [
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
  ]
  readonly property var moreRows: [
    ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
    ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "`"]
  ]
  readonly property var punctuation: [".", ",", "?", "!", "'"]
  readonly property var pageCharacters: symbolRows[0].concat(symbolRows[1], moreRows[0], moreRows[1], punctuation)
  readonly property var extraSymbols: layoutSymbols.filter(function(c) {
    return root.pageCharacters.indexOf(c) === -1
  }).slice(0, 4)

  // Hold a letter for the characters that belong to it, as the desktop
  // keyboard does and as every phone keyboard does. A password is typed in
  // characters, and a layout can keep letters off its letter rows entirely —
  // AZERTY has é, è, ç and à on its number row — so without this they can't
  // be typed here at all.
  //
  // Copied by hand from Keyboard.qml, table and all, because this file shares
  // no code with it. It shows what is being held, which anyone watching the
  // screen can see; so does a pressed key, and that is as far as it goes.
  // There is no trail and never will be: see the note on swipe below.
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
  readonly property var variantBase: ({
    "ß": "s", "æ": "a", "ø": "o", "œ": "o", "ł": "l", "đ": "d", "ð": "d",
    "ı": "i", "ŋ": "n", "þ": "t", "ħ": "h", "ĸ": "k"
  })
  // The layout's own letters, from the same file as its rows and checked the
  // same way, first behind the letter they decompose to.
  property var layoutLetters: []
  readonly property var variantsOf: {
    var map = {}
    for (var b in root.variantTable) map[b] = root.variantTable[b].slice()
    var own = {}
    root.layoutLetters.forEach(function(c) {
      var lower = c.toLowerCase()
      var base = root.variantBase[lower] || lower.normalize("NFD")[0]
      if (base.length !== 1 || base === lower || base.toLowerCase() === base.toUpperCase()) return
      if (!(base in own)) own[base] = []
      if (own[base].indexOf(lower) === -1) own[base].push(lower)
    })
    for (var k in own) {
      map[k] = own[k].concat((map[k] || []).filter(function(c) { return own[k].indexOf(c) === -1 }))
    }
    return map
  }

  function variantsFor(key) {
    var list = root.variantsOf[key]
    if (!list || list.length === 0) return []
    return [key].concat(list).slice(0, 9).map(function(c) { return root.upper ? c.toUpperCase() : c })
  }

  // The open popup: { key, items, index, x, y, cellWidth, cellHeight }, or
  // null. A plain object, so changing it means replacing it.
  property var popup: null

  function openPopup(key, item) {
    var items = root.variantsFor(key)
    if (items.length < 2 || !root.typing) return
    var at = item.mapToItem(root, 0, 0)
    var cell = Math.max(item.width + root.gap, root.unit * 0.92)
    var total = items.length * cell
    var x = total > root.width - 2 * root.padding ? (root.width - total) / 2
      : Math.min(Math.max(at.x, root.padding), root.width - root.padding - total)
    root.popup = { key: key, items: items, index: 0, x: x,
                   y: Math.max(0, at.y - item.height - root.gap),
                   cellWidth: cell, cellHeight: item.height }
  }

  // Which cell the finger is on, in this item's coordinates. Sliding well
  // below the popup takes nothing.
  function selectAt(x, y) {
    var p = root.popup
    if (!p) return
    var index = -1
    if (y < p.y + p.cellHeight + root.keyHeight) {
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
    if (!p || p.index < 0 || !root.typing) return
    root.view.wakeRequested()
    root.type(p.items[p.index])
  }

  readonly property var pages: ({
    "letters": [
      letters(layoutRows[0]),
      letters(layoutRows[1]),
      ["shift"].concat(letters(layoutRows[2]), ["backspace"]),
      ["symbols", "space", ".", "enter"]
    ],
    "symbols": [
      symbolRows[0],
      symbolRows[1],
      ["more"].concat(punctuation, extraSymbols.slice(0, 2), ["backspace"]),
      ["letters", "space", ",", "enter"]
    ],
    "more": [
      moreRows[0],
      moreRows[1],
      ["symbols"].concat(punctuation, extraSymbols.slice(2, 4), ["backspace"]),
      ["letters", "space", ",", "enter"]
    ]
  })
  // The key back to the letters page names the script rather than a
  // language: the layout's own first three letters by code point, A B C on a
  // Latin layout and А Б В on a Cyrillic one.
  readonly property string lettersLabel: {
    var all = []
    root.layoutRows.forEach(function(row) {
      row.forEach(function(k) { if (all.indexOf(k[0]) === -1) all.push(k[0]) })
    })
    all.sort()
    return all.length >= 3 ? all.slice(0, 3).join("").toUpperCase() : "ABC"
  }

  // Shift, Backspace and Enter carry a drawn icon (LockKeyIcon.qml), so
  // they have no text label.
  readonly property var labels: ({
    "shift": "", "backspace": "", "enter": "",
    "symbols": "?123", "more": "#+=", "letters": root.lettersLabel
  })
  readonly property var widths: ({
    "shift": 1.5, "backspace": 1.5, "symbols": 1.5, "more": 1.5, "letters": 1.5,
    "space": 5.5, "enter": 2
  })

  // The key style's shape and measurements, as Ragtop's service last wrote
  // them. Checked again here with this file's own rules; anything missing,
  // unknown or out of range gets the Rounded default.
  property var style: cleanStyle(null)

  function cleanStyle(raw) {
    raw = raw && typeof raw === "object" ? raw : {}
    function num(value, low, high, fallback) {
      return typeof value === "number" && isFinite(value) ? Math.min(high, Math.max(low, value)) : fallback
    }
    function pick(value, allowed, fallback) {
      return allowed.indexOf(value) !== -1 ? value : fallback
    }
    return {
      shape: pick(raw.shape, ["omarchy", "rounded", "pill", "angular"], "omarchy"),
      relief: pick(raw.relief, ["flat", "raised"], "flat"),
      fill: pick(raw.fill, ["dark", "light", "outline"], "light"),
      keyTransparency: pick(raw.keyTransparency, ["opaque", "low", "medium", "high", "full"], "opaque"),
      size: pick(raw.size, ["compact", "normal", "large"], "normal"),
      labels: pick(raw.labels, ["small", "normal", "large"], "normal"),
      depth: num(raw.depth, 0, 10, 4),
      chamfer: num(raw.chamfer, 0, 20, 8),
      // Off-theme sizes; colours are left to the lock screen's own palette.
      borderWidth: typeof raw.borderWidth === "number" ? num(raw.borderWidth, 0, 4, "auto") : "auto",
      radius: typeof raw.radius === "number" ? num(raw.radius, 0, 30, "auto") : "auto"
    }
  }

  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ragtop-style.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var raw = null
      try { raw = JSON.parse(text()) } catch (e) {}
      root.style = root.cleanStyle(raw)
    }
    onLoadFailed: root.style = root.cleanStyle(null)
  }

  // Sized as the desktop keyboard is, on Omarchy's spacing scale, stepped
  // by the style's density.
  readonly property int gap: style.size === "compact" ? Style.spacing.sm
    : style.size === "large" ? Style.spacing.lg : Style.spacing.md
  readonly property int padding: style.size === "compact" ? Style.spacing.md
    : style.size === "large" ? Style.spacing.xl : Style.spacing.lg
  readonly property real keyScale: style.size === "compact" ? 0.88 : style.size === "large" ? 1.15 : 1
  readonly property real rowUnits: Math.max(10, layoutRows[0].length, layoutRows[1].length, layoutRows[2].length + 3)

  // How wide a key is, in units, once a short row has been stretched to the
  // keyboard's width by its own stretchy keys: the space bar, or the wide
  // keys at both ends of a third row. Rows of plain keys stay centred, so
  // the letters keep one size. Copied by hand from the desktop keyboard
  // (Keyboard.qml's stretch), as everything here is. The letter rows come up
  // short only on some layouts — French's bottom row is six keys against
  // eleven on the row above — while the symbol pages' third row is short on
  // any of them.
  function keyUnits(row, index) {
    var key = row[index]
    var base = root.widths[key] || 1
    var used = row.reduce(function(a, k) { return a + (root.widths[k] || 1) }, 0)
    var slack = root.rowUnits - used
    if (slack <= 0.01) return base
    var space = row.indexOf("space")
    if (space !== -1) return key === "space" ? base + slack : base
    if (row.length > 1 && (row[0] in root.widths) && (row[row.length - 1] in root.widths)
        && (index === 0 || index === row.length - 1)) return base + slack / 2
    return base
  }
  readonly property real unit: Math.min((width - 2 * padding) / rowUnits, Math.round(84 * keyScale))
  readonly property real keyHeight: Math.max(Math.round(36 * keyScale),
    Math.min(Math.round(unit * 0.78), Math.round(60 * keyScale)))

  // Omarchy's shared control states, in the lock screen's own colours.
  readonly property color themeKeyColor: Style.normalFillFor(Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  // A raised key's side: a translucent wash towards the lock screen's text
  // colour, which contrasts with its surface on dark and light themes
  // alike, with a little of its accent so it reads as an edge.
  // A raised key's side is part of the key: the face's colour in shadow,
  // fading with it. An outline key has no face colour, so it stays a wash.
  readonly property color keySide: seeThrough(style.fill === "outline"
    ? Util.alpha(Qt.tint(Color.lock.text, Util.alpha(Color.lock.borderActive, 0.35)), 0.3)
    : Qt.tint(Qt.darker(keyBase, 1.35), Util.alpha(Color.lock.borderActive, 0.12)))
  // Solid keys sit on the lock screen's own surface colour, subtle ones let
  // it show through, outline keys are carried by their edge alone.
  // How see-through the keys are; what shows through is the lock screen
  // behind them.
  readonly property real keyOpacity:
    ({ "opaque": 1, "low": 0.85, "medium": 0.7, "high": 0.5, "full": 0 })[style.keyTransparency]
  function seeThrough(c) { return Qt.rgba(c.r, c.g, c.b, c.a * keyOpacity) }

  // A key sits darker or lighter than the lock screen's own surface; where
  // that surface already is the theme's darkest or lightest colour, the
  // step is taken from the surface itself.
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  readonly property color lockSurface: Qt.rgba(Color.lock.background.r, Color.lock.background.g, Color.lock.background.b, 1)
  readonly property color lighterRole: luminance(Color.lock.text) > luminance(lockSurface) ? Color.lock.text : lockSurface
  readonly property color darkerRole: luminance(Color.lock.text) > luminance(lockSurface) ? lockSurface : Color.lock.text
  function stepped(role, factorColor) {
    var mixed = Qt.tint(lockSurface, Util.alpha(role, 0.14))
    return Math.abs(luminance(mixed) - luminance(lockSurface))
      >= Math.abs(luminance(factorColor) - luminance(lockSurface)) ? mixed : factorColor
  }
  readonly property color keyBase: style.fill === "outline" ? "transparent"
    : Qt.tint(style.fill === "dark" ? stepped(darkerRole, Qt.darker(lockSurface, 1.35))
                                    : stepped(lighterRole, Qt.lighter(lockSurface, 1.3)),
              themeKeyColor)
  readonly property color keyColor: seeThrough(keyBase)
  readonly property color pressedKeyColor: Style.pressedFillFor(Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  readonly property color latchedKeyColor: Style.selectedFillFor(Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  readonly property color specialTextColor: Color.lock.placeholder
  readonly property var keyBorderSpec: Border.controlSpec("normal", Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  readonly property color keyBorder: Border.color(keyBorderSpec)
  readonly property real keyBorderWidth: style.borderWidth !== "auto" ? Style.space(style.borderWidth)
    // An outline key is its edge, so it always keeps one.
    : style.fill === "outline" ? Math.max(1, Border.top(keyBorderSpec))
    : Border.top(keyBorderSpec)
  // The Outline shape's edges, which carry the key on their own.
  readonly property color outline: Util.alpha(Color.lock.text, 0.45)
  readonly property real keyRadius: style.radius !== "auto" ? Style.space(style.radius)
    : style.shape === "omarchy" ? Style.cornerRadius
    : style.shape === "angular" ? 0
    : Style.space(8)
  readonly property real keyDepth: style.relief === "raised" ? Style.space(style.depth) : 0
  readonly property real keyChamfer: Style.space(style.chamfer)
  // Labels on Omarchy's scales, growing with the keys; glyph keys take its
  // icon scale.
  function labelPx(size) { return Math.max(8, Math.round(size * keyScale)) }
  readonly property int labelSize: labelPx(style.labels === "small" ? Style.font.heading
    : style.labels === "large" ? Style.font.displayLarge : Style.font.display)
  readonly property int wordSize: labelPx(style.labels === "small" ? Style.font.bodySmall
    : style.labels === "large" ? Style.font.heading : Style.font.title)
  readonly property int iconSize: labelPx(style.labels === "small" ? Style.font.iconSmall
    : style.labels === "large" ? Style.font.display : Style.font.iconLarge)
  readonly property var iconKeys: ["shift", "backspace", "enter"]
  function labelKind(key) {
    if (iconKeys.indexOf(key) !== -1) return "drawn"
    return root.label(key).length > 1 ? "word" : "char"
  }

  implicitHeight: rows.implicitHeight + 2 * padding + 12
  opacity: typing ? 1 : 0.5

  function label(key) {
    if (key === "space") return root.layoutName
    if (key in labels) return labels[key]
    return upper ? shifted(key) : key
  }

  function shifted(key) {
    return shiftOf[key] || key.toUpperCase()
  }

  function type(text) {
    root.view.passwordTextEdited(root.view.passwordText + text)
    if (root.shift) root.shift = false
  }

  function press(key) {
    if (!root.typing) return
    root.view.wakeRequested()
    switch (key) {
    case "shift":
      // A second tap soon after the first locks capitals on.
      if (root.capsLock) { root.capsLock = false; root.shift = false }
      else if (root.shift && shiftTap.running) { root.capsLock = true; root.shift = false }
      else { root.shift = !root.shift; shiftTap.restart() }
      break
    case "backspace":
      root.view.passwordTextEdited(root.view.passwordText.slice(0, -1))
      break
    case "enter":
      // As the password field's own Enter does.
      var submitted = root.view.passwordText
      root.view.passwordTextEdited("")
      if (submitted.length > 0) root.view.submitPassword(submitted)
      root.shift = false
      break
    case "space":
      root.type(" ")
      break
    case "symbols":
    case "more":
    case "letters":
      root.page = key
      break
    default:
      root.type(root.upper ? root.shifted(key) : key)
    }
  }

  Timer { id: shiftTap; interval: 400 }

  // The popup, over the rows above the key being held: the letters on a card
  // of their own, so it reads as one thing lifted off the keyboard rather
  // than a few keys floating over it. Card and keys are both opaque — what
  // is behind them is the keyboard, and Key Transparency is for showing the
  // lock screen through the keyboard, not the keyboard through itself. It
  // draws its own keys rather than reusing this file's delegate, which is
  // bound to a row model; the shapes and measurements are the same ones,
  // from the same style.
  Item {
    id: popupLayer
    visible: root.popup !== null
    z: 10
    x: root.popup ? root.popup.x : 0
    y: root.popup ? root.popup.y : 0
    width: root.popup ? root.popup.items.length * root.popup.cellWidth : 0
    height: root.popup ? root.popup.cellHeight : 0

    Rectangle {
      anchors.fill: parent
      anchors.margins: -root.gap
      radius: root.keyRadius + root.gap / 2
      color: Qt.rgba(Color.lock.background.r, Color.lock.background.g, Color.lock.background.b, 1)
      border.width: Math.max(1, root.keyBorderWidth)
      border.color: Color.lock.borderActive
    }

    Repeater {
      model: root.popup ? root.popup.items : []

      Rectangle {
        required property int index
        required property string modelData
        readonly property bool chosen: root.popup && index === root.popup.index
        x: index * (root.popup ? root.popup.cellWidth : 0) + root.gap / 2
        width: (root.popup ? root.popup.cellWidth : 0) - root.gap
        height: parent.height
        radius: root.style.shape === "pill" ? height / 2 : root.keyRadius
        // Opaque, both of them: Key Transparency is there to let the lock
        // screen show through the keyboard, and behind a popup key is the
        // popup's own panel, so all it would do here is muddy the letter.
        color: chosen ? Color.lock.borderActive : root.keyBase
        border.width: root.keyBorderWidth
        border.color: root.style.fill === "outline" ? root.outline : root.keyBorder

        Text {
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: parent.modelData
          color: parent.chosen ? Color.lock.background : Color.lock.text
          font.family: Style.font.family
          font.pixelSize: root.labelSize
        }
      }
    }
  }

  Column {
    id: rows
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.padding + 12
    spacing: root.gap

    Repeater {
      model: root.pages[root.page]

      Row {
        id: keyRow
        required property var modelData
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.gap

        Repeater {
          model: parent.modelData

          Item {
            id: key
            required property string modelData
            required property int index
            readonly property bool accent: modelData === "enter" || (modelData === "shift" && root.capsLock)
            readonly property bool latched: modelData === "shift" && root.shift
            readonly property bool special: modelData in root.labels || modelData === "space"
            readonly property string shape: root.style.shape
            readonly property color fill: area.pressed ? root.pressedKeyColor
              : accent ? root.seeThrough(Color.lock.borderActive)
              : latched ? root.seeThrough(root.latchedKeyColor)
              : root.keyColor
            // Keycap: the face sits above the key's side and sinks when pressed.
            readonly property real depth: Math.min(root.keyDepth, height / 4)
            readonly property real faceY: area.pressed ? depth * 0.6 : 0
            readonly property real faceHeight: height - depth
            width: root.unit * root.keyUnits(keyRow.modelData, index) - root.gap
            height: root.keyHeight

            // Angular keys are drawn as a chamfered box; the same path
            // serves the face and the side, so a raised angular key keeps
            // its cut corners.
            readonly property real chamfer: Math.min(root.keyChamfer, width / 3, height / 3)
            function chamferPath(top, boxHeight) {
              var c = chamfer, w = width, bottom = top + boxHeight
              return "M " + c + " " + top + " L " + (w - c) + " " + top
                + " L " + w + " " + (top + c) + " L " + w + " " + (bottom - c)
                + " L " + (w - c) + " " + bottom + " L " + c + " " + bottom
                + " L 0 " + (bottom - c) + " L 0 " + (top + c) + " Z"
            }

            // A raised key's side, only ever below the face.
            Rectangle {
              visible: key.depth > 0 && key.shape !== "angular"
              y: key.faceY
              width: key.width
              height: key.height - key.faceY
              radius: key.shape === "pill" ? height / 2 : root.keyRadius
              color: root.keySide
            }

            Shape {
              visible: key.depth > 0 && key.shape === "angular"
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                fillColor: root.keySide
                strokeWidth: 0
                strokeColor: "transparent"
                PathSvg { path: key.chamferPath(key.faceY, key.height - key.faceY) }
              }
            }

            // The face, in every shape but Angular.
            Rectangle {
              visible: key.shape !== "angular"
              y: key.faceY
              width: key.width
              height: key.faceHeight
              radius: key.shape === "pill" ? height / 2 : root.keyRadius
              color: key.fill
              border.width: root.keyBorderWidth
              border.color: root.style.fill === "outline" ? root.outline : root.keyBorder
            }

            // Angular: the corners cut off.
            Shape {
              visible: key.shape === "angular"
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer

              ShapePath {
                fillColor: key.fill
                strokeColor: root.style.fill === "outline" ? root.outline : root.keyBorder
                strokeWidth: root.keyBorderWidth
                joinStyle: ShapePath.MiterJoin
                PathSvg { path: key.chamferPath(key.faceY, key.faceHeight) }
              }
            }

            // The label's size on Omarchy's scales, kept inside the key.
            readonly property string kind: root.labelKind(modelData)
            readonly property color labelColor: accent ? Color.background
              : special ? root.specialTextColor
              : Color.lock.text
            readonly property int labelPixelSize: Math.min(
              kind === "drawn" ? root.iconSize : kind === "word" ? root.wordSize : root.labelSize,
              Math.round(faceHeight * 0.62))

            Text {
              visible: key.kind !== "drawn"
              y: key.faceY
              width: key.width
              height: key.faceHeight
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: root.label(key.modelData)
              color: key.labelColor
              font.family: Style.font.family
              font.pixelSize: key.labelPixelSize
            }

            LockKeyIcon {
              visible: key.kind === "drawn"
              y: key.faceY + (key.faceHeight - height) / 2
              x: (key.width - width) / 2
              height: Math.round(key.labelPixelSize * 1.2)
              // Wider than tall for Enter's long arrow.
              width: Math.min(implicitWidth, key.width - root.gap)
              name: key.modelData
              color: key.labelColor
              filled: key.modelData === "shift" && root.capsLock
            }

            MouseArea {
              id: area
              // Half the gap on every side, so neighbouring keys meet in the
              // middle of the gap and a tap there isn't lost.
              anchors.fill: parent
              anchors.margins: -root.gap / 2
              // A key with variants types when it lifts instead, so a hold
              // can still become a popup rather than a letter already typed.
              readonly property bool holdable: root.variantsFor(key.modelData).length > 1
              pressAndHoldInterval: 420
              onPressed: if (!holdable) root.press(key.modelData)
              // Holding backspace keeps deleting; holding a letter offers the
              // characters that belong to it.
              onPressAndHold: {
                if (key.modelData === "backspace") repeat.start()
                else if (holdable) root.openPopup(key.modelData, key)
              }
              onPositionChanged: function(mouse) {
                if (root.popup === null) return
                var at = mapToItem(root, mouse.x, mouse.y)
                root.selectAt(at.x, at.y)
              }
              onReleased: {
                repeat.stop()
                if (root.popup !== null) root.choosePopup()
                else if (holdable) root.press(key.modelData)
              }
              onCanceled: {
                repeat.stop()
                root.popup = null
              }
            }

            Timer {
              id: repeat
              interval: 80
              repeat: true
              onTriggered: root.press("backspace")
            }
          }
        }
      }
    }
  }
}
