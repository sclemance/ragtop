import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// A short tour of the keyboard, drawn on Ragtop's overlay layer (Service.qml,
// overlayWindow), which sits above the keys. Each step lights one part of
// the keyboard and dims the rest, with a card beside it saying what that
// part does, and shows it working: a card opened as a hold would open it,
// Shift going through its states, a word drawn across the letters.
//
// It shows and never changes. Themes and boards are previews laid over the
// settings and never written (Service.qml, previewSettings and
// previewLayout), suggestions and swipe are shown whether they are on or
// not, and the overlay takes every touch while the tour runs, so nothing
// typed reaches anything. Ending it, by Skip or Done or the keyboard going
// away, puts everything back (Service.qml, endTour).
//
// It is offered once, the first time the keyboard comes up, and is in the
// controls from then on. The offer is a card and nothing else: it takes
// touches only on itself, so the keyboard under it still types.
//
// English only, like the rest of Ragtop's words.
Item {
  id: tour

  required property var service
  required property var keyboard
  // Where the keyboard item's top edge is in this item.
  property real keyboardTop: 0
  // The handle under the keyboard, in this item, or null while there is none.
  property var handleRect: null

  // What takes touches: the whole layer during the tour, the card alone
  // while it is only being offered (see the overlay's mask).
  readonly property Item card: bubble

  readonly property bool running: tour.service.tourActive === true
  readonly property bool offering: tour.service.tourOffered === true && !tour.running
  property int step: 0
  property int tick: 0

  readonly property var current: tour.steps[Math.max(0, Math.min(tour.step, tour.steps.length - 1))]

  // ---- Themes, read once per tour -------------------------------------------

  // { slug: { name, values } } for every theme, from `ragtop theme show`,
  // which checks a theme exactly as applying one does and writes nothing.
  property var themes: ({})
  // The ones the tour shows, which are not the one in use.
  readonly property var shownThemes: {
    var liked = ["spaceship", "typewriter", "glass", "industrial", "soft", "omarchy"]
    var out = []
    for (var i = 0; i < liked.length && out.length < 3; i++)
      if (liked[i] !== tour.service.currentTheme && tour.themes[liked[i]]) out.push(liked[i])
    return out
  }
  property string previewName: ""
  function showTheme(slug) {
    var t = tour.themes[slug]
    if (!t) return
    tour.service.previewSettings = t.values
    tour.previewName = t.name
  }
  Process {
    id: themesProc
    command: ["bash", "-c", 'r="$1"; for t in $(bash "$r" theme list); do echo "@$t"; bash "$r" theme show "$t"; done',
              "_", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = {}, slug = ""
        text.split("\n").forEach(function(line) {
          if (line.charAt(0) === "@") { slug = line.slice(1); out[slug] = { name: slug, values: {} }; return }
          var eq = line.indexOf("=")
          if (!slug || eq < 1) return
          var k = line.slice(0, eq), v = line.slice(eq + 1)
          if (k === "name") out[slug].name = v
          else out[slug].values[k] = v
        })
        tour.themes = out
      }
    }
  }

  // ---- The steps --------------------------------------------------------------

  // Each: target, the parts lit (Keyboard.qml, demoRect; the first one this
  // board has wins, and "keys" when it has none); title; body; and what it
  // does on arriving (enter) and at each beat of the clock (beat).
  readonly property var steps: [
    { target: ["keys"], title: "A quick tour",
      body: "A minute's walk around the keyboard: the keys worth knowing, and what holding them does. Tap Next to go on, or Skip tour to stop at any time." },

    { target: ["handle"], title: "The handle",
      body: function() {
        return "The bar along the bottom edge lowers the keyboard with a tap, and raises it again with another."
          + (tour.service.autoShowEnabled ? " The keyboard also comes up by itself when you tap into a text field." : "")
      },
      beat: function(n) { tour.service.tourLowered = n % 4 === 1 || n % 4 === 2 } },

    { target: ["super"], title: "The Omarchy key",
      body: "Super, the key every Omarchy shortcut starts with. Tap it and then a letter: Super then K lists every shortcut, Super then Space opens the launcher.",
      beat: function(n) { tour.keyboard.setMod("super", n % 2 ? "latched" : "off") } },

    { target: ["gear"], title: "Ragtop's controls",
      body: "The gear opens the controls: key size, themes, boards, suggestions, swipe, updates, and this tour again." },

    { target: ["menu", "gear"], title: "The Menu key",
      body: function() {
        var where = tour.keyboard.demoSlot("menu") ? "This board has a key of its own for it."
          : tour.keyboard.hasFnKey ? "Hold the gear for it, or tap the gear with Fn on."
          : "Hold the gear for it: the mark in its corner says so."
        return "Menu opens the right-click menu where you are typing, in browsers, file managers and most apps: the right click a tablet does not have. A terminal ignores it.\n\n" + where
      } },

    { target: ["keys"], top: true, title: "Themes",
      body: function() {
        return "A theme is the keys' shape and finish. The colours always follow your Omarchy theme."
          + "\n\nThis is " + (tour.previewName || "yours") + "."
      },
      beat: function(n) {
        var list = tour.shownThemes
        if (list.length === 0) return
        var at = Math.floor(n / 2) % (list.length + 1)
        if (at === list.length) { tour.service.previewSettings = ({}); tour.previewName = "" }
        else tour.showTheme(list[at])
      } },

    { target: ["keys"], top: true, title: "Boards",
      body: function() {
        var names = { "mobile": "Mobile", "60": "60%", "75": "75%", "80": "80%" }
        return "From a phone's three rows to a full keyboard. Auto picks the widest that fits your screen, and the controls can pick one for good."
          + "\n\nThis is " + (names[tour.keyboard.form] || tour.keyboard.form) + "."
      },
      beat: function(n) {
        var boards = ["mobile", "60", "75", "80"]
        tour.service.previewLayout = boards[Math.floor(n / 2) % boards.length]
      } },

    { target: ["popup", "e"], title: "Hold a letter",
      body: "Hold a letter for its accents and the symbol in its corner, slide onto one, and let go.",
      enter: function() { tour.keyboard.demoHold("e") },
      beat: function(n) { if (tour.reopen("e")) tour.keyboard.demoChoose(n % 4 - 1) } },

    { target: ["popup", "space"], title: "Hold Space",
      body: function() {
        return tour.keyboard.popup
          ? "Hold Space for your keyboard layouts and input methods, and slide to the one you want."
          : "Hold Space for your keyboard layouts and input methods. You have one layout now; Omarchy's keyboard settings add more."
      },
      enter: function() { tour.keyboard.demoHold("space") },
      beat: function(n) {
        if (tour.reopen("space")) tour.keyboard.demoChoose(n % (tour.keyboard.popup.items.length + 1) - 1)
      } },

    { target: ["shift"], title: "Sticky modifiers",
      body: function() {
        var state = { "off": "off", "latched": "on for the next key", "locked": "locked" }
        return "Tap Shift once for the next key, twice to lock it, and again to let go. Ctrl, Alt and Super work the same way, so a shortcut is one key at a time."
          + "\n\nShift is " + state[tour.keyboard.mods.shift] + "."
      },
      beat: function(n) { tour.keyboard.setMod("shift", ["off", "latched", "locked"][n % 3]) } },

    { target: ["fn"], title: "Fn",
      body: function() {
        return tour.keyboard.hasFnKey
          ? "On the 60% and 75% boards, Fn reaches what the board leaves out: F1 to F12 on the number row, arrows and page keys around J, Delete on Backspace. It is sticky too."
          : "On the 60% and 75% boards, Fn reaches what the board leaves out: F1 to F12, arrows and page keys, Delete. Your screen is too narrow to show one here."
      },
      enter: function() { if (!tour.keyboard.hasFnKey) tour.service.previewLayout = "60" },
      beat: function(n) { tour.keyboard.setMod("fn", n % 2 ? "latched" : "off") } },

    { target: ["altgr"], title: "AltGr",
      body: function() {
        return tour.keyboard.hasAltGr
          ? "AltGr types the characters a layout keeps on a key's third level, like € and ß. It is sticky too."
          : "AltGr types the characters a layout keeps on a key's third level, like € and ß. Your layout has none, so there is no AltGr now. Switch to one that has some, and it appears."
      },
      beat: function(n) { if (tour.keyboard.hasAltGr) tour.keyboard.setMod("altgr", n % 2 ? "latched" : "off") } },

    { target: ["popup", "strip"], title: "Suggestions",
      body: function() {
        return "Words appear here as you type. Tap one to take it, hold one for its other forms. Nothing leaves this device."
          + (tour.service.predictionsEnabled ? "\n\nYour suggestions are on." : "\n\nYour suggestions are off: turn them on in the controls.")
      },
      enter: function() {
        tour.service.setSuggestions("tour", { items: [{ text: "walk" }, { text: "walking" }, { text: "walked" },
                                                      { text: "walks" }, { text: "walker" }] })
      },
      beat: function(n) {
        if (n % 4 === 2) tour.keyboard.demoForms(0, ["walks", "walked", "walking", "walker"])
        else if (n % 4 === 0) tour.keyboard.cancelTouches()
        else if (n % 4 === 3) tour.keyboard.demoChoose(1)
      } },

    { target: ["keys"], title: "Swipe",
      body: function() {
        return "Draw a word across the letters without lifting, and let go. It works with suggestions on."
          + (tour.service.swipeEnabled ? "\n\nYour swipe typing is on." : "\n\nYour swipe typing is off: turn it on in the controls.")
      },
      enter: function() { swipeClock.restart() } },

    { target: ["gear"], title: "That's it",
      body: "Take the tour again any time from the controls, behind the gear." }
  ]

  // A card the keyboard closed, opened again. The keyboard drops every card
  // when it changes size (Keyboard.qml, cancelTouches), which it does when
  // the step before showed another board. True when there is one open.
  function reopen(name) {
    return tour.keyboard.popup !== null || tour.keyboard.demoHold(name)
  }

  // Back to the keyboard as it was before each step does its own thing.
  function reset() {
    swipeClock.stop()
    tour.keyboard.demoClear()
    tour.service.tourLowered = false
    tour.service.previewSettings = ({})
    tour.service.previewLayout = ""
    tour.service.setSuggestions("tour", null)
    tour.previewName = ""
  }
  function go(to) {
    tour.reset()
    tour.pin = null
    settle.restart()
    tour.step = Math.max(0, Math.min(tour.steps.length - 1, to))
    tour.tick = 0
    var s = tour.current
    // A frame later, so the board a step asks for has been laid out before
    // anything looks for a key on it.
    Qt.callLater(function() {
      if (!tour.running || tour.current !== s) return
      if (s.enter) s.enter()
      if (s.beat) s.beat(0)
    })
  }

  onRunningChanged: {
    if (tour.running) {
      themesProc.running = true
      tour.go(0)
    } else {
      tour.reset()
    }
  }

  Timer {
    interval: 1400
    repeat: true
    running: tour.running && !!tour.current.beat
    onTriggered: {
      tour.tick++
      tour.current.beat(tour.tick)
    }
  }

  // The swipe, drawn a little at a time and then left up long enough to read,
  // with the word it made in the strip.
  property real swipeAt: 0
  Timer {
    id: swipeClock
    interval: 33
    repeat: true
    onTriggered: {
      tour.swipeAt += 0.022
      if (tour.swipeAt >= 2.4) {
        tour.swipeAt = 0
        tour.service.setSuggestions("tour", null)
      }
      if (tour.swipeAt < 1) {
        tour.keyboard.demoSwipe("hello", tour.swipeAt)
      } else if (tour.service.suggestions.source !== "tour") {
        // Lifted: the trail goes and the word arrives, as it does for real.
        tour.keyboard.demoSwipe("", 0)
        tour.service.setSuggestions("tour", { items: [{ text: "hello" }, { text: "hell" }, { text: "jello" }] })
      }
    }
    onRunningChanged: tour.swipeAt = 0
  }

  // ---- What is lit ----------------------------------------------------------

  // The lit part, in this item. Read again whenever the keys move, a card
  // opens or the strip comes and goes.
  readonly property var target: {
    var deps = [tour.keyboard.slots, tour.keyboard.popup, tour.keyboard.stripShown,
                tour.keyboard.height, tour.keyboardTop, tour.handleRect]
    var names = tour.current.target
    var found = null
    for (var i = 0; i < names.length && !found; i++) {
      if (names[i] === "handle") {
        // Already in this item's terms, so it skips the keyboard's offset.
        var h = tour.handleRect
        if (h) return { x: h.x, y: h.y - Style.space(2), width: h.width, height: h.height + Style.space(2) }
        continue
      }
      found = tour.keyboard.demoRect(names[i])
    }
    // A card is lit with what it came from: its key, or the strip.
    if (found && names[0] === "popup" && names.length > 1) {
      var key = tour.keyboard.demoRect(names[1])
      if (key) {
        var x = Math.min(found.x, key.x), y = Math.min(found.y, key.y)
        found = { x: x, y: y, width: Math.max(found.x + found.width, key.x + key.width) - x,
                  height: Math.max(found.y + found.height, key.y + key.height) - y }
      }
    }
    if (!found) found = tour.keyboard.demoRect("keys")
    if (!found) return { x: 0, y: tour.height, width: tour.width, height: 0 }
    var pad = Style.space(6)
    return { x: found.x - pad, y: tour.keyboardTop + found.y - pad,
             width: found.width + 2 * pad, height: found.height + 2 * pad }
  }

  // The hole, eased from one target to the next.
  Item {
    id: hole
    x: tour.target.x
    y: tour.target.y
    width: tour.target.width
    height: tour.target.height
    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
  }

  // Everything but the hole dimmed, as Omarchy dims behind its menus.
  Item {
    anchors.fill: parent
    opacity: tour.running ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: tour.service.dimFade } }

    Rectangle { width: tour.width; height: Math.max(0, hole.y); color: tour.service.scrimColor }
    Rectangle {
      y: hole.y + hole.height
      width: tour.width
      height: Math.max(0, tour.height - y)
      color: tour.service.scrimColor
    }
    Rectangle { y: hole.y; width: Math.max(0, hole.x); height: hole.height; color: tour.service.scrimColor }
    Rectangle {
      x: hole.x + hole.width
      y: hole.y
      width: Math.max(0, tour.width - x)
      height: hole.height
      color: tour.service.scrimColor
    }
    Rectangle {
      x: hole.x
      y: hole.y
      width: hole.width
      height: hole.height
      color: "transparent"
      radius: Style.cornerRadius
      border.color: Color.accent
      border.width: Math.max(1, Style.space(2))
    }
  }

  // ---- The card -----------------------------------------------------------------

  readonly property real margin: Style.space(16)
  // How far the card stands off what is lit, which is the tail's length.
  readonly property real arrowSize: Style.space(24)
  // Above what is lit where there is room, else below it, else over it at the
  // top of the screen with no arrow. A step that changes the keyboard's size
  // as it goes (themes, boards) puts it at the top from the start.
  readonly property string liveSide: !tour.running ? "offer"
    : tour.current.top ? "top"
    : tour.target.y - tour.arrowSize - tour.cardHeight >= tour.margin ? "above"
    : tour.target.y + tour.target.height + tour.arrowSize + tour.cardHeight <= tour.height - tour.margin ? "below"
    : "over"
  readonly property real targetMiddle: tour.target.x + tour.target.width / 2
  readonly property real cardHeight: content.implicitHeight + 2 * bubble.inset

  // Where the card settled once the step had laid itself out, and where it
  // then stays for the rest of the step. Following the keyboard as a theme
  // or a board changed it moved the buttons out from under the finger
  // reaching for them. Above what is lit, its bottom edge is what is kept,
  // so text that grows pushes the card up and the buttons stay put.
  property var pin: null
  // Except when what is lit grows under it: a card the keyboard reopened a
  // beat late. Then it settles once more, clear of it.
  onTargetChanged: {
    if (!tour.pin) return
    var t = tour.target
    var top = bubble.y, bottom = bubble.y + tour.cardHeight
    var left = bubble.x, right = bubble.x + bubble.width
    if (t.y < bottom && t.y + t.height > top && t.x < right && t.x + t.width > left) {
      tour.pin = null
      settle.restart()
    }
  }
  readonly property string side: tour.pin ? tour.pin.side : tour.liveSide
  Timer {
    id: settle
    interval: 300
    onTriggered: tour.pin = { side: tour.liveSide, x: bubble.liveX, y: bubble.liveY,
                              bottom: bubble.liveY + tour.cardHeight }
  }

  // The card and its tail, one outline: traced around the card with the tail
  // as part of the same path, then filled and edged once, so the tail grows
  // out of the card instead of being a triangle stamped on its edge.
  //
  // Where the tail leaves the card and how it leans both follow where the
  // card is on the screen, for the variety of it. A card further across the
  // screen starts its tail further along its own edge, scaled into the middle
  // three fifths of it so a tail never leaves from a corner, and leans
  // it inwards, towards the middle of the screen, and the nearer the screen's
  // edge, the further: 45 degrees at the very edge, none in the middle. The
  // card is placed so that the leaning tail still ends on its key, and the
  // tip always sits on the spotlight's edge.
  // The cards for themes and boards sit at the top of the screen, so their
  // tail is as long as the way down to the keyboard, and stretches and
  // shrinks as the boards change height under a card that stays put.
  readonly property bool tailDown: tour.side === "above" || tour.side === "top"
  readonly property bool tailed: bubble.visible && (tour.tailDown || tour.side === "below")
    && (tour.side !== "top" || tour.target.y > bubble.y + bubble.height + Style.space(8))
  readonly property real tailHalf: Style.space(11)
  // 0 at the screen's left edge, 1 at its right, for a card at x.
  function across(x) { return Math.max(0, Math.min(1, (x + bubble.width / 2) / Math.max(1, tour.width))) }
  // The tail's base on a card at x, before anything holds it to the card.
  function baseAt(x) { return x + (0.2 + 0.6 * tour.across(x)) * bubble.width }
  function leanAt(x) { return (0.5 - tour.across(x)) * Math.PI / 2 }
  function tipFrom(x) { return tour.baseAt(x) + Math.tan(tour.leanAt(x)) * tour.arrowSize }
  // Where a card must sit for its tail to end at t: a few steps of moving it
  // by however far the tip missed, which settles at once, since the tip moves
  // with the card nearly one for one.
  function cardXFor(t) {
    var x = t - bubble.width / 2
    for (var i = 0; i < 6; i++) x += t - tour.tipFrom(x)
    return Math.max(tour.margin, Math.min(tour.width - tour.margin - bubble.width, x))
  }
  // A key: its middle. Something wider than the card: wherever the tail
  // lands on it.
  readonly property bool narrowTarget: tour.target.width < bubble.width
  readonly property real tailTipX: tour.narrowTarget ? tour.targetMiddle
    : Math.max(tour.target.x + Style.space(12),
               Math.min(tour.target.x + tour.target.width - Style.space(12), tour.tipFrom(bubble.x)))
  // The base, kept on the card's straight edge and never leaning past 45
  // degrees, which a card held in by the screen's margin could otherwise ask.
  readonly property real tailBase: {
    var r = Style.cornerRadius
    var room = Math.max(tour.tailHalf + Style.space(6), bubble.width * 0.15)
    var reach = Math.max(tour.arrowSize, tour.tailTipY - (bubble.y + bubble.height), bubble.y - tour.tailTipY)
    var base = Math.max(tour.tailTipX - reach, Math.min(tour.tailTipX + reach, tour.baseAt(bubble.x)))
    return Math.max(bubble.x + r + room, Math.min(bubble.x + bubble.width - r - room, base))
  }
  readonly property real tailTipY: tour.tailDown ? tour.target.y : tour.target.y + tour.target.height

  Canvas {
    id: outline
    visible: bubble.visible
    readonly property real edge: Math.max(1, Style.space(2))
    x: Math.min(bubble.x, tour.tailed ? tour.tailTipX : bubble.x) - edge * 2
    y: Math.min(bubble.y, tour.tailed ? tour.tailTipY : bubble.y) - edge * 2
    width: Math.max(bubble.x + bubble.width, tour.tailed ? tour.tailTipX : 0) - x + edge * 2
    height: Math.max(bubble.y + bubble.height, tour.tailed ? tour.tailTipY : 0) - y + edge * 2
    readonly property var shape: [bubble.x, bubble.y, bubble.width, bubble.height, tour.tailed,
                                  tour.tailBase, tour.tailTipX, tour.tailTipY, tour.side,
                                  Color.popups.background, Color.popups.border]
    onShapeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.translate(-outline.x, -outline.y)
      var x0 = bubble.x, y0 = bubble.y, x1 = x0 + bubble.width, y1 = y0 + bubble.height
      var r = Math.min(Style.cornerRadius, bubble.width / 2, bubble.height / 2)
      var b = tour.tailBase, h = tour.tailHalf
      ctx.beginPath()
      ctx.moveTo(x0 + r, y0)
      if (tour.tailed && tour.side === "below") {
        ctx.lineTo(b - h, y0)
        ctx.lineTo(tour.tailTipX, tour.tailTipY)
        ctx.lineTo(b + h, y0)
      }
      ctx.arcTo(x1, y0, x1, y1, r)
      ctx.arcTo(x1, y1, x0, y1, r)
      if (tour.tailed && tour.tailDown) {
        ctx.lineTo(b + h, y1)
        ctx.lineTo(tour.tailTipX, tour.tailTipY)
        ctx.lineTo(b - h, y1)
      }
      ctx.arcTo(x0, y1, x0, y0, r)
      ctx.arcTo(x0, y0, x1, y0, r)
      ctx.closePath()
      ctx.fillStyle = Color.popups.background
      ctx.fill()
      ctx.lineJoin = "round"
      ctx.strokeStyle = Color.popups.border
      ctx.lineWidth = outline.edge
      ctx.stroke()
    }
  }

  Item {
    id: bubble
    visible: tour.running || tour.offering
    // The edge and the padding inside it, as Omarchy's popups have them.
    readonly property real inset: outline.edge + Style.spacing.popupPadding
    width: Math.min(Style.space(460), tour.width - 2 * tour.margin)
    height: tour.cardHeight
    readonly property real liveX: tour.liveSide === "offer" || tour.liveSide === "top"
      ? (tour.width - width) / 2
      : tour.target.width < width ? tour.cardXFor(tour.targetMiddle)
      : Math.max(tour.margin, Math.min(tour.width - tour.margin - width, tour.targetMiddle - width / 2))
    // Nothing while hidden: the shell's windows are still taking their sizes
    // as it starts, and following them then only reported a binding loop.
    readonly property real liveY: !bubble.visible ? 0 : tour.liveSide === "offer" ? Math.max(tour.margin, tour.keyboardTop + tour.keyboard.height
                                                     - tour.keyboard.visibleHeight - tour.arrowSize - tour.cardHeight)
      : tour.liveSide === "top" ? tour.service.barSize + tour.margin
      : tour.liveSide === "above" ? tour.target.y - tour.arrowSize - tour.cardHeight
      : tour.liveSide === "below" ? tour.target.y + tour.target.height + tour.arrowSize
      : tour.margin
    x: tour.pin ? tour.pin.x : liveX
    y: !tour.pin ? liveY : tour.pin.side === "above" ? tour.pin.bottom - tour.cardHeight : tour.pin.y
    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Column {
      id: content
      x: bubble.inset
      y: bubble.inset
      width: bubble.width - 2 * bubble.inset
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        visible: tour.running
        text: (tour.step + 1) + " of " + tour.steps.length
        color: Color.popups.text
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: tour.running ? tour.current.title : "New here?"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: !tour.running
          ? "A one-minute tour of the keyboard shows where things are and what holding a key does. It is in the controls, behind the gear, if you would rather later."
          : typeof tour.current.body === "function" ? tour.current.body() : tour.current.body
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: parent.width
        height: nextButton.implicitHeight

        Button {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          visible: !tour.running || tour.step < tour.steps.length - 1
          text: tour.running ? "Skip tour" : "No thanks"
          foreground: Color.popups.text
          onClicked: tour.running ? tour.service.endTour() : tour.service.declineTour()
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlGap

          Button {
            visible: tour.running && tour.step > 0
            text: "Back"
            bordered: true
            foreground: Color.popups.text
            onClicked: tour.go(tour.step - 1)
          }
          Button {
            id: nextButton
            text: !tour.running ? "Show me"
              : tour.step < tour.steps.length - 1 ? "Next" : "Done"
            bordered: true
            selected: true
            foreground: Color.popups.text
            onClicked: {
              if (!tour.running) tour.service.startTour()
              else if (tour.step < tour.steps.length - 1) tour.go(tour.step + 1)
              else tour.service.endTour()
            }
          }
        }
      }
    }
  }
}
