.pragma library

// Called once on a visual press, never on an animation frame or key repeat.
// Distance is measured in key/row pitches so tall and wide layouts agree.
function spread(keys, origin, columnPitch, rowPitch) {
  if (!origin || columnPitch <= 0 || rowPitch <= 0) return
  var cx = origin.x + origin.width / 2, cy = origin.y + origin.height / 2
  for (var i = 0; i < keys.count; i++) {
    var key = keys.itemAt(i)
    if (!key || key === origin) continue
    var dx = (key.x + key.width / 2 - cx) / columnPitch
    var dy = (key.y + key.height / 2 - cy) / rowPitch
    var distance = Math.sqrt(dx * dx + dy * dy)
    if (distance <= 2.4) key.pulseGlow(distance)
  }
}
