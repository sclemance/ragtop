import QtQuick

// The band above the keys that offers what a word could be: the kanji for
// some kana, the hanzi for some pinyin, and later whatever else fills it
// (Service.qml, suggestions). It only draws. Each suggestion is a key, thin
// and as long as its word, in Omarchy's default shape and Enter's style
// (keyKind): there is no panel behind the keyboard for plain words to sit
// on, and a key reads over any wallpaper. Which item a touch means is
// asked of it (cellAt), and the keyboard's own touch layer does the asking,
// the same as for every key, so a finger that comes down here and moves is a
// scroll and one that lifts where it landed is a choice.
Item {
  id: strip

  // Keyboard supplies its flat SupportingTheme, not the main cap theme.
  required property var theme
  // How the keyboard draws Enter, which the suggestions are drawn as.
  property string keyKind: "accent"
  // [{ text, note }]. The note is what kind of thing the text is, drawn
  // smaller after it: "カタカナ" beside a katakana spelling.
  property var items: []
  // The item the input method would take if asked now, -1 for none.
  property int cursor: -1
  property bool hasPrev: false
  property bool hasNext: false
  // How far the list is scrolled, owned by whoever handles the touches.
  property real scroll: 0
  // The cell under a finger: an item's index, prevCell, nextCell, or -1.
  property int pressedIndex: -1
  // Shown when there is nothing to choose: which input method is on, since
  // nothing else on the keyboard is as near the text being written.
  property string idleText: ""
  // How tall the strip's words are drawn for. A strip taller than this is a
  // bigger target, not bigger writing (Keyboard.qml, stripFraction).
  property real textHeight: height

  // Only the tour animates an entrance; ordinary candidate changes stay still.
  property real entranceProgress: 1
  opacity: entranceProgress
  transform: Translate { y: (1 - strip.entranceProgress) * strip.height * 0.4 }

  readonly property int prevCell: -2
  readonly property int nextCell: -3
  readonly property int scrollLeftCell: -4
  readonly property int scrollRightCell: -5
  readonly property real arrowWidth: Math.round(height * 1.1)
  // Between the input method's page arrows, when it has them.
  readonly property real spanLeft: hasPrev ? arrowWidth : 0
  readonly property real spanWidth: width - spanLeft - (hasNext ? arrowWidth : 0)
  // More words than fit: a chevron at each end says which way there is more,
  // ‹ while the list can scroll left and › while it can scroll right. Their
  // room is kept at both ends for as long as the list overflows, so the
  // words do not shift as one comes and goes. A tap on one scrolls.
  readonly property real chevronWidth: Math.round(height * 0.7)
  readonly property bool overflows: contentWidth > spanWidth
  readonly property bool canScrollLeft: overflows && scroll > 0.5
  readonly property bool canScrollRight: overflows && scroll < maxScroll - 0.5
  readonly property real listLeft: spanLeft + (overflows ? chevronWidth : 0)
  readonly property real listWidth: spanWidth - (overflows ? 2 * chevronWidth : 0)
  // Size words against a compact key's face, excluding its raised side.
  // More target height still buys touch room rather than larger lettering.
  readonly property real textFaceHeight: textHeight
    - Math.min(theme.keyDepth, textHeight * theme.maxDepthFraction)
  readonly property int textSize: Math.max(10, Math.round(textFaceHeight * 0.55))
  readonly property int noteSize: Math.max(9, Math.round(textSize * 0.55))
  readonly property real pad: Math.round(textHeight * 0.45)

  FontMetrics { id: textMetrics; font.family: strip.theme.fontFamily; font.pixelSize: strip.textSize }
  FontMetrics { id: noteMetrics; font.family: strip.theme.fontFamily; font.pixelSize: strip.noteSize }

  // Each item's cell, left to right, as { x, width } within the list. As
  // wide as its text, and never narrower than it is tall, so a single
  // character is still something a finger can land on.
  // advanceWidth() is a method; reading its result alone does not track a
  // font change. Include both fonts so cells refit when theme/size changes.
  readonly property var cells: measureCells(textMetrics.font, noteMetrics.font)
  function measureCells(textFont, noteFont) {
    var out = []
    var x = 0
    for (var i = 0; i < strip.items.length; i++) {
      var item = strip.items[i]
      var w = textMetrics.advanceWidth(item.text)
      if (item.note) w += Math.round(strip.pad / 2) + noteMetrics.advanceWidth(item.note)
      w = Math.max(strip.height, Math.ceil(w) + 2 * strip.pad)
      out.push({ x: x, width: w })
      x += w
    }
    return out
  }
  readonly property real contentWidth: cells.length > 0
    ? cells[cells.length - 1].x + cells[cells.length - 1].width : 0
  readonly property real maxScroll: Math.max(0, contentWidth - listWidth)

  // A new list starts at its beginning.
  onItemsChanged: strip.scroll = 0

  // What a touch at x means.
  function cellAt(x) {
    if (strip.hasPrev && x < strip.arrowWidth) return strip.prevCell
    if (strip.hasNext && x >= strip.width - strip.arrowWidth) return strip.nextCell
    if (strip.overflows && x < strip.listLeft)
      return strip.canScrollLeft ? strip.scrollLeftCell : -1
    if (strip.overflows && x >= strip.listLeft + strip.listWidth)
      return strip.canScrollRight ? strip.scrollRightCell : -1
    var at = x - strip.listLeft + strip.scroll
    for (var i = 0; i < strip.cells.length; i++)
      if (at >= strip.cells[i].x && at < strip.cells[i].x + strip.cells[i].width) return i
    return -1
  }

  function scrollTo(value) { strip.scroll = Math.max(0, Math.min(strip.maxScroll, value)) }
  // A chevron's tap: most of a strip's width that way, a word or so kept.
  function scrollBy(direction) { strip.scrollTo(strip.scroll + direction * strip.listWidth * 0.8) }

  Text {
    // Never rich text: see KeyboardKey.qml.
    textFormat: Text.PlainText
    visible: strip.items.length === 0
    anchors.fill: parent
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: strip.idleText
    color: strip.theme.specialText
    font.family: strip.theme.fontFamily
    font.pixelSize: strip.noteSize + 2
    elide: Text.ElideRight
  }

  Item {
    x: strip.listLeft
    width: strip.listWidth
    height: strip.height
    clip: true

    Repeater {
      model: strip.items

      Item {
        required property int index
        required property var modelData
        readonly property var cell: strip.cells[index] || { x: 0, width: 0 }
        readonly property bool chosen: index === strip.cursor
        x: cell.x - strip.scroll
        width: cell.width
        height: strip.height

        KeyboardKey {
          id: candidateKey
          x: Math.round(strip.theme.gap / 2)
          width: parent.width - strip.theme.gap
          height: parent.height
          theme: strip.theme
          label: ""
          // The one the input method would take is filled, as a card's
          // chosen cell is.
          kind: parent.chosen ? "locked" : strip.keyKind
          pressed: strip.pressedIndex === index
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          y: candidateKey.faceY + (candidateKey.faceHeight - height) / 2
          spacing: Math.round(strip.pad / 2)

          Text {
            textFormat: Text.PlainText
            text: modelData.text
            color: strip.theme.strongContrast ? candidateKey.labelColor
              : parent.parent.chosen ? strip.theme.accentText
              : strip.keyKind === "accent" ? strip.theme.accent : strip.theme.text
            font.family: strip.theme.fontFamily
            font.pixelSize: strip.textSize
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            textFormat: Text.PlainText
            visible: !!modelData.note
            text: modelData.note || ""
            color: strip.theme.strongContrast ? candidateKey.labelColor : strip.theme.specialText
            font.family: strip.theme.fontFamily
            font.pixelSize: strip.noteSize
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }

  Repeater {
    model: [{ shown: strip.canScrollLeft, cell: strip.scrollLeftCell, glyph: "‹",
              x: strip.spanLeft },
            { shown: strip.canScrollRight, cell: strip.scrollRightCell, glyph: "›",
              x: strip.spanLeft + strip.spanWidth - strip.chevronWidth }]

    // On a key's fill, outlined in the chevron's own colour, so it stands
    // out from the words beside it.
    Rectangle {
      required property var modelData
      visible: modelData.shown
      x: modelData.x + Math.round(strip.theme.gap / 2)
      width: strip.chevronWidth - strip.theme.gap
      height: strip.height
      radius: strip.theme.keyRadius
      color: strip.pressedIndex === modelData.cell ? strip.theme.pressedKey : strip.theme.key
      border.color: strip.theme.accent
      border.width: Math.max(1, strip.theme.keyBorderWidth)

      Text {
        textFormat: Text.PlainText
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: parent.modelData.glyph
        color: strip.theme.strongContrast
          ? strip.theme.readableText(strip.theme.accent, parent.color) : strip.theme.accent
        font.family: strip.theme.fontFamily
        font.pixelSize: Math.round(strip.textSize * 1.3)
        font.bold: true
      }
    }
  }

  // The input method's own pages, where it has them. Pinyin sends its whole
  // list at once and has none; that one scrolls.
  Repeater {
    model: [{ shown: strip.hasPrev, cell: strip.prevCell, glyph: "‹" },
            { shown: strip.hasNext, cell: strip.nextCell, glyph: "›" }]

    KeyboardKey {
      required property var modelData
      visible: modelData.shown
      x: (modelData.cell === strip.prevCell ? 0 : strip.width - strip.arrowWidth) + Math.round(strip.theme.gap / 2)
      width: strip.arrowWidth - strip.theme.gap
      height: strip.height
      theme: strip.theme
      label: modelData.glyph
      labelKind: "word"
      kind: strip.keyKind
      pressed: strip.pressedIndex === modelData.cell
    }
  }
}
