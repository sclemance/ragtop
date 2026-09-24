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

  // Override from the widget's settings; blank means auto-detect.
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

  // The hinge's switch, as last read; only followed in the "auto" setting.
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
      'd="${XDG_RUNTIME_DIR:-/tmp}" && printf "%s\\n" "$1" > "$d/ragtop-mode.tmp" && mv -f "$d/ragtop-mode.tmp" "$d/ragtop-mode"',
      "--", tablet ? "tablet" : "laptop"
    ]
    modeWriteProc.running = true
    // The keyboard toggle is hidden outside tablet mode, so the keyboard
    // must be put away here. The first reading counts too: the shell may
    // (re)start while already in laptop mode with the keyboard up.
    if (!tablet) root.setOskVisible(false)
  }

  function toggleOsk() {
    setOskVisible(!root.oskVisible)
  }

  function setOskVisible(visible) {
    root.oskVisible = visible
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
      // on the handle would only throw it away; a cloned picker leaves the
      // handle usable, for filter typing.
      visible: root.tabletMode && root.layerRulesReady && (!root.pickerOpen || root.pickerPatched)

      // Under an open keyboard the handle takes the keyboard's background
      // and text colours, so the two read as one panel with the handle as
      // its tab; otherwise it matches the bar. Only on the keyboard's screen.
      readonly property bool underKeyboard: root.oskVisible && modelData === keyboardWindow.screen
      readonly property color fill: underKeyboard ? keyboardTheme.background
        : root.barTransparent ? Qt.rgba(Color.bar.background.r, Color.bar.background.g, Color.bar.background.b, 0)
        : Color.bar.background
      readonly property color line: underKeyboard ? keyboardTheme.text : Color.bar.text

      WlrLayershell.namespace: "ragtop-keyboard-handle"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Auto
      anchors { bottom: true; left: true; right: true }
      // The bar says how much room it needs, since a narrow screen puts it
      // on two rows and a wide one does not.
      implicitHeight: root.arrangeOpen ? arrangeBar.neededHeight : root.handleHeight
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
        // Only a handle when it is a handle. While arranging, the bar's own
        // controls take the taps and a miss between them should do nothing
        // rather than drop you out of the mode.
        enabled: !root.arrangeOpen
        onTapped: root.toggleOsk()
      }

      // While arranging, the strip is the controls.
      ArrangeBar {
        id: arrangeBar
        anchors.fill: parent
        visible: root.arrangeOpen
        service: root
      }

      // A wide ^ while the keyboard is hidden, a wide v while it's showing.
      Shape {
        id: chevron
        anchors.centerIn: parent
        visible: !root.arrangeOpen
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
  // lock isn't briefly overridden at startup; unlocked if none reports in.
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
  // the shell runs. The setup steps say what's missing; this just stops
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
               + "register. Setup › Tablet › Tablet Mode sets it by hand."]
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
  // shell for it — that is the whole point of setup naming what is missing.
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
  function internalMonitorName() {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++)
      if (/^(eDP|DSI|LVDS)-/.test(monitors[i].name)) return monitors[i].name
    return monitors.length > 0 ? monitors[0].name : ""
  }

  // Rotation waits while the screen is locked: Omarchy's lock screen isn't
  // redrawn for a rotated display, though touches would be rotated, so what's
  // drawn and where taps land would disagree. Asking only when about to
  // rotate avoids polling; while locked, it asks again until unlocked.
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
      if (!root.arrangeOpen) return
      arrangeSettle.again = 2
      arrangeSettle.restart()
    }
  }
  // The interval is set by wantSensor, from the deadline.
  Timer {
    id: rotationRestart
    interval: 3000
    onTriggered: root.wantSensor()
  }

  // Settings written by the `ragtop` command (Setup › Tablet in the
  // Omarchy menu), as key=value lines; a missing key keeps its default.
  property var settings: ({})
  property bool settingsLoaded: false

  // Whether Omarchy's bar is transparent (Style › Bar › Transparency), passed
  // on by the bar widget; the keyboard handle and, by default, the keyboard's
  // background follow it.
  property bool barTransparent: false
  // Both files below are watched — settings.conf by this service, and the
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
      'd="${XDG_RUNTIME_DIR:-/tmp}"; [ -e "$d/ragtop-mode" ] || printf "laptop\n" > "$d/ragtop-mode"']
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
  // "show"; hiding stays with the user (see fcitx-osk-bridge.py for why).
  // Stopping it hands fcitx5 back its own interface.
  // `running` cannot be a binding here. The restart timer assigns to it, and
  // an assignment breaks a binding for good, so after the first crash the
  // bridge stopped following tablet mode at all and auto-show stayed dead
  // until the shell restarted. The switch watcher below already avoided this
  // by driving its process from a changed handler, and so does this now.
  readonly property bool wantFocusBridge: root.tabletMode && root.autoShowEnabled
  onWantFocusBridgeChanged: {
    focusBridgeRestart.stop()
    focusBridgeProc.running = root.wantFocusBridge
  }
  Process {
    id: focusBridgeProc
    command: ["python3", Qt.resolvedUrl("fcitx-osk-bridge.py").toString().replace(/^file:\/\//, "")]
    stdout: SplitParser {
      onRead: function(line) {
        if (line !== "show") return
        root.autoShows++
        // Not while arranging. The keyboard coming back ends the mode, and
        // the bar's own buttons change which window has focus, so a window
        // with a text field in it would raise the keyboard and close the
        // mode out from under the button that was just tapped. Asking for
        // the keyboard still ends the mode, because that goes through
        // setOskVisible rather than through here.
        if (root.tabletMode && root.autoShowEnabled && !root.oskVisible
            && !root.pickerOpen && !root.arrangeOpen)
          root.setOskVisible(true)
      }
    }
    onRunningChanged: if (running) root.retryStarted("autoshow")
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

  // Whether the keyboard has a background at all is Omarchy's call, not a
  // setting of ours: double-tapping the bar makes it transparent, and the
  // keyboard's background goes with it, so the keys float over the desktop
  // the way the bar does. With the bar solid, the background is whatever the
  // theme asked for.
  readonly property real backgroundOpacity: root.barTransparent
    ? 0 : 1 - root.look.transparency / 100

  Process { id: modeWriteProc }

  // A plugin added with `omarchy plugin add` runs without install.sh having
  // set up its config lines, layouts and overlay patches. Check once per
  // session and offer to run the installer; installing a plugin never runs
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

  // Namespaces of overlays patched by overlay-clones.sh. An open overlay
  // covers the bar, so the keyboard is brought up with it; with a stock
  // overlay taps on the keyboard would only close it, so only patched ones
  // count.
  property var patchedOverlays: []
  property var openOverlays: []
  property bool oskShownForOverlay: false

  // Omarchy's theme and background pickers are both its image picker, whose
  // surface is named for what it does rather than for the plugin.
  readonly property string pickerNamespace: "omarchy-image-selector"
  // Whether the picker runs as a Ragtop clone, which is what makes the nav
  // strip tappable at all; see PickerNav.qml.
  property bool pickerPatched: false

  Process {
    id: patchCheckProc
    command: ["sh", "-c",
      'for p in menu:Menu emojis:Emojis clipboard:Clipboard polkit:PolkitAgent; do ' +
      'grep -qs "id: ragtopMode" "$HOME/.config/omarchy/plugins/$USER.${p%%:*}/${p#*:}.qml" && echo "omarchy-${p%%:*}"; ' +
      'done; ' +
      'grep -qs "id: ragtopMode" "$HOME/.config/omarchy/plugins/$USER.image-picker/ImagePicker.qml" && ' +
      'echo "omarchy-image-selector"; true']
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        var found = text.split("\n").filter(function(s) { return s !== "" })
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
      if (root.tabletMode) root.setOskVisible(true)
    }
  }

  // The last layout a real keyboard switched to; see onRawEvent.
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
        // moved — which is how this was found, switching themes on a tablet
        // held upright. Forget what was applied and apply it again.
        root.appliedOrientation = ""
        root.applyOrientation(root.pendingOrientation)
      }
      // Omarchy's screensaver, watched by window class; see the catcher
      // below for what Ragtop does about it.
      if (name === "openwindow") {
        var fields = String(event.data || "").split(",")
        if (fields.length >= 3 && fields[2] === "org.omarchy.screensaver") root.screensaverAddress = fields[0]
      } else if (name === "closewindow") {
        if (String(event.data || "").trim() === root.screensaverAddress) root.screensaverAddress = ""
      }

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
        if (open.length === 1 && root.tabletMode && !root.oskVisible) {
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
    tabletModeProc.running = root.watchSwitch
    applyLayerRules()
  }
  Process {
    id: tabletModeProc
    command: ["python3", Qt.resolvedUrl("tablet-switch.py").toString().replace(/^file:\/\//, ""), root.switchDevice]
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
    command: ["python3", Qt.resolvedUrl("keyboard-helper.py").toString().replace(/^file:\/\//, "")]
    running: true
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line.startsWith("labels ")) {
          try { root.keyLabels = JSON.parse(line.slice(7)) } catch (e) {}
        }
      }
    }
    onRunningChanged: if (running) root.retryStarted("keyboard")
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
  // { name, rows: [[[normal, shifted], ...], ...] }; null until it reports.
  // Also written to $XDG_RUNTIME_DIR/ragtop-layout.json for the lock
  // screen's keyboard, which can't reach this service.
  property var keyLabels: null
  onKeyLabelsChanged: {
    if (!root.keyLabels) return
    layoutWriteProc.command = [
      "sh", "-c",
      'd="${XDG_RUNTIME_DIR:-/tmp}" && printf "%s\\n" "$1" > "$d/ragtop-layout.json.tmp" && mv -f "$d/ragtop-layout.json.tmp" "$d/ragtop-layout.json"',
      "--", JSON.stringify(root.keyLabels)
    ]
    layoutWriteProc.running = true
  }
  Process { id: layoutWriteProc }

  // One command per line; see keyboard-helper.py.
  function sendKeys(command) {
    if (keyboardHelper.running) keyboardHelper.write(command + "\n")
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
  function runWindowAction(name) {
    var lua = root.windowActions[name]
    if (!lua) return
    var proc = root.windowActionProc.createObject(root,
      { command: ["hyprctl", "eval", "hl.dispatch(" + lua + ")"] })
    if (proc) proc.running = true
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

  // A number rather than a name, checked against the range Hyprland has, so
  // the only thing that reaches a command line is a digit this decided on.
  function workspaceLua(id, send) {
    var n = parseInt(id, 10)
    if (!(n >= 1 && n <= 10)) return ""
    return send ? 'hl.dsp.window.move({ workspace = "' + n + '" })'
                : 'hl.dsp.focus({ workspace = "' + n + '" })'
  }
  function runWorkspace(id, send) {
    var lua = root.workspaceLua(id, send)
    if (lua === "") return
    var proc = root.windowActionProc.createObject(root,
      { command: ["hyprctl", "eval", "hl.dispatch(" + lua + ")"] })
    if (proc) proc.running = true
  }

  // ---- arrange mode -------------------------------------------------------

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

  // Whether a special workspace is showing. The scratchpad is not the
  // focused workspace while it is up: it is an overlay, and it lives in the
  // monitor's own specialWorkspace rather than in focusedWorkspace, so
  // asking the usual place says no every time.
  // How many times the focus bridge has asked for the keyboard. Zero after a
  // long session is the signature of an input method gone quiet: everything
  // reports healthy and nothing ever comes up.
  property int autoShows: 0

  property bool specialShown: false

  property bool arrangeOpen: false
  property var arrangeWindows: []

  function openArrange() {
    // The keyboard's strip is reserved, so hiding it first lets the windows
    // reflow to the full screen. The list is read after that settles, or the
    // outlines would be drawn around where the windows used to be.
    root.setOskVisible(false)
    root.arrangeOpen = true
    specialReadProc.running = true
    arrangeIdle.restart()
    arrangeSettle.restart()
  }
  // Done came from the keyboard, so it goes back to it. A timeout or tablet
  // mode ending did not, and putting a keyboard up for nobody would only
  // shrink the windows again.
  function closeArrange(restore) {
    // Cleared before the keyboard is asked for, or the rule below would see
    // it come up and call this a second time.
    root.arrangeOpen = false
    root.sendMod = "off"
    arrangeIdle.stop()
    arrangeSettle.stop()
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
    arrangeIdle.restart()
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
    arrangeIdle.restart()
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
      if (root.arrangeOpen && !arrangeClientsProc.running)
        arrangeClientsProc.running = true
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
    arrangeIdle.restart()
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
      if (root.arrangeOpen && !arrangeClientsProc.running)
        arrangeClientsProc.running = true
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
    arrangeIdle.restart()
  }

  // Read once on the way in, because the event below only fires on a change
  // and the scratchpad may already be up.
  Process {
    id: specialReadProc
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var any = false
          JSON.parse(text).forEach(function(m) {
            if (m.specialWorkspace && m.specialWorkspace.id !== 0) any = true
          })
          root.specialShown = any
        } catch (e) {}
      }
    }
  }

  Timer {
    id: arrangeSettle
    interval: 260
    // Twice, a beat apart: a rotation is still settling when the first read
    // happens, and one stale set of outlines is worth a second look.
    property int again: 0
    onTriggered: {
      arrangeClientsProc.running = true
      if (again > 0) {
        again--
        arrangeSettle.restart()
      }
    }
  }
  Timer {
    id: arrangeIdle
    interval: 90000
    onTriggered: root.closeArrange()
  }
  // Tablet mode ending takes the mode with it, along with everything else
  // that only makes sense with a screen you are holding.
  onTabletModeChanged: if (!root.tabletMode) root.closeArrange()

  Process {
    id: arrangeClientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.arrangeOpen) return
        var monitor = Hyprland.focusedMonitor
        var ox = monitor ? monitor.x : 0
        var oy = monitor ? monitor.y : 0
        var ws = root.focusedWorkspace
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
                       focused: c.focusHistoryID === 0 })
          })
        } catch (e) {
          return
        }
        // A stable order, so the model's rows never reshuffle when focus
        // or stacking changes. Reordering rebuilds every delegate, which
        // kills whatever gesture is in flight. What is drawn on top is
        // decided in the layer instead.
        out.sort(function(a, b) { return a.address < b.address ? -1 : 1 })
        root.arrangeWindows = out
      }
    }
  }
  // Anything that moves a window moves an outline with it.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.arrangeOpen) return
      var n = event.name
      if (n === "activespecial") {
        // "workspacename,monitorname", and an empty name means it went away.
        root.specialShown = String(event.data).split(",")[0] !== ""
      }
      // The monitor ones matter because a rotation from anywhere else, the
      // bar's button or a keybinding, has to be noticed too.
      if (n === "openwindow" || n === "closewindow" || n === "movewindow"
          || n === "resizewindow" || n === "activewindow" || n === "changefloatingmode"
          || n === "fullscreen" || n === "monitorlayoutchanged"
          || n === "monitoradded" || n === "monitorremoved"
          || n === "configreloaded" || n === "activespecial") {
        arrangeSettle.restart()
      }
    }
  }

  // What the bar's window button does, and the socket below with it: one
  // way in and out of arranging, so both agree about what a second tap
  // means.
  function toggleArrangeMode() {
    if (root.arrangeOpen) root.closeArrange(true)
    else root.openArrange()
  }
  onOskVisibleChanged: {
    if (!root.oskVisible) root.toolsOpen = false
    // The keyboard and arrange mode are exclusive: entering hides the
    // keyboard, and the keyboard coming back by any route ends the mode.
    // That covers the handle, auto-show on a text field, and the bar's own
    // button, and it is also the fix for a real fault: the keyboard's
    // exclusive zone changing relayouts every window, Hyprland emits no
    // resizewindow for that, so the outlines used to sit over a keyboard,
    // drawn around windows that had already shrunk away from them.
    if (root.oskVisible && root.arrangeOpen) root.closeArrange()
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
  function stepSize(by) {
    var at = root.sizeSteps.indexOf(root.look.sizeAdjust)
    root.setSize((at < 0 ? 2 : at) + by)
  }
  // Dragging the slider asks for a size faster than a process can write one,
  // and reassigning a Process that is still running drops the write. So the
  // latest ask is held and sent when the last one finishes, which coalesces
  // a drag into a couple of writes and guarantees the value under the finger
  // when it lifts is the one that lands.
  property string pendingSize: ""
  property string lastAskedSize: ""
  function setSize(index) {
    var next = root.sizeSteps[Math.max(0, Math.min(root.sizeSteps.length - 1, index))]
    if (!next) return
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
    backgroundOpacity: root.backgroundOpacity
    look: root.look
  }

  // ---- The keyboard's look ---------------------------------------------

  // Every part of the look is a setting (Setup › Tablet), so what the menu
  // shows is what the keyboard does. Presets are files that write these
  // settings; see the `ragtop` command. Values are checked here too, since
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
    return {
      shape: pick("shape", ["omarchy", "rounded", "pill", "angular"], "omarchy"),
      // How see-through the keys are over the keyboard's background, and the
      // background over the desktop. 0 is solid and 100 is gone.
      keyTransparency: num("key-transparency", 0, 100, 0),
      transparency: num("transparency", 0, 100, 0),
      // Raised keys stand on a side, like a keycap; flat ones don't.
      relief: pick("relief", ["flat", "raised"], "flat"),
      fill: pick("fill", ["auto", "dark", "light", "outline"], "light"),
      // The theme's key size, as a percentage of the usual, and the nudge on
      // top of it that is the user's alone. A theme cannot write size-adjust,
      // so how big the keys are for these eyes survives changing theme.
      size: num("size", 60, 160, 100),
      sizeAdjust: pick("size-adjust", root.sizeSteps, "regular"),
      sizeNudge: root.sizeNudges[pick("size-adjust", root.sizeSteps, "regular")] || 1,
      background: pick("background", ["tint", "gradient"], "tint"),
      edge: pick("edge", ["border", "fade", "none"], "none"),
      labels: pick("labels", ["small", "normal", "large"], "normal"),
      // How far the keys that produce no character sit from the letters.
      specialKeys: pick("special-keys", ["off", "darker", "lighter"], "darker"),
      depth: num("depth", 0, 10, 4),
      chamfer: num("chamfer", 0, 20, 8),
      edgeFade: num("edge-fade", 0, 24, 8),
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
  // see-through windows too — so when Ragtop turns it on, it also tells
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
  // Hyprland arranged them, which is whichever mapped first — so a bar
  // moved to the bottom after the handle exists would end up between the
  // handle and the keyboard. These orders pin the arrangement instead: the
  // bar keeps the edge, the handle sits above it, the keyboard above that.
  // Runtime only, so nothing is written to the Hyprland config; a config
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
      'd="${XDG_RUNTIME_DIR:-/tmp}" && printf "%s\\n" "$1" > "$d/ragtop-style.json.tmp" && mv -f "$d/ragtop-style.json.tmp" "$d/ragtop-style.json"',
      "--", JSON.stringify(root.look)
    ]
    styleWriteProc.running = true
  }
  Process { id: styleWriteProc }

  // Omarchy's screensaver, while it's up: its window address, or "".
  property string screensaverAddress: ""

  // Window events only tell us about a screensaver that starts while the
  // shell is running, so ask once at startup as well — restarting the shell
  // with the screensaver already up is the ordinary case while working on
  // Ragtop, not a corner one.
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
          if (found.length > 0 && root.screensaverAddress === "")
            root.screensaverAddress = String(found[0].address).replace(/^0x/, "")
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
  // covered until a key is pressed — no use on a folded laptop, and no use
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
    screen: Quickshell.screens.find(function(s) { return s.name === root.internalMonitorName() }) || Quickshell.screens[0]
    visible: root.screensaverAddress !== "" && root.layerRulesReady

    WlrLayershell.namespace: "ragtop-screensaver-catcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    MouseArea {
      anchors.fill: parent
      onPressed: root.sendKeys("key Escape")
    }
  }

  // Arrange mode's surface. Top rather than Overlay, and ordered below the
  // bar and the keyboard's handle, so both of those stay tappable the whole
  // time it is up. The screensaver catcher next door is Overlay because it
  // has to cover everything. This one must not: a full-screen layer that
  // swallows every touch is the worst thing to get stuck on a machine that
  // is folded shut, and those two surfaces are two more ways back out.
  PanelWindow {
    screen: keyboardWindow.screen
    visible: root.arrangeOpen && root.layerRulesReady

    WlrLayershell.namespace: "ragtop-arrange"
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
    mask: Region { item: arrangeLayer.touchArea }

    ArrangeLayer {
      id: arrangeLayer
      anchors.fill: parent
      service: root
      windows: root.arrangeWindows
    }
  }

  // On the built-in screen, reserving its space so windows move up out of
  // its way. It never takes keyboard focus, so typing goes to the window
  // underneath. Created when shown, so it stacks above the handle.
  PanelWindow {
    id: keyboardWindow
    screen: Quickshell.screens.find(function(s) { return s.name === root.internalMonitorName() }) || Quickshell.screens[0]
    visible: root.oskVisible && root.layerRulesReady

    // Where the keyboard takes touches (see Keyboard's touchArea): the whole
    // surface while it draws a background, and only the keys' own extent
    // when that background is fully clear, so a tap can reach the window
    // underneath exactly where the keyboard doesn't cover it.
    mask: Region { item: keyboard.touchArea }

    WlrLayershell.namespace: "ragtop-keyboard"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Auto
    anchors { bottom: true; left: true; right: true }
    implicitHeight: keyboard.implicitHeight
    color: "transparent"

    Keyboard {
      id: keyboard
      anchors.fill: parent
      service: root
      theme: keyboardTheme
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
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Reserves nothing of its own, but sits below Omarchy's bar rather than
    // under it. Anchored to one edge, so its size is its own.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    anchors { top: true }
    implicitWidth: 596
    implicitHeight: 258
    margins.top: 22
    color: "transparent"

    ToolsPanel {
      anchors.fill: parent
      service: root
      theme: keyboardTheme
      onDismissed: root.toolsOpen = false
    }
  }

  // The picker's nav strip, in the keyboard's place while the picker is up.
  // Only with a cloned picker: a stock one takes every touch on the screen,
  // so the strip would be there but untappable.
  PanelWindow {
    id: pickerNavWindow
    screen: Quickshell.screens.find(function(s) { return s.name === root.internalMonitorName() }) || Quickshell.screens[0]
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
    screen: Quickshell.screens.find(function(s) { return s.name === root.internalMonitorName() }) || Quickshell.screens[0]
    visible: root.setupOpen

    WlrLayershell.namespace: "ragtop-setup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // Only the card takes input; the dimmed rest of the screen stays usable,
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
        tabletSwitch: root.watchSwitch ? root.retryHealth("switch", tabletModeProc.running) : "off",
        sensor: !root.rotationAvailable ? "absent"
          : root.rotationLocked ? "held"
          : root.sensorClaimed ? "ok"
          : root.sensorFailures >= 2 ? "stuck"
          : rotationProc.running ? "claiming" : "waiting"
      })
    }
    function closeSetup(): string { root.setupOpen = false; return "ok" }
    function toggleArrange(): string {
      root.toggleArrangeMode()
      return root.arrangeOpen ? "open" : "closed"
    }
    // What the keyboard and the picker are doing, for scripts and for a bug
    // report. Read-only, and no key that was typed appears in either.
    function keyboardState(): string {
      return JSON.stringify({ visible: root.oskVisible,
                              page: keyboard.page, mods: keyboard.mods })
    }
    function pickerState(): string {
      return JSON.stringify({ open: root.pickerOpen, patched: root.pickerPatched,
                              nav: pickerNavWindow.visible })
    }
  }
}
