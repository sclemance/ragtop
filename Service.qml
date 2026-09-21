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
  property bool rotationLocked: false
  property bool tabletMode: false
  property bool oskVisible: false

  function configure(device, locked) {
    root.tabletSwitchDevice = device || ""
    root.rotationLocked = locked
    configureFallback.stop()
    // Locking just means "stop watching the orientation", which freezes the
    // display at whatever orientation it's currently in.
    if (locked) { orientationSettle.stop(); lockRecheck.stop() }
    rotationProc.running = !locked && root.rotationAvailable
  }

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
      implicitHeight: root.handleHeight
      color: "transparent"

      Rectangle {
        anchors.fill: parent
        color: handle.fill
        Behavior on color { ColorAnimation { duration: 150 } }
      }

      MouseArea {
        id: handleArea
        anchors.fill: parent
        onClicked: root.toggleOsk()
      }

      // A wide ^ while the keyboard is hidden, a wide v while it's showing.
      Shape {
        id: chevron
        anchors.centerIn: parent
        width: 56
        height: 8
        opacity: handleArea.pressed ? 0.5 : 1
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
    onTriggered: rotationProc.running = !root.rotationLocked && root.rotationAvailable
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
  Process {
    id: sensorCheckProc
    running: true
    command: ["sh", "-c", "command -v monitor-sensor >/dev/null"]
    onExited: function(code) {
      root.rotationAvailable = code === 0
      if (root.rotationAvailable) rotationProc.running = !root.rotationLocked
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
    onRunningChanged: if (running) root.appliedOrientation = ""
    stdout: SplitParser {
      onRead: function(line) {
        var match = /orientation(?: changed)?: ([a-z-]+)/.exec(line)
        if (!match || !(match[1] in root.orientationTransforms)) return
        root.pendingOrientation = match[1]
        orientationSettle.restart()
      }
    }
    onExited: if (!root.rotationLocked && root.rotationAvailable) rotationRestart.start()
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
  Process { id: rotateApplyProc }
  Timer {
    id: rotationRestart
    interval: 3000
    onTriggered: if (!root.rotationLocked && root.rotationAvailable) rotationProc.running = true
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
  readonly property string modifierMode: root.settings["modifiers"] === "sticky" ? "sticky" : "oneshot"

  // In tablet mode, bring the keyboard up when a text field gets focus. The
  // bridge learns about focus from fcitx5, Omarchy's input method, and prints
  // "show"; hiding stays with the user (see fcitx-osk-bridge.py for why).
  // Stopping it hands fcitx5 back its own interface.
  Process {
    id: focusBridgeProc
    command: ["python3", Qt.resolvedUrl("fcitx-osk-bridge.py").toString().replace(/^file:\/\//, "")]
    running: root.tabletMode && root.autoShowEnabled
    stdout: SplitParser {
      onRead: function(line) {
        if (line === "show" && root.tabletMode && root.autoShowEnabled && !root.oskVisible && !root.pickerOpen)
          root.setOskVisible(true)
      }
    }
    onExited: if (root.tabletMode && root.autoShowEnabled) focusBridgeRestart.start()
  }
  Timer {
    id: focusBridgeRestart
    interval: 5000
    onTriggered: focusBridgeProc.running = root.tabletMode && root.autoShowEnabled
  }

  // The keyboard's background transparency. "auto" follows Omarchy's bar
  // transparency (Style › Bar › Transparency), which is either fully clear
  // or solid.
  readonly property string keyboardTransparency: {
    var level = root.settings["transparency"]
    if (["opaque", "low", "medium", "high", "full"].indexOf(level) !== -1) return level
    return root.barTransparent ? "full" : "opaque"
  }

  Process { id: modeWriteProc }

  // A plugin added with `omarchy plugin add` runs without install.sh having
  // set up its config lines, layouts and overlay patches. Check once per
  // session and offer to run the installer; installing a plugin never runs
  // its code, so this asks rather than doing it.
  readonly property string installScript:
    Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, "")

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
  onSwitchDeviceChanged: if (tabletModeProc.running) tabletModeProc.running = false
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
    onExited: {
      if (root.tabletSwitchDevice === "" && !detectProc.running) detectProc.running = true
      if (root.watchSwitch) tabletModeRestart.start()
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
    onExited: keyboardHelperRestart.start()
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

  KeyboardTheme {
    id: keyboardTheme
    backgroundOpacity: ({ "opaque": 1, "low": 0.85, "medium": 0.7, "high": 0.5, "full": 0 })[root.keyboardTransparency]
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
      // How see-through the keys are, over the keyboard's background.
      keyTransparency: pick("key-transparency", ["opaque", "low", "medium", "high", "full"], "opaque"),
      // Raised keys stand on a side, like a keycap; flat ones don't.
      relief: pick("relief", ["flat", "raised"], "flat"),
      fill: pick("fill", ["auto", "dark", "light", "outline"], "light"),
      size: pick("size", ["compact", "normal", "large"], "normal"),
      background: pick("background", ["tint", "gradient"], "tint"),
      edge: pick("edge", ["border", "fade", "none"], "none"),
      labels: pick("labels", ["small", "normal", "large"], "normal"),
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
      "hl.layer_rule({ match = { namespace = '^ragtop-keyboard-handle$' }, order = -1 }) "
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
  // and tapping a fullscreen window doesn't move focus. So in tablet mode
  // the screen stays covered until a key is pressed — no use on a folded
  // laptop.
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
    visible: root.tabletMode && root.screensaverAddress !== "" && root.layerRulesReady

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
  IpcHandler {
    target: "ragtop"

    function showKeyboard(): string { root.setOskVisible(true); return "ok" }
    function hideKeyboard(): string { root.setOskVisible(false); return "ok" }
    function toggleKeyboard(): string { root.toggleOsk(); return "ok" }
    function keyboardVisible(): string { return root.oskVisible ? "true" : "false" }
    function openSetup(): string { root.openSetup(); return "ok" }
    function closeSetup(): string { root.setupOpen = false; return "ok" }
    // Presses and releases a key of the keyboard by name ("q", "shift",
    // "ctrl", "enter"...), as a tap would. For testing and automation.
    function tapKey(key: string): string {
      if (!keyboardWindow.visible) return "keyboard not shown"
      keyboard.press(key)
      keyboard.release(key)
      return "ok"
    }
    function keyboardState(): string {
      return JSON.stringify({ visible: root.oskVisible,
                              page: keyboard.page, mods: keyboard.mods, modifierMode: root.modifierMode })
    }
    // Presses and releases one of the picker nav strip's buttons ("prev",
    // "select", "next", "cancel"), as a tap would. Only while the strip is
    // up, so its keys can only ever reach the picker. For testing.
    function tapPickerNav(button: string): string {
      if (!pickerNavWindow.visible) return "picker nav not shown"
      var found = pickerNav.buttons.filter(function(b) { return b.name === button })
      if (found.length === 0) return "no such button: " + button
      pickerNav.press(found[0])
      pickerNav.release(found[0])
      return "ok"
    }
    function pickerState(): string {
      return JSON.stringify({ open: root.pickerOpen, patched: root.pickerPatched,
                              nav: pickerNavWindow.visible })
    }
  }
}
