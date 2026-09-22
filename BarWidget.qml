import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.ragtop"

  property var service: null
  readonly property bool rotationLocked: root.setting("rotationLocked", false) === true
  readonly property string tabletSwitchDevice: String(root.setting("tabletSwitchDevice", ""))
  readonly property bool tabletMode: root.service ? root.service.tabletMode : false
  property bool shortcutsOpen: false

  // PopupCard calls its owner's close() when tapped outside.
  function close() { root.shortcutsOpen = false }
  onTabletModeChanged: if (!root.tabletMode) root.close()

  // Always there. Rotation follows the sensor whether or not the machine is
  // folded, so a screen can start turning with the keyboard attached, and the
  // one control that stops it should not be somewhere you have to fold the
  // machine to reach.
  visible: true
  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight

  function pushConfig() {
    if (root.service) root.service.configure(root.tabletSwitchDevice, root.rotationLocked)
  }
  onServiceChanged: {
    pushConfig()
    pushBarTransparent()
    // The keyboard's tools page has a rotation lock key. The lock is kept
    // here, so the keyboard asks and this answers.
    if (root.service) root.service.rotationLockRequested.connect(root.setRotationLocked)
  }

  // The bar keeps `transparent` live on the object it hands widgets.
  readonly property bool barTransparent: root.bar ? root.bar.transparent === true : false
  onBarTransparentChanged: pushBarTransparent()
  function pushBarTransparent() {
    if (root.service) root.service.barTransparent = root.barTransparent
  }
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
      id: shortcutsButton
      visible: root.tabletMode
      bar: root.bar
      text: ""
      tooltipText: "Window shortcuts"
      active: root.shortcutsOpen
      onPressed: root.shortcutsOpen = !root.shortcutsOpen
    }

    BarIconButton {
      bar: root.bar
      text: root.rotationLocked ? "" : ""
      tooltipText: root.rotationLocked ? "Unlock rotation" : "Lock rotation"
      active: root.rotationLocked
      onPressed: root.toggleRotationLock()
    }
  }

  ShortcutsPopup {
    anchorItem: shortcutsButton
    bar: root.bar
    owner: root
    open: root.shortcutsOpen
  }
}
