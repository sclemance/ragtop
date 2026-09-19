import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.fliparchy"

  property var service: null
  readonly property bool rotationLocked: root.setting("rotationLocked", false) === true
  readonly property string tabletSwitchDevice: String(root.setting("tabletSwitchDevice", ""))
  readonly property bool tabletMode: root.service ? root.service.tabletMode : false
  readonly property bool oskVisible: root.service ? root.service.oskVisible : false

  // Stay visible while locked, even outside tablet mode, so a rotation that
  // was locked in portrait can always be unlocked from the bar.
  visible: root.tabletMode || root.rotationLocked
  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight

  function pushConfig() {
    if (root.service) root.service.configure(root.tabletSwitchDevice, root.rotationLocked)
  }
  onServiceChanged: pushConfig()
  onRotationLockedChanged: pushConfig()
  onTabletSwitchDeviceChanged: pushConfig()

  // Persisted inline on this widget's shell.json entry, the same way the
  // built-in clock saves its format; the shell only writes when it changed.
  function toggleRotationLock() {
    setRotationLocked(!root.rotationLocked)
  }

  // Idempotent, since every monitor's widget instance reacts to the same
  // tablet-mode exit.
  function setRotationLocked(locked) {
    if (root.rotationLocked === locked) return
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.rotationLocked = locked
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // A lock is never wanted in laptop mode. State-based rather than an event,
  // so it also holds when the widget attaches after the switch was read;
  // requires a real reading so a missing service doesn't count as laptop.
  readonly property bool laptopModeConfirmed: root.service !== null
    && root.service.tabletModeKnown && !root.service.tabletMode
  onLaptopModeConfirmedChanged: if (root.laptopModeConfirmed) root.setRotationLocked(false)

  // The service may be created after this widget, so retry until it exists.
  Timer {
    interval: 500
    repeat: true
    triggeredOnStart: true
    running: root.service === null
    onTriggered: {
      if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
        root.service = root.bar.shell.serviceFor(root.moduleName)
    }
  }

  Grid {
    id: grid
    columns: root.vertical ? 1 : 2

    BarIconButton {
      visible: root.tabletMode
      bar: root.bar
      text: "󰌌"
      tooltipText: root.oskVisible ? "Hide on-screen keyboard" : "Show on-screen keyboard"
      onPressed: if (root.service) root.service.toggleOsk()
    }

    BarIconButton {
      bar: root.bar
      text: root.rotationLocked ? "" : ""
      tooltipText: root.rotationLocked ? "Unlock rotation" : "Lock rotation"
      active: root.rotationLocked
      onPressed: root.toggleRotationLock()
    }
  }
}
