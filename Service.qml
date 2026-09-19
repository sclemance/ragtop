import QtQuick
import Quickshell.Io

// Headless singleton: the shell creates one of these per session, whereas the
// bar widget is created once per monitor. Owning the daemons here means there
// is exactly one rotation daemon for the lock to stop.
Item {
  id: root

  property string tabletSwitchDevice: "/dev/input/by-path/platform-PNP0C14:07-event"
  property bool rotationLocked: false
  property bool tabletMode: false
  property bool oskVisible: false

  readonly property string oskDest: "sm.puri.OSK0"
  readonly property string oskPath: "/sm/puri/OSK0"

  function configure(device, locked) {
    if (device) root.tabletSwitchDevice = device
    root.rotationLocked = locked
    configureFallback.stop()
    // Locking just means "stop the rotation daemon", which freezes the
    // display at whatever orientation it's currently in.
    rotationProc.running = !locked
  }

  // False until the first switch reading, so "laptop mode" can be told
  // apart from "not polled yet".
  property bool tabletModeKnown: false

  function applySwitchReading(tablet) {
    var first = !root.tabletModeKnown
    root.tabletModeKnown = true
    if (tablet === root.tabletMode && !first) return
    root.tabletMode = tablet
    // The keyboard toggle is hidden outside tablet mode, so the keyboard
    // must be put away here. The first reading counts too: the shell may
    // (re)start while already in laptop mode with the keyboard up.
    if (!tablet) root.setOskVisible(false)
  }

  function toggleOsk() {
    setOskVisible(!root.oskVisible)
  }

  function setOskVisible(visible) {
    oskToggleProc.command = [
      "gdbus", "call", "--session",
      "--dest", root.oskDest,
      "--object-path", root.oskPath,
      "--method", root.oskDest + ".SetVisible",
      visible ? "true" : "false"
    ]
    oskToggleProc.running = true
  }

  // Rotation waits for a widget to report the saved lock state, so a saved
  // lock isn't briefly overridden at startup; unlocked if none reports in.
  Timer {
    id: configureFallback
    interval: 2000
    running: true
    onTriggered: rotationProc.running = !root.rotationLocked
  }

  Process {
    id: rotationProc
    command: ["iio-hyprland"]
    onExited: if (!root.rotationLocked) rotationRestart.start()
  }
  Timer {
    id: rotationRestart
    interval: 3000
    onTriggered: if (!root.rotationLocked) rotationProc.running = true
  }

  Process {
    id: oskProc
    command: ["squeekboard"]
    onExited: oskRestart.start()
  }
  Timer { id: oskRestart; interval: 3000; onTriggered: oskProc.running = true }

  Component.onCompleted: oskProc.running = true

  Process { id: oskToggleProc }

  // Poll the hardware tablet-mode switch (Lenovo Yoga WMI SW_TABLET_MODE).
  Process {
    id: tabletModeProc
    command: ["evtest", "--query", root.tabletSwitchDevice, "EV_SW", "SW_TABLET_MODE"]
    onExited: function(exitCode) { root.applySwitchReading(exitCode === 10) }
  }
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!tabletModeProc.running) tabletModeProc.running = true
  }

  // Poll squeekboard's current visibility to keep the icon/tooltip in sync.
  Process {
    id: oskVisProc
    command: [
      "gdbus", "call", "--session",
      "--dest", root.oskDest,
      "--object-path", root.oskPath,
      "--method", "org.freedesktop.DBus.Properties.Get",
      root.oskDest, "Visible"
    ]
    stdout: StdioCollector {
      onStreamFinished: root.oskVisible = text.indexOf("true") !== -1
    }
  }
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!oskVisProc.running) oskVisProc.running = true
  }
}
