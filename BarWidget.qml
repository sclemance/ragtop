import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.ragtop"

  property var service: null
  // The service keeps this, in Ragtop's own settings, so the button here and
  // the controls on the keyboard are the same switch rather than two copies.
  readonly property string rotationMode: root.service ? root.service.rotationMode : "auto"
  readonly property bool rotationLocked: root.service ? root.service.rotationLocked : false
  readonly property string tabletSwitchDevice: String(root.setting("tabletSwitchDevice", ""))
  readonly property bool tabletMode: root.service ? root.service.tabletMode : false
  // A machine with no switch to read never reports laptop, and Automatic must
  // not take silence for one: a slate would sit frozen and never turn.
  readonly property bool tabletModeKnown: root.service ? root.service.tabletModeKnown : false
  property bool shortcutsOpen: false

  // PopupCard calls its owner's close() when tapped outside.
  function close() { root.shortcutsOpen = false }
  onTabletModeChanged: if (!root.tabletMode) root.close()

  // Always there. Rotation follows the sensor whether or not the machine is
  // in tablet mode, so a screen can start turning while it is still a laptop,
  // and the one control that stops it should not be somewhere you have to
  // reach tablet mode to find.
  visible: true
  implicitWidth: grid.implicitWidth
  implicitHeight: grid.implicitHeight

  function pushConfig() {
    if (root.service) root.service.configure(root.tabletSwitchDevice)
  }
  onServiceChanged: {
    pushConfig()
    pushBarTransparent()
    // The keyboard's tools page has a rotation lock key. The lock is kept
    // here, so the keyboard asks and this answers.
  }

  // The bar keeps `transparent` live on the object it hands widgets.
  readonly property bool barTransparent: root.bar ? root.bar.transparent === true : false
  onBarTransparentChanged: pushBarTransparent()
  function pushBarTransparent() {
    if (root.service) root.service.barTransparent = root.barTransparent
  }
  onTabletSwitchDeviceChanged: pushConfig()

  // Persisted inline on this widget's shell.json entry, the same way the
  // built-in clock saves its format; the shell only writes when it changed.
  // Automatic, then locked, then unlocked, then round again.
  function cycleRotationMode() {
    if (!root.service) return
    var order = root.service.rotationModes
    root.service.setRotationMode(order[(order.indexOf(root.rotationMode) + 1) % order.length])
  }

  // What stood here forced the lock off on unfolding, because a lock was
  // never wanted in laptop mode and the button could not be reached there to
  // undo one. Automatic says that properly now, and the button is always
  // reachable, so a lock that is asked for is a lock that is kept.
  //
  // What also stood here wrote the mode onto this widget's own bar entry.
  // Ragtop's settings file is where it belongs: a bar without this widget on
  // it left the keyboard's controls and the IPC with nothing to write to.

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
