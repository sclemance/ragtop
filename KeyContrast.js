.pragma library

// Keep the key's opacity when a momentary control tint is applied. An
// outline has no face to preserve, so it still gains the tint on press.
function pressedFill(base, overlay) {
  if (base.a === 0) return overlay
  var tinted = Qt.tint(Qt.rgba(base.r, base.g, base.b, 1), overlay)
  return Qt.rgba(tinted.r, tinted.g, tinted.b, base.a)
}

function linear(value) {
  return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
}

function luminance(color) {
  return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
}

function ratio(a, b) {
  var x = luminance(a), y = luminance(b)
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

// Used only by the opt-in strong treatment. Keep the palette's preferred
// text whenever readable; otherwise choose an opaque dark or light label.
// The caller supplies the composited, opaque face behind the lettering.
function readableText(preferred, face) {
  if (ratio(Qt.tint(face, preferred), face) >= 4.5) return preferred
  var black = Qt.rgba(0, 0, 0, 1), white = Qt.rgba(1, 1, 1, 1)
  return ratio(black, face) >= ratio(white, face) ? black : white
}
