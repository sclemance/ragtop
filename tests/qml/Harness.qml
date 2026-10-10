import QtQuick
import Quickshell

// Runs a test written as timed steps and reports each check on a line of its
// own, which lib.sh's run_qml picks out of quickshell's log. Steps rather
// than one function because nearly everything under test settles a moment
// later: a timer runs out, a watched file is noticed.
Scope {
  id: harness

  property var steps: []
  property int at: 0

  function ok(condition, what) {
    console.log("TEST " + (condition ? "ok" : "not ok") + " - " + what)
  }

  function equal(got, want, what) {
    harness.ok(got === want, got === want ? what
      : what + " (expected " + JSON.stringify(want) + ", got " + JSON.stringify(got) + ")")
  }

  // run([[ms, function], ...]): each function runs ms after the one before it.
  function run(list) {
    harness.steps = list
    harness.at = 0
    harness.advance()
  }

  function advance() {
    if (harness.at >= harness.steps.length) {
      console.log("TEST done")
      Qt.quit()
      return
    }
    clock.interval = harness.steps[harness.at][0]
    clock.start()
  }

  Timer {
    id: clock
    onTriggered: {
      var step = harness.steps[harness.at][1]
      harness.at++
      try {
        step()
      } catch (e) {
        harness.ok(false, "step " + harness.at + " threw: " + e)
      }
      harness.advance()
    }
  }
}
