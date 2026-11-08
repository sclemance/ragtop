.pragma library

// What Ragtop knows of the text before the cursor, from what it typed
// itself: Service.qml's typedTail, kept here as plain functions so that what
// each typing-memory setting holds can be tested on its own
// (tests/typed-record-test.sh).
//
// A record is { tail, cursor, fromStart, sentenceStart }: the text, where in
// it the cursor is, whether it reaches back to the start of the field, and
// whether the next letter starts a sentence.
//
// How much of it is text depends on the setting (Setup › Tablet › Typing
// Memory):
//
//   full   the text itself, up to MOST characters, for as long as the field
//          has focus. Deleting whole words names them, BackSpace into a word
//          brings it back, and the next word is chosen by the one before.
//   word   the word being typed, and nothing that was typed before it.
//   none   no typed text at all.
//
// In word and none, what came before the word is kept only as what kind of
// thing it was: WORD for any word, "." for the end of a sentence, "," for
// other punctuation, a hyphen, a space or a new line, "~" for any other
// mark, and only the last KINDS of those. That is enough to know a sentence
// starts, that two spaces follow a word, or that a hyphen follows one,
// which is what capitals, double-space full stops and hyphen joins ask, and
// it holds not a letter of what was written. Anything that cannot be
// followed from kinds alone, a BackSpace past the word or a cursor moved,
// makes the record unknown, as a shortcut does in full.

var MOST = 400
var KINDS = 3
// Stands for a whole word that is not kept. Not a letter, so nothing that
// looks for words in the record finds one in it.
var WORD = "\u0001"

function isWordChar(c) {
  return c === WORD || c.toLowerCase() !== c.toUpperCase() || (c >= "0" && c <= "9")
}

// A character as BackSpace counts one: a code point. An emoji past U+FFFF
// is two UTF-16 units here, a surrogate pair, which is never cut in two.
// The arrows and Delete go by grapheme instead, in Qt as in most toolkits:
// e and a combining accent, or an emoji and its skin tone, are one step.
// Where that could differ from a code point (atJoin: anywhere not surely
// between two graphemes), the record does not guess and becomes unknown.
function isHigh(u) { return u >= 0xd800 && u <= 0xdbff }
function isLow(u) { return u >= 0xdc00 && u <= 0xdfff }
function paired(t, i) { return i > 0 && isLow(t.charCodeAt(i)) && isHigh(t.charCodeAt(i - 1)) }
// Whether offset i is surely between two graphemes, as a text field's arrows
// and Delete see them. Only claimed between characters known never to join
// anything: printable ASCII, Latin, Greek and Cyrillic letters (precomposed,
// no combining marks), common punctuation and symbols, and a lone emoji
// beside one of those. Anything else, any script with marks or jamo, any
// variation selector, joiner or flag, and the record lets go rather than
// guess (Codex found Hebrew, Arabic, Devanagari, Hangul and more behaving
// so in a Qt field).
function plain(u) {
  return (u >= 0x20 && u <= 0x7e) || u === 0x0a || u === 0x09
    || (u >= 0xa0 && u <= 0x2ff) || (u >= 0x370 && u <= 0x482) || (u >= 0x48a && u <= 0x52f)
    || (u >= 0x2010 && u <= 0x2027) || (u >= 0x2030 && u <= 0x205e)
    || (u >= 0x20a0 && u <= 0x20c0) || (u >= 0x2100 && u <= 0x21ff)
}
// A single emoji, which needs no other code point to be whole: not a skin
// tone (1F3FB-1F3FF), which joins the one before, nor a regional indicator,
// two of which make a flag.
function lone(u) {
  return (u >= 0x1f300 && u <= 0x1f3fa) || (u >= 0x1f400 && u <= 0x1f64f)
    || (u >= 0x1f680 && u <= 0x1f6ff) || (u >= 0x1f900 && u <= 0x1f9ff) || (u >= 0x1fa70 && u <= 0x1faff)
}
function cpBefore(t, i) { return paired(t, i - 1) ? t.codePointAt(i - 2) : t.charCodeAt(i - 1) }
function between(t, i) {
  if (i <= 0 || i >= t.length) return true
  var a = cpBefore(t, i), b = t.codePointAt(i)
  return (plain(a) && plain(b)) || (lone(a) && plain(b)) || (plain(a) && lone(b))
}
function atJoin(t, i) { return !between(t, i) }
// How many units the character before c, or at c, takes.
function stepBack(t, c) { return c >= 2 && paired(t, c - 1) ? 2 : 1 }
function stepForward(t, c) { return c + 1 < t.length && paired(t, c + 1) ? 2 : 1 }
// How many characters s is, so how many BackSpaces take it back.
function codePoints(s) {
  var n = 0
  for (var i = 0; i < s.length; i++) if (!paired(s, i)) n++
  return n
}
// The last n units of t, or one fewer where that would split a pair.
function lastUnits(t, n) {
  var cut = Math.max(0, t.length - n)
  if (cut > 0 && paired(t, cut)) cut++
  return t.slice(cut)
}

function isLetter(c) {
  return c !== WORD && (c === "'" || c.toLowerCase() !== c.toUpperCase() || (c >= "0" && c <= "9"))
}

function empty(fromStart) {
  return { tail: "", cursor: 0, fromStart: !!fromStart, sentenceStart: !!fromStart }
}

function kindOf(c) {
  if (isWordChar(c)) return WORD
  if (c === "." || c === "!" || c === "?") return "."
  if (c === "," || c === ";" || c === ":") return ","
  if (c === "-" || c === " " || c === "\n") return c
  return "~"
}

// The text as kinds, a run of letters one WORD.
function kinds(text) {
  var out = ""
  for (var i = 0; i < text.length; i++) {
    var k = kindOf(text[i])
    if (k === WORD && out[out.length - 1] === WORD) continue
    out += k
  }
  return out
}

// What a record in `mode` may hold of `text`, the cursor at its end:
// { tail, cut }, cut when anything was let go.
function keep(text, mode) {
  if (mode === "full") {
    if (text.length <= MOST) return { tail: text, cut: false }
    return { tail: lastUnits(text, MOST), cut: true }
  }
  var w = text.length
  if (mode === "word") while (w > 0 && isLetter(text[w - 1])) w--
  var before = kinds(text.slice(0, w))
  var word = text.slice(w)
  if (word !== "" && before[before.length - 1] === WORD) before = before.slice(0, -1)
  var cut = before.length > KINDS
  if (cut) before = before.slice(before.length - KINDS)
  return { tail: before + word, cut: cut || w > 0 }
}

// The record after one command as sent to the keyboard helper, or null for
// one that types nothing (up, hold, release, route). atPrompt: Enter at a
// shell's prompt runs the line and the next starts empty.
function note(record, line, mode, atPrompt) {
  if (line === "") return null
  var space = line.indexOf(" ")
  var cmd = space < 0 ? line : line.slice(0, space)
  var arg = space < 0 ? "" : line.slice(space + 1)
  var t = record.tail
  var c = Math.min(record.cursor, t.length)
  var fromStart = record.fromStart
  var lean = mode !== "full"
  // A named key's modifiers follow it: Shift+Return is a new line still,
  // and only Ctrl, Alt or Super make it a shortcut, which could do anything.
  var parts = arg.split(" ")
  var keysym = parts[0]
  var shortcut = parts.slice(1).some(function(m) { return m !== "shift" })
  var named = (cmd === "key" || cmd === "down") && !shortcut
  var lineStart = t.lastIndexOf("\n", c - 1) + 1
  var unknown = false
  function insert(text) {
    t = t.slice(0, c) + text + t.slice(c)
    c += text.length
  }
  if (cmd === "type") insert(arg)
  else if (named && keysym === "space") insert(" ")
  else if (named && keysym === "Return") {
    if (atPrompt) { t = "\n"; c = 1 } else insert("\n")
  } else if (named && keysym === "BackSpace") {
    // Kinds cannot be taken back a letter at a time: only the word being
    // typed, which word keeps as it is.
    if (lean && !(mode === "word" && c > 0 && isLetter(t[c - 1]))) unknown = true
    else if (c > 0) { var b = stepBack(t, c); t = t.slice(0, c - b) + t.slice(c); c -= b }
    else unknown = !fromStart
  } else if (named && (keysym === "Delete" || keysym === "Left" || keysym === "Right"
                       || keysym === "Home" || keysym === "End") && lean) {
    unknown = true
  } else if (named && keysym === "Delete") {
    if (c < t.length) {
      var f = stepForward(t, c)
      if (atJoin(t, c) || atJoin(t, c + f)) unknown = true
      else t = t.slice(0, c) + t.slice(c + f)
    }
  } else if (named && keysym === "Left") {
    if (c > 0) {
      c -= stepBack(t, c)
      if (atJoin(t, c)) unknown = true
    } else unknown = !fromStart
  } else if (named && keysym === "Right") {
    if (c < t.length) {
      c += stepForward(t, c)
      if (atJoin(t, c)) unknown = true
    }
  } else if (named && keysym === "Home") {
    if (lineStart === 0 && !fromStart) unknown = true
    else c = lineStart
  } else if (named && keysym === "End") {
    var next = t.indexOf("\n", c)
    c = next < 0 ? t.length : next
  } else if (cmd === "key" || cmd === "down") unknown = true   // ↑ ↓, Tab, a shortcut
  else return null                                             // up, hold, release, route
  if (unknown) return empty(false)
  var before = t.slice(0, c)
  // Spanish opens a question or an exclamation with ¿ or ¡, and the word
  // after it still starts the sentence: "¿Qué?".
  var lead = before.replace(/[¡¿]+$/, "")
  var sentenceStart = lead === "" ? fromStart : /([.!?] |\n)$/.test(lead)
  if (lean) {
    // The cursor is always at the end here: everything that moves it made
    // the record unknown above.
    var kept = keep(t, mode)
    t = kept.tail
    c = t.length
    if (kept.cut) fromStart = false
  } else if (t.length > MOST) {
    var kept = lastUnits(t, MOST)
    var cut = t.length - kept.length
    t = kept
    c = Math.max(0, c - cut)
    fromStart = false
  }
  return { tail: t, cursor: c, fromStart: fromStart, sentenceStart: sentenceStart }
}
