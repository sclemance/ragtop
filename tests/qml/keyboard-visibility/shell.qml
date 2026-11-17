import QtQuick
import QtQuick.Window
import QtTest
import Quickshell

ShellRoot {
  id: root
  Harness { id: t }
  TestCase { id: input; name: "KeyboardVisibility"; when: false; optional: true }
  property Window stage: Window {
    width: 200; height: 200; visible: true
    KeyboardInput { id: keyboard }
  }
  property var sequence: null
  property int hiddenCount: 0
  property int reopenedCount: 0

  Component.onCompleted: {
    var steps = []
    ;["left", "delete"].forEach(function(key) {
      ;[false, true].forEach(function(alreadyRepeating) {
        var label = key + (alreadyRepeating ? " repeating" : " waiting to repeat")
        steps.push([200, function() {
          keyboard.selectedKey = key
          keyboard.service.sent = []
          root.sequence = input.touchEvent(keyboard)
          root.sequence.press(0, keyboard, 50, 50).commit()
        }])
        steps.push([alreadyRepeating ? 800 : 40, function() {
          t.equal(keyboard.service.sent[0], "key " + keyboard.keysyms[key], label + " sends the initial key")
          t.ok(alreadyRepeating ? keyboard.service.sent.length > 1 : keyboard.service.sent.length === 1,
            label + " reaches the expected repeat phase")
          t.ok(keyboard.repeatRunning, label + " starts the real repeat timer")
          keyboard.keysShown = false
        }])
        steps.push([250, function() {
          t.equal(keyboard.opacity, 0, label + " finishes fading")
          t.ok(keyboard.visible, label + " keeps the keyboard item visible")
          t.ok(!keyboard.enabled, label + " disables input after fading")
          t.equal(Object.keys(keyboard.held).length, 0, label + " cancels the held touch")
          t.equal(keyboard.repeating, "", label + " clears the repeat command")
          t.ok(!keyboard.repeatRunning, label + " stops the repeat timer")
          root.hiddenCount = keyboard.service.sent.length
        }])
        steps.push([750, function() {
          t.equal(keyboard.service.sent.length, root.hiddenCount, label + " sends no keys while hidden")
          root.sequence.release(0, keyboard, 50, 50).commit()
          keyboard.keysShown = true
        }])
        steps.push([250, function() {
          t.equal(keyboard.opacity, 1, label + " reopens fully")
          t.ok(keyboard.enabled, label + " accepts input after reopening")
          root.reopenedCount = keyboard.service.sent.length
          root.sequence = input.touchEvent(keyboard)
          root.sequence.press(0, keyboard, 50, 50).commit()
        }])
        steps.push([40, function() {
          root.sequence.release(0, keyboard, 50, 50).commit()
        }])
        steps.push([750, function() {
          t.equal(keyboard.service.sent.length, root.reopenedCount + 1, label + " types one fresh tap after reopening")
          t.equal(Object.keys(keyboard.held).length, 0, label + " releases the fresh touch")
          t.ok(!keyboard.repeatRunning, label + " leaves no repeat timer after the fresh tap")
        }])
      })
    })
    t.run(steps)
  }
}
