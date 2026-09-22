import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.ragtop"

  property var service: null
  // Locked, unlocked or automatic. An entry written before there were three
  // states carries a plain flag, and a locked one becomes locked while the
  // rest become automatic, which is what that flag meant in practice.
  readonly property string rotationMode: {
    var saved = String(root.setting("rotationMode", ""))
    if (["locked", "unlocked", "auto"].indexOf(saved) !== -1) return saved
    return root.setting("rotationLocked", false) === true ? "locked" : "auto"
  }
  readonly property bool rotationLocked: root.rotationMode === "locked"
    || (root.rotationMode === "auto" && !root.tabletMode)
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
    if (root.service) root.service.configure(root.tabletSwitchDevice, root.rotationMode)
  }
  onServiceChanged: {
    pushConfig()
    pushBarTransparent()
    // The keyboard's tools page has a rotation lock key. The lock is kept
    // here, so the keyboard asks and this answers.
    if (root.service) root.service.rotationModeRequested.connect(root.setRotationMode)
  }

  // The bar keeps `transparent` live on the object it hands widgets.
  readonly property bool barTransparent: root.bar ? root.bar.transparent === true : false
  onBarTransparentChanged: pushBarTransparent()
  function pushBarTransparent() {
    if (root.service) root.service.barTransparent = root.barTransparent
  }
  onRotationModeChanged: pushConfig()
  onTabletSwitchDeviceChanged: pushConfig()

  // Persisted inline on this widget's shell.json entry, the same way the
  // built-in clock saves its format; the shell only writes when it changed.
  // Automatic, then locked, then unlocked, then round again.
  function cycleRotationMode() {
    var order = ["auto", "locked", "unlocked"]
    setRotationMode(order[(order.indexOf(root.rotationMode) + 1) % order.length])
  }

  // Idempotent, since every monitor's widget instance reacts to the same
  // tablet-mode exit.
  function setRotationMode(mode) {
    if (root.rotationMode === mode || ["locked", "unlocked", "auto"].indexOf(mode) === -1) return
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    delete entry.rotationLocked
    entry.rotationMode = mode
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // What stood here forced the lock off on unfolding, because a lock was
  // never wanted in laptop mode and the button could not be reached there to
  // undo one. Automatic says that properly now, and the button is always
  // reachable, so a lock that is asked for is a lock that is kept.

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
      tooltipText: root.rotationMode === "locked" ? "Screen rotation: locked"
        : root.rotationMode === "unlocked" ? "Screen rotation: unlocked"
        : "Screen rotation: automatic, follows tablet mode"
      active: root.rotationLocked
      onPressed: root.cycleRotationMode()
    }
  }

  ShortcutsPopup {
    anchorItem: shortcutsButton
    bar: root.bar
    owner: root
    open: root.shortcutsOpen
  }
}
