.pragma library
.import "KeyContrast.js" as Contrast

// Read only flat colour/mode declarations; never evaluate theme contents.
function parse(raw) {
  var values = {}
  String(raw || "").split("\n").forEach(function(line) {
    var m = line.match(/^\s*([a-zA-Z0-9_-]+)\s*=\s*["'](#[0-9a-fA-F]{6}|dark|light)["']\s*(?:#.*)?$/)
    if (m) values[m[1]] = m[2]
  })
  return values
}

function color(raw) {
  if (typeof raw !== "string" || !/^#[0-9a-fA-F]{6}$/.test(raw)) return null
  var n = parseInt(raw.slice(1), 16)
  return Qt.rgba((n >> 16) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255, 1)
}

function distance(a, b) {
  return Math.sqrt(Math.pow(a.r - b.r, 2) + Math.pow(a.g - b.g, 2) + Math.pow(a.b - b.b, 2))
}

function hue(c) {
  var high = Math.max(c.r, c.g, c.b), low = Math.min(c.r, c.g, c.b)
  var chroma = high - low
  if (chroma < 0.0001) return { angle: 0, chroma: 0 }
  var angle = high === c.r ? (c.g - c.b) / chroma
    : high === c.g ? (c.b - c.r) / chroma + 2 : (c.r - c.g) / chroma + 4
  return { angle: (angle * 60 + 360) % 360, chroma: chroma }
}

// Rank opposite hues after the legend's white tint, discounting near-neutral
// candidates. This visual heuristic is not an accessibility guarantee.
function separation(base, candidate) {
  var a = Qt.tint(base, Qt.rgba(1, 1, 1, 0.18))
  var b = Qt.tint(candidate, Qt.rgba(1, 1, 1, 0.18))
  var ah = hue(a), bh = hue(b)
  var delta = Math.abs(ah.angle - bh.angle)
  delta = Math.min(delta, 360 - delta)
  return delta / 180 * Math.min(ah.chroma / 0.12, 1)
    * Math.min(bh.chroma / 0.12, 1) + 0.25 * distance(a, b)
}

// Bright labels are not necessarily bright in every community palette.
// Keep a sufficiently bright colour exactly; otherwise lift its existing
// hue towards white. This runs on palette changes, never on animation frames.
function luminous(c, background, dark) {
  if (!dark) return c
  function enough(v) { return Contrast.luminance(v) >= 0.35 && Contrast.ratio(v, background) >= 3 }
  if (enough(c)) return c
  var low = 0, high = 1
  for (var i = 0; i < 10; i++) {
    var mid = (low + high) / 2
    if (enough(Qt.tint(c, Qt.rgba(1, 1, 1, mid)))) high = mid
    else low = mid
  }
  return Qt.tint(c, Qt.rgba(1, 1, 1, high))
}

// Trial floor for the neighbour wave on dark themes. Find the smallest
// white lift whose sampled transition stays above 0.18 relative luminance.
// Check the blend as well as its trough: different hues can darken midway.
// Runs once per palette/override change, never in a key's animation binding.
function waveWhiteMix(base, press, dark) {
  if (!dark) return 0
  var floor = Math.min(0.18, Contrast.luminance(base))
  function enough(whiteMix) {
    for (var i = 1; i <= 32; i++) {
      var amount = i / 32, brightness = 1 - 0.5 * amount
      var dim = Qt.rgba((base.r + (press.r - base.r) * amount) * brightness,
        (base.g + (press.g - base.g) * amount) * brightness,
        (base.b + (press.b - base.b) * amount) * brightness, 1)
      if (Contrast.luminance(Qt.tint(dim, Qt.rgba(1, 1, 1, whiteMix * amount))) < floor)
        return false
    }
    return true
  }
  if (enough(0)) return 0
  var low = 0, high = 1
  for (var step = 0; step < 10; step++) {
    var mid = (low + high) / 2
    if (enough(mid)) high = mid
    else low = mid
  }
  return high
}

function choose(palette, accent, foreground, background) {
  palette = palette || {}
  var dark = palette.mode === "dark" || (palette.mode !== "light"
    && Contrast.luminance(background) < Contrast.luminance(foreground))
  var families = ["red", "green", "yellow", "blue", "magenta", "cyan"]
  var ansi = [1, 2, 3, 4, 5, 6]
  function normal(i) { return color(palette[families[i]]) || color(palette["color" + ansi[i]]) }
  function bright(i) { return color(palette["bright_" + families[i]]) || color(palette["color" + (ansi[i] + 8)]) || normal(i) }
  var base = color(palette.accent) || accent
  var closest = -1, nearest = 0.20
  for (var i = 0; i < families.length; i++) {
    var candidate = normal(i)
    if (candidate && distance(base, candidate) < nearest) {
      nearest = distance(base, candidate)
      closest = i
    }
  }
  if (closest !== -1) base = bright(closest) || base
  base = luminous(base, background, dark)

  var candidates = families.map(function(_, i) { return bright(i) })
  candidates.push(color(palette.bright_orange) || color(palette.orange))
  var press = null, best = -1
  candidates.forEach(function(candidate) {
    if (!candidate) return
    candidate = luminous(candidate, background, dark)
    if (distance(base, candidate) < 0.12) return
    var score = separation(base, candidate)
    if (score > best) { best = score; press = candidate }
  })
  // Sparse/monochrome palettes may have no contrasting chromatic option.
  if (!press) {
    candidates = [color(palette.bright_foreground), color(palette.foreground),
      color(palette.color15), color(palette.color7)]
    candidates.forEach(function(candidate) {
      if (!candidate) return
      candidate = luminous(candidate, background, dark)
      var score = distance(base, candidate)
      if (score > best) { best = score; press = candidate }
    })
  }
  return { base: base, press: press || Qt.rgba(1, 1, 1, 1), dark: dark }
}
