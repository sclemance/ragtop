import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.fliparchy"

  property bool tabletMode: false
  property bool oskVisible: false
  property bool rotationLocked: false
  property string tabletSwitchDevice: "/dev/input/by-path/platform-PNP0C14:07-event"

  readonly property string oskDest: "sm.puri.OSK0"
  readonly property string oskPath: "/sm/puri/OSK0"

  visible: root.tabletMode
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

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

  function toggleRotationLock() {
    root.rotationLocked = !root.rotationLocked
    // Locking just means "stop restarting the rotation daemon", which
    // freezes the display at whatever orientation it's currently in.
    rotationProc.running = !root.rotationLocked
    writeConfig()
  }

  function loadConfig() {
    configReadProc.running = true
  }

  // Atomic write: render to a temp file then rename it over the target.
  // A crash or power loss mid-write can then never leave a truncated or
  // corrupt config, and we never touch the user's Hyprland config or any
  // other plugin's files -- everything lives under ~/.config/fliparchy.
  function writeConfig() {
    const payload = JSON.stringify({
      rotationLocked: root.rotationLocked,
      tabletSwitchDevice: root.tabletSwitchDevice
    }, null, 2)
    configWriteProc.command = [
      "sh", "-c",
      'mkdir -p "$HOME/.config/fliparchy" && tmp="$HOME/.config/fliparchy/config.json.tmp.$$" && printf "%s" "$1" > "$tmp" && mv -f "$tmp" "$HOME/.config/fliparchy/config.json"',
      "--", payload
    ]
    configWriteProc.running = true
  }

  Process { id: configWriteProc }

  // Read our own config file (creating its directory if needed) before
  // starting any daemons, so a previously-locked rotation state and any
  // device-path override are respected from the first frame.
  Process {
    id: configReadProc
    command: ["sh", "-c", "mkdir -p \"$HOME/.config/fliparchy\" && cat \"$HOME/.config/fliparchy/config.json\" 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        let parsed = {}
        try { parsed = JSON.parse(text) } catch (e) { parsed = {} }
        if (typeof parsed.rotationLocked === "boolean") root.rotationLocked = parsed.rotationLocked
        if (typeof parsed.tabletSwitchDevice === "string" && parsed.tabletSwitchDevice.length > 0)
          root.tabletSwitchDevice = parsed.tabletSwitchDevice

        oskProc.running = true
        if (!root.rotationLocked) rotationProc.running = true
        tabletModeProc.running = true
      }
    }
  }

  // Keep the rotation daemon alive for the whole shell session, unless the
  // user has locked orientation -- then we hold it stopped instead of
  // restarting it, freezing the display where it is.
  Process {
    id: rotationProc
    command: ["iio-hyprland"]
    onExited: if (!root.rotationLocked) rotationRestart.start()
  }
  Timer { id: rotationRestart; interval: 3000; onTriggered: rotationProc.running = true }

  // Keep the on-screen keyboard daemon alive for the whole shell session.
  Process {
    id: oskProc
    command: ["squeekboard"]
    onExited: oskRestart.start()
  }
  Timer { id: oskRestart; interval: 3000; onTriggered: oskProc.running = true }

  Component.onCompleted: loadConfig()

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

  Row {
    id: row
    anchors.fill: parent
    spacing: 4

    BarIconButton {
      id: oskButton
      bar: root.bar
      text: root.oskVisible ? "󰌌" : "󰌈"
      tooltipText: root.oskVisible ? "Hide on-screen keyboard" : "Show on-screen keyboard"
      active: root.oskVisible
      onPressed: root.toggleOsk()
    }

    BarIconButton {
      id: lockButton
      bar: root.bar
      text: root.rotationLocked ? "" : ""
      tooltipText: root.rotationLocked ? "Unlock rotation" : "Lock rotation"
      active: root.rotationLocked
      onPressed: root.toggleRotationLock()
    }
  }
}
