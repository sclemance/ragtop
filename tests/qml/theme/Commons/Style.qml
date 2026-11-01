pragma Singleton
import QtQuick
// Default shell metrics, deliberately independent of the installed shell.
QtObject {
  property int cornerRadius: 0
  property var spacing: ({ sm: 4, md: 6, lg: 8, xl: 10 })
  property var font: ({ family: "monospace", body: 12, bodySmall: 11, title: 14,
    heading: 16, display: 24, displayLarge: 28, iconSmall: 11, iconLarge: 18 })
  function space(n) { return Math.round(n) }
  function normalFillFor(t, a, u) { return Util.alpha(t, 0.04) }
  function pressedFillFor(t, a, u) { return Util.alpha(t, 0.22) }
  function selectedFillFor(t, a, u) { return Util.alpha(a, 0.18) }
}
