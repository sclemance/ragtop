import QtQuick
import Quickshell
Scope {
  LayoutService { id: service }
  Chooser { id: chooser; service: service }
  Harness { id: test }
  function choose(index) {
    chooser.popup = {kind: "layouts", index: index}
    chooser.choosePopup()
  }
  Component.onCompleted: test.run([
    [0, function() { choose(1) }],
    [300, function() {
      test.equal(service.reloads, 1, "French refreshes without an activelayout event")
      test.equal(chooser.activeLayout, 0, "labels deliberately remain stale English")
      choose(0)
    }],
    [300, function() {
      test.equal(service.reloads, 2, "English selection works despite stale English labels")
      choose(1)
      choose(0)
    }],
    [500, function() {
      test.equal(service.reloads, 3, "rapid return is queued and final layout refreshed")
      test.equal(service.pendingLayout, -1, "queued selection drained")
      service.switchLayout(99)
    }],
    [300, function() {
      test.equal(service.reloads, 3, "failed switch does not claim a new layout")
      choose(-1)
      test.equal(service.reloads, 3, "cancelled chooser sends no switch")
      choose(2)
      test.equal(service.selectedEngine, "pinyin", "IME selection remains separate")
    }]
  ])
}
