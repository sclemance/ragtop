import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Singleton: the shell creates one of these per session, whereas the
// bar widget is created once per monitor. Owning the daemons here means there
// is exactly one orientation watcher for the lock to stop.
Item {
  id: root

  // Override from the widget's settings. Blank means auto-detect.
  property string tabletSwitchDevice: ""
  property string detectedSwitchDevice: ""
  readonly property string switchDevice: root.tabletSwitchDevice !== "" ? root.tabletSwitchDevice : root.detectedSwitchDevice
  // Locked, unlocked, or automatic, which means rotate while in tablet mode
  // and hold still in laptop mode. A machine whose switch is
  // never found is not a laptop, it is unknown, and Automatic rotates there
  // rather than freezing a slate that has no switch to report with. Automatic is what the old
  // pair of states was reaching for when it force unlocked on unfolding: a
  // screen that turns in your hands but not while it is sat on a desk.
  readonly property string rotationMode: ["locked", "unlocked", "auto"]
    .indexOf(root.settings["rotation"]) !== -1 ? root.settings["rotation"] : "auto"
  readonly property bool rotationLocked: root.rotationMode === "locked"
    || (root.rotationMode === "auto" && root.tabletModeKnown && !root.tabletMode)
  property bool tabletMode: false
  property bool oskVisible: false

  function configure(device) {
    root.tabletSwitchDevice = device || ""
    configureFallback.stop()
    root.applyRotationLock()
  }

  // Locking just means "stop watching the orientation", which freezes the
  // display at whatever orientation it is in. Automatic reaches this too,
  // every time the machine is folded or unfolded.
  function applyRotationLock() {
    if (root.rotationLocked) {
      orientationSettle.stop()
      lockRecheck.stop()
      rotationRestart.stop()
      // Killing monitor-sensor while its claim is still in flight is what
      // leaves iio-sensor-proxy unable to answer the next one. If the claim
      // has not landed yet, let it run. Nothing it reports is applied while
      // rotation is locked, and it is stopped the moment the claim lands.
      if (!rotationProc.running || root.sensorClaimed) rotationProc.running = false
    } else {
      root.wantSensor()
    }
  }
  onRotationLockedChanged: root.applyRotationLock()

  // False until tablet mode is first decided, so "laptop mode" can be told
  // apart from "not decided yet".
  property bool tabletModeKnown: false

  // The hinge's switch, as last read, and only followed in "auto".
  property bool switchTablet: false
  property bool switchKnown: false

  function applySwitchReading(tablet) {
    root.switchTablet = tablet
    root.switchKnown = true
    root.updateTabletMode()
  }

  // Tablet mode is the switch, or fixed on or off by the "tablet-mode"
  // setting (Setup › Tablet › Tablet Mode), for convertibles without a
  // usable switch or for touch controls in laptop mode.
  readonly property string tabletModeSetting:
    ["on", "off"].indexOf(root.settings["tablet-mode"]) !== -1 ? root.settings["tablet-mode"] : "auto"
  onTabletModeSettingChanged: updateTabletMode()

  function updateTabletMode() {
    // Waits for the settings, so a fixed mode isn't briefly overridden by
    // the switch at startup.
    if (!root.settingsLoaded) return
    if (root.tabletModeSetting === "auto") {
      if (root.switchKnown) applyTabletMode(root.switchTablet)
    } else {
      applyTabletMode(root.tabletModeSetting === "on")
    }
  }

  function applyTabletMode(tablet) {
    var first = !root.tabletModeKnown
    root.tabletModeKnown = true
    if (tablet === root.tabletMode && !first) return
    root.tabletMode = tablet
    // Read by the patched overlay clones (overlay-clones.sh) to pick their
    // focus mode.
    modeWriteProc.command = [
      "sh", "-c",
      'd="${XDG_RUNTIME_DIR:-}" && [ -n "$d" ] && printf "%s\\n" "$1" > "$d/ragtop-mode.tmp" && mv -f "$d/ragtop-mode.tmp" "$d/ragtop-mode"',
      "--", tablet ? "tablet" : "laptop"
    ]
    modeWriteProc.running = true
    // The keyboard's handle is hidden where the keyboard is not available, so
    // the keyboard has to be put away with it. That used to happen here on
    // every drop out of tablet mode. It is onKeyboardAvailableChanged's job
    // now, because whether laptop mode is reason enough depends on the
    // keyboard's own setting. The first reading is covered too: the shell may
    // (re)start in laptop mode, and setOskVisible refuses to raise it.
    if (!tablet && !root.keyboardAvailable) root.setOskVisible(false)
  }

  // Which keyboard the on-screen keyboard draws, from the
  // "keyboard-layout" setting.
  //
  //   auto   the widest board that fits the screen, which is what it does
  //          unless told otherwise, and what makes a fold into portrait
  //          change the keyboard rather than shrink it
  //   60     a real keyboard's five rows, no function row and no arrows
  //   mobile the three letter rows and the symbol pages
  //
  // Auto weighs both width and height. A named one is taken at its word on
  // height and still gives way on width, because a board too wide for the
  // screen cannot be drawn at all. Keyboard.qml does the choosing, since the
  // shapes and what they cost are its to know.
  // One list, so the controls panel and anything else offering a choice
  // cannot drift apart from what the setting accepts. Automatic at the head,
  // then the boards from the simplest to the fullest, which is the order
  // somebody reads them in rather than the order the fallback walks them.
  // Every monitor, for the controls panel, with Auto at the head. Only worth
  // offering where there is more than one, which is why the panel asks how
  // many there are before drawing the row.
  // What to call a monitor. DP-1 is the connector, not the screen, and on a
  // desk with two of them it says nothing about which is which.
  //
  // Hyprland reports make and model per monitor, and how useful they are
  // varies wildly. An external panel usually gives something a person would
  // recognise, LG or Samsung. A built-in one gives its panel vendor, which
  // this machine reports as "AU Optronics" with a model of "0x635C", and
  // nobody thinks of their laptop that way. So the built-in panel is called
  // what it is and the rest take their maker's name, with the connector kept
  // wherever the label would not be unique or there is nothing better.
  function monitorLabel(m) {
    if (/^(eDP|DSI|LVDS)-/.test(m.name)) return "Built-in"
    var make = String(m.make || "").trim().split(/\s+/)[0]
    // A maker that is blank, or a hex blob, is worse than the connector.
    if (!make || /^0x/i.test(make)) return m.name
    return make
  }
  readonly property var displayOptions: {
    var out = [{ value: "auto", label: "Auto-detect" }]
    var monitors = Hyprland.monitors.values
    var counts = {}
    monitors.forEach(function(m) {
      var l = root.monitorLabel(m)
      counts[l] = (counts[l] || 0) + 1
    })
    monitors.forEach(function(m) {
      var l = root.monitorLabel(m)
      // Two screens from the same maker need the connector to tell them
      // apart, and only then.
      out.push({ value: m.name, label: counts[l] > 1 ? l + " " + m.name : l })
    })
    return out
  }
  readonly property int monitorCount: Hyprland.monitors.values.length

  function setDisplay(name) {
    if (displayProc.running) return
    displayProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                           "display", "set", name]
    displayProc.running = true
  }
  Process { id: displayProc }

  readonly property var keyboardLayoutOptions: [
    { value: "auto", label: "Auto-select" },
    { value: "mobile", label: "Mobile" },
    { value: "60", label: "60%" },
    { value: "75", label: "75%" },
    { value: "80", label: "80%" }
  ]
  readonly property var keyboardLayouts:
    root.keyboardLayoutOptions.map(function(o) { return o.value })
  readonly property string keyboardLayout:
    root.keyboardLayouts.indexOf(root.settings["keyboard-layout"]) !== -1
      ? root.settings["keyboard-layout"] : "auto"
  function setKeyboardLayout(name) {
    if (root.keyboardLayouts.indexOf(name) === -1 || keyboardLayoutProc.running) return
    keyboardLayoutProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                                  "keyboard-layout", "set", name]
    keyboardLayoutProc.running = true
  }
  Process { id: keyboardLayoutProc }

  // Whether the on-screen keyboard is on offer at all: the "keyboard"
  // setting, cycled from the bar button and Setup › Tablet › Keyboard.
  //
  //   sensor  follow the tablet-mode switch, which is what it has always done
  //   on      always, laptop mode included, for a machine whose switch says
  //           nothing or someone who wants touch keys at a desk
  //   off      never, for a machine with a keyboard attached for good
  //
  // Only the keyboard reads this. Tablet mode itself still decides tiling
  // mode, the overlay clones and whether rotation follows the sensor, because
  // turning the keys off is not the same as saying this is a laptop.
  readonly property var keyboardModes: ["sensor", "on", "off"]
  readonly property string keyboardMode:
    ["on", "off"].indexOf(root.settings["keyboard"]) !== -1 ? root.settings["keyboard"] : "sensor"
  readonly property bool keyboardAvailable: root.keyboardMode === "on"
    || (root.keyboardMode === "sensor" && root.tabletMode)
  // Turning it off puts away one that is already up.
  onKeyboardAvailableChanged: if (!root.keyboardAvailable) root.setOskVisible(false)

  function setKeyboardMode(mode) {
    if (root.keyboardModes.indexOf(mode) === -1 || keyboardModeProc.running) return
    keyboardModeProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                                "keyboard", "set", mode]
    keyboardModeProc.running = true
  }
  Process { id: keyboardModeProc }

  function toggleOsk() {
    setOskVisible(!root.oskVisible)
  }

  function setOskVisible(visible) {
    root.oskVisible = visible && root.keyboardAvailable
  }

  // A handle along the bottom edge in tablet mode: tap it to show or hide
  // the keyboard. It reserves its own space, so windows never sit under it.
  // Layers reserving the same edge stack in the order they appear, so a
  // bottom bar keeps the edge with the handle above it, and the keyboard
  // opens above the handle, leaving the handle where it was.
  readonly property int handleHeight: 24

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: handle
      required property var modelData
      screen: modelData
      // While a stock picker is up every touch reaches the picker, so a tap
      // on the handle would only throw it away. A cloned picker leaves the
      // handle usable, for filter typing.
      // Only on the screen the keyboard itself uses. One per screen is how
      // Variants works, and a handle on a monitor the keyboard will never
      // appear on is a switch wired to another room.
      visible: modelData === root.keyboardScreen
        && root.keyboardAvailable && root.layerRulesReady
        && (!root.pickerOpen || root.pickerPatched)
        && root.screensaverAddress === ""

      // The bar's, keyboard up or down: the handle is part of the screen's
      // frame, as the bar is, and the keyboard has no panel to match.
      readonly property color fill: root.barTransparent
        ? Qt.rgba(Color.bar.background.r, Color.bar.background.g, Color.bar.background.b, 0)
        : Color.bar.background
      readonly property color line: Color.bar.text

      WlrLayershell.namespace: "ragtop-keyboard-handle"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Auto
      anchors { bottom: true; left: true; right: true }
      // The bar says how much room it needs, since a narrow screen puts it
      // on two rows and a wide one does not.
      implicitHeight: root.tilingOpen ? tilingBar.neededHeight : root.handleHeight
      color: "transparent"

      Rectangle {
        anchors.fill: parent
        color: handle.fill
        Behavior on color { ColorAnimation { duration: 150 } }
      }

      // TapHandler rather than MouseArea: see ToolsPanel for why a tap
      // target reads touch instead of a mouse event synthesised from it.
      TapHandler {
        id: handleTap
        // Only a handle when it is a handle. While tiling, the bar's own
        // controls take the taps and a miss between them should do nothing
        // rather than drop you out of the mode.
        enabled: !root.tilingOpen
        onTapped: root.toggleOsk()
      }

      // While tiling, the strip is the controls.
      TilingBar {
        id: tilingBar
        anchors.fill: parent
        visible: root.tilingOpen
        service: root
      }

      // A wide ^ while the keyboard is hidden, a wide v while it's showing.
      Shape {
        id: chevron
        anchors.centerIn: parent
        visible: !root.tilingOpen
        width: 56
        height: 8
        opacity: handleTap.pressed ? 0.5 : 1
        preferredRendererType: Shape.CurveRenderer
        property color lineColor: handle.line
        Behavior on lineColor { ColorAnimation { duration: 150 } }

        ShapePath {
          strokeColor: chevron.lineColor
          strokeWidth: 2
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          startX: 0
          startY: root.oskVisible ? 0 : 8
          PathLine { x: 28; y: root.oskVisible ? 8 : 0 }
          PathLine { x: 56; y: root.oskVisible ? 0 : 8 }
        }
      }
    }
  }

  // Rotation waits for a widget to report the saved lock state, so a saved
  // lock isn't briefly overridden at startup. Unlocked if none reports in.
  Timer {
    id: configureFallback
    interval: 2000
    running: true
    onTriggered: root.applyRotationLock()
  }

  // Orientation comes from iio-sensor-proxy, through its monitor-sensor
  // tool, which prints the current orientation on start and every change
  // after. Changes are applied once the sensor settles, since a tilt can
  // pass through several in quick succession.
  property string pendingOrientation: ""
  property string appliedOrientation: ""
  readonly property var orientationTransforms:
    ({ "normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3 })

  // Rotation needs iio-sensor-proxy, which Omarchy doesn't ship. Without it
  // there is nothing to watch and nothing to restart: a machine with no
  // accelerometer, or one where the package was never installed, would
  // otherwise respawn a missing command every three seconds for as long as
  // the shell runs. The setup steps say what's missing, and this just stops
  // asking.
  property bool rotationAvailable: true

  // monitor-sensor asks iio-sensor-proxy to claim the accelerometer, and
  // that call can hang. It gives up after 25 seconds, and a restart three
  // seconds later asks again before the daemon has cleared the last one, so
  // the retry keeps wedged the very thing it is waiting for. Measured on a
  // Yoga 300w: the claim had been timing out for every caller, monitor-sensor
  // was being respawned every 23 seconds, and stopping it for 40 seconds made
  // the same claim answer in a fifth of a second.
  //
  // So a run that never reached the sensor counts as a failure, and each
  // failure waits longer than the last. The first wait is already long
  // enough to be the quiet window the daemon needs.
  property int sensorFailures: 0
  property bool sensorClaimed: false
  property bool sensorStuckReported: false

  // Whether this machine has an accelerometer at all, which is a different
  // question from whether iio-sensor-proxy is installed, and one Ragtop never
  // used to ask. rotationAvailable is `command -v monitor-sensor` and nothing
  // more.
  //
  // A touchscreen with no accelerometer, a kiosk or a desk panel, would have
  // the package, because Ragtop's own setup asks for it and nothing else here
  // needs it. Every claim then fails forever, which landed it in the same
  // state as a wedged daemon and got it told to run
  // `systemctl restart iio-sensor-proxy`, advice that cannot help when there
  // is nothing to claim.
  //
  // iio-sensor-proxy answers it directly over D-Bus, so this asks. -1 until
  // it has answered, 0 for no, 1 for yes. Only a definite 0 is ever acted on:
  // a daemon too broken to answer its own property is a fault worth
  // reporting, and absence has to be proved rather than assumed from a
  // silence.
  property int accelPresent: -1
  Process {
    id: accelCheckProc
    running: true
    command: ["busctl", "get-property", "net.hadess.SensorProxy",
              "/net/hadess/SensorProxy", "net.hadess.SensorProxy", "HasAccelerometer"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.trim()
        root.accelPresent = t === "b true" ? 1 : t === "b false" ? 0 : -1
      }
    }
  }
  // The package arriving is what makes the question answerable, so ask again
  // when it does.
  onRotationAvailableChanged: if (root.rotationAvailable && !accelCheckProc.running)
    accelCheckProc.running = true

  // Rotation that is meant to be working and is not. Every clause matters:
  // the package has to be there to fail, the hardware must not be known
  // absent, and rotation must not be held, because while it is held Ragtop
  // does not claim the sensor at all and a failure count left over from
  // before says nothing about now. Same precedence as the sensor line in
  // health(). This is the one rotation state worth an alarm, because
  // something that exists has stopped and there is a thing to do about it.
  readonly property bool sensorStuck: root.rotationAvailable && root.accelPresent !== 0
    && !root.rotationLocked && !root.sensorClaimed && root.sensorFailures >= 2

  // Known to have no accelerometer, so nothing here can follow the device.
  // Manual rotation still works, since that is Hyprland and not the sensor.
  readonly property bool accelAbsent: root.accelPresent === 0

  // Nothing says "absent" or "broken" until Ragtop has had a moment to ask.
  // Without this the bar would show a fault, or hide a button, for the second
  // or so between the shell starting and the first answers arriving, on every
  // restart. The same reason tabletModeKnown exists.
  property bool probesSettled: false
  Timer {
    interval: 4000
    running: !root.probesSettled
    onTriggered: root.probesSettled = true
  }
  readonly property var sensorBackoff: [3000, 30000, 120000, 300000]
  // When the next attempt is allowed, as a clock reading rather than a
  // timer that is running. Four things ask for the sensor at startup, within
  // a second of each other, and whichever arrives while the timer is being
  // armed would otherwise start it anyway. A deadline cannot be raced.
  property double sensorRetryAt: 0

  // The only way the sensor is ever started. Either it is due, or the timer
  // is armed for the rest of the wait.
  function wantSensor() {
    if (root.rotationLocked || !root.rotationAvailable || rotationProc.running) return
    var wait = root.sensorRetryAt - Date.now()
    if (wait <= 0) {
      rotationProc.running = true
      return
    }
    rotationRestart.interval = wait
    rotationRestart.start()
  }

  // The sensor was not the only process being respawned forever with nothing
  // said. The keyboard helper, the focus bridge and the switch watcher all
  // did it too, and each one is a headline feature that can be dead while
  // the plugin looks fine. They share a policy now.
  //
  // A run that lasted ten seconds was working, whatever stopped it, so it
  // starts again at once. A run that died sooner is a failure, and failures
  // wait longer each time. A stop we asked for is neither.
  readonly property var retryBackoff: [3000, 15000, 60000, 300000]
  readonly property int retryGoodRun: 10000
  property var retryState: ({})

  function retryFor(name) {
    if (!root.retryState[name]) root.retryState[name] = { failures: 0, at: 0, told: false }
    return root.retryState[name]
  }
  function retryStarted(name) { root.retryFor(name).at = Date.now() }

  // How long to wait before starting it again.
  function retryAfterExit(name) {
    var s = root.retryFor(name)
    if (s.at && Date.now() - s.at >= root.retryGoodRun) {
      s.failures = 0
      s.told = false
    } else {
      s.failures++
    }
    return root.retryBackoff[Math.min(s.failures, root.retryBackoff.length - 1)]
  }
  function retryHealth(name, running) {
    var s = root.retryState[name]
    if (!s || s.failures === 0) return running ? "ok" : "starting"
    // Already up for longer than a good run, so it is working now whatever
    // went wrong before it. The count is only cleared when it next exits.
    if (running && s.at && Date.now() - s.at >= root.retryGoodRun) return "ok"
    return "failing:" + s.failures
  }

  // What stopped working, in the words of the thing the user lost. Said once
  // per run of bad luck, and only on the second failure, so a single crash
  // that recovers goes unremarked. Two in a row means the first wait of
  // fifteen seconds did not help, and a keyboard that has not typed for
  // fifteen seconds has earned an explanation.
  readonly property var retryTrouble: ({
    "keyboard": ["The on-screen keyboard is not typing",
                 "Ragtop's key sender keeps stopping. Check that python-pywayland "
                 + "is installed. Setup › Tablet › Diagnostics has the rest."],
    "autoshow": ["The keyboard is not coming up by itself",
                 "The watcher that notices text fields keeps stopping. Tap the handle "
                 + "at the bottom to raise the keyboard by hand."],
    "switch": ["Tablet mode is not being noticed",
               "The tablet-mode switch watcher keeps stopping, so folding will not "
               + "register. Setup › Tablet › Tablet Mode sets it by hand."],
    "predict": ["Word suggestions have stopped",
                "Ragtop's word suggester keeps stopping. `ragtop words install` "
                + "fetches the word list again."]
  })
  function retryTell(name) {
    var s = root.retryFor(name)
    if (s.told || s.failures < 2 || retryNotifyProc.running) return
    var words = root.retryTrouble[name]
    if (!words) return
    s.told = true
    retryNotifyProc.command = ["omarchy-notification-send", "-g", "󰌌",
                               words[0], words[1]]
    retryNotifyProc.running = true
  }
  Process { id: retryNotifyProc }

  // Rotation not working is invisible until someone turns the machine and
  // nothing happens, so say it once, with the command that clears it.
  function reportSensorStuck() {
    // Nothing to claim, so nothing to restart. A kiosk used to be told to
    // restart a daemon that was working perfectly well.
    if (root.accelPresent === 0) return
    // Not answered yet. Ask again and let the next failure decide, rather
    // than sending advice that may turn out to be wrong.
    if (root.accelPresent === -1) {
      if (!accelCheckProc.running) accelCheckProc.running = true
      return
    }
    if (root.sensorStuckReported) return
    root.sensorStuckReported = true
    sensorNotifyProc.command = [
      "omarchy-notification-send", "-g", "󰌌",
      "Rotation is not working",
      "iio-sensor-proxy is not answering, so the screen will not follow the "
        + "device. Restarting it usually clears this:\n"
        + "systemctl restart iio-sensor-proxy"
    ]
    sensorNotifyProc.running = true
  }
  Process { id: sensorNotifyProc }

  Process {
    id: sensorCheckProc
    running: true
    command: ["sh", "-c", "command -v monitor-sensor >/dev/null"]
    onExited: function(code) {
      root.rotationAvailable = code === 0
      if (root.rotationAvailable) root.applyRotationLock()
    }
  }
  // Someone who installs the package is owed rotation without restarting the
  // shell for it, which is the whole point of setup naming what is missing.
  // Checking once at startup left it dead until the next restart, so keep
  // looking while it is absent. One `command -v` a minute costs nothing.
  Timer {
    interval: 60000
    repeat: true
    running: !root.rotationAvailable
    onTriggered: if (!sensorCheckProc.running) sensorCheckProc.running = true
  }

  Process {
    id: rotationProc
    command: ["monitor-sensor", "--accel"]
    // A fresh start reports the current orientation, which must be applied
    // even if it matches the last one, since it may have been changed
    // while locked.
    onRunningChanged: {
      if (!running) return
      root.appliedOrientation = ""
      root.sensorClaimed = false
    }
    stdout: SplitParser {
      onRead: function(line) {
        var match = /orientation(?: changed)?: ([a-z-]+)/.exec(line)
        if (!match || !(match[1] in root.orientationTransforms)) return
        // The first orientation is the proof that the claim went through.
        root.sensorClaimed = true
        root.sensorFailures = 0
        root.sensorStuckReported = false
        root.sensorRetryAt = 0
        // A stop held back while the claim was in flight happens now.
        if (root.rotationLocked) {
          rotationProc.running = false
          return
        }
        root.pendingOrientation = match[1]
        orientationSettle.restart()
      }
    }
    onExited: {
      if (!root.sensorClaimed) root.sensorFailures++
      root.sensorRetryAt = Date.now() + root.sensorBackoff[
        Math.min(root.sensorFailures, root.sensorBackoff.length - 1)]
      if (root.sensorFailures >= 2) root.reportSensorStuck()
      root.wantSensor()
    }
  }
  Timer {
    id: orientationSettle
    interval: 300
    onTriggered: root.applyOrientation(root.pendingOrientation)
  }

  // The built-in panel, which is the one with the accelerometer.
  // Which display Ragtop puts itself on. Every one of its surfaces asks this,
  // so the keyboard, its handle, the controls, the picker strip, setup and
  // tiling mode can never end up on different screens.
  //
  //   the "display" setting, when it names a monitor that is actually there
  //   the monitor the compositor binds the touchscreen to, if the user has
  //     bound one (input:touchdevice:output, which reads [[Auto]] unset)
  //   the built-in panel, which on a convertible is the touchscreen
  //   whatever is first, so there is always an answer
  readonly property string displaySetting: String(root.settings["display"] || "auto")
  property string touchOutput: ""
  readonly property string keyboardMonitorName: {
    var monitors = Hyprland.monitors.values
    function named(n) {
      for (var i = 0; i < monitors.length; i++) if (monitors[i].name === n) return n
      return ""
    }
    return named(root.displaySetting) || named(root.touchOutput)
      || root.internalMonitorName()
  }
  readonly property var keyboardScreen:
    Quickshell.screens.find(function(s) { return s.name === root.keyboardMonitorName })
      || Quickshell.screens[0]
  // The same monitor as Hyprland knows it, for its origin and its workspace.
  readonly property var keyboardMonitor: {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (monitors[i].name === root.keyboardMonitorName) return monitors[i]
    return Hyprland.focusedMonitor
  }

  // Asked at startup and whenever the monitors change. Unset it reads
  // "[[Auto]]", which is not a monitor name and so falls through.
  //
  // It used to be asked only once, though this comment already claimed
  // otherwise. Binding the touchscreen to an output after the shell had
  // started, or plugging in a screen that changed which output it belongs
  // to, left Ragtop on the old answer until the shell was restarted.
  Process {
    id: touchOutputProc
    running: true
    command: ["hyprctl", "getoption", "input:touchdevice:output", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var v = JSON.parse(text)
          root.touchOutput = v && v.set && typeof v.str === "string" ? v.str.trim() : ""
        } catch (e) { root.touchOutput = "" }
      }
    }
  }

  // What the monitors say about themselves is read off them rather than
  // tracked, so it has to be read again when they change. Not gated on
  // tiling mode, unlike the other rawEvent handler: which screen Ragtop
  // belongs on and how many pixels it has to the millimetre matter whether
  // or not anything is open.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n !== "monitoradded" && n !== "monitorremoved"
          && n !== "monitorlayoutchanged" && n !== "configreloaded") return
      if (!touchOutputProc.running) touchOutputProc.running = true
      // A mode change moves the pixels without moving the name, so this one
      // cannot wait for keyboardMonitorName to notice.
      if (!densityProc.running) densityProc.running = true
    }
  }

  function internalMonitorName() {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (/^(eDP|DSI|LVDS)-/.test(monitors[i].name)) return monitors[i].name
    return monitors.length > 0 ? monitors[0].name : ""
  }

  // Rotation waits while the screen is locked: Omarchy's lock screen isn't
  // redrawn for a rotated display, though touches would be rotated, so what's
  // drawn and where taps land would disagree. Asking only when about to
  // rotate avoids polling. While locked, it asks again until unlocked.
  function applyOrientation(orientation) {
    if (root.rotationLocked || orientation === root.appliedOrientation) return
    if (!lockCheckProc.running) lockCheckProc.running = true
  }

  Process {
    id: lockCheckProc
    command: ["omarchy-shell", "lock", "isLocked"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.trim() === "true") lockRecheck.restart()
        else root.rotateNow(root.pendingOrientation)
      }
    }
  }
  Timer {
    id: lockRecheck
    interval: 2000
    onTriggered: root.applyOrientation(root.pendingOrientation)
  }

  // The same transform for the display, touchscreen and pen, so touches
  // land where they're drawn.
  // Turning the screen by hand, which is only offered while rotation is
  // locked: unlocked, the sensor would undo it on the next tilt.
  //
  // It turns the display Ragtop is on, which is not always the one the sensor
  // turns. The sensor's is the built-in panel, because that is the panel the
  // accelerometer is bolted to. This one is the screen the panel you are
  // tapping is drawn on, which on a kiosk or a desk is the screen you mean.
  // On a convertible with one display they are the same screen.
  //
  // The current transform is read at the moment the button is tapped rather
  // than tracked, because a tracked one that has drifted would turn the
  // screen somewhere nobody asked for.
  property int rotateStep: 0
  function rotateBy(step) {
    if (rotateReadProc.running || rotateManualProc.running) return
    root.rotateStep = step
    rotateReadProc.running = true
  }

  Process {
    id: rotateReadProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        // The built-in panel, the same screen the sensor turns, and not
        // whichever one Ragtop happens to be drawn on. That screen is the one
        // that physically turns, and the input transform these commands set
        // is global: turning an external monitor would rotate the touchscreen
        // mapping of the panel in your hands to match a screen that had not
        // moved.
        var name = root.internalMonitorName()
        if (name === "") return
        var cur = -1
        try {
          JSON.parse(text).forEach(function(m) {
            if (m.name === name) cur = Number(m.transform) || 0
          })
        } catch (e) { return }
        if (cur < 0) return
        var t = ((cur + root.rotateStep) % 4 + 4) % 4
        rotateManualProc.command = ["hyprctl", "eval",
          "hl.monitor({ output = '" + name + "', transform = " + t + " }) " +
          "hl.config({ input = { touchdevice = { transform = " + t + " }, tablet = { transform = " + t + " } } })"]
        rotateManualProc.running = true
        // Whatever the sensor last thought is no longer what the screen is
        // doing, so unlocking later re-applies rather than deciding it is
        // already there.
        root.appliedOrientation = ""
      }
    }
  }

  Process {
    id: rotateManualProc
    // Same as the sensor's own apply: turning the screen moves every window
    // on it and Hyprland says nothing per window, so the outlines are told.
    onExited: {
      if (root.tilingOpen) {
        tilingIdle.restart()
        tilingSettle.restart()
      }
    }
  }

  function rotateNow(orientation) {
    if (root.rotationLocked || orientation === "" || orientation === root.appliedOrientation) return
    var output = root.internalMonitorName()
    if (output === "") return
    var t = root.orientationTransforms[orientation]
    rotateApplyProc.command = ["hyprctl", "eval",
      "hl.monitor({ output = '" + output + "', transform = " + t + " }) " +
      "hl.config({ input = { touchdevice = { transform = " + t + " }, tablet = { transform = " + t + " } } })"]
    rotateApplyProc.running = true
    root.appliedOrientation = orientation
  }
  Process {
    id: rotateApplyProc
    // Turning the screen moves and resizes every window on it, and Hyprland
    // says nothing per window about that, so the outlines would keep the
    // shape the screen had before. Same trap as the keyboard's exclusive
    // zone. Read the geometry back once the transform has landed.
    onExited: {
      if (!root.tilingOpen) return
      tilingSettle.again = 2
      tilingSettle.restart()
    }
  }
  // The interval is set by wantSensor, from the deadline.
  Timer {
    id: rotationRestart
    interval: 3000
    onTriggered: root.wantSensor()
  }

  // Settings written by the `ragtop` command (Setup › Tablet in the
  // Omarchy menu), as key=value lines. A missing key keeps its default.
  property var settings: ({})
  property bool settingsLoaded: false

  // Whether Omarchy's bar is transparent (Style › Bar › Transparency), passed
  // on by the bar widget. The keyboard handle and, by default, the keyboard's
  // background follow it.
  property bool barTransparent: false
  // Set by the bar widget, which is the only thing that can ask the bar.
  property int barSize: Style.bar.sizeHorizontal
  // Both files below are watched, settings.conf by this service and the
  // mode file by every patched overlay clone. A watcher on a path that does
  // not exist yet never learns that it appeared: on a machine where Ragtop
  // had never run, the first setting written went unnoticed until the shell
  // was restarted, which is how it was found (Tablet Mode set to Always On,
  // and no handle until a reboot). Create both before anything looks.
  Process {
    id: ensureFilesProc
    running: true
    command: ["sh", "-c",
      'mkdir -p "$HOME/.config/ragtop"; : >> "$HOME/.config/ragtop/settings.conf"; ' +
      'd="${XDG_RUNTIME_DIR:-}"; [ -z "$d" ] || [ -e "$d/ragtop-mode" ] || printf "laptop\n" > "$d/ragtop-mode"']
  }

  // And if it goes missing while running, keep asking: a watcher that has
  // lost its file stays lost otherwise.
  Timer {
    id: settingsRetry
    interval: 3000
    repeat: true
    onTriggered: settingsFile.reload()
  }

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/ragtop/settings.conf"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      settingsRetry.stop()
      var parsed = {}
      text().split("\n").forEach(function(line) {
        var eq = line.indexOf("=")
        if (eq > 0) parsed[line.slice(0, eq).trim()] = line.slice(eq + 1).trim()
      })
      root.settings = parsed
      root.settingsLoaded = true
      root.updateTabletMode()
    }
    onLoadFailed: {
      root.settings = ({})
      root.settingsLoaded = true
      root.updateTabletMode()
      settingsRetry.start()
    }
  }
  readonly property bool autoShowEnabled: root.settings["auto-show"] !== "off"
  // Modifiers apply to the next key ("oneshot") or stay on until tapped
  // again ("sticky").

  // In tablet mode, bring the keyboard up when a text field gets focus. The
  // bridge learns about focus from fcitx5, Omarchy's input method, and prints
  // "show". Hiding stays with the user (see fcitx-osk-bridge.py for why).
  // Stopping it hands fcitx5 back its own interface.
  // `running` cannot be a binding here. The restart timer assigns to it, and
  // an assignment breaks a binding for good, so after the first crash the
  // bridge stopped following tablet mode at all and auto-show stayed dead
  // until the shell restarted. The switch watcher below already avoided this
  // by driving its process from a changed handler, and so does this now.
  // The bridge is also how Chinese, Japanese and Korean reach the keyboard
  // (see the input methods below), so it runs for either.
  readonly property bool wantFocusBridge: root.keyboardAvailable
    && (root.autoShowEnabled || root.inputMethodsEnabled)

  // Whether a focused text field may raise the keyboard on its own. Asking
  // for it by hand still works in each of these: they go through
  // setOskVisible rather than through the bridge.
  //
  // Not while the picker is up, because the keyboard covers the preview the
  // picker exists to show. Not while tiling, because the keyboard coming
  // back ends the mode, and the bar's own buttons change which window has
  // focus, so a window with a text field would close the mode out from
  // under the button just tapped. Not while the screensaver is up, because
  // nothing should be drawn over it.
  readonly property bool autoShowAllowed: root.keyboardAvailable && root.autoShowEnabled
    && !root.pickerOpen && !root.tilingOpen && root.screensaverAddress === ""
  onWantFocusBridgeChanged: {
    focusBridgeRestart.stop()
    focusBridgeProc.running = root.wantFocusBridge
  }
  Process {
    id: focusBridgeProc
    command: ["/usr/bin/python3", Qt.resolvedUrl("fcitx-osk-bridge.py").toString().replace(/^file:\/\//, "")]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line === "hide") {
          // Not another keyboard: Ragtop's own keys cause one too, and so
          // does focus settling into a field, which comes with a show.
          if (Date.now() - root.lastKeysAt > root.ownHideWithin
              && Date.now() - root.freshFieldAt > 500) root.finishWord()
          return
        }
        if (line === "show") {
          root.currentWord = ""
          root.freshField()
          root.autoShows++
          if (root.autoShowAllowed && !root.oskVisible) root.setOskVisible(true)
          return
        }
        var space = line.indexOf(" ")
        var kind = line.slice(0, space)
        var value
        try { value = JSON.parse(line.slice(space + 1)) } catch (e) { return }
        if (kind === "engine") root.imeEngine = value
        else if (kind === "field") root.fieldInfo = value
        else if (kind === "engines") root.imeEngines = Array.isArray(value) ? value : []
        else if (kind === "candidates") root.setSuggestions("fcitx", value)
      }
    }
    onRunningChanged: {
      if (running) {
        root.retryStarted("autoshow")
      } else {
        // Whatever it last said went with it.
        root.imeEngine = null
        root.fieldInfo = null
        root.imeEngines = []
        root.setSuggestions("fcitx", null)
      }
    }
    onExited: {
      if (!root.wantFocusBridge) return
      focusBridgeRestart.interval = root.retryAfterExit("autoshow")
      focusBridgeRestart.start()
      root.retryTell("autoshow")
    }
  }
  Timer {
    id: focusBridgeRestart
    interval: 5000
    onTriggered: focusBridgeProc.running = root.wantFocusBridge
  }

  Process { id: modeWriteProc }

  // A plugin added with `omarchy plugin add` runs without install.sh having
  // set up its config lines, layouts and overlay patches. Check once per
  // session and offer to run the installer. Installing a plugin never runs
  // its code, so this asks rather than doing it.
  function offerSetup(problems) {
    if (problems.length === 0) return
    // Never set up on this machine: open setup rather than describe it.
    if (problems.indexOf("The installer hasn't been run yet.") !== -1) {
      root.openSetup()
      return
    }
    var shown = problems.slice(0, 3)
    if (problems.length > 3) shown.push("…and " + (problems.length - 3) + " more.")
    setupNotifyProc.command = [
      "omarchy-notification-send", "-g", "󰌌",
      "Ragtop needs setup",
      shown.join("\n") + "\nClick to fix it.",
      "--exec", "omarchy-shell", "ragtop", "openSetup"
    ]
    setupNotifyProc.running = true
  }

  Process {
    id: setupCheckProc
    command: ["bash", Qt.resolvedUrl("setup-check.sh").toString().replace(/^file:\/\//, "")]
    stdout: StdioCollector {
      onStreamFinished: root.offerSetup(text.split("\n").filter(function(s) { return s !== "" }))
    }
  }
  Process { id: setupNotifyProc }
  Timer {
    interval: 8000
    running: true
    onTriggered: setupCheckProc.running = true
  }

  // Ragtop's own patches to the overlay clones change between versions, and
  // updating a plugin fires no Omarchy post-update hook, so the hook alone
  // would leave a clone on an old patch until Omarchy itself moved. Re-sync
  // at startup as well: an overlay already in step costs a hash, an overlay
  // that isn't gets re-cloned and says so.
  //
  // Through systemd-run, because re-cloning isn't atomic: it removes the
  // clone, makes a new one and patches it. The shell reloads this plugin
  // whenever its files change -- which is exactly what updating Ragtop does
  // -- and that kills any process the plugin owns. Killed between the clone
  // and the patch, it would leave an unpatched clone behind, which is how
  // this was found.
  Process {
    id: overlaySyncProc
    command: ["systemd-run", "--user", "--quiet", "--collect",
              "--unit", "ragtop-overlay-sync",
              "bash", Qt.resolvedUrl("overlay-clones.sh").toString().replace(/^file:\/\//, ""), "sync"]
  }
  Timer {
    interval: 12000
    running: true
    onTriggered: overlaySyncProc.running = true
  }

  // Namespaces of the overlays a touch can get past to the keyboard: the
  // ones patched by overlay-clones.sh, and Omarchy's own where it has
  // cooperative focus and nothing has turned that off. An open overlay
  // covers the bar, so the keyboard is brought up with it. With any other
  // overlay taps on the keyboard would only close it, so only these count.
  property var patchedOverlays: []
  property var openOverlays: []
  property bool oskShownForOverlay: false

  // Omarchy's theme and background pickers are both its image picker, whose
  // surface is named for what it does rather than for the plugin.
  readonly property string pickerNamespace: "omarchy-image-selector"
  // Whether the picker is one of those, which is what makes the nav strip
  // tappable at all. See PickerNav.qml.
  property bool pickerPatched: false

  Process {
    id: patchCheckProc
    // Asked once. Turning cooperative focus on or off in shell.json is
    // noticed at the next shell restart, as a new clone is.
    command: ["bash", Qt.resolvedUrl("overlay-clones.sh").toString().replace(/^file:\/\//, ""), "tappable"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        var found = text.split("\n").filter(function(s) { return s !== "" }).map(function(name) {
          return name === "image-picker" ? root.pickerNamespace : "omarchy-" + name
        })
        root.pickerPatched = found.indexOf(root.pickerNamespace) !== -1
        // The picker is kept out of patchedOverlays: an open overlay brings
        // the keyboard up, and the picker wants it away (see pickerOpen).
        root.patchedOverlays = found.filter(function(s) { return s !== root.pickerNamespace })
      }
    }
  }

  // The picker, while it's up. Its carousel is the one overlay the keyboard
  // hurts rather than helps: it covers the preview the picker exists to
  // show, and a stock picker takes every touch on the screen, so a tap on
  // the keyboard reaches the scrim and throws the picker away. Ragtop takes
  // the keyboard off it and offers PickerNav instead.
  property bool pickerOpen: false
  property bool oskHiddenForPicker: false
  onPickerOpenChanged: {
    if (root.pickerOpen) {
      if (root.oskVisible) {
        root.oskHiddenForPicker = true
        root.setOskVisible(false)
      }
    } else if (root.oskHiddenForPicker) {
      root.oskHiddenForPicker = false
      if (root.keyboardAvailable) root.setOskVisible(true)
    }
  }

  // The last layout a real keyboard switched to. See onRawEvent.
  property string lastLayoutName: ""

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      // Hyprland also sends activelayout whenever input switches between
      // keyboards, including every key from fcitx5 and Ragtop's helper, so
      // only a real keyboard changing layout counts.
      var layoutChanged = name === "configreloaded"
      if (name === "activelayout") {
        var data = String(event.data || "")
        var device = data.slice(0, data.indexOf(","))
        var layout = data.slice(data.indexOf(",") + 1)
        if (!device.startsWith("hl-virtual-keyboard") && layout !== root.lastLayoutName) {
          root.lastLayoutName = layout
          layoutChanged = true
        }
      }
      if (layoutChanged) root.sendKeys("reload")
      if (name === "configreloaded") {
        // A reload drops runtime rules, and the surfaces re-map with it.
        root.layerRulesReady = false
        root.applyLayerRules()
        if (root.blurKeyboard) root.applyBlur()
        // It drops the rotation with them: the transform is a runtime value,
        // so the display returns to whatever the config says while the device
        // is still lying where it was. The sensor has nothing new to report,
        // so nothing would put it back until the machine was physically
        // moved, which is how this was found, switching themes on a tablet
        // held upright. Forget what was applied and apply it again.
        root.appliedOrientation = ""
        root.applyOrientation(root.pendingOrientation)
      }
      // Omarchy's screensaver, watched by window class. See the catcher
      // below for what Ragtop does about it.
      if (name === "openwindow") {
        var fields = String(event.data || "").split(",")
        if (fields.length >= 3 && fields[2] === "org.omarchy.screensaver") root.screensaverAddress = fields[0]
      } else if (name === "closewindow") {
        if (String(event.data || "").trim() === root.screensaverAddress) root.screensaverAddress = ""
        else if (root.screensaverAddress !== "") root.confirmScreensaver()
      }
      // A window opening or closing while a screensaver is supposedly up
      // says the session is awake, which a screensaver mostly is not. These
      // events are already subscribed, so asking costs nothing.
      if (name === "openwindow" && root.screensaverAddress !== ""
          && String(event.data || "").split(",")[0] !== root.screensaverAddress)
        root.confirmScreensaver()

      if (name !== "openlayer" && name !== "closelayer") return
      var ns = String(event.data || "")
      if (ns === root.pickerNamespace) {
        root.pickerOpen = name === "openlayer"
        return
      }
      if (root.patchedOverlays.indexOf(ns) === -1) return
      // Tracked as a set so hopping from one overlay to another (menu to
      // emoji picker) doesn't hide the keyboard when the first one closes.
      var open = root.openOverlays.filter(function(o) { return o !== ns })
      if (name === "openlayer") open.push(ns)
      root.openOverlays = open
      if (name === "openlayer") {
        if (open.length === 1 && root.keyboardAvailable && !root.oskVisible) {
          root.oskShownForOverlay = true
          root.setOskVisible(true)
        }
      } else if (open.length === 0 && root.oskShownForOverlay) {
        root.oskShownForOverlay = false
        root.setOskVisible(false)
      }
    }
  }

  // Find the device reporting SW_TABLET_MODE, whichever driver provides it
  // (lenovo-ymc, intel-vbtn, intel-hid, asus-wmi, hp-wmi, thinkpad_acpi...):
  // the one whose switch bitmask ("B: SW=", last word is bits 0-63) has bit 1.
  // Retried while none is found, e.g. a detachable's keyboard not yet attached.
  function findSwitchDevice(devices) {
    var blocks = devices.split(/\n\s*\n/)
    for (var i = 0; i < blocks.length; i++) {
      var handler = /^H: Handlers=.*\b(event\d+)\b/m.exec(blocks[i])
      var sw = /^B: SW=([0-9a-fA-F ]+)$/m.exec(blocks[i])
      if (!handler || !sw) continue
      var words = sw[1].trim().split(/\s+/)
      if (parseInt(words[words.length - 1], 16) & 2) return "/dev/input/" + handler[1]
    }
    return ""
  }

  Process {
    id: detectProc
    command: ["cat", "/proc/bus/input/devices"]
    stdout: StdioCollector {
      onStreamFinished: root.detectedSwitchDevice = root.findSwitchDevice(text)
    }
  }
  Timer {
    interval: 10000
    running: root.detectedSwitchDevice === "" && root.tabletModeSetting === "auto"
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!detectProc.running) detectProc.running = true
  }

  // Watch the tablet-mode switch: tablet-switch.py prints "tablet" or
  // "laptop" at start and whenever it moves.
  readonly property bool watchSwitch: root.switchDevice !== "" && root.tabletModeSetting === "auto"
  onWatchSwitchChanged: tabletModeProc.running = root.watchSwitch
  // A different device: stop, and onExited starts it again on the new one.
  // That stop is one we asked for, so it is not counted as a failure.
  property bool switchDeviceChanging: false
  onSwitchDeviceChanged: {
    if (!tabletModeProc.running) return
    root.switchDeviceChanging = true
    tabletModeProc.running = false
  }
  Component.onCompleted: {
    // Which word lists there are, for the strip's offer.
    root.readWordLanguages()
    tabletModeProc.running = root.watchSwitch
    applyLayerRules()
  }
  Process {
    id: tabletModeProc
    command: ["/usr/bin/python3", Qt.resolvedUrl("tablet-switch.py").toString().replace(/^file:\/\//, ""), root.switchDevice]
    stdout: SplitParser {
      onRead: function(line) {
        if (line === "tablet" || line === "laptop") root.applySwitchReading(line === "tablet")
      }
    }
    // The watcher exits when its device goes away, which on a detachable can
    // mean the keyboard was taken off. Look for a switch again rather than
    // retrying a path that may no longer be there.
    onRunningChanged: if (running) root.retryStarted("switch")
    onExited: {
      if (root.tabletSwitchDevice === "" && !detectProc.running) detectProc.running = true
      var asked = root.switchDeviceChanging
      root.switchDeviceChanging = false
      if (!root.watchSwitch) return
      tabletModeRestart.interval = asked ? root.retryBackoff[0] : root.retryAfterExit("switch")
      tabletModeRestart.start()
      if (!asked) root.retryTell("switch")
    }
  }
  Timer {
    id: tabletModeRestart
    interval: 5000
    onTriggered: tabletModeProc.running = root.watchSwitch
  }

  // ---- The on-screen keyboard ------------------------------------------

  // Sends its keys: QML can't be a Wayland virtual keyboard itself.
  Process {
    id: keyboardHelper
    command: ["/usr/bin/python3", Qt.resolvedUrl("keyboard-helper.py").toString().replace(/^file:\/\//, "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line.startsWith("labels ")) {
          try { root.keyLabels = JSON.parse(line.slice(7)) } catch (e) {}
        }
      }
    }
    onRunningChanged: {
      if (!running) return
      root.retryStarted("keyboard")
      // A new helper starts on the Wayland route, whatever the old one was on.
      if (root.imeComposing) root.sendRoute()
    }
    onExited: {
      keyboardHelperRestart.interval = root.retryAfterExit("keyboard")
      keyboardHelperRestart.start()
      root.retryTell("keyboard")
    }
  }
  Timer {
    id: keyboardHelperRestart
    interval: 3000
    onTriggered: keyboardHelper.running = true
  }

  // The active layout's name and letter keys, from the helper:
  // { name, rows: [[[normal, shifted], ...], ...] }. Null until it reports.
  // Also written to $XDG_RUNTIME_DIR/ragtop-layout.json for the lock
  // screen's keyboard, which can't reach this service.
  property var keyLabels: null
  onKeyLabelsChanged: {
    if (!root.keyLabels) return
    root.sendRows()
    layoutWriteProc.command = [
      "sh", "-c",
      'd="${XDG_RUNTIME_DIR:-}" && [ -n "$d" ] && printf "%s\\n" "$1" > "$d/ragtop-layout.json.tmp" && mv -f "$d/ragtop-layout.json.tmp" "$d/ragtop-layout.json"',
      "--", JSON.stringify(root.keyLabels)
    ]
    layoutWriteProc.running = true
  }
  Process { id: layoutWriteProc }

  // One command per line. See keyboard-helper.py. Everything typed passes
  // here, which is what makes it the place to follow the word being typed.
  function sendKeys(command) {
    // A space after a word finishes it (finished); anything else typed
    // means the moment for its forms has passed.
    if (/^(type|key|down) /.test(command)) {
      var word = command === "key space" ? root.currentWord : ""
      root.setFinished(word, " ", false)
      if (root.suggestions.source === "forms") root.setSuggestions("forms", null)
    }
    // BackSpace straight after a swipe takes the whole word back, and the
    // space after it, as on a phone: a wrong swipe is undone in one tap.
    // The space a swipe put in front stays, ready for the next one. The
    // key's release, when it comes, is swallowed: it was never pressed.
    if (command === "key BackSpace" && root.swipedWord !== "" && keyboardHelper.running) {
      var out = ""
      for (var i = root.swipeLead.length; i < root.swipedWord.length; i++) out += "key BackSpace\n"
      root.writeKeys(out)
      root.swipedWord = ""
      root.autoSpaced = false
      root.currentWord = ""
      root.swallowBackSpaceUp = true
      if (root.suggestions.source === "swipe") root.setSuggestions("swipe", null)
      return
    }
    if (command === "up BackSpace" && root.swallowBackSpaceUp) {
      root.swallowBackSpaceUp = false
      return
    }
    // A space straight after punctuation that Ragtop already spaced, "test"
    // taken from the strip and then a full stop, is swallowed, as on a
    // phone: the space is there, and a second one would also use up the
    // capital waiting for the next word.
    if (command === "key space" && root.autoSpaced && root.assistsActive
        && /[.,!?;:] $/.test(root.beforeCursor)) {
      root.autoSpaced = false
      return
    }
    // A second space soon after a word is a full stop, as on a phone: the
    // first space goes back and ". " goes in, and the next word starts a
    // sentence (capitalNext).
    if (command === "key space" && root.assistsActive && keyboardHelper.running
        && Date.now() - root.lastKeysAt < root.doubleSpaceWithin && root.endsWordThenSpace()) {
      root.trackWord(command)
      root.writeKeys("key BackSpace\ntype . \n")
      root.autoSpaced = false
      return
    }
    // Punctuation straight after a space Ragtop put in itself goes before
    // that space, as on a phone: a swiped "test" then a comma is "test, ",
    // not "test ,". A space typed by hand is never moved.
    var mark = command.length === 6 && command.indexOf("type ") === 0
      && root.closingMarks.indexOf(command[5]) !== -1
    if (mark && root.autoSpaced && keyboardHelper.running) {
      root.trackWord(command)
      root.writeKeys("key BackSpace\ntype " + command[5] + " \n")
      root.autoSpaced = true
      return
    }
    root.trackWord(command)
    // Only something typed counts. A release, a held modifier or a change of
    // route between a word and its full stop types nothing.
    if (/^(type|key|down) /.test(command)) root.autoSpaced = false
    if (keyboardHelper.running) root.writeKeys(command + "\n")
  }
  readonly property string closingMarks: ".,!?;:"

  // How a held key repeats, Hyprland's own setting, for the keyboard, which
  // repeats its keys itself (Keyboard.qml, keyRepeat). Its defaults until read.
  property int repeatDelay: 600
  property int repeatInterval: 40
  Process {
    id: repeatProc
    command: ["bash", "-c", 'hyprctl getoption input:repeat_delay -j; hyprctl getoption input:repeat_rate -j']
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var all = JSON.parse("[" + text.replace(/}\s*{/g, "},{") + "]")
          var delay = all[0].int, rate = all[1].int
          if (delay > 0) root.repeatDelay = delay
          if (rate > 0) root.repeatInterval = Math.max(10, Math.round(1000 / rate))
        } catch (e) {}
      }
    }
  }

  // Every key Ragtop sends goes through here, so it knows when it last
  // typed (see finishWord) and what (typedTail).
  property real lastKeysAt: 0
  function writeKeys(text) {
    root.lastKeysAt = Date.now()
    text.split("\n").forEach(root.noteTyped)
    keyboardHelper.write(text)
  }

  // ---- Typing assists ------------------------------------------------------

  // A capital at the start of a sentence, and a full stop for a double
  // space, as on a phone. Ragtop sees only the keys it sends, so it keeps
  // what it typed in this field (typedTail) and decides from that, and
  // where it cannot know, after an arrow or a tap in the text, it does
  // nothing rather than guess.
  //
  // All of it, not the last few characters: BackSpace uncovers what came
  // before, and keeping four meant deleting a short word after a full stop
  // left nothing to say the full stop was there. On unless turned off; never in a terminal,
  // where "ls" is not the start of a sentence, nor in a password prompt or
  // while a CJK engine composes.
  readonly property bool assistsEnabled: root.settings["assists"] !== "off"
  readonly property bool assistsActive: root.assistsEnabled && !root.inTerminal
    && !root.secretField && !root.imeComposing && !(root.fieldInfo && root.fieldInfo.noCapitals)
  readonly property bool capitalNext: root.assistsActive && root.sentenceStart
  readonly property int doubleSpaceWithin: 1500
  property string typedTail: ""
  // Where in typedTail the cursor is, which ← → Home End move and which
  // typing and deleting happen at, as in a line editor; past its end when
  // typedTail has been emptied, which reads as its end.
  property int typedCursor: 0
  readonly property string beforeCursor: root.typedTail.slice(0, Math.min(root.typedCursor, root.typedTail.length))
  // Whether typedTail reaches back to the start of the field, so that all of
  // it deleted is the start of the field again rather than unknown.
  property bool typedFromStart: false
  readonly property int typedKept: 400
  property bool sentenceStart: false
  function isWordChar(c) { return c.toLowerCase() !== c.toUpperCase() || (c >= "0" && c <= "9") }
  function endsWordThenSpace() {
    var t = root.beforeCursor
    return t.length >= 2 && t[t.length - 1] === " " && root.isWordChar(t[t.length - 2])
  }
  // One command as sent, for typedTail and sentenceStart. Everything that
  // cannot be followed, ↑ ↓, Tab, a shortcut, leaves it unknown, and unknown
  // never capitalises or suggests.
  function noteTyped(line) {
    if (line === "") return
    if (root.secretField) return     // kept nowhere: see secretField
    var space = line.indexOf(" ")
    var cmd = space < 0 ? line : line.slice(0, space)
    var arg = space < 0 ? "" : line.slice(space + 1)
    var t = root.typedTail
    var c = Math.min(root.typedCursor, t.length)
    // A named key's modifiers follow it: Shift+Return is a new line still,
    // and only Ctrl, Alt or Super make it a shortcut, which could do anything.
    var parts = arg.split(" ")
    var keysym = parts[0]
    var shortcut = parts.slice(1).some(function(m) { return m !== "shift" })
    var named = (cmd === "key" || cmd === "down") && !shortcut
    var lineStart = t.lastIndexOf("\n", c - 1) + 1
    var unknown = false
    function insert(text) {
      t = t.slice(0, c) + text + t.slice(c)
      c += text.length
    }
    if (cmd === "type") insert(arg)
    else if (named && keysym === "space") insert(" ")
    else if (named && keysym === "Return") {
      // At a shell's prompt Enter runs the line, all of it, and the next
      // starts empty; anywhere else it breaks the line at the cursor.
      if (root.atPrompt) { t = "\n"; c = 1 } else insert("\n")
    } else if (named && keysym === "BackSpace") {
      if (c > 0) { t = t.slice(0, c - 1) + t.slice(c); c-- }
      else unknown = !root.typedFromStart
    } else if (named && keysym === "Delete") {
      if (c < t.length) t = t.slice(0, c) + t.slice(c + 1)
    } else if (named && keysym === "Left") {
      if (c > 0) c--
      else unknown = !root.typedFromStart
    } else if (named && keysym === "Right") {
      if (c < t.length) c++
    } else if (named && keysym === "Home") {
      if (lineStart === 0 && !root.typedFromStart) unknown = true
      else c = lineStart
    } else if (named && keysym === "End") {
      var next = t.indexOf("\n", c)
      c = next < 0 ? t.length : next
    } else if (cmd === "key" || cmd === "down") unknown = true   // ↑ ↓, Tab, a shortcut
    else return                                                  // up, hold, release, route
    if (unknown) {
      t = ""
      c = 0
      root.typedFromStart = false
    }
    if (t.length > root.typedKept) {
      var cut = t.length - root.typedKept
      t = t.slice(cut)
      c = Math.max(0, c - cut)
      root.typedFromStart = false
    }
    root.typedTail = t
    root.typedCursor = c
    var before = t.slice(0, c)
    root.sentenceStart = before === "" ? root.typedFromStart : /([.!?] |\n)$/.test(before)
  }
  // A field just focused is the start of something, and another keyboard
  // having typed is anywhere at all.
  function freshField() {
    root.typedTail = ""
    root.typedFromStart = true
    root.sentenceStart = true
    root.freshFieldAt = Date.now()
  }
  property real freshFieldAt: 0

  // Which application has focus, by class, for inTerminal.
  property string activeClass: ""
  readonly property var terminalClasses: ["foot", "footclient", "alacritty", "kitty", "ghostty",
    "com.mitchellh.ghostty", "org.wezfurlong.wezterm", "wezterm", "xterm", "urxvt", "st",
    "st-256color", "konsole", "org.kde.konsole", "org.gnome.console", "gnome-terminal-server",
    "org.gnome.terminal", "tilix", "com.gexperts.tilix", "terminator", "rio", "contour",
    "warp", "dev.warp.warp", "blackbox", "com.raggesilver.blackbox", "ptyxis", "org.gnome.ptyxis"]
  // And the one Omarchy is set to open, which is a terminal by fact rather
  // than by the list: `omarchy-default-terminal` names Omarchy's four, and
  // gives any other's desktop id, which is its window class.
  property string defaultTerminalClass: ""
  readonly property var omarchyTerminals: ({ alacritty: "alacritty", foot: "foot",
                                             ghostty: "com.mitchellh.ghostty", kitty: "kitty" })
  Process {
    id: defaultTerminalProc
    command: ["omarchy-default-terminal"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.trim()
        root.defaultTerminalClass = (root.omarchyTerminals[t] || t.replace(/\.desktop$/, "")).toLowerCase()
      }
    }
  }
  readonly property bool inTerminal: {
    if (root.fieldInfo && root.fieldInfo.terminal) return true
    var c = root.activeClass.toLowerCase()
    return c !== "" && (c === root.defaultTerminalClass || root.terminalClasses.indexOf(c) !== -1)
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event && event.name ? event.name : "") !== "activewindow") return
      var data = String(event.data || "")
      root.activeClass = data.slice(0, data.indexOf(",") < 0 ? data.length : data.indexOf(","))
      root.termJustFocused = true
      Qt.callLater(root.readTermPlace)
      // A new window is a new place to type, and where in it is unknown,
      // unless fcitx5 has just said a text field took focus: the two come
      // together when a window is tapped into, the window's often second,
      // and it undid the field's fresh start.
      if (Date.now() - root.freshFieldAt < 500) return
      root.typedTail = ""
      root.typedFromStart = false
      root.sentenceStart = false
    }
  }
  Process {
    id: activeClassProc
    command: ["hyprctl", "-j", "activewindow"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.activeClass = String(JSON.parse(text).class || "") } catch (e) {}
      }
    }
  }

  // The word in progress is over, by a route Ragtop cannot see: another
  // keyboard typed, or focus left the field. Whatever it had armed to take
  // back, a swiped word, a word's letters or an automatic space, would now
  // take back someone else's text, so it is all let go.
  //
  // fcitx5 reports any key from a keyboard device with a hide, which the
  // bridge passes on. Ragtop's own keys cause one too, within moments of
  // being sent, so a hide that long after Ragtop's last key is somebody
  // else's.
  readonly property int ownHideWithin: 250
  function finishWord() {
    root.setFinished("", "", false)
    root.typedTail = ""
    root.typedFromStart = false
    root.sentenceStart = false
    root.currentWord = ""
    root.swipedWord = ""
    root.autoSpaced = false
    if (root.suggestions.source === "predict" || root.suggestions.source === "swipe")
      root.setSuggestions(root.suggestions.source, null)
  }
  property bool swallowBackSpaceUp: false
  // Whether the last thing typed was a space Ragtop added after a word.
  property bool autoSpaced: false

  // ---- Input methods: Chinese, Japanese, Korean ------------------------

  // Typing these goes through fcitx5, which turns romaji into kana and kanji,
  // pinyin into hanzi, and jamo into Hangul syllables, and offers what it
  // could mean. Its own list of those pops up by the text and cannot be
  // touched, so while one of its composing engines is on in the focused
  // field, the keyboard shows them in its suggestion strip instead, and its
  // keys go through fcitx5's on-screen keyboard interface so the list keeps
  // coming (keyboard-helper.py, FcitxRoute). A plain layout is untouched.
  //
  // Which engine is on is fcitx5's to say and the bridge passes it on. The
  // setting is the way out of all of it: off, keys go the Wayland way as
  // they always have and fcitx5 draws its own list.
  readonly property bool inputMethodsEnabled: root.settings["input-methods"] !== "off"
  // { name, label, title } for the composing engine on in the focused field,
  // e.g. { "mozc", "あ", "Mozc" }, or null for a plain layout.
  property var imeEngine: null
  // Every composing engine in the user's fcitx5 group, the same objects, for
  // a hold on the space bar to offer.
  property var imeEngines: []
  readonly property bool imeComposing: root.inputMethodsEnabled && root.imeEngine !== null
  onImeComposingChanged: root.sendRoute()
  function sendRoute() { root.sendKeys("route " + (root.imeComposing ? "fcitx" : "wayland")) }

  function sendBridge(command) {
    if (focusBridgeProc.running) focusBridgeProc.write(command + "\n")
  }
  function switchEngine(name) { root.sendBridge("switch " + name) }
  function leaveEngine() { root.sendBridge("deactivate") }

  // What the suggestion strip shows: { source, items: [{ text, note }],
  // prev, next, cursor }. One strip whoever fills it. fcitx5 is the only
  // source today; a source that predicts words, or reads a swipe, would fill
  // the same object and answer chooseSuggestion for its own items.
  readonly property var noSuggestions: ({ source: "", items: [], prev: false, next: false, cursor: -1 })
  property var suggestions: root.noSuggestions
  function setSuggestions(source, value) {
    // Nothing from a source clears only what that source put there. The
    // bridge says "no candidates" after every key on a plain layout, and
    // without this it wiped the word suggestions a moment after each one
    // appeared.
    if (!value || !Array.isArray(value.items) || value.items.length === 0) {
      if (root.suggestions.source === source) root.suggestions = root.noSuggestions
      return
    }
    root.suggestions = { source: source, items: value.items, prev: !!value.prev,
                         next: !!value.next, cursor: value.cursor | 0 }
  }
  // Whether the strip has a place on the keyboard. Only while it has
  // something in it, since an empty band is screen given up for nothing, and
  // for a few seconds after (stripLingers), so that while someone is typing
  // it stays, and the windows above move once when typing starts and once
  // when it stops rather than at every word.
  readonly property bool suggestionsSource: root.imeComposing || root.predicting || root.swipeActive
    || root.offerLanguage !== "" || root.terminalSuggesting
  readonly property bool suggestionsShown: root.suggestionsSource
    && (root.suggestions.items.length > 0 || root.stripLingers)
  property bool stripLingers: false
  onSuggestionsChanged: {
    if (root.suggestions.items.length > 0) {
      root.stripLingers = true
      stripLinger.stop()
    } else {
      stripLinger.restart()
    }
  }
  Timer { id: stripLinger; interval: 4000; onTriggered: root.stripLingers = false }
  // Whether a strip could appear at all, for the keyboard to choose a board
  // that has room for it either way.
  readonly property bool stripPossible: root.predictionsEnabled
    || (root.inputMethodsEnabled && root.imeEngines.length > 0)
  function chooseSuggestion(index) {
    if (root.suggestions.source === "fcitx") root.sendBridge("select " + index)
    else if (root.suggestions.source === "predict") root.takeWord(index)
    else if (root.suggestions.source === "swipe") root.swapSwiped(index)
    else if (root.suggestions.source === "offer") root.answerOffer(index)
    else if (root.suggestions.source === "term") root.takeTerm(index)
    else if (root.suggestions.source === "forms") {
      var item = root.suggestions.items[index]
      if (item) root.replaceFinished(item.text, index)
    }
  }
  function pageSuggestions(forward) {
    if (root.suggestions.source === "fcitx") root.sendBridge(forward ? "next" : "prev")
  }

  // ---- Word suggestions --------------------------------------------------

  // What the word being typed could be, from predictor.py and wordfreq's
  // lists. Off unless turned on: a field that does not say it is a password
  // field is a password field Ragtop cannot see (see secretField), and the
  // strip would show what is being typed into it.
  //
  // off; layout, in the language of the layout being typed on (Ragtop
  // deciding by its xkb name: English on us, French on fr); or all, English
  // on any layout, the way past that decision, for a German keyboard writing
  // English. "on" and "english" are what layout was called before.
  readonly property string predictionsMode: {
    var m = root.settings["predictions"]
    return m === "on" || m === "english" ? "layout" : m === "layout" || m === "all" ? m : "off"
  }
  readonly property bool predictionsEnabled: root.predictionsMode !== "off"
  readonly property string wordsRoot: (Quickshell.env("XDG_DATA_HOME")
    || Quickshell.env("HOME") + "/.local/share") + "/ragtop/words"

  // The languages Ragtop has lists for, from the CLI's table, which is the
  // one list of them: { "fr": { size, installed, declined, name } }.
  property var wordLanguages: ({})
  function readWordLanguages() { if (!wordLanguagesProc.running) wordLanguagesProc.running = true }
  Process {
    id: wordLanguagesProc
    command: ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""), "words", "languages"]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = {}
        text.split("\n").forEach(function(line) {
          var f = line.split(" ")
          if (f.length >= 5)
            out[f[0]] = { size: f[1], installed: f[2] === "installed", declined: f[3] === "declined",
                          name: f.slice(4).join(" ") }
        })
        root.wordLanguages = out
      }
    }
  }

  // Which language a layout is typed in, by its xkb name and variant. Only
  // a guess, which the all setting is the way past.
  function languageOfLayout(code, variant) {
    if (code === "ca") return variant === "eng" ? "en" : "fr"
    if (code === "ch") return variant.indexOf("fr") === 0 ? "fr" : "de"
    if (code === "in") return variant === "eng" ? "en" : ""
    var by = { us: "en", gb: "en", au: "en", nz: "en", ie: "en", za: "en",
               fr: "fr", be: "fr", de: "de", at: "de", es: "es", latam: "es",
               pt: "pt", br: "pt", it: "it", nl: "nl", ru: "ru", ua: "uk" }
    return by[code] || ""
  }
  // The language suggestions are in now, or "" when there are none to have:
  // English on any layout, or the layout's own when Ragtop has a list for it.
  readonly property string wordLanguage: {
    if (!root.predictionsEnabled) return ""
    if (root.predictionsMode === "all") return "en"
    if (!root.keyLabels) return ""
    var lang = root.languageOfLayout(root.keyLabels.code || "", root.keyLabels.variant || "")
    return lang in root.wordLanguages ? lang : ""
  }
  onWordLanguageChanged: root.sendLanguage()
  // The language whose list the predictor has open, "" until it says.
  property string wordsLoaded: ""
  readonly property bool wordsReady: root.wordLanguage !== "" && root.wordsLoaded === root.wordLanguage
  function sendLanguage() {
    if (predictorProc.running && root.wordLanguage !== "")
      predictorProc.write("lang " + root.wordLanguage + "\n")
  }

  // A language Ragtop has a list for and has not fetched is offered in the
  // strip, where its words would go, one tap to fetch it: the only way a
  // list is downloaded without being asked for by name. "Not now" is kept,
  // and the CLI can fetch it any time.
  property bool wordsFetching: false
  readonly property string offerLanguage: {
    var lang = root.wordLanguage
    var info = root.wordLanguages[lang]
    return lang !== "" && info && !info.installed && !info.declined
      && !root.imeComposing && !root.secretField ? lang : ""
  }
  onOfferLanguageChanged: root.showOffer()
  onWordsFetchingChanged: root.showOffer()
  function showOffer() {
    var lang = root.offerLanguage
    if (lang === "") {
      root.setSuggestions("offer", null)
      return
    }
    var info = root.wordLanguages[lang]
    root.setSuggestions("offer", { items: root.wordsFetching
      ? [{ text: "Fetching " + info.name + " words\u2026", note: "" }]
      : [{ text: "Add " + info.name + " word suggestions", note: info.size + " KB" },
         { text: "Not now", note: "" }], prev: false, next: false, cursor: -1 })
  }
  function answerOffer(index) {
    var lang = root.offerLanguage
    if (lang === "" || root.wordsFetching || index > 1) return
    wordsOfferProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                              "words", index === 0 ? "install" : "decline", lang]
    root.wordsFetching = index === 0
    wordsOfferProc.running = true
  }
  Process {
    id: wordsOfferProc
    onExited: {
      root.wordsFetching = false
      root.readWordLanguages()
      // A list fetched is opened straight away.
      root.sendLanguage()
    }
  }
  // The one password prompt Ragtop can see: Omarchy's polkit agent, whose
  // patched clone types with this keyboard.
  readonly property bool passwordOpen: root.openOverlays.indexOf("omarchy-polkit") !== -1

  // What kind of field has focus, from fcitx5 through the bridge:
  // { password, terminal, noCapitals }, or null when there is no telling.
  property var fieldInfo: null
  // A password or sensitive field, in an application or in Omarchy's prompt.
  // Nothing typed into one is kept: not the field's text, not the word, not a
  // swipe, and nothing is suggested or capitalised there. What was held when
  // it took focus is let go, and the helper forgets which characters it had
  // to look up once it is left.
  readonly property bool secretField: root.passwordOpen || (!!root.fieldInfo && root.fieldInfo.password)
  onSecretFieldChanged: {
    root.typedTail = ""
    root.typedFromStart = false
    root.sentenceStart = false
    root.currentWord = ""
    root.swipedWord = ""
    root.autoSpaced = false
    root.setFinished("", "", false)
    if (["predict", "swipe", "forms"].indexOf(root.suggestions.source) !== -1)
      root.setSuggestions(root.suggestions.source, null)
    if (!root.secretField && keyboardHelper.running) keyboardHelper.write("forget\n")
  }
  readonly property bool predicting: root.predictionsEnabled && root.wordsReady
    && !root.imeComposing && !root.secretField && !root.atPrompt
  onPredictingChanged: {
    root.currentWord = ""
    if (!root.predicting) root.setSuggestions("predict", null)
  }

  // The word being typed, as far as the keys sent say. Only a guess: a tap
  // in the text moves the cursor without a key, so anything that is not a
  // letter, BackSpace aside, starts again rather than guess further.
  property string currentWord: ""
  property real backSpaceDownAt: 0
  function trackWord(command) {
    if (root.secretField) {
      root.currentWord = ""
      return
    }
    // Anything typed after a swipe makes its word final.
    if (root.swipedWord !== "") {
      root.swipedWord = ""
      if (root.suggestions.source === "swipe") root.setSuggestions("swipe", null)
    }
    var space = command.indexOf(" ")
    var cmd = space < 0 ? command : command.slice(0, space)
    var arg = space < 0 ? "" : command.slice(space + 1)
    if (cmd === "type") {
      var letters = arg.length > 0
      for (var i = 0; i < arg.length; i++)
        if (arg[i] !== "'" && arg[i].toLowerCase() === arg[i].toUpperCase()) letters = false
      root.currentWord = letters ? root.currentWord + arg : ""
    } else if (arg === "BackSpace" && (cmd === "key" || cmd === "down")) {
      root.currentWord = root.currentWord.slice(0, -1)
      if (cmd === "down") root.backSpaceDownAt = Date.now()
    } else if (cmd === "up" && arg === "BackSpace") {
      // Held long enough to repeat, it took an unknown number of letters.
      if (Date.now() - root.backSpaceDownAt > 400) root.currentWord = ""
    } else if (cmd !== "up" && cmd !== "hold" && cmd !== "release" && cmd !== "route") {
      root.currentWord = ""
    }
  }
  onCurrentWordChanged: {
    if (!root.predicting) return
    if (root.currentWord === "") {
      root.setSuggestions("predict", null)
    } else if (predictorProc.running) {
      root.asked.push(root.currentWord)
      predictorProc.write("complete " + root.currentWord + "\n")
    }
  }
  // The words asked about, oldest first, which the answers come back in the
  // order of. An answer for a word that has since changed is dropped: fast
  // typing otherwise had one arrive after a space, offering words for what
  // was no longer being typed, and taking one deleted nothing.
  property var asked: []

  // Swaps the word typed so far for the one chosen, and a space after it,
  // the way a phone keyboard does.
  function takeWord(index) {
    var item = root.suggestions.items[index]
    if (item) root.typeInPlace(item.text)
  }
  function typeInPlace(text) {
    // No word in progress means these were for one already finished.
    if (!keyboardHelper.running || root.currentWord === "") return
    var out = ""
    for (var i = 0; i < root.currentWord.length; i++) out += "key BackSpace\n"
    root.writeKeys(out + "type " + text + " \n")
    root.currentWord = ""
    root.autoSpaced = true
    root.setFinished(text, " ", false)
  }

  // A word's other forms, for a hold on it in the strip: summed and sums
  // for sum. The answer comes as formsArrived, for the keyboard to offer.
  signal formsArrived(string word, var forms)
  property var formsAsked: []
  function askForms(word) {
    if (!predictorProc.running || word === "") return
    root.formsAsked.push(word)
    predictorProc.write("forms " + word + "\n")
  }
  // One taken from the card, in the place of whatever the strip was
  // offering for: the word being typed, the word a swipe typed, or the word
  // just finished.
  function takeForm(text) {
    if (root.suggestions.source === "predict") root.typeInPlace(text)
    else if (root.suggestions.source === "swipe") root.swapTo(text, -1)
    else if (root.suggestions.source === "forms") root.replaceFinished(text, -1)
  }

  // ---- Terminals ------------------------------------------------------------

  // In a terminal the strip offers a command line's parts rather than
  // English (predictor.py, Terminal): commands, then files and folders from
  // the terminal's folder. Only for a line Ragtop typed all of since the last
  // Enter, which typedTail holds, since it cannot see one recalled with Up or
  // typed on the physical keyboard, and offers nothing rather than guess.
  // Part of word suggestions, and never in a password field.
  //
  // Only at the shell's prompt, though: a terminal is often running
  // something else, Claude Code, vim, less, where what is typed is that
  // program's and mostly prose, and English and swipe stay. Which program
  // holds the terminal is the kernel's to say (the shell's foreground
  // process group), and it can change with no focus change at all, so it is
  // read again every moment the keyboard is up in a terminal. Not known yet
  // counts as not the prompt.
  property string termForeground: ""
  readonly property bool atPrompt: root.inTerminal && root.termForeground !== ""
    && root.termForeground === root.termShell
  readonly property bool terminalSuggesting: root.predictionsEnabled && root.atPrompt
    && !root.secretField && !root.imeComposing
  // The command line as Ragtop typed it, or null when it does not know it.
  readonly property var termLine: {
    var t = root.beforeCursor
    var nl = t.lastIndexOf("\n")
    return nl >= 0 ? t.slice(nl + 1) : root.typedFromStart ? t : null
  }
  // The terminal's folder and shell, from Omarchy's own way of finding the
  // folder (omarchy-cmd-terminal-cwd) and the same shell process's name.
  property string termCwd: ""
  property string termShell: "bash"
  function readTermPlace() {
    if (root.inTerminal && !termPlaceProc.running) termPlaceProc.running = true
  }
  Process {
    id: termPlaceProc
    command: ["bash", "-c", 'cwd=$(omarchy-cmd-terminal-cwd 2>/dev/null); '
      + 'pid=$(hyprctl activewindow 2>/dev/null | awk \'/pid:/ {print $2}\'); '
      + 'sp=$(pgrep -P "$pid" | tail -n1); '
      + 'shell=$(basename "$(readlink -f /proc/$sp/exe 2>/dev/null)" 2>/dev/null); '
      + 'fg=$(cat /proc/$(awk \'{print $8}\' /proc/$sp/stat 2>/dev/null)/comm 2>/dev/null); '
      + 'printf "%s\\t%s\\t%s\\n" "$cwd" "${shell:-bash}" "$fg"']
    stdout: StdioCollector {
      onStreamFinished: {
        var f = text.replace(/\n$/, "").split("\t")
        if (f.length === 3 && f[0].charAt(0) === "/") {
          var moved = f[0] !== root.termCwd
          root.termCwd = f[0]
          root.termShell = f[1] || "bash"
          root.termForeground = f[2]
          // A terminal just focused, at its shell's prompt, is taken to be at
          // an empty line, which is what a prompt mostly is. Otherwise its
          // line is unknown until an Enter, and the strip offered nothing at
          // all. A half-typed line left in it makes a first suggestion wrong,
          // and nothing happens without a tap.
          if (root.termJustFocused) {
            root.termJustFocused = false
            if (root.atPrompt && root.typedTail === "" && !root.typedFromStart) {
              root.typedFromStart = true
              root.typedCursor = 0
              moved = true
            }
          }
          if (moved) root.askTerm()
        }
      }
    }
  }
  Timer {
    interval: 1500
    repeat: true
    running: root.inTerminal && root.oskVisible && root.predictionsEnabled
    onTriggered: root.readTermPlace()
  }
  onAtPromptChanged: {
    root.setSuggestions("term", null)
    root.askTerm()
  }
  onInTerminalChanged: {
    root.setSuggestions("term", null)
    root.termForeground = ""
    root.readTermPlace()
  }
  // Set on every window focus, two terminals of one class included, which a
  // change of class would miss (the activewindow handler).
  property bool termJustFocused: false
  property var termAsked: []
  function askTerm() {
    var line = root.termLine
    if (!root.terminalSuggesting || line === null || root.termCwd === "" || !predictorProc.running) {
      root.setSuggestions("term", null)
      return
    }
    root.termAsked.push(line)
    predictorProc.write("term " + JSON.stringify({ cwd: root.termCwd, line: line, shell: root.termShell }) + "\n")
  }
  onTermLineChanged: {
    root.askTerm()
    // An Enter may have run cd.
    if (root.termLine === "") root.readTermPlace()
  }
  function termAnswer(found) {
    var forLine = root.termAsked.shift()
    if (!root.terminalSuggesting || forLine !== root.termLine) return
    root.setSuggestions("term", { items: found, prev: false, next: false, cursor: -1 })
  }
  // A suggestion in place of the word being typed: a command or file with a
  // space after it, a folder without, to go on into.
  function takeTerm(index) {
    var item = root.suggestions.items[index]
    if (!item || !keyboardHelper.running || root.termLine === null) return
    var out = ""
    for (var i = 0; i < (item.back | 0); i++) out += "key BackSpace\n"
    root.writeKeys(out + "type " + item.text + (item.kind === "dir" ? "" : " ") + "\n")
  }

  // ---- The word just finished --------------------------------------------

  // The almost-right word is usually noticed just after it is done: sum,
  // and a space, when summed was meant. So a word just finished, typed and
  // spaced, taken from the strip, or swiped, is remembered with what
  // followed it, and when nothing more is typed for a moment the strip
  // offers its other forms, a swipe's runners-up first. A tap swaps the
  // word for one in place. Anything typed after it lets it go. In the
  // strip, so nothing covers a key at the moment someone may be about to
  // tap one, which a card would.
  property var finished: null       // { word, tail, swiped }
  readonly property int formsAfter: 1000
  property bool finishedFormsAsked: false
  function setFinished(word, tail, swiped) {
    if (root.secretField) word = ""
    root.finished = word !== "" ? { word: word, tail: tail, swiped: swiped } : null
    root.finishedFormsAsked = false
    if (root.finished && root.predicting) finishedPause.restart()
    else finishedPause.stop()
  }
  Timer {
    id: finishedPause
    interval: root.formsAfter
    onTriggered: {
      if (!root.finished || !root.predicting) return
      root.finishedFormsAsked = true
      root.askForms(root.finished.word)
    }
  }
  function finishedForms(word, forms) {
    var f = root.finished
    if (!root.finishedFormsAsked || !f || word !== f.word || !root.predicting) return
    root.finishedFormsAsked = false
    var items = []
    // A swipe's runners-up stay first: a wrong word is likelier than a
    // wrong form of the right one.
    if (f.swiped && root.suggestions.source === "swipe")
      items = root.suggestions.items.filter(function(i) { return i.text !== f.word })
    forms.forEach(function(w) {
      if (!items.some(function(i) { return i.text === w })) items.push({ text: w, note: "" })
    })
    if (items.length > 0)
      root.setSuggestions("forms", { items: items, prev: false, next: false, cursor: -1 })
  }
  // The finished word swapped for `text`, keeping what followed it.
  function replaceFinished(text, index) {
    var f = root.finished
    if (!f || !keyboardHelper.running) return
    var out = ""
    for (var i = 0; i < f.word.length + f.tail.length; i++) out += "key BackSpace\n"
    root.writeKeys(out + "type " + text + f.tail + "\n")
    if (f.swiped) root.swipedWord = root.swipeLead + text + f.tail
    root.finished = { word: text, tail: f.tail, swiped: f.swiped }
    root.autoSpaced = true
    if (index >= 0) root.setSuggestions("forms", { items: root.suggestions.items, prev: false,
                                                   next: false, cursor: index })
  }

  // ---- Swipes ------------------------------------------------------------

  // A word drawn across the letters, decoded by predictor.py against the
  // same list (Keyboard.qml draws and sends the path). Off unless turned on,
  // since it changes what a finger moving over the keys means.
  readonly property bool swipeEnabled: root.settings["swipe"] === "on"
  // Only ever with suggestions: the same words, and its runners-up in the
  // same strip.
  readonly property bool swipeActive: root.swipeEnabled && root.predicting
  onSwipeActiveChanged: if (!root.swipeActive) root.setSuggestions("swipe", null)
  property var swipeKeys: null
  function setSwipeKeys(value) {
    root.swipeKeys = value
    if (predictorProc.running) predictorProc.write("keys " + JSON.stringify(value) + "\n")
  }
  // The word the last swipe typed, with its spaces, so a tap on one of the
  // others can take it back; and whether it began with a capital.
  property string swipedWord: ""
  // The space a swipe put in front of its word, or "". A swipe after letters
  // that were tapped starts a word of its own: "a" can only be tapped, and
  // "a" then a swiped "test" ran together as "atest". After a space, a
  // swipe, or a chosen suggestion there is nothing to separate.
  property string swipeLead: ""
  property bool swipeShifted: false
  // The guess so far, while a finger is still drawing: Keyboard.qml calls
  // this as the path grows. One guess is asked for at a time, and the next
  // waits for its answer and then takes the path as it is by then, so a
  // slow answer is never queued behind others that are already stale.
  property bool swipeDrawing: false
  property bool peekPending: false
  property var peekPath: null
  function swipeDrawn(points) {
    if (!root.swipeActive || !predictorProc.running) return
    root.swipeDrawing = true
    root.peekPath = points
    if (!root.peekPending) root.sendPeek()
  }
  function sendPeek() {
    var path = root.peekPath
    root.peekPath = null
    if (!path) return
    root.peekPending = true
    predictorProc.write("peek " + JSON.stringify(path.map(function(p) {
      return [Math.round(p[0]), Math.round(p[1])]
    })) + "\n")
  }
  function peeked(words) {
    root.peekPending = false
    // A guess that lands after the finger has lifted is already out of date.
    if (!root.swipeDrawing) return
    if (words.length > 0)
      root.setSuggestions("swipe", { items: words.map(function(w) { return { text: w, note: "" } }),
                                     prev: false, next: false, cursor: 0 })
    if (root.peekPath) root.sendPeek()
  }
  // A swipe that ended without a word, cancelled by a rotation: its guesses
  // go with it.
  function swipeAbandoned() {
    if (!root.swipeDrawing) return
    root.swipeDrawing = false
    root.peekPath = null
    if (root.suggestions.source === "swipe" && root.swipedWord === "")
      root.setSuggestions("swipe", null)
  }
  function swipe(points, shifted) {
    root.swipeDrawing = false
    root.peekPath = null
    if (!root.swipeActive || !predictorProc.running) return
    root.swipeShifted = shifted
    predictorProc.write("swipe " + JSON.stringify(points.map(function(p) {
      return [Math.round(p[0]), Math.round(p[1])]
    })) + "\n")
  }
  function capitalised(word) {
    return root.swipeShifted ? word.charAt(0).toUpperCase() + word.slice(1) : word
  }
  function typeSwiped(words) {
    if (!root.swipeActive || !keyboardHelper.running) return
    if (words.length === 0) {
      // Nothing it could spell: the guesses shown while drawing go too.
      if (root.suggestions.source === "swipe") root.setSuggestions("swipe", null)
      return
    }
    root.swipeLead = root.currentWord !== "" ? " " : ""
    var word = root.swipeLead + root.capitalised(words[0]) + " "
    root.writeKeys("type " + word + "\n")
    root.currentWord = ""
    root.swipedWord = word
    root.autoSpaced = true
    root.setFinished(root.capitalised(words[0]), " ", true)
    root.setSuggestions("swipe", { items: words.map(function(w) { return { text: root.capitalised(w), note: "" } }),
                                   prev: false, next: false, cursor: 0 })
  }
  function swapSwiped(index) {
    var item = root.suggestions.items[index]
    if (item) root.swapTo(item.text, index)
  }
  // Swaps the swiped word for `text`, and marks `index` in the strip as the
  // one now typed (-1 for a word from elsewhere, a form off the card).
  function swapTo(text, index) {
    if (!keyboardHelper.running || root.swipedWord === "") return
    var out = ""
    for (var i = 0; i < root.swipedWord.length; i++) out += "key BackSpace\n"
    var word = root.swipeLead + text + " "
    root.writeKeys(out + "type " + word + "\n")
    root.swipedWord = word
    root.autoSpaced = true
    root.setFinished(text, " ", true)
    root.setSuggestions("swipe", { items: root.suggestions.items, prev: false, next: false, cursor: index })
  }

  readonly property bool wantPredictor: root.keyboardAvailable && root.predictionsEnabled

  // The controls panel's switches. Through the CLI, which is what fetches
  // the word list when it is missing and says so.
  function toggleSetting(name) {
    if (settingToggleProc.running) return   // a second tap mid-write would be lost
    settingToggleProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                                 name, "toggle"]
    settingToggleProc.running = true
  }
  Process { id: settingToggleProc }
  onWantPredictorChanged: {
    predictorRestart.stop()
    predictorProc.running = root.wantPredictor
  }
  Process {
    id: predictorProc
    command: ["/usr/bin/python3", Qt.resolvedUrl("predictor.py").toString().replace(/^file:\/\//, ""),
              root.wordsRoot]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line.startsWith("ready ")) {
          root.wordsLoaded = line.split(" ")[1]
          root.sendRows()
          if (root.swipeKeys) predictorProc.write("keys " + JSON.stringify(root.swipeKeys) + "\n")
        } else if (line.startsWith("missing ")) {
          root.wordsLoaded = ""
          // The CLI may know better by now: a list removed by hand.
          root.readWordLanguages()
        } else if (line.startsWith("termsuggest ")) {
          var found
          try { found = JSON.parse(line.slice(12)) } catch (e) { root.termAsked.shift(); return }
          root.termAnswer(found)
        } else if (line.startsWith("forms ")) {
          var forWhat = root.formsAsked.shift()
          var forms
          try { forms = JSON.parse(line.slice(6)) } catch (e) { return }
          if (forWhat === undefined) return
          root.finishedForms(forWhat, forms)
          root.formsArrived(forWhat, forms)
        } else if (line.startsWith("peeked ")) {
          var guess
          try { guess = JSON.parse(line.slice(7)) } catch (e) { root.peekPending = false; return }
          root.peeked(guess)
        } else if (line.startsWith("swiped ")) {
          var found
          try { found = JSON.parse(line.slice(7)) } catch (e) { return }
          root.typeSwiped(found)
        } else if (line.startsWith("suggest ")) {
          var forWord = root.asked.shift()
          if (!root.predicting || forWord !== root.currentWord) return
          var words
          try { words = JSON.parse(line.slice(8)) } catch (e) { return }
          root.setSuggestions("predict", { items: words.map(function(w) { return { text: w, note: "" } }),
                                           prev: false, next: false, cursor: -1 })
        }
      }
    }
    onRunningChanged: {
      root.asked = []
      root.formsAsked = []
      root.termAsked = []
      root.peekPending = false
      root.wordsLoaded = ""
      if (running) {
        root.retryStarted("predict")
        root.sendLanguage()
      }
    }
    onExited: {
      if (!root.wantPredictor) return
      predictorRestart.interval = root.retryAfterExit("predict")
      predictorRestart.start()
      root.retryTell("predict")
    }
  }
  Timer {
    id: predictorRestart
    interval: 5000
    onTriggered: predictorProc.running = root.wantPredictor
  }
  // The layout's letter rows, so a slip is judged by which keys are really
  // neighbours on it.
  function sendRows() {
    if (!predictorProc.running || !root.keyLabels || !Array.isArray(root.keyLabels.rows)) return
    predictorProc.write("rows " + JSON.stringify(root.keyLabels.rows.map(function(row) {
      return row.map(function(k) { return k[0] })
    })) + "\n")
  }

  function openSettings() {
    Quickshell.execDetached(["omarchy", "menu", "summon", "setup.tablet"])
  }

  // What the controls tile asks for. Rotation is kept by the bar widget,
  // inline on its own shell.json entry, so the tile asks the widget rather
  // than reaching for a file it does not own.
  // Asks for a state rather than a step: there is one bar widget per screen
  // and every one of them hears this, so setRotationMode settling on the
  // named mode is safe where cycling would have each screen advance it again
  // and land somewhere nobody asked for.
  // Ragtop's controls, on their own surface above the keyboard. They go away
  // with it, so they can never be left floating over nothing.
  property bool toolsOpen: false

  // ---- window management -------------------------------------------------

  // What the keyboard's windows page can do, by name. The keyboard asks for
  // a name and this looks it up, so a name is the only thing that ever
  // crosses into a command line and an unknown one does nothing. These are
  // the same dispatches the bar's popup used to run, which is where they
  // came from.
  readonly property var windowActions: ({
    // True fullscreen is deliberately not here. It covers the whole monitor,
    // reserved space and all, so the keyboard and the bar both go under it
    // and the only two ways back are invisible. On a machine that is folded
    // shut there is no third way, and the toggle that would undo it is the
    // key you can no longer see. Maximized gets the same "make this big"
    // without taking the way out with it.
    "wide": 'hl.dsp.window.fullscreen({ mode = "maximized" })',
    // Omarchy's own SUPER + CTRL + F. The window keeps its place in the
    // layout and only the client is told it is fullscreen, so an app drops
    // its chrome while the bar and the keyboard stay exactly where they are.
    // This is the fullscreen a machine with no other keyboard can afford.
    "tiled": 'hl.dsp.exec_cmd("omarchy-hyprland-window-tiled-fullscreen-toggle")',
    "float": 'hl.dsp.window.float({ action = "toggle" })',
    "split": 'hl.dsp.layout("togglesplit")',
    "scratch": 'hl.dsp.workspace.toggle_special("scratchpad")',
    "toscratch": 'hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })'
  })
  // One process per tap, so quick repeated taps are not dropped.
  property Component windowActionProc: Component { Process { onExited: destroy() } }
  // How the workspace arranges its windows, which Hyprland keeps as
  // general:layout. Read rather than assumed, because Omarchy ships dwindle
  // and a user may already be on something else.
  //
  // This is Hyprland's global layout, not one workspace's. Nothing in
  // Hyprland lets a workspace carry its own without a rule written ahead of
  // time, so the button says what it does and does not pretend otherwise.
  property string workspaceLayout: ""
  // What to go back to. Coming off scrolling on a machine set up for master
  // should give master back rather than quietly converting it to dwindle,
  // which is what a plain two way toggle would have done.
  property string layoutBefore: ""
  readonly property bool scrollingLayout: root.workspaceLayout === "scrolling"

  Process {
    id: layoutReadProc
    command: ["hyprctl", "getoption", "general:layout", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var v = JSON.parse(text)
          if (v && typeof v.str === "string") root.workspaceLayout = v.str.trim()
        } catch (e) {}
      }
    }
  }

  function toggleWorkspaceLayout() {
    if (layoutSetProc.running) return
    var next
    if (root.scrollingLayout) {
      next = root.layoutBefore !== "" ? root.layoutBefore : "dwindle"
    } else {
      root.layoutBefore = root.workspaceLayout
      next = "scrolling"
    }
    layoutSetProc.command = ["hyprctl", "eval",
      "hl.config({ general = { layout = \"" + next + "\" } })"]
    layoutSetProc.running = true
  }

  Process {
    id: layoutSetProc
    onExited: {
      // Read it back rather than assuming it took. A layout Hyprland does not
      // have would leave the button lit for something that never happened.
      layoutReadProc.running = true
      // Changing the layout rearranges every window, and Hyprland sends no
      // event for it, so the outlines have to be told to catch up.
      if (root.tilingOpen) {
        tilingIdle.restart()
        tilingSettle.restart()
      }
    }
  }

  function runWindowAction(name) {
    var lua = root.windowActions[name]
    if (!lua) return
    var proc = root.windowActionProc.createObject(root,
      { command: ["hyprctl", "eval", "hl.dispatch(" + lua + ")"] })
    if (proc) proc.running = true
    // The bar's own buttons land here. Two things follow from that.
    //
    // Whatever this dispatched moved or resized something, and only some of
    // them emit an event saying so. togglesplit emits nothing at all, which
    // is why Split left the outlines drawn around the old shape while the
    // windows underneath had already changed. Say so rather than depending
    // on which dispatch happens to be noisy.
    //
    // And a tap on the bar is someone using the mode, so it is not idle.
    // Without this the ninety second timeout ran while you were working.
    if (root.tilingOpen) {
      // Read twice for the two that change a window's fullscreen state.
      // What the bar shows there is fullscreenClient, which is Hyprland's
      // record of what it last told the window rather than anything the
      // window has confirmed, and the application repaints on its own
      // schedule. One read 260ms later can land between the two and latch a
      // value that is already wrong. A second read a beat behind costs one
      // hyprctl call and catches it.
      if (name === "tiled" || name === "wide") tilingSettle.again = 1
      tilingSettle.restart()
      tilingIdle.restart()
    }
  }

  // Which workspaces the strip offers, by Omarchy's own rule: always 1 to 5,
  // plus any other that exists up to 10. Copied from its Workspaces widget
  // so the keyboard and the bar never disagree about what there is.
  readonly property var workspaceIds: {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(a, b) { return a - b })
    return ids
  }
  readonly property int focusedWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  // The workspace tiling mode is about, which is the one on Ragtop's own
  // screen and not the one with keyboard focus. The outlines already came
  // from here. The strip did not, so with focus on another monitor it lit
  // the number of a workspace whose windows were nowhere on screen. Falls
  // back to the focused one, which is the right answer on one monitor and
  // the only answer before Hyprland has reported a monitor at all.
  readonly property int tilingWorkspace: {
    var m = root.keyboardMonitor
    return m && m.activeWorkspace ? m.activeWorkspace.id : root.focusedWorkspace
  }

  // A number rather than a name, checked against the range Hyprland has, so
  // the only thing that reaches a command line is a digit this decided on.
  function workspaceLua(id, send) {
    var n = parseInt(id, 10)
    if (!(n >= 1 && n <= 10)) return ""
    return send ? 'hl.dsp.window.move({ workspace = "' + n + '" })'
                : 'hl.dsp.focus({ workspace = "' + n + '" })'
  }
  // Hyprland switches the workspace on whichever monitor has focus, so a tap
  // on the strip used to change a screen you were not looking at while the
  // outlines beside it stayed where they were. Ragtop's own monitor is taken
  // first, which is a no-op on one screen and names the right one on more.
  // Only for going to a workspace: sending a window somewhere follows the
  // window, which is already on this screen.
  function runWorkspace(id, send) {
    var lua = root.workspaceLua(id, send)
    if (lua === "") return
    var name = root.keyboardMonitorName
    var pre = (!send && name !== "")
      ? "hl.dispatch(hl.dsp.focus({ monitor = '" + name + "' })) " : ""
    var proc = root.windowActionProc.createObject(root,
      { command: ["hyprctl", "eval", pre + "hl.dispatch(" + lua + ")"] })
    if (proc) proc.running = true
    // The bar's own buttons land here. Two things follow from that.
    //
    // Whatever this dispatched moved or resized something, and only some of
    // them emit an event saying so. togglesplit emits nothing at all, which
    // is why Split left the outlines drawn around the old shape while the
    // windows underneath had already changed. Say so rather than depending
    // on which dispatch happens to be noisy.
    //
    // And a tap on the bar is someone using the mode, so it is not idle.
    // Without this the ninety second timeout ran while you were working.
    if (root.tilingOpen) {
      tilingSettle.restart()
      tilingIdle.restart()
    }
  }

  // ---- tiling mode -------------------------------------------------------

  // A transparent layer over the real windows, for rearranging them by hand.
  // It draws outlines and nothing solid: the whole reason to do this over the
  // windows instead of over a map is that their content is visible and
  // reflows as you work, and a panel on top of a window is a panel you cannot
  // judge a split through.
  //
  // Phase one only shows where the windows are and gets out of the way again.
  // Nothing here moves or resizes anything yet. What it does prove is the
  // geometry matching, the timing around the keyboard's exclusive zone, and
  // every way back out.
  // The Send latch, which used to live on the keyboard's windows page. Off,
  // then armed for the next workspace, then locked, then off, the same
  // ladder Shift climbs and the same one Omarchy spells as SUPER versus
  // SUPER + SHIFT.
  property string sendMod: "off"
  function stepSendMod() {
    root.sendMod = root.sendMod === "off" ? "latched"
      : root.sendMod === "latched" ? "locked" : "off"
  }
  function takeWorkspace(id) {
    root.runWorkspace(id, root.sendMod !== "off")
    if (root.sendMod === "latched") root.sendMod = "off"
  }
  function takeScratchpad() {
    root.runWindowAction(root.sendMod !== "off" ? "toscratch" : "scratch")
    if (root.sendMod === "latched") root.sendMod = "off"
  }

  // How many times the focus bridge has asked for the keyboard. Zero after a
  // long session is the signature of an input method gone quiet: everything
  // reports healthy and nothing ever comes up.
  property int autoShows: 0

  // Whether a special workspace is showing on Ragtop's screen. The scratchpad
  // is not the focused workspace while it is up: it is an overlay, and it
  // lives in the monitor's own specialWorkspace rather than in
  // focusedWorkspace, so asking the usual place says no every time.
  property bool specialShown: false

  property bool tilingOpen: false
  property var tilingWindows: []
  // The window the shape buttons act on, so the bar can say what is already
  // true rather than offering a toggle with no state on it.
  readonly property var tilingFocused: {
    for (var i = 0; i < root.tilingWindows.length; i++)
      if (root.tilingWindows[i].focused) return root.tilingWindows[i]
    return null
  }

  function openTiling() {
    // The keyboard's strip is reserved, so hiding it first lets the windows
    // reflow to the full screen. The list is read after that settles, or the
    // outlines would be drawn around where the windows used to be.
    root.setOskVisible(false)
    root.tilingOpen = true
    layoutReadProc.running = true
    specialReadProc.running = true
    tilingIdle.restart()
    tilingSettle.restart()
  }
  // Done came from the keyboard, so it goes back to it. A timeout or tablet
  // mode ending did not, and putting a keyboard up for nobody would only
  // shrink the windows again.
  function closeTiling(restore) {
    // Cleared before the keyboard is asked for, or the rule below would see
    // it come up and call this a second time.
    root.tilingOpen = false
    root.sendMod = "off"
    tilingIdle.stop()
    tilingSettle.stop()
    if (restore) root.setOskVisible(true)
  }

  // The keyboard and this mode are exclusive: entering hides the keyboard,
  // and the keyboard coming back by any route ends the mode. That is the
  // handle, auto-show on a text field, and the bar's own button.
  //
  // It is also the fix for a real fault. The keyboard's exclusive zone
  // changing relayouts every window, and Hyprland emits no resizewindow for
  // that, so the event-driven refresh never fired and the outlines sat over
  // a keyboard, around windows that had already shrunk away from them.
  // Focus a window by its address. Checked against the shape Hyprland gives
  // them before it goes anywhere, so the only thing that reaches a command
  // line is an address this recognised.
  function focusWindow(address) {
    if (!/^0x[0-9a-f]+$/.test(address)) return
    var proc = root.windowActionProc.createObject(root,
      { command: ["hyprctl", "eval",
                  "hl.dispatch(hl.dsp.focus({ window = \"address:" + address + "\" }))"] })
    if (proc) proc.running = true
    tilingIdle.restart()
  }

  // Resize by a relative delta, as fast as a finger can ask for it.
  //
  // One hyprctl at a time: a drag asks far more often than a process can
  // answer, so the newest ask is held while one is in flight and sent when
  // it finishes, adding up anything that arrived meanwhile. Nothing is
  // dropped and nothing queues up behind the finger. The size slider learnt
  // this the same way.
  property var resizeHeld: null
  property bool resizeBusy: false

  function resizeWindow(address, dx, dy) {
    if (!/^0x[0-9a-f]+$/.test(address)) return
    if (dx === 0 && dy === 0) return
    if (root.resizeBusy) {
      if (root.resizeHeld && root.resizeHeld.address === address) {
        root.resizeHeld.dx += dx
        root.resizeHeld.dy += dy
      } else {
        root.resizeHeld = { address: address, dx: dx, dy: dy }
      }
      return
    }
    root.sendResize(address, dx, dy)
  }

  function sendResize(address, dx, dy) {
    root.resizeBusy = true
    resizeProc.command = ["hyprctl", "eval",
      "hl.dispatch(hl.dsp.window.resize({ window = \"address:" + address
      + "\", x = " + Math.round(dx) + ", y = " + Math.round(dy)
      + ", relative = true }))"]
    resizeProc.running = true
    // Hyprland emits no geometry event for a resize asked for this way, and
    // an outline drawn where a window used to be is not only wrong to look
    // at: windowAt reads these same rectangles to decide what a drag lands
    // on, so a stale one picks the wrong window to swap with.
    tilingIdle.restart()
    tilingSettle.restart()
  }

  Process {
    id: resizeProc
    onExited: {
      root.resizeBusy = false
      var held = root.resizeHeld
      root.resizeHeld = null
      if (held) {
        root.sendResize(held.address, held.dx, held.dy)
        return
      }
      // Read the geometry back the moment the resize lands, so the outlines
      // keep up with the windows. Resizing a tile moves its neighbour as
      // well, so guessing the new shape locally would draw one of them
      // right and the other wrong. This rides the resize rate, which is
      // already limited to one at a time.
      if (root.tilingOpen && !tilingClientsProc.running)
        tilingClientsProc.running = true
    }
  }

  // A floating window has no splits, and a relative resize grows it from
  // the centre, which can never move one edge on its own. So its rectangle
  // is set outright instead: position and size in one dispatch, latest ask
  // wins, no deltas to accumulate and nothing to drift.
  property var geomHeld: null
  property bool geomBusy: false

  function setWindowGeom(address, x, y, w, h) {
    if (!/^0x[0-9a-f]+$/.test(address)) return
    if (root.geomBusy) {
      root.geomHeld = { address: address, x: x, y: y, w: w, h: h }
      return
    }
    root.sendGeom(address, x, y, w, h)
  }

  function sendGeom(address, x, y, w, h) {
    root.geomBusy = true
    var win = "\"address:" + address + "\""
    geomProc.command = ["hyprctl", "eval",
      "hl.dispatch(hl.dsp.window.resize({ window = " + win
        + ", x = " + Math.round(w) + ", y = " + Math.round(h) + " })) "
      + "hl.dispatch(hl.dsp.window.move({ window = " + win
        + ", x = " + Math.round(x) + ", y = " + Math.round(y) + " }))"]
    geomProc.running = true
    // As above. Setting a floating window's geometry moves it with no event
    // to say so.
    tilingIdle.restart()
    tilingSettle.restart()
  }

  Process {
    id: geomProc
    onExited: {
      root.geomBusy = false
      var held = root.geomHeld
      root.geomHeld = null
      if (held) {
        root.sendGeom(held.address, held.x, held.y, held.w, held.h)
        return
      }
      if (root.tilingOpen && !tilingClientsProc.running)
        tilingClientsProc.running = true
    }
  }

  // Swap two windows by address. A tile has no free position, so dropping
  // one on another is an exchange rather than a move, and Hyprland takes
  // both addresses for it, which means no guessing a direction from the
  // drag.
  function swapWindows(from, to) {
    if (from === to) return
    if (!/^0x[0-9a-f]+$/.test(from) || !/^0x[0-9a-f]+$/.test(to)) return
    var proc = root.windowActionProc.createObject(root,
      { command: ["hyprctl", "eval",
                  "hl.dispatch(hl.dsp.window.swap({ window = \"address:" + from
                  + "\", target = \"address:" + to + "\" }))"] })
    if (proc) proc.running = true
    // Measured on the socket: a swap emits no movewindow and no resizewindow,
    // and it does not change focus either, so nothing arrives to notice it
    // by. Tapping a window first happened to fix it only because focusing
    // does emit activewindow. Say so directly instead.
    tilingIdle.restart()
    tilingSettle.restart()
  }

  // Read on the way in, because the scratchpad may already be up, and again
  // on every activespecial event.
  Process {
    id: specialReadProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var any = false
          JSON.parse(text).forEach(function(m) {
            // Only this screen's. A scratchpad up on another monitor put its
            // windows in the layer here, drawn at coordinates belonging to a
            // display Ragtop is not on.
            if (m.name !== root.keyboardMonitorName) return
            if (m.specialWorkspace && m.specialWorkspace.id !== 0) any = true
          })
          root.specialShown = any
        } catch (e) {}
      }
    }
  }

  Timer {
    id: tilingSettle
    interval: 260
    // Twice, a beat apart: a rotation is still settling when the first read
    // happens, and one stale set of outlines is worth a second look.
    property int again: 0
    onTriggered: {
      tilingClientsProc.running = true
      if (again > 0) {
        again--
        tilingSettle.restart()
      }
    }
  }
  Timer {
    id: tilingIdle
    interval: 90000
    onTriggered: root.closeTiling()
  }
  // Tablet mode ending takes the mode with it, along with everything else
  // that only makes sense with a screen you are holding.
  onTabletModeChanged: {
    if (root.tabletMode) return
    root.closeTiling()
    // Out of tablet mode the physical keyboard is back, and what it types
    // Ragtop does not see (finishWord).
    root.finishWord()
  }

  Process {
    id: tilingClientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.tilingOpen) return
        // The monitor this surface is actually on, not whichever one has
        // focus. Hyprland reports a window at its place across the whole
        // desktop, so the origin subtracted here has to belong to the screen
        // the outlines are drawn on. Taking the focused monitor's origin drew
        // another screen's windows onto this one, at that screen's
        // coordinates: the handles appeared over the wrong display, and
        // dragging them resized windows you were not looking at.
        var monitor = root.keyboardMonitor
        var ox = monitor ? monitor.x : 0
        var oy = monitor ? monitor.y : 0
        // And its workspace, for the same reason. The focused workspace is on
        // whichever monitor has focus, which need not be this one.
        var ws = root.tilingWorkspace
        var out = []
        try {
          JSON.parse(text).forEach(function(c) {
            if (!c.mapped || c.hidden) return
            // A special workspace is drawn over the normal one, so while it
            // is up its windows are on screen and belong in the layer too.
            if (!c.workspace) return
            if (c.workspace.id !== ws
                && !(root.specialShown && c.workspace.id < 0)) return
            if (c.size[0] <= 0 || c.size[1] <= 0) return
            out.push({ address: c.address, x: c.at[0] - ox, y: c.at[1] - oy,
                       w: c.size[0], h: c.size[1],
                       name: c.title || c["class"] || "", floating: !!c.floating,
                       // What the bar's shape buttons light from. `fullscreen`
                       // is the internal state, which maximized sets, and
                       // `fullscreenClient` is the one Omarchy's tiled toggle
                       // reads and writes, where 2 means it is on.
                       full: Number(c.fullscreen) || 0,
                       fullClient: Number(c.fullscreenClient) || 0,
                       // A key shared by every member of a group, and "" for
                       // a window in none. Sorted, so the members agree on it
                       // whichever one is being read.
                       group: Array.isArray(c.grouped) && c.grouped.length > 1
                         ? c.grouped.slice().sort().join(",") : "",
                       order: Number(c.focusHistoryID),
                       focused: c.focusHistoryID === 0 })
          })
        } catch (e) {
          return
        }
        // One row per group, not one per window in it.
        //
        // Grouped windows are tabs sharing a tile, and Hyprland reports
        // every member at the same geometry with hidden false on all of
        // them. Left alone that is N outlines, N chips and N sets of
        // handles stacked exactly on top of each other, and a tap resolves
        // by whatever the tiebreak happens to pick, possibly a tab you
        // cannot see.
        //
        // Any member will do as the handle. Measured: swapping one member
        // with another tile moves the whole group and leaves it intact, so
        // a group is a tile as far as the tree is concerned and the members
        // are interchangeable for every action here.
        //
        // The one kept is the most recently focused, which is almost always
        // the visible tab, so the title chip usually matches. It is only the
        // chip: the group's own tab bar sits above this outline and is what
        // actually says which window is on top.
        var byGroup = {}
        out = out.filter(function(w) {
          if (!w.group) return true
          var seen = byGroup[w.group]
          if (seen === undefined || w.order < seen) {
            byGroup[w.group] = w.order
            return true
          }
          return false
        }).filter(function(w) {
          return !w.group || byGroup[w.group] === w.order
        })

        // A stable order, so the model's rows never reshuffle when focus
        // or stacking changes. Reordering rebuilds every delegate, which
        // kills whatever gesture is in flight. What is drawn on top is
        // decided in the layer instead.
        out.sort(function(a, b) { return a.address < b.address ? -1 : 1 })
        root.tilingWindows = out
      }
    }
  }
  // Anything that moves a window moves an outline with it.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.tilingOpen) return
      var n = event.name
      if (n === "activespecial" && !specialReadProc.running) {
        // Asked rather than parsed out of the event. The event carries
        // "workspacename,monitorname" and this only cares about one monitor,
        // so reading the monitors back is both shorter and the authority on
        // which screen the scratchpad landed on. It fires on a scratchpad
        // toggle and nowhere near as often as the client reads do.
        specialReadProc.running = true
      }
      // The monitor ones matter because a rotation from anywhere else, the
      // bar's button or a keybinding, has to be noticed too.
      if (n === "openwindow" || n === "closewindow" || n === "movewindow"
          || n === "resizewindow" || n === "activewindow" || n === "changefloatingmode"
          || n === "fullscreen" || n === "monitorlayoutchanged"
          || n === "monitoradded" || n === "monitorremoved"
          || n === "configreloaded" || n === "activespecial") {
        tilingSettle.restart()
      }
    }
  }

  // What the bar's window button does, and the socket below with it: one
  // way in and out of tiling, so both agree about what a second tap
  // means.
  function toggleTilingMode() {
    if (root.tilingOpen) root.closeTiling(true)
    else root.openTiling()
  }
  onOskVisibleChanged: {
    // A keyboard put away is the end of whatever word it was typing.
    root.currentWord = ""
    if (!root.oskVisible) root.toolsOpen = false
    // The keyboard and tiling mode are exclusive: entering hides the
    // keyboard, and the keyboard coming back by any route ends the mode.
    // That covers the handle, auto-show on a text field, and the bar's own
    // button, and it is also the fix for a real fault: the keyboard's
    // exclusive zone changing relayouts every window, Hyprland emits no
    // resizewindow for that, so the outlines used to sit over a keyboard,
    // drawn around windows that had already shrunk away from them.
    if (root.oskVisible && root.tilingOpen) root.closeTiling()
  }


  readonly property var rotationModes: ["auto", "locked", "unlocked"]
  // Written here, to the same file as everything else. The bar widget used
  // to own this on its own shell.json entry, which meant the tile, the IPC
  // and the bar button all did nothing on a bar with no Ragtop widget on it.
  function setRotationMode(mode) {
    if (root.rotationModes.indexOf(mode) === -1 || rotationModeProc.running) return
    rotationModeProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                                "rotation", "set", mode]
    rotationModeProc.running = true
  }
  Process { id: rotationModeProc }

  // Key size against whatever the theme asked for, stepped rather than set,
  // so the keyboard needs no argument-taking IPC to offer it.
  readonly property var sizeSteps: ["smallest", "smaller", "regular", "larger", "largest"]
  // What each step does to the theme's size, defined here and nowhere else.
  // Both keyboards draw from it, the lock screen's through the style file,
  // because a second copy is how Smallest and Largest came to do nothing.
  readonly property var sizeNudges: ({ "smallest": 0.78, "smaller": 0.88, "regular": 1,
                                       "larger": 1.15, "largest": 1.3 })
  // The size setting is a percentage now, anywhere from 60 to 160, so the
  // slider moves smoothly instead of snapping through five stops. The five
  // names are still read, because they are what is written in every
  // settings.conf that existed before this and in the menu rows, which cannot
  // offer a slider. They resolve to the percentages they always meant.
  readonly property real sizeMin: 60
  readonly property real sizeMax: 160
  function sizePercent(value) {
    var raw = String(value === undefined ? root.settings["size-adjust"] : value).trim()
    if (raw in root.sizeNudges) return root.sizeNudges[raw] * 100
    var n = Number(raw)
    if (isFinite(n) && n >= root.sizeMin && n <= root.sizeMax) return n
    return 100
  }
  readonly property bool sizeAuto:
    String(root.settings["size-adjust"] || "").trim() === "auto"

  // What the screen itself says the size should be.
  //
  // How big a key is in the hand comes from one number, the pixels the screen
  // has to the millimetre, and where that number comes from is the whole
  // story: see monitorDensity below, which takes it from Hyprland because
  // Qt's own figure turns with the screen. Measured here it is 5.31 px/mm,
  // which over 1366 pixels is a 257mm panel, which is the 11.6 inch screen
  // this was written on.
  //
  // 84 logical pixels is the widest Ragtop ever draws a key at scale 1, so
  // that is what the target is measured against. A key of about a centimetre
  // and a half is a keycap, which is what a finger expects.
  //
  // It is a preference and not a promise. A key is the smaller of that cap
  // and the room the board has, so a board already filling the width cannot
  // grow into it: measured here, a tenkeyless across 1366 pixels gets 74px
  // keys whatever the scale asks for, because eighteen and a quarter units
  // have to fit. What Auto still decides there is the row height and the
  // smallest a key may be, which is what picks the board in the first place.
  readonly property real targetKeyMm: 16

  // How many pixels the screen has to the millimetre, from Hyprland rather
  // than from Qt.
  //
  // Qt's physicalPixelDensity changes when the screen is rotated, which a
  // panel cannot do: measured on this machine it reads 5.37 landscape and
  // 6.36 in portrait. Auto believed the second one, asked for keys a fifth
  // larger than it meant to, and that raised the minimum a key may be far
  // enough to throw out every real board. Turning the screen chose a
  // different keyboard, which is the opposite of what Auto is for.
  //
  // Hyprland reports the panel's millimetres and its MODE, and neither of
  // those turns with the transform, so the number is the same whichever way
  // up the machine is. Taken on the diagonal because a panel's millimetres
  // are rounded to whole numbers and the two axes disagree slightly: 260 by
  // 140 gives 5.25 across and 5.49 down, and 5.31 on the diagonal.
  property real monitorDensity: 0
  Process {
    id: densityProc
    running: true
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var want = root.keyboardMonitorName
        var found = 0
        try {
          JSON.parse(text).forEach(function(m) {
            if (m.name !== want) return
            var pw = Number(m.physicalWidth) || 0, ph = Number(m.physicalHeight) || 0
            var w = Number(m.width) || 0, h = Number(m.height) || 0
            if (pw > 0 && ph > 0 && w > 0 && h > 0)
              found = Math.sqrt(w * w + h * h) / Math.sqrt(pw * pw + ph * ph)
          })
        } catch (e) { return }
        root.monitorDensity = found
      }
    }
  }
  // Re-read when the screen Ragtop lives on changes, since the panel does.
  onKeyboardMonitorNameChanged: densityProc.running = true

  readonly property real autoSizePercent: {
    var scr = root.keyboardScreen
    if (!scr) return 100
    // Hyprland's first, and Qt's only if Hyprland gave nothing.
    var density = root.monitorDensity > 0 ? root.monitorDensity
      : (scr.physicalPixelDensity || 0)
    var dpr = scr.devicePixelRatio || 1
    // A monitor whose EDID lies about its size is worse than no answer, so
    // anything outside what a real screen can be falls back to the default.
    if (!(density > 2 && density < 25) || !(dpr > 0)) return 100
    var scale = root.targetKeyMm * density / (84 * dpr)
    // Expressed against the theme's own size, so Auto lands on the target
    // whatever a theme asked for rather than being multiplied by it.
    var themeSize = Number(root.settings["size"]) || 100
    var pct = scale / (themeSize / 100) * 100
    return Math.max(root.sizeMin, Math.min(root.sizeMax, Math.round(pct)))
  }

  // Stepping starts from the size on screen, which under Auto is whatever
  // Auto worked out and not 100. sizePercent("auto") has no number to give
  // and answers 100, so a step from Auto used to jump to 105 or 95 however
  // big the keys actually were. On a dense screen, where Auto lands at 140,
  // asking for bigger keys made them smaller.
  function stepSize(by) {
    var from = root.lastAskedSize !== "" ? root.lastAskedSize
      : String(root.settings["size-adjust"] || "")
    var base = from.trim() === "auto" ? root.autoSizePercent : root.sizePercent(from)
    root.setSize(base + by * 5)
  }
  // Dragging the slider asks for a size faster than a process can write one,
  // and reassigning a Process that is still running drops the write. So the
  // latest ask is held and sent when the last one finishes, which coalesces
  // a drag into a couple of writes and guarantees the value under the finger
  // when it lifts is the one that lands.
  property string pendingSize: ""
  property string lastAskedSize: ""
  // A percentage, or the word auto. Rounded, because a slider hands over
  // fractions nobody needs written to a file.
  function setSize(percent) {
    var next = percent === "auto" ? "auto"
      : String(Math.round(Math.max(root.sizeMin, Math.min(root.sizeMax, Number(percent)))))
    if (next === "NaN") return
    // Against what was last asked for, not what has settled. The settled
    // value lags a drag, so dragging away and back again used to look like
    // no change at all and leave the handle somewhere the keyboard was not.
    var current = root.lastAskedSize !== "" ? root.lastAskedSize : root.look.sizeAdjust
    if (next === current) return
    root.lastAskedSize = next
    root.pendingSize = next
    root.flushSize()
  }
  function flushSize() {
    if (sizeStepProc.running || root.pendingSize === "") return
    var next = root.pendingSize
    root.pendingSize = ""
    sizeStepProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                            "size-adjust", "set", next]
    sizeStepProc.running = true
  }
  Process { id: sizeStepProc; onExited: root.flushSize() }

  // Whether the keyboard comes up by itself on a text field. It belongs
  // beside the other things you change while holding the machine, since the
  // moment you want it off is the moment it has just appeared over what you
  // were reading.
  function toggleAutoShow() {
    if (autoShowProc.running) return   // a second tap mid-write would be lost
    autoShowProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                            "auto-show", "toggle"]
    autoShowProc.running = true
  }
  Process { id: autoShowProc }

  // The themes there are to step through, by slug. Read once, since a theme
  // arriving in the folder mid-session is not worth watching a directory for,
  // and which one is on is already in settings.
  property var themeList: []
  readonly property string currentTheme: root.settings["theme"] || "omarchy"
  Process {
    id: themeListProc
    running: true
    command: ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""), "theme", "list"]
    stdout: StdioCollector {
      onStreamFinished: root.themeList = text.split("\n").filter(function(n) { return n !== "" })
    }
  }
  function stepTheme(by) {
    // Until the write lands, currentTheme still names the old one, so a
    // second tap would both compute the same answer and be dropped for
    // reassigning a running process. Two taps would move one theme, or none.
    if (root.themeList.length === 0 || themeApplyProc.running) return
    var at = root.themeList.indexOf(root.currentTheme)
    var count = root.themeList.length
    var next = root.themeList[(((at < 0 ? 0 : at) + by) % count + count) % count]
    themeApplyProc.command = ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""),
                              "theme", "apply", next]
    themeApplyProc.running = true
  }
  Process { id: themeApplyProc }

  // A machine that upgraded in place still has the previous version's
  // settings and menu rows. Nothing else runs on an update: the only hook
  // Ragtop installs is the overlay re-sync, and that is opt-in per overlay,
  // so this is the one path that fires however the plugin arrived. It says
  // nothing and writes nothing when there is nothing to do.
  Process {
    id: migrateProc
    running: true
    command: ["bash", Qt.resolvedUrl("ragtop").toString().replace(/^file:\/\//, ""), "migrate"]
  }

  // Switch to one of the layouts Hyprland has configured, by its index.
  // Hyprland owns the layout, so this asks rather than imposes: nothing is
  // written to anyone's config, and the switch is the same one a keybinding
  // would do. It emits activelayout, which is already what tells the helper
  // to re-read the keymap, so the keys and their labels follow on their own.
  function switchLayout(index) {
    if (switchLayoutProc.running) return
    switchLayoutProc.command = ["hyprctl", "switchxkblayout", "all", String(index)]
    switchLayoutProc.running = true
  }
  Process { id: switchLayoutProc }

  KeyboardTheme {
    id: keyboardTheme
    look: root.look
  }

  // ---- The keyboard's look ---------------------------------------------

  // Every part of the look is a setting (Setup › Tablet), so what the menu
  // shows is what the keyboard does. Presets are files that write these
  // settings. See the `ragtop` command. Values are checked here too, since
  // settings.conf is a plain file anyone can edit.
  readonly property var look: {
    function pick(key, allowed, fallback) {
      return allowed.indexOf(root.settings[key]) !== -1 ? root.settings[key] : fallback
    }
    function num(key, low, high, fallback) {
      var value = Number(root.settings[key])
      return isFinite(value) ? Math.min(high, Math.max(low, value)) : fallback
    }
    function color(key) {
      var value = String(root.settings[key] || "")
      return ["foreground", "background", "accent", "urgent"].indexOf(value) !== -1
        || /^#[0-9a-fA-F]{6,8}$/.test(value) ? value : ""
    }
    // Four corner styles, clockwise from the top left, for a theme after a
    // silhouette none of the names cover. Anything that is not four known
    // words falls back to the shape's own corners rather than half-applying.
    function cornerSpec() {
      var raw = String(root.settings["corners"] || "auto").trim().toLowerCase()
      if (raw === "" || raw === "auto") return "auto"
      var parts = raw.split(/\s+/)
      if (parts.length !== 4) return "auto"
      for (var i = 0; i < 4; i++)
        if (["round", "cut", "square"].indexOf(parts[i]) === -1) return "auto"
      return parts.join(" ")
    }
    return {
      shape: pick("shape", ["omarchy", "rounded", "pill", "angular", "bevel"], "omarchy"),
      corners: cornerSpec(),
      // How see-through the keys are over the keyboard's background, and the
      // background over the desktop. 0 is solid and 100 is gone.
      keyTransparency: num("key-transparency", 0, 100, 0),
      // Raised keys stand on a side, like a keycap, and flat ones don't.
      relief: pick("relief", ["flat", "raised"], "flat"),
      fill: pick("fill", ["auto", "dark", "light", "outline"], "light"),
      // The theme's key size, as a percentage of the usual, and the nudge on
      // top of it that is the user's alone. A theme cannot write size-adjust,
      // so how big the keys are for these eyes survives changing theme.
      size: num("size", 60, 160, 100),
      // The setting as written, which is a percentage, the word auto, or one
      // of the five names an older Ragtop wrote. The nudge is what that comes
      // out as, and it is the only one of the two anything downstream reads,
      // including the lock screen through its style file.
      sizeAdjust: String(root.settings["size-adjust"] || "regular").trim(),
      sizeNudge: (root.sizeAuto ? root.autoSizePercent
        : root.sizePercent(root.settings["size-adjust"])) / 100,
      labels: pick("labels", ["small", "normal", "large"], "normal"),
      // How far the keys that produce no character sit from the letters.
      specialKeys: pick("special-keys", ["off", "darker", "lighter"], "darker"),
      depth: num("depth", 0, 10, 4),
      chamfer: num("chamfer", 0, 20, 8),
      // Off-theme: set, and that part stops following the Omarchy theme.
      keyColor: color("key-color"),
      labelColor: color("label-color"),
      keyFillAlpha: root.settings["key-fill-alpha"] === undefined ? "auto" : num("key-fill-alpha", 0, 1, "auto"),
      borderWidth: root.settings["border-width"] === undefined ? "auto" : num("border-width", 0, 4, "auto"),
      radius: root.settings["radius"] === undefined ? "auto" : num("radius", 0, 30, "auto")
    }
  }

  // Blur behind the keyboard and its handle, so the two match. Hyprland
  // blurs nothing unless its global blur is on, and that would blur
  // see-through windows too, so when Ragtop turns it on it also tells
  // Hyprland to leave every window alone, and only the keyboard blurs.
  // Nothing is written to the Hyprland config: `hyprctl reload` clears it.
  readonly property bool blurKeyboard: root.settings["blur"] === "on"
  // Whether Hyprland's global blur was already on, i.e. the user's own
  // choice, which Ragtop leaves alone.
  property bool globalBlurWasOn: false
  property bool blurChecked: false
  onBlurKeyboardChanged: root.applyBlur()

  Process {
    id: blurCheckProc
    command: ["hyprctl", "getoption", "-j", "decoration:blur:enabled"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.globalBlurWasOn = JSON.parse(text()).int === 1 || JSON.parse(text()).bool === true } catch (e) {}
        root.blurChecked = true
        root.applyBlur()
      }
    }
  }

  // Layers reserving the same screen edge are laid out in the order
  // Hyprland arranged them, which is whichever mapped first, so a bar
  // moved to the bottom after the handle exists would end up between the
  // handle and the keyboard. These orders pin the arrangement instead: the
  // bar keeps the edge, the handle sits above it, the keyboard above that.
  // Runtime only, so nothing is written to the Hyprland config. A config
  // reload drops them, and they are set again then.
  property bool layerRulesReady: false
  function applyLayerRules() {
    layerRulesProc.command = ["hyprctl", "eval",
      "hl.layer_rule({ match = { namespace = '^ragtop-tools$' }, order = 1 }) "
      + "hl.layer_rule({ match = { namespace = '^ragtop-keyboard-handle$' }, order = -1 }) "
      + "hl.layer_rule({ match = { namespace = '^ragtop-picker-nav$' }, order = -2 }) "
      + "hl.layer_rule({ match = { namespace = '^ragtop-keyboard$' }, order = -3 })"]
    layerRulesProc.running = true
  }
  Process {
    id: layerRulesProc
    // The surfaces wait for the rules, so they map in the right order.
    onExited: root.layerRulesReady = true
  }

  function applyBlur() {
    if (!root.blurChecked) { blurCheckProc.running = true; return }
    var lua = "hl.layer_rule({ match = { namespace = '^ragtop-(keyboard(-handle)?|picker-nav)$' }, blur = " + root.blurKeyboard
      + ", ignore_alpha = 0.3 }) "
    if (!root.globalBlurWasOn) {
      // Ragtop's own blur: on for its layers, off for every window.
      lua += "hl.config({ decoration = { blur = { enabled = " + root.blurKeyboard + " } } }) "
      if (root.blurKeyboard) lua += "hl.window_rule({ match = { class = '.*' }, no_blur = true }) "
    }
    blurProc.command = ["hyprctl", "eval", lua]
    blurProc.running = true
  }
  Process { id: blurProc }

  // The look, for the lock screen's keyboard, which can't reach this
  // service and takes only the shape and measurements from it.
  onLookChanged: root.writeStyleForLock()
  function writeStyleForLock() {
    styleWriteProc.command = [
      "sh", "-c",
      'd="${XDG_RUNTIME_DIR:-}" && [ -n "$d" ] && printf "%s\\n" "$1" > "$d/ragtop-style.json.tmp" && mv -f "$d/ragtop-style.json.tmp" "$d/ragtop-style.json"',
      "--", JSON.stringify(root.look)
    ]
    styleWriteProc.running = true
  }
  Process { id: styleWriteProc }

  // Omarchy's screensaver, while it's up: its window address, or "".
  property string screensaverAddress: ""
  property bool oskHiddenForScreensaver: false

  // The screensaver is an ordinary window and everything Ragtop puts on
  // screen is a layer surface above it, so none of it goes away on its own
  // when the screensaver starts. The catcher next door covers the screen
  // and swallows the touch, so the keyboard was never doing anything there,
  // it was only sitting on top of a screensaver looking like a fault.
  //
  // Tiling ends rather than pausing. Coming back to a tiling layer
  // drawn around windows that may have moved while the screen was off is
  // worse than coming back to the desktop.
  onScreensaverAddressChanged: {
    if (root.screensaverAddress !== "") {
      if (root.tilingOpen) root.closeTiling(true)
      if (root.oskVisible) {
        root.oskHiddenForScreensaver = true
        root.setOskVisible(false)
      }
    } else if (root.oskHiddenForScreensaver) {
      root.oskHiddenForScreensaver = false
      if (root.keyboardAvailable) root.setOskVisible(true)
    }
  }

  // Window events only tell us about a screensaver that starts while the
  // shell is running, so ask once at startup as well. Restarting the shell
  // with the screensaver already up is the ordinary case while working on
  // Ragtop, not a corner one.
  // What the address was when the read below was started. A reply is about
  // the moment it was asked, not the moment it arrives, so a screensaver
  // that opened in between must not be cleared by an answer that predates
  // it.
  property string screensaverCheckedFor: ""

  // Ask whether the screensaver is really still there.
  //
  // Nothing here runs on a timer. A screensaver is meant to run for as long
  // as it likes, and waking the machine every few seconds to check on it
  // would be its own kind of interference, on battery through exactly the
  // stretch the machine should be quiet.
  //
  // So this is called when a human is already there: on a tap on the
  // catcher, and when a window opens or closes while we believe a
  // screensaver is up. Both mean the session is alive. A stuck catcher on a
  // machine nobody is touching harms nobody. The moment it matters is the
  // moment someone taps and nothing happens, and that is the moment this
  // runs.
  function confirmScreensaver() {
    if (screensaverCheckProc.running) return
    root.screensaverCheckedFor = root.screensaverAddress
    screensaverCheckProc.running = true
  }

  Process {
    id: screensaverCheckProc
    running: true
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var found = JSON.parse(text).filter(function(c) { return c["class"] === "org.omarchy.screensaver" })
          // hyprctl writes an address as 0x589cf9091790 and the window
          // events as 589cf9091790. Keep the events' spelling, or closewindow
          // never matches and the catcher stays up over a screensaver that
          // has already gone, swallowing every tap.
          if (found.length > 0) {
            if (root.screensaverAddress === "")
              root.screensaverAddress = String(found[0].address).replace(/^0x/, "")
          } else if (root.screensaverAddress !== ""
                     && root.screensaverAddress === root.screensaverCheckedFor) {
            // Gone, and gone since before we asked. Whatever closewindow we
            // missed, this is the way back: the catcher comes down and the
            // keyboard and handle return.
            root.screensaverAddress = ""
          }
        } catch (e) {}
      }
    }
  }

  // Ending the screensaver by touch.
  //
  // Omarchy's screensaver is a fullscreen terminal (org.omarchy.screensaver)
  // running ttfx, which quits when its terminal reads a character or when it
  // loses focus. A touchscreen gives it neither: a terminal ignores touch,
  // and tapping a fullscreen window doesn't move focus. So the screen stays
  // covered until a key is pressed, no use on a folded laptop, and no use
  // either on an open one that someone reaches for by the screen.
  //
  // The catcher isn't limited to tablet mode. A touchscreen is a touchscreen
  // whichever way the hinge is, the tap works the same in both, and a
  // machine with no touchscreen simply never taps it.
  //
  // This catcher is a transparent overlay that exists only while that window
  // does. It takes no keyboard focus, so the screensaver's terminal stays
  // focused and receives the key Ragtop sends when the catcher is tapped,
  // which is exactly what pressing a key by hand does.
  //
  // It is deliberately specific to Omarchy's screensaver: it matches that
  // window class, and it relies on that screensaver quitting on any key.
  // Another screensaver wouldn't be recognised, and might not quit on Escape
  // even if it were.
  PanelWindow {
    screen: root.keyboardScreen
    visible: root.screensaverAddress !== "" && root.layerRulesReady

    WlrLayershell.namespace: "ragtop-screensaver-catcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    MouseArea {
      anchors.fill: parent
      // Escape first, so a screensaver that is really there dies on the
      // touch rather than waiting for a round trip. The check runs beside
      // it, and only matters when the screensaver has already gone: then
      // this tap is spent on a stray Escape to whatever has focus, once,
      // and the next tap behaves normally because the catcher is gone.
      // One stray Escape is a better failure than a screen that eats every
      // touch with no way back.
      onPressed: {
        root.sendKeys("key Escape")
        root.confirmScreensaver()
      }
    }
  }

  // Tiling mode's surface. Top rather than Overlay, and ordered below the
  // bar and the keyboard's handle, so both of those stay tappable the whole
  // time it is up. The screensaver catcher next door is Overlay because it
  // has to cover everything. This one must not: a full-screen layer that
  // swallows every touch is the worst thing to get stuck on a machine that
  // is folded shut, and those two surfaces are two more ways back out.
  PanelWindow {
    screen: keyboardWindow.screen
    visible: root.tilingOpen && root.layerRulesReady

    WlrLayershell.namespace: "ragtop-tiling"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    // The surface covers the screen so the outlines can be drawn at the
    // windows' own coordinates, but it only takes touches where it has
    // something to take them with. Everything else falls through, which is
    // how the bar and the keyboard's handle stay usable underneath it
    // without depending on layer ordering to arrange that. Layer order was
    // the first attempt and it put this on top of both.
    mask: Region { item: tilingLayer.touchArea }

    TilingLayer {
      id: tilingLayer
      anchors.fill: parent
      service: root
      windows: root.tilingWindows
    }
  }

  // On the built-in screen, reserving its space so windows move up out of
  // its way. It never takes keyboard focus, so typing goes to the window
  // underneath. Created when shown, so it stacks above the handle.
  PanelWindow {
    id: keyboardWindow
    screen: root.keyboardScreen
    visible: root.oskVisible && root.layerRulesReady

    // Where the keyboard takes touches (see Keyboard's touchArea): the whole
    // surface while it draws a background, and only the keys' own extent
    // when that background is fully clear, so a tap can reach the window
    // underneath exactly where the keyboard doesn't cover it.
    mask: Region { item: keyboard.touchArea }

    WlrLayershell.namespace: "ragtop-keyboard"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Reserves what can be seen, which a hidden suggestion strip's room is
    // not: the surface keeps one height and only the reservation changes,
    // so the keys never move (Keyboard.qml, stripSlot).
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: keyboard.visibleHeight
    anchors { bottom: true; left: true; right: true }
    implicitHeight: keyboard.implicitHeight
    color: "transparent"

    Keyboard {
      id: keyboard
      anchors.fill: parent
      service: root
      theme: keyboardTheme
      // How much of the screen the keyboard may take when it is choosing a
      // form factor for itself. Half, so the window it comes up over keeps
      // at least the other half. A form factor asked for by name ignores
      // this: asking for it is asking for the height it needs.
      maxHeight: keyboardWindow.screen ? keyboardWindow.screen.height / 2 : 0
    }
  }

  // Ragtop's controls are a tile of their own. One window, not two: a
  // full-screen sheet behind it to catch the dismissing tap took the input
  // for itself, so nothing on the tile could be touched and every tap closed
  // it. The keyboard puts them away instead, which needs no second surface.
  //
  // The tile is anchored to the top of the screen only, with a fixed size.
  // Nothing it shares an edge with can resize it, which is the whole point:
  // when this window respected the keyboard's exclusive zone, every step of
  // the size slider resized the keyboard, resized this, and cancelled the
  // touch that was dragging it.
  PanelWindow {
    id: toolsWindow
    screen: keyboardWindow.screen
    visible: root.oskVisible && root.toolsOpen && root.layerRulesReady

    WlrLayershell.namespace: "ragtop-tools"
    // On the same layer as Omarchy's notifications rather than under it.
    // Notifications are an Overlay layer anchored top right, so on a portrait
    // screen one of them lands on top of this panel and covers the very
    // control being dragged. Surfaces on one layer stack in the order they
    // map, so this now comes out in front of a notification that was already
    // up when the panel was opened.
    //
    // It does NOT fix the other way round, and measured: Omarchy's
    // notification window is `visible: popupModel.count > 0`, so it maps when
    // a notification arrives, which is after this one and therefore on top.
    // Fixing that needs a choice nobody has made yet. Either hold
    // notifications while the panel is open, which means a plugin writing
    // Omarchy's persisted `dnd`, or drop the panel down the screen far
    // enough to clear the toast column, which no fixed margin can promise
    // for two toasts.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Reserves nothing of its own, but sits below Omarchy's bar rather than
    // under it. Anchored to one edge, so its size is its own.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    anchors { top: true }
    // Its own size, from what the controls need, and never wider than the
    // screen: a fixed 596 all but filled a 768 pixel portrait screen edge to
    // edge, leaving the card's border against it.
    implicitWidth: Math.min(toolsPanel.implicitWidth,
                            (toolsWindow.screen ? toolsWindow.screen.width : 768)
                              - 2 * Style.gapsOut)
    // As tall as its contents, but never past halfway down the screen, and
    // the panel scrolls what does not fit. Halfway is exactly where Automatic
    // stops the keyboard growing, so the two cannot meet.
    //
    // It deliberately does NOT measure the space above the keyboard, which
    // would be the obvious way to do it. The keyboard's height changes on
    // every step of the size slider, so a panel sized from it would resize
    // under the finger doing the dragging, which is the bug this window was
    // moved to the top of the screen to escape in the first place.
    readonly property real room: (toolsWindow.screen ? toolsWindow.screen.height : 768) / 2
      - root.barSize - toolsWindow.margins.top - Style.gapsOut
    implicitHeight: Math.min(toolsPanel.implicitHeight, Math.max(120, toolsWindow.room))
    margins.top: 22
    color: "transparent"

    ToolsPanel {
      id: toolsPanel
      anchors.fill: parent
      service: root
      onDismissed: root.toolsOpen = false
    }
  }

  // The picker's nav strip, in the keyboard's place while the picker is up.
  // Only with a cloned picker: a stock one takes every touch on the screen,
  // so the strip would be there but untappable.
  PanelWindow {
    id: pickerNavWindow
    screen: root.keyboardScreen
    visible: root.tabletMode && root.pickerOpen && root.pickerPatched && root.layerRulesReady

    WlrLayershell.namespace: "ragtop-picker-nav"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // It reserves its space, so the cloned picker centres its carousel above
    // the strip instead of behind it.
    exclusionMode: ExclusionMode.Auto
    anchors { bottom: true; left: true; right: true }
    implicitHeight: pickerNav.implicitHeight
    color: "transparent"

    PickerNav {
      id: pickerNav
      anchors.fill: parent
      service: root
      theme: keyboardTheme
    }
  }

  // Setup, in the shell rather than in a terminal (SetupWizard.qml). Opened
  // by `ragtop setup`, by the setup notification, and by itself the first
  // time Ragtop runs on a machine the installer has never been run on.
  property bool setupOpen: false
  function openSetup() { root.setupOpen = true }

  // Run something in Omarchy's floating terminal with setup out of the way,
  // and bring setup back when it finishes. Setup cannot simply sit there: it
  // covers the screen, and the terminal would open behind it.
  function runSetupTerminal(command) {
    root.setupOpen = false
    setupTerminalProc.command = ["omarchy-launch-floating-terminal-with-presentation", command]
    setupTerminalProc.running = true
  }
  Process {
    id: setupTerminalProc
    onExited: {
      // Whatever was installed in there, notice it now rather than in a
      // minute: setup is about to ask the same question.
      if (!sensorCheckProc.running) sensorCheckProc.running = true
      root.openSetup()
    }
  }

  PanelWindow {
    id: setupWindow
    screen: root.keyboardScreen
    visible: root.setupOpen

    WlrLayershell.namespace: "ragtop-setup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // Only the card takes input, and the dimmed rest of the screen stays usable,
    // so a terminal can be reached while setup is open.
    mask: Region { item: setupLoader.item ? setupLoader.item.card : null }

    Loader {
      id: setupLoader
      anchors.fill: parent
      active: root.setupOpen
      sourceComponent: SetupWizard {
        service: root
        onFinished: root.setupOpen = false
      }
    }
  }

  // omarchy-shell ragtop <function>: for keybindings and scripts.
  //
  // Nothing here sends a key. Each function flips a state the user can flip
  // by hand or returns a status string, and none of them takes an argument.
  // Keys come from a touch on a key: Keyboard.qml's press() and release()
  // are called from its own touch handlers and nowhere else. tapKey and
  // tapPickerNav used to be here, to drive the keyboard from a shell while
  // developing, but anything that can call this socket could then type into
  // the focused window. Drive the keyboard with a real tap instead, or the
  // helper's --dry-run.
  IpcHandler {
    target: "ragtop"

    function showKeyboard(): string { root.setOskVisible(true); return "ok" }
    function hideKeyboard(): string { root.setOskVisible(false); return "ok" }
    function toggleKeyboard(): string { root.toggleOsk(); return "ok" }
    function keyboardVisible(): string { return root.oskVisible ? "true" : "false" }
    function openSetup(): string { root.openSetup(); return "ok" }
    // The things worth binding a key to, and every one of them takes no
    // argument, so nothing on this socket can be handed a value to act on.
    function toggleControls(): string {
      if (!root.oskVisible) root.setOskVisible(true)
      root.toolsOpen = !root.toolsOpen
      return "ok"
    }
    function cycleRotation(): string {
      var order = root.rotationModes
      root.setRotationMode(order[(order.indexOf(root.rotationMode) + 1) % order.length])
      return root.rotationMode
    }
    // Sensor, then on, then off, the same three the bar button cycles.
    function cycleKeyboardMode(): string {
      var order = root.keyboardModes
      root.setKeyboardMode(order[(order.indexOf(root.keyboardMode) + 1) % order.length])
      return root.keyboardMode
    }
    function keyboardModeState(): string { return root.keyboardMode }
    function growKeyboard(): string { root.stepSize(1); return "ok" }
    function shrinkKeyboard(): string { root.stepSize(-1); return "ok" }
    function rotationState(): string { return root.rotationMode }
    // What is working and what is not. Four things run in the background and
    // each can be dead while everything on screen looks right, so this is
    // what a bug report needs and the settings cannot say.
    function health(): string {
      return JSON.stringify({
        keyboard: root.retryHealth("keyboard", keyboardHelper.running),
        autoshow: root.wantFocusBridge ? root.retryHealth("autoshow", focusBridgeProc.running) : "off",
        raises: root.autoShows,
        inputMethod: !root.inputMethodsEnabled ? "off"
          : root.imeEngine ? root.imeEngine.name : "layout",
        words: root.wordLanguage,
        assists: !root.assistsEnabled ? "off" : root.inTerminal ? "terminal" : root.assistsActive ? "on" : "idle",
        field: !root.fieldInfo ? "unknown" : root.fieldInfo.password ? "password"
          : root.fieldInfo.terminal ? "terminal" : root.fieldInfo.noCapitals ? "nocapitals" : "plain",
        swipe: !root.swipeEnabled || !root.predictionsEnabled ? "off" : !root.wordsReady ? "nowords"
          : root.swipeActive ? "on" : "idle",
        predictions: !root.predictionsEnabled ? "off"
          : root.terminalSuggesting ? "prompt"
          : !predictorProc.running ? root.retryHealth("predict", false)
          : !root.wordsReady ? "nowords"
          : root.predicting ? "on" : "idle",
        tabletSwitch: root.watchSwitch ? root.retryHealth("switch", tabletModeProc.running) : "off",
        sensor: !root.rotationAvailable ? "absent"
          // Told apart from "absent", which is the package, and from
          // "stuck", which is a sensor that exists and has stopped. A bug
          // report from a machine with no accelerometer should say so.
          : root.accelPresent === 0 ? "no accelerometer"
          : root.rotationLocked ? "held"
          : root.sensorClaimed ? "ok"
          : root.sensorFailures >= 2 ? "stuck"
          : rotationProc.running ? "claiming" : "waiting"
      })
    }
    function closeSetup(): string { root.setupOpen = false; return "ok" }
    function toggleTiling(): string {
      root.toggleTilingMode()
      return root.tilingOpen ? "open" : "closed"
    }
    // What the keyboard and the picker are doing, for scripts and for a bug
    // report. Read-only, and no key that was typed appears in either.
    function keyboardState(): string {
      return JSON.stringify({ visible: root.oskVisible,
                              page: keyboard.page, mods: keyboard.mods,
                              caps: keyboard.caps })
    }
    function pickerState(): string {
      return JSON.stringify({ open: root.pickerOpen, patched: root.pickerPatched,
                              nav: pickerNavWindow.visible })
    }
  }
}
