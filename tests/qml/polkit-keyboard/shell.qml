import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root
  Harness { id: t }
  TestCase { id: input; name: "PolkitKeyboard"; when: false; optional: true }
  Sender { id: sender }
  property Window stage: Window {
    width: 1366; height: 768; visible: true
    Gate { id: gate; anchors.fill: parent }
    TextInput { id: other; text: "other application" }
  }
  function keys(item) {
    var found = []
    for (var child of item.children) {
      if (child.modelData !== undefined && child.labelColor !== undefined) found.push(child)
      found = found.concat(keys(child))
    }
    return found
  }
  function tap(name) {
    var board = gate.keyboard
    var key = keys(board).filter(function(k) { return k.modelData === name })[0]
    var point = key.mapToItem(board, key.width / 2, key.height / 2)
    var touch = input.touchEvent(board)
    touch.press(0, board, point.x, point.y).commit()
    touch.release(0, board, point.x, point.y).commit()
  }
  Component.onCompleted: t.run([
    [400, function() {
      t.equal(gate.askedFocus, WlrKeyboardFocus.Exclusive, "polkit keeps exclusive focus with keyboard enabled")
      t.equal(gate.exclusion, ExclusionMode.Ignore, "authentication surface keeps stock geometry")
      t.ok(!!gate.keyboard && gate.keyboard.typing, "embedded password keyboard is ready")
      other.forceActiveFocus()
      root.tap("q")
    }],
    [50, function() {
      t.equal(gate.password, "q", "real keyboard touch edits only the prompt")
      t.equal(other.text, "other application", "another focused item receives no password input")
      root.tap("backspace")
    }],
    [50, function() {
      t.equal(gate.password, "", "Backspace edits the prompt directly")
      gate.password = "test password"
      root.tap("enter")
    }],
    [50, function() {
      t.equal(gate.received, "test password", "Enter submits through the original polkit handler")
      t.equal(gate.requests, 1, "one authentication response submitted")
      t.equal(gate.password, "", "submission clears the prompt")
      t.ok(!gate.keyboard.typing, "authentication in progress disables the keyboard")
      gate.adapter.passwordTextEdited("blocked")
      gate.adapter.submitPassword("blocked")
      t.equal(gate.password, "", "adapter rejects edits while submitted")
      t.equal(gate.requests, 1, "adapter rejects repeated submission")
      sender.layerEvent("openlayer")
      t.ok(sender.passwordOpen, "polkit is tracked even without a cooperative clone")
      t.ok(!sender.keysShown, "authentication hides the desktop keyboard")
      sender.writeKeys("type secret\n")
      t.equal(sender.sent, "", "desktop sender blocks delayed authentication input")
      t.equal(sender.recorded, 0, "blocked desktop input is not recorded")
      sender.writeKeys("route wayland\n")
      t.equal(sender.sent, "route wayland\n", "input-method routing can settle without typing")
      sender.writeKeys("reload\ntype blocked\n")
      t.equal(sender.sent, "route wayland\n", "a control command cannot carry queued input through the guard")
      sender.sent = ""
      gate.submitted = false
      gate.responseRequired = false
      gate.adapter.passwordTextEdited("blocked")
      t.equal(gate.password, "", "no response request means no password editing")
      gate.responseRequired = true
      gate.closing = true
      gate.adapter.submitPassword("blocked")
      t.equal(gate.requests, 1, "closing prompt rejects input")
      gate.dialogVisible = false
    }],
    [50, function() {
      t.ok(!gate.keyboard, "closing authentication unloads the embedded keyboard")
      sender.layerEvent("closelayer")
      t.ok(!sender.passwordOpen && sender.keysShown, "closing polkit restores desktop keyboard visibility")
      sender.writeKeys("type normal\n")
      t.equal(sender.sent, "type normal\n", "desktop typing resumes outside authentication")
    }]
  ])
}
