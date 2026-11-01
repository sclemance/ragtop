import QtQuick
import Quickshell
Scope {
  Preferences { id: service }
  Harness { id: test }
  Component.onCompleted: test.run([
    [0, function() {
      service.toggleAutoShow(); service.toggleAutoShow()
      service.setKeyboardLayout("60"); service.setKeyboardLayout("75")
      service.setKeyboardMode("sensor")
      service.queuePreference(["keyboard", "cycle"])
      service.queuePreference(["keyboard", "cycle"])
      service.queuePreference(["rotation", "cycle"])
      service.queuePreference(["rotation", "cycle"])
      service.stepTheme(1); service.stepTheme(1)
      service.queuePreference(["invalid-command"])
      service.setKeyboardLayout("80")
      service.setDisplay("invalid-screen")
      test.equal(service.displayPreview, "", "unknown display is rejected")
      service.setDisplay("HDMI-A-1")
      test.equal(service.displaySetting, "HDMI-A-1", "display changes during preview")
      test.equal(service.settings.display, "auto", "preview does not persist")
      service.displaySeconds = 1
    }],
    [3500, function() {
      test.equal(service.preferenceQueue.length, 0, "rapid preference requests all drained")
      test.equal(service.preferenceBusy, false, "queue finishes after invalid command")
      test.equal(service.preferenceFailed, true, "failed write stays visible")
      test.equal(service.displaySetting, "auto", "timeout restores previous display")
      service.setDisplay("HDMI-A-1"); service.revertDisplay()
      test.equal(service.displayPreview, "", "manual revert cancels preview")
      service.setDisplay("HDMI-A-1"); service.keepDisplay()
      service.revertDisplay()
      test.equal(service.displaySaving, "HDMI-A-1", "cannot revert a committed selection mid-write")
    }],
    [600, function() {
      test.equal(service.settings.display, "HDMI-A-1", "confirmed display survives watcher delay")
      test.equal(service.displayPreview, "", "confirmation clears preview")
      test.equal(service.displaySaving, "", "confirmation finishes")
    }]
  ])
}
