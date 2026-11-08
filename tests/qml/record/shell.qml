import QtQuick
import Quickshell
import "typed-record.js" as Record

// typed-record.js: what each typing-memory setting keeps of what is typed.
// "word" and "none" must never hold a letter of a word that is finished, nor
// "none" a letter at all, while capitals and double-space full stops still
// know where a sentence starts.
ShellRoot {
  id: test

  Harness { id: t }

  // The record after typing `lines` from the start of a field.
  function typed(mode, lines) {
    var r = Record.empty(true)
    lines.forEach(function(line) {
      var next = Record.note(r, line, mode, false)
      if (next !== null) r = next
    })
    return r
  }
  function letters(text) {
    return text.split("").filter(function(c) { return c.toLowerCase() !== c.toUpperCase() }).join("")
  }

  readonly property var sentence: ["type Hello", "key space", "type world", "type .", "key space", "type Sec"]

  Component.onCompleted: t.run([
    [0, function() {
      var r = test.typed("full", test.sentence)
      t.equal(r.tail, "Hello world. Sec", "full keeps the text")
      t.equal(r.cursor, r.tail.length, "full keeps the cursor at its end")
    }],
    [0, function() {
      var r = test.typed("word", test.sentence)
      t.equal(test.letters(r.tail), "Sec", "word keeps the word being typed and no letter before it")
      t.ok(r.tail.indexOf("Hello") < 0 && r.tail.indexOf("world") < 0, "word keeps no finished word")
      var after = test.typed("word", test.sentence.concat(["key space"]))
      t.equal(test.letters(after.tail), "", "word lets the word go at the space after it")
    }],
    [0, function() {
      var r = test.typed("none", test.sentence)
      t.equal(test.letters(r.tail), "", "none keeps no letter at all")
      t.ok(r.tail.length <= Record.KINDS, "none keeps no more than a few kinds of thing")
      for (var i = 1; i <= test.sentence.length; i++)
        if (test.letters(test.typed("none", test.sentence.slice(0, i)).tail) !== "")
          t.ok(false, "none held a letter after " + i + " commands")
    }],
    [0, function() {
      // An emoji past U+FFFF is one character to the application, two UTF-16
      // units here: BackSpace, the arrows and the length cut never split it.
      var r = test.typed("full", ["type keep 😀 ", "key BackSpace", "key BackSpace"])
      t.equal(r.tail, "keep ", "two BackSpaces take the space and the whole emoji")
      r = test.typed("full", ["type a😀b", "key Left", "key Left", "key BackSpace"])
      t.equal(r.tail, "😀b", "Left steps over the emoji, and BackSpace takes the a")
      r = test.typed("full", ["type a😀b", "key Home", "key Right", "key Delete"])
      t.equal(r.tail, "ab", "Delete takes the whole emoji")
      var long = ""
      for (var i = 0; i < 300; i++) long += "😀"
      r = test.typed("full", ["type " + long])
      t.ok(!/^[\udc00-\udfff]/.test(r.tail), "the length cut never leaves half an emoji at the start")
      t.equal(Record.codePoints("x😀y"), 3, "x😀y is three characters to BackSpace")
      long = "x"
      for (var j = 0; j < 300; j++) long += "😀"
      r = test.typed("full", ["type " + long])
      t.ok(!/^[\udc00-\udfff]/.test(r.tail), "nor at an odd offset")
      // A grapheme of more than one code point: the arrows and Delete cross
      // it whole in a real text field, so the record lets go rather than
      // guess. BackSpace takes the accent alone, as the field does.
      r = test.typed("full", ["type ae\u0301b", "key Left", "key Left"])
      t.ok(r.tail === "" && !r.fromStart, "Left into e and its accent: the record lets go")
      r = test.typed("full", ["type ae\u0301b", "key Left", "key Delete"])
      t.ok(r.tail === "" && !r.fromStart, "Left to just after an accent lets go too: no guessing next to one")
      r = test.typed("full", ["type a👍🏽", "key Left"])
      t.ok(r.tail === "" && !r.fromStart, "Left into an emoji and its skin tone: lets go")
      r = test.typed("full", ["type a👍🏽b", "key Home", "key Right", "key Delete"])
      t.ok(r.tail === "" && !r.fromStart, "Delete of an emoji with a skin tone: lets go")
      // Marks and scripts beyond the plain ones: Hebrew sheva, Arabic
      // shadda, a Devanagari vowel sign, Hangul jamo, a variation selector
      // after a Han character. None is guessed at.
      ;["ae\u05b0b", "ae\u0651b", "a\u0915\u093fb", "a\u1100\u1161b", "a\u6f22\udb40\udd00b"].forEach(function(s, k) {
        var q = test.typed("full", ["type " + s, "key Left", "key Left"])
        t.ok(q.tail === "" && !q.fromStart, "case " + k + ": Left into an unsure grapheme lets go")
      })
      r = test.typed("full", ["type héllo wörld", "key Left", "key Left", "key Delete"])
      t.equal(r.tail, "héllo wörd", "Latin letters, accented or not, are still followed")
      r = test.typed("full", ["type a😀 b", "key Left", "key Left", "key Left", "key Delete"])
      t.equal(r.tail, "a b", "and a lone emoji beside them")
      r = test.typed("full", ["type ae\u0301", "key BackSpace"])
      t.equal(r.tail, "ae", "BackSpace takes the combining accent alone")
    }],
    [0, function() {
      ["full", "word", "none"].forEach(function(mode) {
        t.ok(test.typed(mode, []).sentenceStart, mode + ": a fresh field starts a sentence")
        t.ok(!test.typed(mode, ["type Hello"]).sentenceStart, mode + ": inside a word is no sentence start")
        t.ok(test.typed(mode, ["type Hello", "type .", "key space"]).sentenceStart,
             mode + ": after a full stop and a space a sentence starts")
        t.ok(!test.typed(mode, ["type Hello", "type ,", "key space"]).sentenceStart,
             mode + ": after a comma it does not")
        t.ok(test.typed(mode, ["type Hello", "key Return"]).sentenceStart, mode + ": a new line starts one")
        t.ok(test.typed(mode, ["type ¿"]).sentenceStart, mode + ": an opening ¿ keeps the sentence start")
        t.ok(test.typed(mode, ["type Hola", "type .", "key space", "type ¡"]).sentenceStart,
             mode + ": so does ¡ after a full stop")
        t.ok(!test.typed(mode, ["type Hola", "key space", "type ¿"]).sentenceStart,
             mode + ": but not mid-sentence")
      })
    }],
    [0, function() {
      // Double-space full stops ask whether a word and then a space came last.
      ["word", "none"].forEach(function(mode) {
        var tail = test.typed(mode, ["type Hello", "key space"]).tail
        t.ok(tail.length >= 2 && Record.isWordChar(tail[tail.length - 2]) && tail[tail.length - 1] === " ",
             mode + ": a word then a space is still known")
      })
    }],
    [0, function() {
      var r = test.typed("word", ["type Hel", "key BackSpace"])
      t.equal(r.tail, "He", "word: BackSpace takes a letter back from the word being typed")
      var past = test.typed("word", ["type Hello", "key space", "key BackSpace"])
      t.ok(past.tail === "" && !past.fromStart && !past.sentenceStart,
           "word: BackSpace past the word makes the record unknown")
      var none = test.typed("none", ["type Hel", "key BackSpace"])
      t.ok(none.tail === "" && !none.sentenceStart, "none: any BackSpace makes the record unknown")
      var moved = test.typed("word", ["type Hello", "key Left"])
      t.ok(moved.tail === "" && !moved.sentenceStart, "word: a cursor moved makes the record unknown")
    }],
    [0, function() {
      var long = []
      for (var i = 0; i < 200; i++) long.push("type ab ")
      t.equal(test.typed("full", long).tail.length, Record.MOST, "full keeps at most MOST characters")
      t.ok(test.typed("none", long).tail.length <= Record.KINDS, "none stays a few kinds long however much is typed")
    }],
    [0, function() {
      t.equal(Record.note(Record.empty(true), "up BackSpace", "full", false), null, "a release types nothing")
      var shortcut = test.typed("full", ["type Hello", "key c ctrl"])
      t.ok(shortcut.tail === "" && !shortcut.fromStart, "a shortcut makes the record unknown")
    }],
  ])
}
