import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "sclemance.ragtop"

  property var service: null
  // The service keeps this, in Ragtop's own settings, so the button here and
  // the controls on the keyboard are the same switch rather than two copies.
  readonly property string rotationMode: root.service ? root.service.rotationMode : "auto"
  readonly property bool rotationLocked: root.service ? root.service.rotationLocked : false
  // What the rotation button has to say, beyond which mode is set. Absent
  // hardware, a daemon that has stopped answering, and a package that was
  // never installed are three different things and only one of them is a
  // fault: see Service.qml's accelPresent.
  readonly property bool accelAbsent: root.service ? root.service.accelAbsent : false
  readonly property bool sensorStuck: root.service ? root.service.sensorStuck : false
  readonly property bool probesSettled: root.service ? root.service.probesSettled : false
  readonly property bool rotationAvailable: root.service ? root.service.rotationAvailable : true
  readonly property string keyboardMode: root.service ? root.service.keyboardMode : "sensor"
  readonly property bool keyboardAvailable: root.service ? root.service.keyboardAvailable : false
  readonly property string tabletSwitchDevice: String(root.setting("tabletSwitchDevice", ""))
  readonly property bool tabletMode: root.service ? root.service.tabletMode : false
  // A machine with no switch to read never reports laptop, and Automatic must
  // not take silence for one: a slate would sit frozen and never turn.
  readonly property bool tabletModeKnown: root.service ? root.service.tabletModeKnown : false

  // PopupCard calls its owner's close() when tapped outside.
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
    pushBarSize()
    // The keyboard's tools page has a rotation lock key. The lock is kept
    // here, so the keyboard asks and this answers.
  }

  // The bar keeps `transparent` live on the object it hands widgets.
  readonly property bool barTransparent: root.bar ? root.bar.transparent === true : false
  onBarTransparentChanged: pushBarTransparent()
  function pushBarTransparent() {
    if (root.service) root.service.barTransparent = root.barTransparent
  }

  // How thick the bar is, which only a widget can ask. The service needs it
  // to know how much screen is left above the keyboard for the controls
  // panel, and has no bar of its own to ask.
  onBarSizeChanged: pushBarSize()
  function pushBarSize() {
    if (root.service && root.barSize > 0) root.service.barSize = root.barSize
  }
  onTabletSwitchDeviceChanged: pushConfig()

  // Persisted inline on this widget's shell.json entry, the same way the
  // built-in clock saves its format. The shell only writes when it changed.
  // Automatic, then locked, then unlocked, then round again.
  function cycleRotationMode() {
    if (!root.service) return
    var order = root.service.rotationModes
    root.service.setRotationMode(order[(order.indexOf(root.rotationMode) + 1) % order.length])
  }

  // Sensor, then on, then off, then round again. Kept in Ragtop's settings by
  // the service, like the rotation mode, so this button and Setup › Tablet ›
  // Keyboard are one switch and not two.
  function cycleKeyboardMode() {
    if (!root.service) return
    var order = root.service.keyboardModes
    root.service.setKeyboardMode(order[(order.indexOf(root.keyboardMode) + 1) % order.length])
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
    // Three across, though only two of them are there in laptop mode: Grid
    // leaves out an invisible child rather than leaving a hole for it, so the
    // row closes up on its own.
    columns: root.vertical ? 1 : 3

    // All drawn by KeyIcon rather than set as a Nerd Font glyph, which is
    // what the keyboard's own keys use. That makes the button that opens
    // tiling mode the same mark as the key that opens it, so the bar and
    // the keyboard are visibly the same control, and it means neither one
    // depends on the bar's font carrying an icon at all.
    BarIconButton {
      id: shortcutsButton
      visible: root.tabletMode
      bar: root.bar
      tooltipText: "Tiling: move and resize windows"
      active: root.service !== null && root.service.tilingOpen
      iconComponent: Component {
        KeyIcon {
          name: "windows"
          color: shortcutsButton.active && shortcutsButton.useActiveColor
            ? shortcutsButton.activeColor : shortcutsButton.foreground
        }
      }
      onPressed: if (root.service) root.service.toggleTilingMode()
    }

    // Whether there is an on-screen keyboard on offer. Always here, like the
    // rotation button and for the same reason: the one control that turns the
    // keyboard on must not itself be somewhere you need the keyboard's mode to
    // reach. It cycles rather than toggles, because "follows the switch" is a
    // third answer and not the absence of one.
    //
    // What this shows is the setting, not whether a keyboard happens to be up.
    //
    // It used to light for keyboardAvailable, and `active` on a bar widget
    // means urgent in Omarchy: WidgetButton defaults activeColor to
    // bar.urgent, so "a keyboard exists right now" was painted the red a bar
    // keeps for things that want attention. A working keyboard is not an
    // alarm.
    //
    // It lights for the setting being overridden instead, in the accent, and
    // the two overrides are told apart by the icon rather than by the colour.
    // A bar has no hover on a touchscreen, so a tooltip cannot be the thing
    // that distinguishes them, which is what the comment here used to assume
    // and got wrong: off and "waiting for tablet mode" looked identical, and
    // the only way to find out which was to tap it.
    BarIconButton {
      id: keyboardButton
      bar: root.bar
      tooltipText: root.keyboardMode === "on" ? "Keyboard: always on"
        : root.keyboardMode === "off" ? "Keyboard: off"
        : "Keyboard: on in tablet mode, follows the switch"
      active: root.keyboardMode !== "sensor"
      activeColor: Color.accent
      iconComponent: Component {
        KeyIcon {
          name: root.keyboardMode === "off" ? "keyboard-off" : "keyboard"
          color: keyboardButton.active && keyboardButton.useActiveColor
            ? keyboardButton.activeColor : keyboardButton.foreground
        }
      }
      onPressed: root.cycleKeyboardMode()
    }

    // A padlock said whether rotation was held, which is the state, not the
    // thing. What this button is about is the screen turning, so it says
    // that. That also stops it reading as a screen lock, which is what a
    // padlock in a bar usually means.
    //
    // Gone entirely where the machine has no accelerometer. Two of the three
    // modes cannot do anything there, and a button that cycles three states
    // where one matters is worse than no button. Nothing is lost: Locked and
    // the two Rotate buttons stay in the controls panel, which is where you
    // want them anyway, since you watch the screen turn as you tap.
    //
    // It used to light `active` for rotationLocked with no activeColor, and
    // `active` on a bar widget means urgent in Omarchy: WidgetButton defaults
    // activeColor to bar.urgent. rotationLocked is also true for Automatic in
    // laptop mode, so the default setting on a laptop with the lid open, the
    // commonest state Ragtop is ever in, painted the attention colour. This
    // is the same mistake the keyboard button had, left on the button beside
    // it.
    //
    // So: the accent for a mode you chose, the slash for rotation that is not
    // going to happen, and the urgent colour for exactly one thing, an
    // accelerometer that is there and has stopped answering. Absence is never
    // an alarm. A missing package is not one either, because without it
    // Ragtop cannot ask whether there is hardware and will not assert what it
    // has not established.
    BarIconButton {
      id: rotationButton
      visible: !(root.accelAbsent && root.probesSettled)
      bar: root.bar
      tooltipText: root.sensorStuck ? "Screen rotation: the sensor has stopped answering"
        : !root.rotationAvailable ? "Screen rotation: needs iio-sensor-proxy to follow the device"
        : root.rotationMode === "locked" ? "Screen rotation: locked, turn it by hand from the controls"
        : root.rotationMode === "unlocked" ? "Screen rotation: unlocked, always follows the sensor"
        : "Screen rotation: automatic, follows tablet mode"
      // Urgent only for the fault. The accent for a mode other than the
      // default, which is what it means on the keyboard button too.
      active: root.sensorStuck || root.rotationMode !== "auto"
      activeColor: root.sensorStuck
        ? (root.bar ? root.bar.urgent : Color.urgent) : Color.accent
      iconComponent: Component {
        KeyIcon {
          name: rotationButton.held ? "rotate-off" : "rotate"
          color: rotationButton.active && rotationButton.useActiveColor
            ? rotationButton.activeColor : rotationButton.foreground
        }
      }
      // Rotation that is not going to happen, whether you held it or it broke.
      readonly property bool held: root.sensorStuck || root.rotationMode === "locked"
      onPressed: root.cycleRotationMode()
    }
  }
}
