import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.tablet-mode"

  property bool tabletMode: false
  property bool oskVisible: false

  readonly property string tabletSwitchDevice: "/dev/input/by-path/platform-PNP0C14:07-event"
  readonly property string oskDest: "sm.puri.OSK0"
  readonly property string oskPath: "/sm/puri/OSK0"

  visible: root.tabletMode
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleOsk() {
    oskToggleProc.command = [
      "gdbus", "call", "--session",
      "--dest", root.oskDest,
      "--object-path", root.oskPath,
      "--method", root.oskDest + ".SetVisible",
      root.oskVisible ? "false" : "true"
    ]
    oskToggleProc.running = true
  }

  // Keep the rotation daemon alive for the whole shell session.
  Process {
    id: rotationProc
    command: ["iio-hyprland"]
    onExited: rotationRestart.start()
  }
  Timer { id: rotationRestart; interval: 3000; onTriggered: rotationProc.running = true }

  // Keep the on-screen keyboard daemon alive for the whole shell session.
  Process {
    id: oskProc
    command: ["squeekboard"]
    onExited: oskRestart.start()
  }
  Timer { id: oskRestart; interval: 3000; onTriggered: oskProc.running = true }

  Component.onCompleted: {
    rotationProc.running = true
    oskProc.running = true
  }

  Process { id: oskToggleProc }

  // Poll the hardware tablet-mode switch (Lenovo Yoga WMI SW_TABLET_MODE).
  Process {
    id: tabletModeProc
    command: ["evtest", "--query", root.tabletSwitchDevice, "EV_SW", "SW_TABLET_MODE"]
    onExited: function(exitCode) { root.tabletMode = (exitCode === 10) }
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.oskVisible ? "󰌌" : "󰌈"
    tooltipText: root.oskVisible ? "Hide on-screen keyboard" : "Show on-screen keyboard"
    active: root.oskVisible
    onPressed: root.toggleOsk()
  }
}
