import QtQuick
import Quickshell

// The suggestion strip's hit testing: which item a touch at a given x
// means, with the input method's page arrows at the ends and the list
// scrolled, and whether cell widths follow changes to the text's font.
ShellRoot {
  id: test

  Harness { id: t }

  // Only what the strip reads from the keyboard's theme.
  QtObject {
    id: fakeTheme
    property string fontFamily: "monospace"
    property real gap: 4
    property real keyRadius: 4
    property color pressedKey: "gray"
    property color specialKey: "darkgray"
    property color accent: "blue"
    property color text: "black"
    property color specialText: "gray"
    property color outline: "gray"
    property color key: "white"
    property real keyBorderWidth: 1
    property real keyDepth: 0
    property real maxDepthFraction: 0.25
    property real pressSink: 0.6
  }

  property SuggestionStrip strip: SuggestionStrip {
    theme: fakeTheme
    width: 800
    height: 40
  }

  readonly property var few: [{ text: "日本語", note: "" }, { text: "ニホンゴ", note: "カタカナ" },
                              { text: "にほんご", note: "ひらがな" }]
  function many() {
    var out = []
    for (var i = 0; i < 40; i++) out.push({ text: "候補" + i, note: "" })
    return out
  }
  function middleOf(i) { return test.strip.cells[i].x + test.strip.cells[i].width / 2 }
  property real flatCellWidth: 0
  property int compactTextSize: 0

  Component.onCompleted: t.run([
    [0, function() {
      test.strip.items = test.few
      var c = test.strip.cells
      t.equal(c.length, 3, "a cell for each item")
      t.equal(c[0].x, 0, "the first cell starts the list")
      t.ok(c[1].x === c[0].x + c[0].width && c[2].x === c[1].x + c[1].width, "cells sit edge to edge")
      t.ok(c.every(function(e) { return e.width >= test.strip.height }), "no cell narrower than it is tall")
      t.ok(c[1].width > c[0].width, "a note widens its cell")
    }],
    [0, function() {
      t.equal(test.strip.cellAt(test.middleOf(0)), 0, "a touch on the first item means it")
      t.equal(test.strip.cellAt(test.middleOf(2)), 2, "a touch on the last item means it")
      t.ok(test.strip.contentWidth < test.strip.width, "three items leave room after them")
      t.equal(test.strip.cellAt(test.strip.width - 1), -1, "a touch past the last item means nothing")
    }],
    [0, function() {
      test.strip.hasPrev = true
      test.strip.hasNext = true
      t.equal(test.strip.cellAt(1), test.strip.prevCell, "the left end is the previous page")
      t.equal(test.strip.cellAt(test.strip.width - 1), test.strip.nextCell, "the right end is the next page")
      t.equal(test.strip.cellAt(test.strip.arrowWidth + test.middleOf(0)), 0,
              "items start after the previous page's arrow")
      test.strip.hasPrev = false
      test.strip.hasNext = false
    }],
    [0, function() {
      test.strip.items = test.many()
      t.ok(test.strip.maxScroll > 0, "a long list can scroll")
      test.strip.scrollTo(1e6)
      t.equal(test.strip.scroll, test.strip.maxScroll, "scrolling stops at the end of the list")
      t.equal(test.strip.cellAt(test.strip.listLeft + test.strip.listWidth - 1), 39,
              "scrolled to the end, the list's right edge is the last item")
      test.strip.scrollTo(-50)
      t.equal(test.strip.scroll, 0, "scrolling stops at the start")
      test.strip.scrollTo(test.strip.cells[10].x)
      t.equal(test.strip.cellAt(test.strip.listLeft + 1), 10, "scrolled, a touch means what is under it now")
    }],
    // Chevrons: which way there is more, and a tap that way scrolls.
    [0, function() {
      test.strip.scrollTo(0)
      t.ok(test.strip.overflows, "a long list overflows")
      t.ok(!test.strip.canScrollLeft && test.strip.canScrollRight, "at the start, only ›")
      t.equal(test.strip.cellAt(test.strip.width - 1), test.strip.scrollRightCell, "the right end is ›")
      t.equal(test.strip.cellAt(1), -1, "no ‹ at the start, so the left end means nothing")
      test.strip.scrollBy(1)
      t.ok(test.strip.scroll > 0, "a tap on › scrolls right")
      t.ok(test.strip.canScrollLeft && test.strip.canScrollRight, "in the middle, both")
      t.equal(test.strip.cellAt(1), test.strip.scrollLeftCell, "the left end is ‹")
      test.strip.scrollTo(1e6)
      t.ok(test.strip.canScrollLeft && !test.strip.canScrollRight, "at the end, only ‹")
      test.strip.scrollTo(test.strip.maxScroll - 1)
      t.equal(test.strip.listLeft, test.strip.spanLeft + test.strip.chevronWidth,
              "the chevrons' room stays while the list overflows, so the words do not shift")
    }],
    [0, function() {
      test.strip.items = test.few
      t.equal(test.strip.scroll, 0, "a new list starts at its beginning")
      t.ok(!test.strip.overflows, "three items fit, so no chevrons")
      test.strip.items = []
      t.equal(test.strip.cellAt(10), -1, "with nothing to choose, nothing is chosen")
    }],
    [0, function() {
      test.strip.height = 30
      test.strip.textHeight = 30
      test.strip.items = [{ text: "suggestions", note: "" }]
    }],
    [0, function() {
      test.flatCellWidth = test.strip.cells[0].width
      fakeTheme.keyDepth = 8
    }],
    [0, function() {
      t.ok(test.strip.cells[0].width < test.flatCellWidth,
           "same word refits when raised relief reduces the font, without changing items or padding")
      test.compactTextSize = test.strip.textSize
      test.strip.height = 60
    }],
    [0, function() {
      t.equal(test.strip.textSize, test.compactTextSize,
              "a taller touch target keeps the compact lettering")
      fakeTheme.keyDepth = 0
    }],
    [0, function() {
      t.equal(test.strip.cells[0].width, test.flatCellWidth,
              "same word regains its width when switching back to a flat theme")
      t.equal(test.strip.opacity, 1, "ordinary strip is fully visible")
      test.strip.entranceProgress = 0.5
      t.equal(test.strip.opacity, 0.5, "tour entrance fades the actual strip")
      t.equal(test.strip.mapToItem(null, 0, 0).y, test.strip.height * 0.2,
              "tour entrance translates content without moving its logical slot")
      t.equal(test.strip.y, 0, "strip slot stays fixed during entrance")
      test.strip.entranceProgress = 1
      t.equal(test.strip.mapToItem(null, 0, 0).y, 0, "settled strip returns to its slot")
    }]
  ])
}
