import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "KeyContrast.js" as KeyContrast

// On-screen keyboard for Omarchy's lock screen. The lock
// screen is a session lock, which hides every other surface, the on-screen
// keyboard included, so Ragtop's patched clone of it (overlay-clones.sh) loads
// this inside it and sets `view` to its LockView. Keys edit the password through
// LockView's own signals, the path typing takes, so checking it is untouched.
// From the service it takes only data: the active layout's letters/symbols
// and the user's key-size adjustment, re-checked here. Appearance is always
// Omarchy's flat keyboard in the lock screen's own palette (Color.lock).
//
// Deliberately separate from Keyboard.qml. It edits the password through
// LockView's signals: no key events, helper, or modifiers other than Shift.
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
  // physical keyboard would. Checked before use, and US if missing or malformed.
  readonly property var usRows: [
    [["q","Q"],["w","W"],["e","E"],["r","R"],["t","T"],["y","Y"],["u","U"],["i","I"],["o","O"],["p","P"]],
    [["a","A"],["s","S"],["d","D"],["f","F"],["g","G"],["h","H"],["j","J"],["k","K"],["l","L"]],
    [["z","Z"],["x","X"],["c","C"],["v","V"],["b","B"],["n","N"],["m","M"]]
  ]
  property var layoutRows: usRows
  property string layoutName: ""
  readonly property var digits: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
  readonly property var usDigits: ({"1":["!"], "2":["@"], "3":["#"], "4":["$"],
    "5":["%"], "6":["^"], "7":["&"], "8":["*"], "9":["("], "0":[")"]})
  property var digitLevels: usDigits

  function cleanDigits(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    root.digits.forEach(function(digit) {
      if (!Array.isArray(raw[digit])) return
      var alternatives = []
      raw[digit].slice(0, 8).forEach(function(c) {
        if (root.cleanChar(c) !== "" && c !== digit && alternatives.indexOf(c) === -1)
          alternatives.push(c)
      })
      if (alternatives.length) out[digit] = alternatives
    })
    return out
  }

  function applyLayout(layout) {
    var ok = root.validLayout(layout)
    root.layoutRows = ok ? layout.rows : root.usRows
    root.layoutName = ok && typeof layout.name === "string" ? layout.name.slice(0, 40) : ""
    root.layoutSymbols = ok ? root.cleanSymbols(layout.symbols) : []
    root.layoutLetters = ok ? root.cleanSymbols(layout.letters) : []
    // An old valid layout without digit metadata gets no invented US hints.
    root.digitLevels = ok ? root.cleanDigits(layout.digits) : root.usDigits
    root.layoutPunctuation = ok ? root.cleanSymbols(layout.punctuation) : []
    root.cancelInteraction()
  }
  // The symbols the active layout carries that the pages below don't (§ and
  // ° on a German keyboard, ¡ and ¿ on a Spanish one). Same source, checked
  // by this file's own rules: single printable characters, nothing that
  // could pass for a control or run away with the layout.
  property var layoutSymbols: []
  property var layoutPunctuation: []
  readonly property var punctuationCore: [".", ",", "?", "!", ":", ";", "\"", "'", "-"]
  readonly property var punctuationExtras: root.layoutPunctuation.filter(function(c) {
    return root.pageCharacters.indexOf(c) === -1 && root.extraSymbols.indexOf(c) === -1
  }).slice(0, 4)

  // One printable character and nothing else: not two, not whitespace,
  // nothing that could pass for a control. Everything this keyboard takes
  // from the layout file goes through this before it can be typed.
  function cleanChar(c) {
    if (typeof c !== "string" || c.trim() !== c) return ""
    var first = c.charCodeAt(0)
    if (c.length === 1)
      return first >= 0x20 && !(first >= 0x7f && first <= 0x9f)
        && !(first >= 0xd800 && first <= 0xdfff) ? c : ""
    // Count a UTF-16 surrogate pair as one printable character, without
    // accepting two ordinary characters or a lone half-surrogate.
    return c.length === 2 && first >= 0xd800 && first <= 0xdbff
      && c.charCodeAt(1) >= 0xdc00 && c.charCodeAt(1) <= 0xdfff ? c : ""
  }

  function cleanSymbols(raw) {
    if (!Array.isArray(raw)) return []
    return raw.filter(function(c) { return root.cleanChar(c) !== "" }).slice(0, 24)
  }

  function validLayout(layout) {
    if (!layout || !Array.isArray(layout.rows) || layout.rows.length !== 3) return false
    return layout.rows.every(function(row) {
      return Array.isArray(row) && row.length > 0 && row.length <= 13 && row.every(function(k) {
        // Four, of which the first two have to be there. The deeper two are
        // optional and checked one at a time where they are read (level3Of),
        // so a layout with something odd on a third level still types its
        // letters rather than falling back to US and losing them.
        return Array.isArray(k) && k.length >= 2 && k.slice(0, 2).every(function(c) {
          return c !== "" && root.cleanChar(c) === c
        })
      })
    })
  }

  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/ragtop-layout.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var layout = null
      try { layout = JSON.parse(text()) } catch (e) {}
      root.applyLayout(layout)
    }
    onLoadFailed: root.applyLayout(null)
  }

  // Each letter's shifted character, e.g. "Ü" for "ü".
  readonly property var shiftOf: {
    var map = {}
    layoutRows.forEach(function(row) { row.forEach(function(k) { map[k[0]] = k[1] }) })
    return map
  }

  // What AltGr, and AltGr with Shift, type on each letter key. This
  // keyboard has no AltGr key and is not getting one, so a hold is the only
  // way to reach them, and it has to reach them: a password was set on a
  // physical keyboard, and on a Polish one ą ć ę ł ń ó ś ź ż are all AltGr
  // and none of them is on any page here. Each character is checked on its
  // own, since these arrive from the same file as everything else.
  function levelOf(index) {
    var map = {}
    layoutRows.forEach(function(row) {
      row.forEach(function(k) {
        var c = root.cleanChar(k[index])
        if (c !== "" && c !== k[0] && c !== k[1]) map[k[0]] = c
      })
    })
    return map
  }
  readonly property var level3Of: root.levelOf(2)
  readonly property var level4Of: root.levelOf(3)
  function letters(row) { return row.map(function(k) { return k[0] }) }

  // Rows of keys. A key is its text, or one of the named keys below. Widths
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
  // characters, and a layout can keep letters off its letter rows entirely.
  // AZERTY has é, è, ç and à on its number row, so without this they can't
  // be typed here at all.
  //
  // Copied by hand from Keyboard.qml, table and all, because this file shares
  // no code with it. It shows what is being held, which anyone watching the
  // screen can see. So does a pressed key, and that is as far as it goes.
  // There is no trail and never will be.
  //
  // Nor swipe, word suggestions, word forms, automatic capitals or anything
  // else the desktop keyboard does with what is typed, and never any of
  // them: this keyboard types only a password. A swipe draws it on the screen
  // for anyone to read, and a suggestion shows what it begins with. Each of
  // those needs the keyboard to hold what has been typed, and this one holds
  // nothing: a key goes straight into the password field and is gone from
  // here. The desktop keyboard keeps nothing in a password field either
  // (Service.qml, secretField), but this one has nothing to switch off.
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
    var out = []
    var typed = root.upper ? root.shifted(key) : key
    function add(c) {
      if (c && c !== typed && out.indexOf(c) === -1) out.push(c)
    }
    // A tap already types the base character. Hold choices contain only
    // alternatives, even when just one exists (1 -> ! on a US layout).
    if (root.digits.indexOf(key) !== -1) {
      (root.digitLevels[key] || []).forEach(add)
    } else if (root.punctuation.indexOf(key) !== -1) {
      root.punctuationExtras.concat(root.punctuationCore).forEach(add)
    } else {
      // Keymap levels are literal characters, not case-converted accents.
      add(root.level3Of[key])
      add(root.level4Of[key])
      ;(root.variantsOf[key] || []).forEach(function(c) { add(root.upper ? c.toUpperCase() : c) })
    }
    return out.slice(0, 12)
  }

  function hintFor(key) {
    if (root.digits.indexOf(key) !== -1) return (root.digitLevels[key] || [])[0] || ""
    return root.page === "letters" ? root.level3Of[key] || "" : ""
  }

  // Geometry belongs to a particular gesture. Resizing, changing page or
  // starting authentication invalidates it, including any pending release.
  property int interactionSerial: 0
  property var popup: null
  property bool popupTravelled: false
  function cancelInteraction() {
    root.popup = null
    root.popupTravelled = false
    root.interactionSerial++
  }
  onWidthChanged: root.cancelInteraction()
  onHeightChanged: root.cancelInteraction()
  onTypingChanged: if (!root.typing) root.cancelInteraction()
  onVisibleChanged: if (!visible) root.cancelInteraction()

  function openPopup(key, item, startX, startY) {
    var items = root.variantsFor(key)
    if (items.length < 1 || !root.typing) return
    var at = item.mapToItem(root, 0, 0)
    var room = Math.max(1, root.width - 2 * root.padding)
    var cell = Math.min(room, Math.max(item.width + root.gap, root.unit * 0.92))
    items = items.slice(0, Math.max(1, Math.floor(room / cell)))
    var total = items.length * cell
    var from = at.x
    var y = at.y - item.height - root.gap
    // A top-row card must not hide under the finger. Put it beside the key
    // where possible, reversing when it opens to the left, like desktop.
    var beside = at.y - item.height / 2 < root.gap
      && item.width + root.gap + total <= room
    if (beside) {
      y = at.y
      from = at.x + item.width + root.gap
      if (from + total > root.width - root.padding) {
        from = at.x - root.gap - total
        items = items.slice().reverse()
      }
    }
    var x = Math.min(Math.max(from, root.padding), root.width - root.padding - total)
    var near = beside && from < at.x ? items.length - 1 : 0
    // Only the printed digit alternate is a hold-and-release shortcut.
    // A shifted/clamped accent card never silently chooses a character.
    var first = root.digits.indexOf(key) !== -1 && x === from
      && items[near] === root.hintFor(key) ? near : -1
    root.popupTravelled = false
    root.popup = { key: key, items: items, index: first, preset: first, x: x,
                   y: Math.max(root.gap, y), beside: beside,
                   startX: startX === undefined ? at.x + item.width / 2 : startX,
                   startY: startY === undefined ? at.y + item.height / 2 : startY,
                   cellWidth: cell, cellHeight: item.height }
  }

  function selectAt(x, y) {
    var p = root.popup
    if (!p) return
    var travelled = Math.abs(x - p.startX) + Math.abs(y - p.startY) > root.unit * 0.4
    if (travelled) root.popupTravelled = true
    // Small finger jitter does not cancel the printed alternate shortcut.
    if (!root.popupTravelled) return
    var within = y >= p.y - p.cellHeight / 2 && y <= p.y + p.cellHeight + root.gap
    if (within && p.beside && (x < p.x || x > p.x + p.items.length * p.cellWidth)) within = false
    var index = within ? Math.max(0, Math.min(p.items.length - 1, Math.floor((x - p.x) / p.cellWidth))) : -1
    if (index === p.index) return
    root.popup = Object.assign({}, p, {index: index})
  }

  function choosePopup() {
    var p = root.popup
    var travelled = root.popupTravelled
    root.popup = null
    root.popupTravelled = false
    if (!p || !root.typing) return
    if (p.index < 0) {
      // Holding a letter still is a slow tap; entering the card and then
      // leaving it is cancellation. Neither needs the base in the card.
      if (!travelled) root.press(p.key)
      return
    }
    root.view.wakeRequested()
    root.type(p.items[p.index])
  }

  // Every page has the same row count. Extra height grows upwards while
  // the two bottom rows (Backspace and Enter) stay anchored in place.
  readonly property var pages: ({
    "letters": (showNumberRow ? [digits] : []).concat([
      letters(layoutRows[0]),
      letters(layoutRows[1]),
      ["shift"].concat(letters(layoutRows[2]), ["backspace"]),
      ["symbols", "space", ".", "enter"]
    ]),
    "symbols": [symbolRows[0], symbolRows[1]].concat(showNumberRow ? [moreRows[0]] : []).concat([
      ["more"].concat(punctuation, extraSymbols.slice(0, 2), ["backspace"]),
      ["letters", "space", ",", "enter"]
    ]),
    "more": (showNumberRow ? [digits] : []).concat([
      moreRows[0], moreRows[1],
      ["symbols"].concat(punctuation, extraSymbols.slice(2, 4), ["backspace"]),
      ["letters", "space", ",", "enter"]
    ])
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

  // Only the user's size adjustment crosses from the desktop. Old style
  // files may contain theme fields; none of those are accepted here.
  property var style: cleanStyle(null)
  function cleanStyle(raw) {
    var value = raw && typeof raw === "object" ? raw.sizeNudge : undefined
    return { sizeNudge: typeof value === "number" && isFinite(value)
      ? Math.min(2, Math.max(0.5, value)) : 1 }
  }

  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/ragtop-style.json" : ""
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

  // Omarchy's 100% base size, with the user's checked adjustment. Desktop
  // theme size is deliberately excluded, so changing theme cannot resize it.
  readonly property real keyScale: Math.max(0.6, Math.min(1.6, style.sizeNudge))
  readonly property string density: keyScale < 0.95 ? "compact"
    : keyScale > 1.08 ? "roomy" : "normal"
  readonly property int gap: density === "compact" ? Style.spacing.sm
    : density === "roomy" ? Style.spacing.lg : Style.spacing.md
  readonly property int padding: density === "compact" ? Style.spacing.md
    : density === "roomy" ? Style.spacing.xl : Style.spacing.lg
  readonly property real rowUnits: Math.max(10, layoutRows[0].length, layoutRows[1].length, layoutRows[2].length + 3)

  // Stretch Space on the bottom row and characters on the row above it.
  // Both rows span the same width, with fixed outer control slots. Plain
  // letter and digit rows stay centred at their normal key width.
  function keyUnits(row, index) {
    var key = row[index]
    var base = root.widths[key] || 1
    var used = row.reduce(function(a, k) { return a + (root.widths[k] || 1) }, 0)
    var slack = root.rowUnits - used
    if (slack <= 0.01) return base
    var space = row.indexOf("space")
    if (space !== -1) return key === "space" ? base + slack : base
    if (row.length > 2 && row[row.length - 1] === "backspace") {
      // Keep both outer controls fixed. Spread spare space among the
      // characters, so fewer symbols never enlarge or move Backspace.
      return index > 0 && index < row.length - 1 ? base + slack / (row.length - 2) : base
    }
    return base
  }
  readonly property real unit: Math.min((width - 2 * padding) / rowUnits, Math.round(84 * keyScale))
  // As the desktop keyboard works it out, and for the same reason.
  readonly property real keyHeight: Math.max(30,
    Math.min(Math.round(60 * keyScale), Math.round(unit * 1.4)))

  // The host lock view is full-screen, unlike our Loader (whose height
  // follows implicitHeight). Never use the Loader's height in this decision.
  // Reserve room below the centred password field for status text and a gap.
  readonly property real availableHeight: root.view && typeof root.view.height === "number"
    ? Math.max(0, root.view.height / 2
        - (typeof root.view.fieldHeight === "number" ? root.view.fieldHeight : 67) / 2
        - 2 * root.padding - 2 * Style.font.body) : 0
  readonly property real expandedHeight: 5 * keyHeight + 4 * gap + 2 * padding + 12
  readonly property bool showNumberRow: expandedHeight <= availableHeight
  onShowNumberRowChanged: root.cancelInteraction()
  onPageChanged: root.cancelInteraction()
  onGapChanged: root.cancelInteraction()
  onPaddingChanged: root.cancelInteraction()

  // Omarchy's shared control states, in the lock screen's own colours.
  readonly property color themeKeyColor: Style.normalFillFor(Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  // A key sits darker or lighter than the lock screen's own surface. Where
  // that surface already is the theme's darkest or lightest colour, the
  // step is taken from the surface itself.
  function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
  readonly property color lockSurface: Qt.rgba(Color.lock.background.r, Color.lock.background.g, Color.lock.background.b, 1)
  readonly property color lighterRole: luminance(Color.lock.text) > luminance(lockSurface) ? Color.lock.text : lockSurface
  function stepped(role, factorColor) {
    var mixed = Qt.tint(lockSurface, Util.alpha(role, 0.14))
    return Math.abs(luminance(mixed) - luminance(lockSurface))
      >= Math.abs(luminance(factorColor) - luminance(lockSurface)) ? mixed : factorColor
  }
  readonly property color lightKeyBase: stepped(lighterRole, Qt.lighter(lockSurface, 1.3))
  readonly property color keyBase: Qt.tint(lightKeyBase, themeKeyColor)
  readonly property color keyColor: keyBase
  readonly property color pressedOverlay: Style.pressedFillFor(Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  function pressFill(base) { return KeyContrast.pressedFill(base, pressedOverlay) }
  readonly property color latchedKeyColor: Style.selectedFillFor(Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  readonly property color specialTextColor: Color.lock.placeholder
  readonly property var keyBorderSpec: Border.controlSpec("normal", Color.lock.text, Color.lock.borderActive, Color.lock.textError)
  readonly property color keyBorder: Border.color(keyBorderSpec)
  readonly property real keyBorderWidth: Border.top(keyBorderSpec)
  readonly property real keyRadius: Style.cornerRadius
  readonly property real keyDepth: 0
  // Labels follow Omarchy's normal type scale and the user's key size.
  function labelPx(size) { return Math.max(8, Math.round(size * keyScale)) }
  readonly property int labelSize: labelPx(Style.font.display)
  readonly property int wordSize: labelPx(Style.font.title)
  readonly property int iconSize: labelPx(Style.font.iconLarge)
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
      // Off, then on for the next character, then locked, then off, as the
      // main keyboard's modifiers go. A tap while it is on locks it however
      // long it comes after the first, because shift only lives until the
      // next character (see type) and so a tap can only mean lock.
      if (root.capsLock) { root.capsLock = false; root.shift = false }
      else if (root.shift) { root.capsLock = true; root.shift = false }
      else root.shift = true
      break
    case "backspace":
      // QString/JS indices are UTF-16 code units. Remove both halves of a
      // supplementary character rather than leaving an invalid surrogate.
      var text = root.view.passwordText
      var end = Math.max(0, text.length - 1)
      if (end > 0 && text.charCodeAt(end) >= 0xdc00 && text.charCodeAt(end) <= 0xdfff
          && text.charCodeAt(end - 1) >= 0xd800 && text.charCodeAt(end - 1) <= 0xdbff) end--
      root.view.passwordTextEdited(text.slice(0, end))
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

  // The popup, over the rows above the key being held: the letters on a card
  // of their own, so it reads as one thing lifted off the keyboard rather
  // than a few keys floating over it. Card and keys are both opaque, and what
  // is behind them is the keyboard. It draws its own keys rather than
  // reusing the row delegate, with the same Omarchy shape and measurements.
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
        radius: root.keyRadius
        // Opaque popup keys keep alternatives legible over the keyboard.
        color: chosen ? Color.lock.borderActive : root.keyBase
        border.width: root.keyBorderWidth
        border.color: root.keyBorder

        Text {
          // Never rich text. A window title, a layout name and an error
          // string all arrive from outside, and AutoText would sniff markup
          // in them and render it, which for Qt includes fetching a remote
          // image named in an img tag.
          textFormat: Text.PlainText
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
            readonly property color restingFill: accent ? Color.lock.borderActive
              : latched ? root.latchedKeyColor : root.keyColor
            readonly property color fill: area.pressed ? root.pressFill(restingFill) : restingFill
            readonly property real faceY: 0
            readonly property real faceHeight: height
            width: root.unit * root.keyUnits(keyRow.modelData, index) - root.gap
            height: root.keyHeight

            Rectangle {
              anchors.fill: parent
              radius: root.keyRadius
              color: key.fill
              border.width: root.keyBorderWidth
              border.color: root.keyBorder
            }

            // The label's size on Omarchy's scales, kept inside the key.
            readonly property string kind: root.labelKind(modelData)
            readonly property color preferredLabelColor: accent ? Color.background
              : special ? root.specialTextColor
              : Color.lock.text
            readonly property color labelColor: preferredLabelColor
            readonly property int labelPixelSize: Math.min(
              kind === "drawn" ? root.iconSize : kind === "word" ? root.wordSize : root.labelSize,
              Math.round(faceHeight * 0.62))

            Text {
              // Never rich text. A window title, a layout name and an error
              // string all arrive from outside, and AutoText would sniff markup
              // in them and render it, which for Qt includes fetching a remote
              // image named in an img tag.
              textFormat: Text.PlainText
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

            // What AltGr types on this key, printed small in the corner the
            // way a keycap prints it. A hold is the only way to it here, and
            // nobody holds a key to look for something they have not been
            // told is there, which on a lock screen means not getting in.
            Text {
              // Never rich text, for the reason given above.
              textFormat: Text.PlainText
              readonly property string hint: root.hintFor(key.modelData)
              // Keep the hint clear of Omarchy's rounded corner.
              readonly property real inset: root.keyRadius * 0.3
              visible: hint !== ""
              y: key.faceY + Math.round(root.gap / 2 + inset / 2)
              width: key.width - Math.round(root.gap / 2 + inset)
              horizontalAlignment: Text.AlignRight
              text: hint
              color: key.labelColor
              // Quieter than the label beside it: it says what the key can
              // also do, not what it does now.
              opacity: 0.5
              font.family: Style.font.family
              font.pixelSize: Math.max(9, Math.round(key.labelPixelSize * 0.52))
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
              // All character keys type on release, as on the desktop,
              // whether or not they happen to have hold alternatives.
              enabled: root.typing
              readonly property bool holdable: root.variantsFor(key.modelData).length > 0
              readonly property bool deferred: !key.special
              property bool offeredPopup: false
              property int pressSerial: -1
              property real startX: 0
              property real startY: 0
              pressAndHoldInterval: 420
              onPressed: function(mouse) {
                offeredPopup = false
                pressSerial = root.interactionSerial
                var at = mapToItem(root, mouse.x, mouse.y)
                startX = at.x
                startY = at.y
                if (!deferred) root.press(key.modelData)
              }
              // Holding backspace keeps deleting, and holding a letter offers the
              // characters that belong to it.
              onPressAndHold: {
                if (pressSerial !== root.interactionSerial || !root.typing) return
                if (key.modelData === "backspace") repeat.start()
                else if (holdable) {
                  offeredPopup = true
                  root.openPopup(key.modelData, key, startX, startY)
                }
              }
              onPositionChanged: function(mouse) {
                if (pressSerial !== root.interactionSerial || root.popup === null || root.popup.key !== key.modelData) return
                var at = mapToItem(root, mouse.x, mouse.y)
                root.selectAt(at.x, at.y)
              }
              onReleased: {
                repeat.stop()
                if (pressSerial !== root.interactionSerial || !root.typing) return
                if (root.popup !== null && root.popup.key === key.modelData) root.choosePopup()
                else if (deferred && !offeredPopup) root.press(key.modelData)
              }
              onCanceled: {
                repeat.stop()
                root.cancelInteraction()
              }
              Connections {
                target: root
                function onInteractionSerialChanged() { repeat.stop() }
              }
            }

            Timer {
              id: repeat
              interval: 80
              repeat: true
              onTriggered: {
                if (area.pressed && root.typing && area.pressSerial === root.interactionSerial) root.press("backspace")
                else stop()
              }
            }
          }
        }
      }
    }
  }
}
