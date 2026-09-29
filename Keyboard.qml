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
  property var mods: ({ "shift": "off", "ctrl": "off", "alt": "off", "super": "off",
                       "altgr": "off", "fn": "off" })
  readonly property bool upper: root.mods.shift !== "off"
  readonly property bool altgrOn: root.mods.altgr !== "off"

  // The extra row of desktop keys, then the pages. A key is its character,
  // or one of the named keys below.
  // AltGr is only there on a layout that puts something on its third level.
  // On a plain US layout there is nothing to reach, so the key would do
  // nothing and the row is better without it.
  readonly property var topRow: ["esc", "tab", "ctrl", "alt"]
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

  // Every printed key of the physical board, by the xkb name for its
  // position, as [plain, shift, altgr, both] (see keyboard-helper.py). The
  // real form factors are drawn from this: they name positions and the
  // active layout says what each one types, so one description draws every
  // language.
  readonly property var grid: root.service.keyLabels && root.service.keyLabels.keys
    ? root.service.keyLabels.keys : ({})

  // The key an ISO board keeps beside the left Shift, and an ANSI board does
  // not. Drawn only where it reaches something the rest of the board cannot,
  // which is the test the AltGr key already passes. Having the position says
  // nothing: Hyprland compiles its keymap for a 105 key model, so every
  // layout here has one. Measured across layouts: US and Dvorak only repeat
  // what , . and \ already type, while German, French, Spanish, Italian and
  // Swedish reach < and >, British \ and |, and Russian |.
  readonly property bool hasIsoKey: {
    var g = root.grid
    if (!g["LSGT"]) return false
    var elsewhere = {}
    for (var n in g)
      if (n !== "LSGT") g[n].slice(0, 2).forEach(function(c) { if (c) elsewhere[c] = true })
    return g["LSGT"].slice(0, 2).some(function(c) { return c && !(c in elsewhere) })
  }

  // A real board names its keys by position, and the same position means the
  // same thing whichever side of the space bar it is on. Everything that
  // acts on a key asks for its role first, so one Shift and the other are
  // one Shift as far as the modifier state is concerned.
  // What each key becomes while Fn is on. Keyed by position, so it holds for
  // any board that draws an Fn key. Nothing moves: the slots are the drawn
  // keys and only their meaning changes, so no key slides out from under a
  // finger when the layer comes on.
  readonly property var fnMap: {
    // Tiling mode is the tap and the context menu is behind Fn, not the other
    // way round. A tablet has no right click, so Menu is worth having at all,
    // but arranging windows by touch is something you do constantly and Menu
    // does nothing whatever in a terminal.
    var map = ({ "BKSP": "delete", "windows": "menu" })
    // The number row carries the function keys, as it does on every board
    // with no row of its own for them.
    for (var i = 1; i <= 12; i++) map["AE" + (i < 10 ? "0" + i : "" + i)] = "f" + i
    // An inverted T for the arrows, with the page and line keys either side
    // of it. The caps say what they do while the layer is on, so none of it
    // has to be remembered, but a finger still aims by shape and a row of
    // four arrows in a line is not a shape you can aim at.
    //
    //        U    I    O          PgUp  Up    PgDn
    //   H    J    K    L    ;     Home  Left  Down  Right  End
    map["AD07"] = "pgup";  map["AD08"] = "up";    map["AD09"] = "pgdn"
    map["AC06"] = "home";  map["AC07"] = "left";  map["AC08"] = "down"
    map["AC09"] = "right"; map["AC10"] = "end"
    return map
  }
  readonly property bool fnOn: root.mods.fn !== "off"
  // The key a touch means once the layer has had its say. Everything that
  // labels, colours, presses or releases a key asks for this first.
  function effectiveKey(key) { return root.fnOn ? (root.fnMap[key] || key) : key }

  readonly property var roles: {
    var map = root.rolesBase
    // The function row is named by position like everything else on a real
    // board, so FK05 is the key and f5 is what it does.
    for (var i = 1; i <= 12; i++) map["FK" + (i < 10 ? "0" + i : "" + i)] = "f" + i
    return map
  }
  readonly property var rolesBase: ({
    "FN": "fn",
    "LFSH": "shift", "RTSH": "shift", "LCTL": "ctrl", "RCTL": "ctrl",
    "LALT": "alt", "RALT": "altgr", "LWIN": "super", "RWIN": "super",
    "BKSP": "backspace", "RTRN": "enter", "TAB": "tab", "SPCE": "space",
    "CAPS": "caps", "MENU": "menu", "ESC": "esc"
  })
  // Whether anything the board actually draws has a third level. The phone
  // layout asks a narrower question (hasLevel3), and rightly: its AltGr key
  // switches the letter caps, so a layout with a third level only on its
  // number row would give it nothing to show. A real board draws the number
  // row too, so the question here is the whole board's.
  //
  // Keys the board leaves out do not count, and that is the whole difficulty.
  // Measured: the only key a US layout gives a third level to is LSGT, the
  // ISO key, which an ANSI board does not draw. Counting it would have said
  // every layout on earth has an AltGr worth a key.
  readonly property bool hasAltGr: {
    var g = root.grid
    for (var n in g) {
      if (n === "LSGT" && !root.hasIsoKey) continue
      if (g[n][2]) return true
    }
    return root.hasLevel3
  }
  // Names the keymap is asked about: the letter and number rows, and the
  // three odd ones out around them.
  function isPrintedPosition(key) {
    return /^(AE|AD|AC|AB)[0-9][0-9]$/.test(key)
      || key === "TLDE" || key === "BKSL" || key === "LSGT"
  }
  function roleOf(key) {
    // The right Alt is AltGr where the layout has a third level to reach,
    // and a plain Alt where it has not, which is what that key is on a US
    // board. It is the same call the phone layout makes by leaving its AltGr
    // key out: a key that reaches nothing is worse than no key. Here the
    // position exists on any real board, so it does the other thing it is
    // for rather than nothing.
    if (key === "RALT") return root.hasAltGr ? "altgr" : "alt"
    return root.roles[key] || key
  }

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
      ["symbols", "super", "space", ".", "enter"]
    ],
    "symbols": [
      symbolRows[0],
      symbolRows[1],
      ["more"].concat(punctuation, extraSymbols.slice(0, 2), ["backspace"]),
      ["letters", "super", "space", ",", "enter"]
    ],
    "more": [
      moreRows[0],
      moreRows[1],
      ["symbols"].concat(punctuation, extraSymbols.slice(2, 4), ["backspace"]),
      ["letters", "super", "space", ",", "enter"]
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

  readonly property var labelsBase: ({
    "esc": "Esc", "tab": "Tab", "ctrl": "Ctrl", "alt": "Alt", "super": "", "altgr": "AltGr",
    "left": "", "up": "", "down": "", "right": "",
    "shift": "", "backspace": "", "enter": "", "space": "",
    "symbols": "?123", "more": "#+=", "letters": root.lettersLabel, "settings": "",
    "windows": "", "caps": "Caps", "menu": "Menu",
    "fn": "Fn", "delete": "Del", "home": "Home", "end": "End",
    "pgup": "PgUp", "pgdn": "PgDn", "insert": "Ins",
    "prtsc": "PrtSc", "scrlk": "ScrLk", "pause": "Pause"
  })
  // The function keys, built rather than written out twelve times over.
  readonly property var fnLabels: {
    var map = ({})
    for (var i = 1; i <= 12; i++) map["f" + i] = "F" + i
    return map
  }
  readonly property var labels: Object.assign({}, root.labelsBase, root.fnLabels)
  readonly property var widths: ({
    "shift": 1.5, "backspace": 1.5, "symbols": 1.5, "more": 1.5, "letters": 1.5,
    "space": 4.5, "enter": 2
  })
  // Keys sent as key events, by the name xkb gives them.
  readonly property var keysymsBase: ({
    "esc": "Escape", "tab": "Tab", "left": "Left", "up": "Up", "down": "Down", "right": "Right",
    "backspace": "BackSpace", "enter": "Return", "space": "space", "menu": "Menu",
    "delete": "Delete", "home": "Home", "end": "End", "insert": "Insert",
    "prtsc": "Print", "scrlk": "Scroll_Lock", "pause": "Pause",
    // X11 has called these Prior and Next since before anyone called them
    // page keys, and the keymap still does.
    "pgup": "Prior", "pgdn": "Next"
  })
  readonly property var fnKeysyms: {
    var map = ({})
    for (var i = 1; i <= 12; i++) map["f" + i] = "F" + i
    return map
  }
  readonly property var keysyms: Object.assign({}, root.keysymsBase, root.fnKeysyms)
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
    var role = root.roleOf(root.effectiveKey(key))
    if (role in root.iconNames) return root.iconNames[role]
    return root.iconKeys.indexOf(role) !== -1 ? role : ""
  }
  function labelKind(key) {
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
  readonly property var holdable: ["backspace", "left", "up", "down", "right",
                                   "delete", "pgup", "pgdn"]

  // Keys whose hold reaches something that is not a character, drawn small in
  // the key's corner the way a cap prints what AltGr types on it. Super holds
  // the gear: Ragtop's controls used to have a key of their own beside the
  // space bar, and Super took that place, so the gear moved into Super's
  // corner rather than onto a row that has no room to spare.
  //
  // A key here acts on release rather than on the way down, for the same
  // reason every character key does: the hold needs room to become the other
  // thing first. Rolling from it into the next key still works, because
  // another finger arriving settles the hold as the tap it was. Hold Super,
  // tap B, and the browser opens with Super latched by commitPending.
  // Keyed by the drawn key where a board has more than one of something, and
  // by role otherwise. Tiling mode briefly lived on a hold on the right
  // Super, which was a use found for a key that had no business existing:
  // that position is Fn now, and tiling is on the layer where it can be
  // labelled.
  // The tiling key holds the context menu. A 75% has no room for a Menu key
  // and a tablet has no right click, so the one board that would otherwise
  // lose it keeps it, and the others gain a second way to it for nothing.
  readonly property var holdOpensByKey: ({ "LWIN": "settings", "windows": "menu" })
  readonly property var holdOpensByRole: ({ "super": "settings" })
  function holdOpenFor(key) {
    if (key in root.holdOpensByKey) return root.holdOpensByKey[key]
    return root.holdOpensByRole[root.roleOf(key)] || ""
  }

  // Keys that are not a character themselves but offer one behind a hold,
  // named by the position whose characters they carry. A 60% board puts Esc
  // where the tilde key sits on a bigger one, which is what the board is
  // made to and also the right call here: a desktop without an Escape is
  // worse off than one that reaches a backtick by holding. Nothing is lost,
  // because holding it gives back exactly what the position types.
  readonly property var holdGrid: ({ "ESC": "TLDE" })

  // Whether the board being drawn has a Caps key of its own. Read off the
  // keys rather than named per form factor, so every real board that gains
  // one gets the same Shift without being listed here.
  readonly property bool hasCapsKey: root.slots.some(function(s) {
    return root.roleOf(s.key) === "caps"
  })

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

  // A key that types itself, as against Esc, Shift or the page keys, which
  // are the ones the labels table names.
  function isCharacter(key) { return !(root.roleOf(key) in root.labels) }

  // What each letter key carries from another page: the characters that page
  // draws in the same place. Matched by where the keys sit and not by how
  // far along the row they are, because the rows are different lengths and
  // each is centred on its own, so only the geometry lines them up. The
  // letters' second row is nine keys against ten symbols, and the third is
  // seven against five between a wide key at either end.
  //
  // What falls out of that is worth knowing: on a layout with ten keys on
  // its top row the digits pair off exactly and sit where they look like
  // they sit, and on the third row the punctuation lands under the letters
  // it sits beneath, which is how a comma comes to be a hold on C.
  //
  // It goes the other way round. Every symbol picks the letter nearest it,
  // rather than every letter picking a symbol, so that no symbol is left
  // with no letter to reach it from. Hebrew types eight letters on its top
  // row and Dvorak seven, and against ten digits the letter row is the
  // narrower of the two, so the outer digits used to overlap nothing and
  // fell off the ends: on a Hebrew layout there was no way to hold a letter
  // and get a 0. Now they go on the nearest letter's card with its own, two
  // to a card, which is why a key maps to a list and not to one character.
  // A letter no symbol chose still has nothing there.
  function overlayOf(page) {
    // Laid out once and reused. slotsOf builds the whole keyboard every call,
    // and this runs for both pages on every change of key size.
    var mine = root.slotsOf("letters")
    var map = {}
    mine.forEach(function(a) { if (root.overlaid(a)) map[a.key] = [] })
    root.slotsOf(page).forEach(function(b) {
      if (!root.overlaid(b)) return
      var best = "", nearest = Infinity
      mine.forEach(function(a) {
        if (a.row !== b.row || !(a.key in map)) return
        var gap = Math.abs((a.x + a.width / 2) - (b.x + b.width / 2))
        if (gap < nearest) { nearest = gap; best = a.key }
      })
      if (best !== "") map[best].push(b.key)
    })
    return map
  }
  // Row 0 is the desktop keys and the last row is the space bar's, and both
  // pages already share them. So does anything that isn't a character, which
  // is a page or an edit key standing in the same place on both.
  function overlaid(slot) {
    return slot.row >= 1 && slot.row <= 3 && root.isCharacter(slot.key)
  }
  // Only the phone layout has pages for a key to stand in for.
  readonly property var symbolLists: root.form === "phone" ? root.overlayOf("symbols") : ({})
  readonly property var moreLists: root.form === "phone" ? root.overlayOf("more") : ({})
  // The one a cap prints in its corner, of however many the key carries.
  function firstOf(lists) {
    var map = {}
    for (var k in lists) if (lists[k].length > 0) map[k] = lists[k][0]
    return map
  }
  readonly property var symbolOf: root.firstOf(root.symbolLists)

  // What else sits on the key that types each digit, as the helper reads it
  // off the keymap: $ on a US 4, and ' and { on a French one, where the
  // digit is the shifted level and the symbol is the plain one. The
  // keyboard's own number row is the same ten characters whatever the
  // layout, so this is the only way a hold on one of them can offer what
  // that layout really keeps there.
  readonly property var digitLevels: root.service.keyLabels && root.service.keyLabels.digits
    ? root.service.keyLabels.digits : ({})

  // The punctuation the active layout carries, in keyboard order (see
  // keyboard-helper.py). Punctuation is nearly universal and not quite:
  // Spanish opens a question with ¿, Greek asks one with ;, French quotes
  // with « », Arabic separates with ، and asks with ؟. So a hold on a
  // punctuation key offers the layout's own marks first, the way a hold on
  // a letter offers that layout's own accents first, since those are the
  // ones it alone can reach, and then the marks every layout shares. CJK's
  // full-width marks are not here: they come from the input method and not
  // from the keymap.
  readonly property var layoutPunctuation: root.service.keyLabels
    && Array.isArray(root.service.keyLabels.punctuation)
    ? root.service.keyLabels.punctuation : []
  readonly property var punctuationCore: [".", ",", "?", "!", ":", ";", "\"", "'", "-"]
  readonly property var punctuationExtras: root.layoutPunctuation.filter(function(c) {
    // Not what the pages already draw, which on a US layout is all of it.
    return root.pageCharacters.indexOf(c) === -1 && root.extraSymbols.indexOf(c) === -1
  }).slice(0, 4)
  function punctuationCard(key) {
    return root.punctuationExtras.concat(
      root.punctuationCore.filter(function(c) { return c !== key }))
  }

  // The accented letters behind a key, in the case the keyboard is typing.
  // The key itself is not among them: nobody holds O to type an O, and
  // leaving it out is what lets the card be shoved sideways to fit without
  // the finger ever resting on a cell it did not aim for.
  function variantsFor(key) {
    var list = root.variantsOf[key]
    if (!list || list.length === 0) return []
    return list.map(function(c) { return root.upper ? c.toUpperCase() : c })
  }

  // What a hold on a key offers: everything behind it, in one card, in the
  // order the two legends on the cap promise. The symbols first, on the
  // left, then what AltGr reaches, then the accents, which are the ones
  // that give way when a key has more than the card can hold.
  function holdItems(key) {
    if (root.roleOf(key) === "space") return root.layoutList.length > 1 ? root.layoutList : []
    // A key the layer has taken over is not the key its accents belong to.
    if (root.fnOn && (key in root.fnMap)) return []
    if (!root.isCharacter(key) && !(key in root.holdGrid)) return []
    var out = []
    function add(c) { if (c && out.indexOf(c) === -1) out.push(c) }
    function addAll(list) { if (list) list.forEach(add) }
    // A real board draws every symbol it has, so nothing here stands in for
    // a page somewhere else. What is left behind a key is what a cap prints
    // in its corner and the accents that belong to the letter on it.
    var lv = root.grid[key] || root.grid[root.holdGrid[key]]
    if (lv) {
      // A key standing in for a position offers what that position types
      // first, since reaching it is the whole reason the hold is there.
      if (key in root.holdGrid) { add(lv[0]); add(lv[1]) }
      if (!root.altgrOn) { add(lv[2]); add(lv[3]) }
      root.variantsFor(lv[0]).forEach(add)
      return out.slice(0, root.cardLimit)
    }
    // A punctuation key offers punctuation and nothing else, on whichever
    // page it is standing. It sits on the bottom row, which no page overlays
    // (see overlaid), so there is nothing here to keep anyway; and a card of
    // brackets behind the period would bury the marks a sentence is made of.
    if (root.punctuation.indexOf(key) !== -1) {
      addAll(root.punctuationCard(key))
      return out.slice(0, root.cardLimit)
    }
    // A digit offers what else its own layout keeps on the key that types
    // it, which is how a hold on 4 reaches $.
    addAll(root.digitLevels[key])
    // Then what this key carries from the symbol page, and for each digit
    // among them the rest of that digit's key straight after it, so 4 and $
    // come up side by side under the letter they sit above.
    ;(root.symbolLists[key] || []).forEach(function(c) {
      add(c)
      addAll(root.digitLevels[c])
    })
    addAll(root.moreLists[key])
    // AltGr's characters are here one key at a time, and on the AltGr key a
    // whole layer at a time. Not while that key is on, since the cap is
    // already showing them and a plain tap already types them: offering
    // them again would be offering a choice that is not one.
    if (!root.altgrOn) {
      add(root.level3Of[key])
      add(root.level4Of[key])
    }
    root.variantsFor(key).forEach(add)
    return out.slice(0, root.cardLimit)
  }

  // As much as a card is ever worth offering. What actually fits is decided
  // where the card is placed and the width is known (openPopup): a key now
  // carries up to four symbols from the other pages, where it used to carry
  // two, and on a landscape screen there is room for those and the accents
  // both. A fixed nine would have thrown the last accents away on a screen
  // with plenty of room for them.
  readonly property int cardLimit: 12


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

  // How wide the phone layout is, in key units: its longest row. Layouts
  // differ, 10 to 12 letter keys.
  readonly property real rowUnits: Math.max(10, layoutRows[0].length, layoutRows[1].length, layoutRows[2].length + 3)
  // Sized so the widest row of the board being drawn fits, which is why this
  // divides by the form's own width and not by the phone layout's. A key is
  // never larger than the size setting asks for, so a board narrower than
  // the screen sits centred with a margin rather than growing into it.
  readonly property real unit: Math.min((width - 2 * theme.padding) / root.formUnits,
                                        Math.round(84 * theme.keyScale))
  // Height follows the size setting, not the width a key happens to get. On
  // a narrow screen the width is spent long before the ladder runs out, so
  // pinning height to it made Larger and Largest render identically to
  // Regular. The cap against `unit` only stops a key becoming a tall ribbon.
  readonly property real keyHeight: Math.max(30,
    Math.min(Math.round(60 * theme.keyScale), Math.round(unit * 1.4)))
  // The extra row is shorter than a row of letters: it is reached for rather
  // than typed on. Held as a fraction so it travels with the row.
  readonly property real topRowFraction: 0.62
  readonly property real topRowHeight: Math.round(keyHeight * root.topRowFraction)
  // The form factors, widest first, which is the order a fallback walks.
  // A real board is 15 units across its main block, which is what a keycap
  // set is made to, and the phone layout is as wide as its widest row needs.
  readonly property var formLadder: ["80", "75", "60", "phone"]
  // Every real board is the same 15 unit main block. A 60% is only that. A
  // 75% is compressed: one more column hard against it with no gap. A
  // tenkeyless keeps the gap and the full three wide cluster, which is what
  // makes it look like the board it is.
  function formUnitsOf(form) {
    return form === "phone" ? root.rowUnits
      : form === "60" ? 15
      : form === "75" ? 16 : 18.25
  }
  // The height of each row, as a fraction of a full one. Only the phone
  // layout has a short row, and only its first. The boards with a function
  // row have six.
  function rowHeightsOf(form) {
    return form === "phone" ? [root.topRowFraction, 1, 1, 1, 1]
      : form === "60" ? [1, 1, 1, 1, 1]
      // A function row is reached for rather than typed on, which is what
      // the phone board's extra row already says about the same class of
      // key, so it is the same fraction of a row. It is not only tidier: a
      // six row board is stopped by the height cap long before it runs out
      // of width, so this is the row that buys the others their place.
      : [root.topRowFraction, 1, 1, 1, 1, 1]
  }
  function formHeightOf(form) {
    var rows = root.rowHeightsOf(form)
    var h = 0
    rows.forEach(function(f) { h += Math.round(root.keyHeight * f) })
    return root.topPadding + h + (rows.length - 1) * root.theme.gap + root.theme.padding
  }

  // The narrowest a key may get before a layout is not worth drawing. 48 is
  // Material's minimum touch target, and it scales with the Key Size setting
  // because that setting is exactly how big keys need to be for these
  // fingers: asking for larger keys asks for a simpler board sooner.
  readonly property real minKeyWidth: 48 * root.theme.keyScale
  // How much height the keyboard may take when it is choosing for itself.
  // The service sets it from the screen. Zero means no limit.
  property real maxHeight: 0

  // Which board is drawn. Auto takes the widest that fits the screen both
  // ways. A named one is taken at its word on height, since asking for it is
  // asking for the height it needs, but still gives way on width: a board
  // too wide for the screen cannot be drawn at all. The phone layout is the
  // floor and always fits.
  readonly property string wanted: root.service.keyboardLayout || "auto"
  readonly property string form: {
    var ladder = root.formLadder
    var auto = root.wanted === "auto"
    var from = auto ? 0 : Math.max(0, ladder.indexOf(root.wanted))
    for (var i = from; i < ladder.length; i++)
      if (root.formFits(ladder[i], auto)) return ladder[i]
    return ladder[ladder.length - 1]
  }
  function formFits(form, checkHeight) {
    if (form === "phone") return true
    if ((root.width - 2 * root.theme.padding) / root.formUnitsOf(form) < root.minKeyWidth)
      return false
    return !(checkHeight && root.maxHeight > 0 && root.formHeightOf(form) > root.maxHeight)
  }

  // How wide the whole keyboard is, in key units.
  readonly property real formUnits: root.formUnitsOf(root.form)

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
  // the way Super does on the row below.
  readonly property var topRowFixed: ({ "windows": 1 })

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
    var slack = root.formUnits - widths.reduce(function(a, b) { return a + b }, 0)
    if (slack * root.unit <= 1) return widths
    var space = row.indexOf("space")
    if (space !== -1) {
      widths[space] += slack
    } else if (row.length > 1 && (row[0] in root.widths) && (row[row.length - 1] in root.widths)) {
      widths[0] += slack / 2
      widths[widths.length - 1] += slack / 2
    }
    return widths
  }

  // A keyboard's shape, as rows of keys with the width each one holds.
  // Everything that differs between one form factor and another is decided
  // here, in key units, and slotsOf below is the same geometry pass for all
  // of them. An entry is { key, w, h }: w in key units, h as a fraction of a
  // full row, so the phone layout's shorter extra row is a property of that
  // row rather than a case inside the geometry.
  function formRows(page) {
    return root.form === "phone" ? root.phoneRows(page) : root.blockRowsFor(root.form)
  }

  // Positions, in the order a row draws them: AE01 through AE12 and so on.
  function positions(prefix, from, to) {
    var out = []
    for (var i = from; i <= to; i++) out.push(prefix + (i < 10 ? "0" + i : "" + i))
    return out
  }

  // A real board: five rows, fifteen units across, with the widths a keycap
  // set is made to, so it reads as the board it is rather than as a grid.
  //
  // It is drawn ANSI shaped whatever the layout. An ISO board's tall Enter
  // and shifted backslash are a keycap shape, and nothing on a screen you
  // tap is better for reproducing them: every key is here and reachable
  // either way. What an ISO layout does get is its extra key beside the left
  // Shift, where it reaches something nothing else does, and the left Shift
  // gives up the width for it exactly as on the real board.
  //
  // A position the layout has no key for is dropped and its width shared out
  // to the ends of its row, so a short row still reaches both edges.
  function blockRowsFor(form) {
    function key(k, w) { return { key: k, w: w === undefined ? 1 : w, h: 1 } }
    function gap(w) { return { key: "", w: w, h: 1 } }
    function have(list) {
      return list.filter(function(k) { return k in root.grid }).map(function(k) { return key(k) })
    }
    function opt(k, w) { return (k in root.grid) ? [key(k, w)] : [] }
    var units = root.formUnitsOf(form)

    // Every real board is the same 15 unit main block with its own clusters
    // to the right. A row is built as those two parts and joined below, so
    // the block always ends where the block above it ended and a cluster
    // cannot be handed width that belongs to a letter.
    var shift = root.hasIsoKey
      ? [key("LFSH", 1.25), key("LSGT")].concat(have(root.positions("AB", 1, 10)))
      : [key("LFSH", 2.25)].concat(have(root.positions("AB", 1, 10)))
    var mainRows = [
      opt("TLDE").concat(have(root.positions("AE", 1, 12)), [key("BKSP", 2)]),
      [key("TAB", 1.5)].concat(have(root.positions("AD", 1, 12)), opt("BKSL", 1.5)),
      [key("CAPS", 1.75)].concat(have(root.positions("AC", 1, 11)), [key("RTRN", 2.25)])
    ]
    var rows

    if (form === "60") {
      // Esc takes the corner the tilde key would have, as it does on a real
      // 60%, and a hold on it gives the backtick back (see holdGrid).
      mainRows[0][0] = key("ESC")
      rows = [
        [mainRows[0], []], [mainRows[1], []], [mainRows[2], []],
        [shift.concat([key("RTSH", 2.75)]), []],
        // Fn where a full board keeps its right Super, which is what a 60%
        // does with that key and the reason it can reach anything at all. A
        // second Super is there so a touch typist can hit one without
        // leaving home position, and nobody touch types on this.
        [[key("LCTL", 1.25), key("LWIN", 1.25), key("LALT", 1.25), key("SPCE", 6.25),
          key("RALT", 1.25), key("FN", 1.25), key("windows", 1.25), key("RCTL", 1.25)], []]
      ]
    } else if (form === "75") {
      // Compressed: the extra column sits hard against the main block with
      // no gap, which is the whole idea of a 75%. The function row is spread
      // across the block rather than grouped in fours, for the same reason
      // and because a bigger key is worth more here than a familiar gap, but
      // it stops where the block stops so Del sits over the column below it.
      // There is no room for a Menu key, so the tiling key holds it.
      var fRow = ["ESC"].concat(root.positions("FK", 1, 12))
      rows = [
        [fRow.map(function(k) { return key(k, 15 / fRow.length) }), [key("delete")]],
        [mainRows[0], [key("home")]],
        [mainRows[1], [key("pgup")]],
        [mainRows[2], [key("pgdn")]],
        [shift.concat([key("RTSH", 1.75), key("up")]), [key("end")]],
        [[key("LCTL", 1.25), key("LWIN", 1.25), key("LALT", 1.25), key("SPCE", 6.75),
          key("RALT", 1.25), key("windows", 1.25), key("left"), key("down")],
         [key("right")]]
      ]
    } else {
      // Tenkeyless: the function row grouped in fours and the nav cluster
      // three wide past a gap, which is what the board looks like and half
      // the reason anyone asks for one.
      rows = [
        [[key("ESC"), gap(1),
          key("FK01"), key("FK02"), key("FK03"), key("FK04"), gap(0.5),
          key("FK05"), key("FK06"), key("FK07"), key("FK08"), gap(0.5),
          key("FK09"), key("FK10"), key("FK11"), key("FK12")],
         [gap(0.25), key("prtsc"), key("scrlk"), key("pause")]],
        [mainRows[0], [gap(0.25), key("insert"), key("home"), key("pgup")]],
        [mainRows[1], [gap(0.25), key("delete"), key("end"), key("pgdn")]],
        [mainRows[2], [gap(3.25)]],
        [shift.concat([key("RTSH", 2.75)]), [gap(1.25), key("up"), gap(1)]],
        // The right Super gives way to tiling here as it does everywhere
        // else, and this board has the room to keep its Menu key as well.
        [[key("LCTL", 1.25), key("LWIN", 1.25), key("LALT", 1.25), key("SPCE", 6.25),
          key("RALT", 1.25), key("windows", 1.25), key("menu", 1.25), key("RCTL", 1.25)],
         [gap(0.25), key("left"), key("down"), key("right")]]
      ]
    }

    // Anything the layout turned out not to have comes off the block, and
    // the block is then stretched back to its 15 units by the keys at its
    // own ends. It has to be its own ends: stretching the whole row would
    // hand the width to a nav key and walk the block's right edge out of
    // line with the row above. With every dead key now reported there
    // should be nothing to stretch, and this is what keeps a layout nobody
    // has tried from coming out ragged.
    var block = form === "phone" ? units : 15
    var heights = root.rowHeightsOf(form)
    return rows.map(function(pair, i) {
      var main = pair[0].filter(function(e) {
        return !root.isPrintedPosition(e.key) || (e.key in root.grid)
      })
      var slack = block - main.reduce(function(a, e) { return a + e.w }, 0)
      if (slack * root.unit > 1 && main.length > 1) {
        main[0] = { key: main[0].key, w: main[0].w + slack / 2 }
        var last = main.length - 1
        main[last] = { key: main[last].key, w: main[last].w + slack / 2 }
      }
      var h = heights[i] === undefined ? 1 : heights[i]
      return main.concat(pair[1]).map(function(e) { return { key: e.key, w: e.w, h: h } })
    })
  }

  // The phone layout: an extra row of desktop keys over the page's own rows.
  // The extra row spreads over the full width, less whatever the windows
  // toggle holds at the end of it, and the page rows take their widths from
  // the table and then stretch to reach the edges.
  function phoneRows(page) {
    var fixed = 0, sharers = 0
    root.topRow.forEach(function(k) {
      if (k in root.topRowFixed) fixed += root.topRowFixed[k]
      else sharers++
    })
    var share = sharers > 0 ? (root.formUnits - fixed) / sharers
      : root.formUnits / root.topRow.length
    var rows = [root.topRow.map(function(k) {
      return { key: k, w: (k in root.topRowFixed) ? root.topRowFixed[k] : share,
               h: root.topRowFraction }
    })]
    root.pages[page].forEach(function(row) {
      var w = root.stretch(row, row.map(function(k) { return root.widths[k] || 1 }))
      rows.push(row.map(function(k, i) { return { key: k, w: w[i], h: 1 } }))
    })
    return rows
  }

  // Where every key of a page sits. Taken by name rather than read off the
  // current page, so the letters page can ask where the symbol pages put
  // their characters without being on one (see overlayOf).
  function slotsOf(page) {
    var gap = root.theme.gap
    var out = []
    var y = root.topPadding
    root.formRows(page).forEach(function(row, i) {
      var total = row.reduce(function(a, e) { return a + e.w }, 0)
      var h = Math.round(root.keyHeight * row[0].h)
      var x = (root.width - total * root.unit) / 2
      row.forEach(function(e) {
        // An entry with no key is the space between clusters on a board that
        // has them. It holds width and takes no touches, so keyAt can never
        // return one and nothing draws there.
        if (e.key !== "")
          out.push({ key: e.key, row: i, x: x + gap / 2, y: y,
                     width: e.w * root.unit - gap, height: h })
        x += e.w * root.unit
      })
      y += h + gap
    })
    return out
  }
  readonly property var slots: root.slotsOf(root.page)
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
    var role = root.roleOf(root.effectiveKey(key))
    if (role === "space") return layoutName
    if (role in labels) return labels[role]
    return root.charFor(key)
  }

  // What a cap prints small in its right corner: the character AltGr types
  // on it. A real board reads it off the position, the phone layout off the
  // letter.
  function hintFor(key) {
    // The layer replaces what a key does, so what it would otherwise reach
    // with AltGr is not what it reaches now.
    if (root.altgrOn || (root.fnOn && (key in root.fnMap))) return ""
    var lv = root.grid[key]
    return lv ? lv[2] : (root.level3Of[key] || "")
  }

  function shifted(key) {
    return shiftOf[key] || key.toUpperCase()
  }

  // The character a key types with the modifiers as they are. A cap shows
  // this, so what is written on a key is always what tapping it gives you.
  // A key with nothing on its third level types its own character, the way
  // it would with AltGr held on a physical keyboard that has nothing there.
  function charFor(key) {
    key = root.effectiveKey(key)
    // A real board's key is a position, and what it types is whatever the
    // active layout puts at that position. Shift comes from the keymap and
    // not from upper casing, because the shifted level of a number row is
    // not the upper case of anything.
    var lv = root.grid[key]
    if (lv) {
      if (root.altgrOn) {
        var level = root.upper ? (lv[3] || lv[2]) : lv[2]
        if (level) return level
      }
      return root.upper ? (lv[1] || lv[0]) : lv[0]
    }
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
    var role = root.roleOf(root.effectiveKey(key))
    // Caps Lock holds the keyboard's own Shift, so it is drawn locked when
    // that is what it has done.
    if (role === "caps") return root.mods.shift === "locked" ? "locked" : "special"
    // Super is the key Omarchy is built around, so at rest it is drawn the
    // way Enter is rather than as another grey modifier. Armed, it drops
    // back to the latched and locked colours, because what it is doing then
    // matters more than how important it is.
    if (role === "super")
      return mods["super"] === "locked" ? "locked"
        : mods["super"] === "latched" ? "latched" : "accent"
    if (role in mods) return mods[role] === "locked" ? "locked" : mods[role] === "latched" ? "latched" : "special"
    if (role === "enter") return "accent"
    // The space bar goes with them rather than with the letters, though it
    // does type a character: it is part of the frame around the letters, it
    // carries the layout's name instead of a legend, and no one hunts for it.
    return root.roleOf(root.effectiveKey(key)) in labels ? "special" : "normal"
  }

  // Modifiers applied to the next key, as the helper names them. AltGr is
  // not one of them: it chooses which character a key types (charFor), and
  // that character is then typed as itself, so a layout's third level works
  // the same whether or not the character has a key of its own.
  function activeMods(includeShift) {
    var names = []
    for (var m in mods)
      if (m !== "altgr" && m !== "fn" && mods[m] !== "off"
          && (includeShift || m !== "shift")) names.push(m)
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
  //
  // Shift is the exception on a board that has a Caps key. Locking is what
  // that key is for, and one keyboard offering two ways to do one thing is
  // one too many, so there Shift only ever latches: off, on for the next
  // key, off. A tap while it is locked still lets go, because the lock can
  // only have come from Caps and a second way out of it costs nothing.
  function tapModifier(name) {
    var state = mods[name]
    if (state === "off") {
      setMod(name, "latched")
    } else if (state === "latched" && !(name === "shift" && root.hasCapsKey)) {
      setMod(name, "locked")
    } else {
      setMod(name, "off")
    }
  }

  function press(key) {
    key = root.effectiveKey(key)
    var role = root.roleOf(key)
    // Caps Lock holds the keyboard's own Shift rather than sending the
    // keysym. A real Caps Lock sets a state in the compositor that the caps
    // drawn here cannot see, and a keyboard that types what it shows has to
    // own that state itself.
    if (role === "caps") {
      root.setMod("shift", root.mods.shift === "locked" ? "off" : "locked")
      return
    }
    if (role in mods) { tapModifier(role); return }
    if (role === "windows") {
      // Straight into tiling, rather than to a page of keys that say the
      // same things. It waits for the finger to lift because it takes the
      // keyboard off the screen: see liftKeys.
      root.afterKey()
      root.service.openTiling()
      return
    }
    switch (role) {
    case "symbols": case "more": case "letters":
      page = role
      return
    case "settings":
      // Ragtop's controls come up over the keyboard rather than in place of
      // it, so the keys stay under them while you change how they look. No
      // key of its own reaches this any more: it is what a hold on Super
      // does (see holdOpens), and a touch anywhere on the keys puts it away.
      root.service.toolsOpen = !root.service.toolsOpen
      return
    }
    if (holdable.indexOf(role) !== -1) {
      service.sendKeys(["down", keysyms[role]].concat(activeMods(true)).join(" "))
      return
    }
    if (role in keysyms) {
      service.sendKeys(["key", keysyms[role]].concat(activeMods(true)).join(" "))
    } else {
      // A character: typed as itself unless Ctrl, Alt or Super make it a
      // shortcut, which goes by the key (Ctrl+C, not Ctrl+"C"). A real
      // board's key is a position, so the character it types unshifted is
      // what stands for it: Ctrl and the 3 key is "key 3 ctrl".
      var combo = activeMods(false)
      var named = root.grid[key] ? root.grid[key][0] : key
      if (combo.length > 0)
        service.sendKeys(["key", named].concat(activeMods(true)).join(" "))
      else
        service.sendKeys("type " + root.charFor(key))
    }
    afterKey()
  }

  function release(key) {
    var role = root.roleOf(root.effectiveKey(key))
    if (root.liftKeys.indexOf(role) !== -1) {
      root.press(key)
      return
    }
    if (holdable.indexOf(role) !== -1) {
      service.sendKeys("up " + keysyms[role])
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

  // Whether the finger has gone anywhere since the popup opened. A hold
  // that never moved was a slow tap and still types the key it came down
  // on. One that went to the card and came away from it again meant to
  // change its mind, and types nothing.
  property bool popupTravelled: false

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

  // Everything a finger was in the middle of, dropped. The card keeps its
  // geometry as plain numbers rather than bindings, so a screen that
  // reshapes under it leaves it pointing at places that have moved: the
  // cell under a finger that never moved would not be the one it went to.
  // Re-aiming it would type a character nobody chose, which is worse than
  // typing nothing, so a rotation cancels outright and the tap is made
  // again. The pending hold goes with it, since the key it belongs to is
  // somewhere else now too.
  function cancelTouches() {
    if (root.popup === null && root.pendingPoint === -1) return
    root.popup = null
    holdTimer.stop()
    root.pendingPoint = -1
    root.pendingKey = ""
    var was = root.held
    root.held = ({})
    // A key sent down has to be sent up whatever else happens, or it
    // repeats for as long as the shell is running.
    for (var id in was)
      if (root.holdable.indexOf(was[id]) !== -1)
        root.service.sendKeys("up " + root.keysyms[was[id]])
  }
  onWidthChanged: root.cancelTouches()
  onHeightChanged: root.cancelTouches()

  // A hold that never became a card, settled as the tap it turned out to
  // be. The space bar typed on the way down and has nothing left to say.
  function commitPending() {
    if (root.pendingPoint === -1) return
    var key = root.pendingKey
    root.endHold()
    if (root.roleOf(key) !== "space") root.press(key)
  }

  // Whether this finger has gone far enough from where it came down to have
  // meant it. One measure for both the hold that has not opened yet and the
  // card that has, so a finger cannot count as still for one and moving for
  // the other.
  function travelled(point) {
    return Math.abs(point.x - root.pendingX) + Math.abs(point.y - root.pendingY) > root.unit * 0.4
  }

  // The popup sits above its key and slides along the row to stay on the
  // keyboard. Where it can't fit at all it's centred. Nothing is chosen
  // when it opens, whatever it had to slide past to fit: a card pushed
  // away from its key leaves the finger over a cell it never aimed at,
  // and choosing that one silently would type it on the way out.
  function openPopup() {
    var key = root.pendingKey
    // One thing behind a key is not a card. A card of a single cell would ask
    // for a slide onto it and give nothing back for the trouble, so this acts
    // straight away and the finger has nothing left to do. endHold is what
    // stops the lift also counting as a tap: with no hold pending and no card
    // open, the finger falls through to release(), which Super ignores.
    var opens = root.holdOpenFor(key)
    if (opens !== "") {
      root.endHold()
      root.press(opens)
      return
    }
    var items = root.holdItems(key)
    if (items.length < 1 || root.pendingPoint === -1) return
    var layouts = root.roleOf(key) === "space"
    var slot = null
    for (var i = 0; i < root.slots.length; i++) if (root.slots[i].key === key) { slot = root.slots[i]; break }
    if (!slot) return
    var room = root.width - 2 * root.theme.padding
    var cell = layouts ? Math.min(root.wordCell(items), room / items.length)
      : Math.max(slot.width + root.theme.gap, root.unit * 0.92)
    // Characters are cut to what the keyboard is wide enough to show, so a
    // card never runs off both edges at once. The ones at the end are the
    // accents, which is the order holdItems puts them in. Layout names are
    // squeezed to fit instead: dropping one would leave a layout that is
    // configured with no way to reach it.
    if (!layouts) items = items.slice(0, Math.max(1, Math.floor(room / cell)))
    var total = items.length * cell
    // Characters start their first cell over the key being held, so the
    // finger has the shortest reach to the one nearest it. Layout names are
    // a list rather than a row of keys, so they sit centred on the space bar.
    var from = layouts ? slot.x + (slot.width - total) / 2 : slot.x
    var x = total > room ? (root.width - total) / 2
      : Math.min(Math.max(from, root.theme.padding), root.width - root.theme.padding - total)
    root.popupTravelled = false
    root.popup = { key: key, kind: layouts ? "layouts" : "chars",
                   items: items, pointId: root.pendingPoint, index: -1,
                   x: x, y: Math.max(root.popupTop, slot.y - slot.height - root.theme.gap),
                   cellWidth: cell, cellHeight: slot.height }
  }

  // Which cell the finger is on. Sliding well below the popup takes
  // nothing, the way letting go somewhere else cancels on a phone.
  function selectAt(x, y) {
    var p = root.popup
    if (!p) return
    var index = -1
    // Nothing is chosen until the finger is on the card, for either kind.
    // Resting on the key it came down on is not a choice: that is the slow
    // tap choosePopup types the plain key for. Characters get a little
    // grace above, where a finger reaching up can overshoot, and down to
    // the gap between the card and the key, so there is no dead band at
    // the edge the finger arrives through.
    var within = p.kind === "layouts"
      ? (y >= p.y && y <= p.y + p.cellHeight)
      : (y >= p.y - p.cellHeight / 2 && y <= p.y + p.cellHeight + root.theme.gap)
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
    var key = root.pendingKey
    var travelled = root.popupTravelled
    root.popup = null
    root.endHold()
    if (!p) return
    if (p.index < 0) {
      // A finger that never went anywhere was a slow tap on the key, and
      // types it. The space bar has already typed by the time its hold
      // opens anything, so it is the one key this must not type again.
      if (!travelled && root.roleOf(key) !== "space") root.press(key)
      return
    }
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
      hint: root.hintFor(modelData.key)
      // Only on the letters page, where the symbol pages are somewhere
      // else. On the symbol pages themselves the character is already the
      // label, and saying so twice would be noise.
      hintLeft: root.form === "phone" && root.page === "letters"
        ? (root.symbolOf[modelData.key] || "") : ""
      // What a hold reaches, drawn rather than written: the gear is an icon
      // and there is no character that says "settings".
      hintIcon: root.iconFor(root.holdOpenFor(modelData.key))
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
        // While a card is open the other fingers wait their turn.
        if (root.popup !== null) return
        var key = root.keyAt(p.x, p.y)
        if (key === null) return
        // Another finger arriving settles whatever hold is still waiting:
        // it was a tap, and it types now, in the order it was pressed.
        // Rolling from one letter into the next is most of typing, and
        // without this the second of them would be dropped.
        root.commitPending()
        next[p.pointId] = key
        // Every key that types a character now types on release, so that a
        // hold has room to become a card first. Whether this one has
        // anything behind it or not, they all answer at the same moment:
        // keys that reply on the way down beside keys that reply on the way
        // up is worse than either on its own. The space bar is the
        // exception, and types on the way down as it always has, because a
        // thumb resting on it must not swallow the letter rolling in after.
        // What the key means now, which the Fn layer may have changed.
        var eff = root.effectiveKey(key)
        var role = root.roleOf(eff)
        // A key with anything behind it waits for the finger to lift, so the
        // hold has room to become a card first. Esc on a 60% board is one of
        // those, though it is no character itself.
        var deep = root.holdOpenFor(key) !== "" || (key in root.holdGrid)
        if (role === "space" || root.isCharacter(eff) || deep)
          root.startHold(p, key)
        if (root.liftKeys.indexOf(role) === -1 && !deep
            && (role === "space" || !root.isCharacter(eff))) pressed.push(key)
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
      if (root.travelled(point)) root.popupTravelled = true
      root.selectAt(point.x, point.y)
      return
    }
    // A finger that wanders off the key it came down on was never holding
    // it: the key still types when it lifts, as it always has.
    if (point.pointId !== root.pendingPoint) return
    if (root.travelled(point)) holdTimer.stop()
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
        if (root.roleOf(key) !== "space") root.press(key)  // a tap after all, and space already did
      } else if (p.pointId in next) {
        lifted.push(next[p.pointId])
      }
      delete next[p.pointId]
    })
    root.held = next
    lifted.forEach(root.release)
  }
}
