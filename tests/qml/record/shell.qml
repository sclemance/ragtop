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
      ["full", "word", "none"].forEach(function(mode) {
        t.ok(test.typed(mode, []).sentenceStart, mode + ": a fresh field starts a sentence")
        t.ok(!test.typed(mode, ["type Hello"]).sentenceStart, mode + ": inside a word is no sentence start")
        t.ok(test.typed(mode, ["type Hello", "type .", "key space"]).sentenceStart,
             mode + ": after a full stop and a space a sentence starts")
        t.ok(!test.typed(mode, ["type Hello", "type ,", "key space"]).sentenceStart,
             mode + ": after a comma it does not")
        t.ok(test.typed(mode, ["type Hello", "key Return"]).sentenceStart, mode + ": a new line starts one")
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
