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

  readonly property string oskDest: "sm.puri.OSK0"
  readonly property string oskPath: "/sm/puri/OSK0"

  function configure(device, locked) {
    root.tabletSwitchDevice = device || ""
    root.rotationLocked = locked
    configureFallback.stop()
    // Locking just means "stop watching the orientation", which freezes the
    // display at whatever orientation it's currently in.
    if (locked) { orientationSettle.stop(); lockRecheck.stop() }
    rotationProc.running = !locked
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
    // Shown straight away; the visibility poll corrects it if it didn't take.
    root.oskVisible = visible
    if (root.keyboardEngine !== "squeekboard") return
    oskToggleProc.command = [
      "gdbus", "call", "--session",
      "--dest", root.oskDest,
      "--object-path", root.oskPath,
      "--method", root.oskDest + ".SetVisible",
      visible ? "true" : "false"
    ]
    oskToggleProc.running = true
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
      required property var modelData
      screen: modelData
      visible: root.tabletMode

      WlrLayershell.namespace: "ragtop-keyboard-handle"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Auto
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.handleHeight
      color: root.barTransparent ? "transparent" : Color.bar.background

      MouseArea {
        id: handleArea
        anchors.fill: parent
        onClicked: root.toggleOsk()
      }

      // A wide ^ while the keyboard is hidden, a wide v while it's showing.
      Shape {
        anchors.centerIn: parent
        width: 56
        height: 8
        opacity: handleArea.pressed ? 0.5 : 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          strokeColor: Color.bar.text
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
    onTriggered: rotationProc.running = !root.rotationLocked
  }

  // Orientation comes from iio-sensor-proxy, through its monitor-sensor
  // tool, which prints the current orientation on start and every change
  // after. Changes are applied once the sensor settles, since a tilt can
  // pass through several in quick succession.
  property string pendingOrientation: ""
  property string appliedOrientation: ""
  readonly property var orientationTransforms:
    ({ "normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3 })

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
    onExited: if (!root.rotationLocked) rotationRestart.start()
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
    onTriggered: if (!root.rotationLocked) rotationProc.running = true
  }

  // Which on-screen keyboard: squeekboard, or Ragtop's own (Keyboard.qml).
  // Only one runs; squeekboard is stopped while Ragtop's is chosen.
  readonly property string keyboardEngine: root.settings["keyboard"] === "ragtop" ? "ragtop" : "squeekboard"
  // Ragtop's keyboard only: modifiers apply to the next key ("oneshot") or
  // stay on until tapped again ("sticky").
  readonly property string modifierMode: root.settings["modifiers"] === "sticky" ? "sticky" : "oneshot"
  onKeyboardEngineChanged: {
    root.setOskVisible(false)
    if (root.keyboardEngine === "squeekboard") root.startSqueekboard()
    else oskProc.running = false
  }
  function startSqueekboard() {
    if (root.keyboardEngine === "squeekboard") oskProc.running = true
  }

  Process {
    id: oskProc
    command: ["squeekboard"]
    // Layouts with a Super key, generated by squeekboard-layouts.py; any
    // layout missing there falls back to squeekboard's built-in one.
    environment: ({ SQUEEKBOARD_KEYBOARDSDIR: Quickshell.env("HOME") + "/.local/state/ragtop/keyboards" })
    onExited: oskRestart.start()
  }
  Timer { id: oskRestart; interval: 3000; onTriggered: root.startSqueekboard() }

  // Settings written by the `ragtop` command (Setup › Tablet in the
  // Omarchy menu), as key=value lines; a missing key keeps its default.
  property var settings: ({})
  property bool settingsLoaded: false

  // Whether Omarchy's bar is transparent (Style › Bar › Transparency), passed
  // on by the bar widget; the keyboard handle and, by default, the keyboard's
  // background follow it.
  property bool barTransparent: false
  FileView {
    path: Quickshell.env("HOME") + "/.config/ragtop/settings.conf"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
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
    }
  }
  readonly property bool autoShowEnabled: root.settings["auto-show"] !== "off"

  // Squeekboard takes its layout from a GNOME setting Omarchy leaves empty;
  // layout-sync.sh fills it from Hyprland's layouts, active one first, and
  // --restore puts back what was there when the "layout-sync" setting is off.
  readonly property bool layoutSyncEnabled: root.settings["layout-sync"] !== "off"
  property string lastLayoutName: ""
  onSettingsLoadedChanged: layoutSync.restart()
  onLayoutSyncEnabledChanged: layoutSync.restart()
  Process { id: layoutSyncProc }
  Timer {
    id: layoutSync
    interval: 300
    onTriggered: {
      if (!root.settingsLoaded) return
      if (layoutSyncProc.running) { layoutSync.restart(); return }
      layoutSyncProc.command = ["bash", Qt.resolvedUrl("layout-sync.sh").toString().replace(/^file:\/\//, "")]
        .concat(root.layoutSyncEnabled ? [] : ["--restore"])
      layoutSyncProc.running = true
    }
  }

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
        if (line === "show" && root.tabletMode && root.autoShowEnabled && !root.oskVisible) root.setOskVisible(true)
      }
    }
    onExited: if (root.tabletMode && root.autoShowEnabled) focusBridgeRestart.start()
  }
  Timer {
    id: focusBridgeRestart
    interval: 5000
    onTriggered: focusBridgeProc.running = root.tabletMode && root.autoShowEnabled
  }

  // Squeekboard only reads GTK CSS at startup. ~/.config/gtk-3.0/gtk.css
  // imports the file written here, so a theme or font change means rewrite
  // then restart. The first write happens before squeekboard's first start.
  // With the "auto-theme" setting off, only the rules Ragtop's own key row
  // needs are written, leaving squeekboard's stock look.
  readonly property string themeScript:
    Qt.resolvedUrl("squeekboard-theme.sh").toString().replace(/^file:\/\//, "")
  readonly property bool autoThemeEnabled: root.settings["auto-theme"] !== "off"
  // "auto" follows Omarchy's bar transparency (Style › Bar › Transparency),
  // which is either fully clear or solid.
  readonly property string keyboardTransparency: {
    var level = root.settings["transparency"]
    if (["opaque", "low", "medium", "high", "full"].indexOf(level) !== -1) return level
    return root.barTransparent ? "full" : "opaque"
  }
  property string themeCss: ""
  property bool themeChecked: false
  onAutoThemeEnabledChanged: themeCheck.restart()
  onKeyboardTransparencyChanged: themeCheck.restart()

  function applyThemeCss(css) {
    var first = !root.themeChecked
    root.themeChecked = true
    if (css === "" || css === root.themeCss) {
      if (first) root.startSqueekboard()
      return
    }
    root.themeCss = css
    themeWriteProc.restartOsk = !first
    themeWriteProc.command = [
      "sh", "-c",
      'd="$HOME/.local/state/ragtop" && mkdir -p "$d" && printf "%s" "$1" > "$d/squeekboard.css.tmp" && mv -f "$d/squeekboard.css.tmp" "$d/squeekboard.css"',
      "--", css
    ]
    themeWriteProc.running = true
  }

  Process {
    id: themeProc
    command: root.autoThemeEnabled
      ? ["sh", root.themeScript, "--transparency", root.keyboardTransparency]
      : ["sh", root.themeScript, "--no-theme"]
    stdout: StdioCollector {
      onStreamFinished: root.applyThemeCss(text)
    }
  }
  Process {
    id: themeWriteProc
    property bool restartOsk: false
    // Stopping squeekboard lets oskProc's own exit handler bring it back.
    onExited: if (restartOsk) oskProc.running = false; else root.startSqueekboard()
  }
  // Waits for the settings, so squeekboard's first start already has the
  // look they ask for.
  Timer {
    id: themeCheck
    interval: 5000
    running: root.settingsLoaded
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!themeProc.running) themeProc.running = true
  }

  Process { id: oskToggleProc }
  Process { id: modeWriteProc }

  // A plugin added with `omarchy plugin add` runs without install.sh having
  // set up its config lines, layouts and overlay patches. Check once per
  // session and offer to run the installer; installing a plugin never runs
  // its code, so this asks rather than doing it.
  readonly property string installScript:
    Qt.resolvedUrl("install.sh").toString().replace(/^file:\/\//, "")

  function offerSetup(problems) {
    if (problems.length === 0) return
    var shown = problems.slice(0, 3)
    if (problems.length > 3) shown.push("…and " + (problems.length - 3) + " more.")
    setupNotifyProc.command = [
      "omarchy-notification-send", "-g", "󰌌",
      "Ragtop needs setup",
      shown.join("\n") + "\nClick to run the installer.",
      "--exec", "omarchy-launch-floating-terminal-with-presentation",
      "'" + root.installScript.replace(/'/g, "'\\''") + "'"
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

  Process {
    id: patchCheckProc
    command: ["sh", "-c",
      'for p in menu:Menu emojis:Emojis clipboard:Clipboard polkit:PolkitAgent; do ' +
      'grep -qs "id: ragtopMode" "$HOME/.config/omarchy/plugins/$USER.${p%%:*}/${p#*:}.qml" && echo "omarchy-${p%%:*}"; ' +
      'done; true']
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.patchedOverlays = text.split("\n").filter(function(s) { return s !== "" })
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      // Hyprland also sends activelayout whenever input switches between
      // keyboards, including every key from squeekboard, fcitx5 and Ragtop's
      // helper, so only a real keyboard changing layout counts.
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
      if (layoutChanged) {
        layoutSync.restart()
        root.sendKeys("reload")
      }
      if (name !== "openlayer" && name !== "closelayer") return
      var ns = String(event.data || "")
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

  // Poll the tablet-mode switch.
  Process {
    id: tabletModeProc
    command: ["evtest", "--query", root.switchDevice, "EV_SW", "SW_TABLET_MODE"]
    onExited: function(exitCode) { root.applySwitchReading(exitCode === 10) }
  }
  Timer {
    interval: 1000
    running: root.switchDevice !== "" && root.tabletModeSetting === "auto"
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
    running: root.keyboardEngine === "squeekboard"
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!oskVisProc.running) oskVisProc.running = true
  }

  // ---- Ragtop's own keyboard ------------------------------------------

  // Sends its keys: QML can't be a Wayland virtual keyboard itself.
  Process {
    id: keyboardHelper
    command: ["python3", Qt.resolvedUrl("keyboard-helper.py").toString().replace(/^file:\/\//, "")]
    running: root.keyboardEngine === "ragtop"
    stdinEnabled: true
    onExited: if (root.keyboardEngine === "ragtop") keyboardHelperRestart.start()
  }
  Timer {
    id: keyboardHelperRestart
    interval: 3000
    onTriggered: keyboardHelper.running = root.keyboardEngine === "ragtop"
  }

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
  }

  // On the built-in screen, reserving its space like squeekboard. It never
  // takes keyboard focus, so typing goes to the window underneath. Created
  // when shown, so it stacks above the handle.
  PanelWindow {
    id: keyboardWindow
    screen: Quickshell.screens.find(function(s) { return s.name === root.internalMonitorName() }) || Quickshell.screens[0]
    visible: root.keyboardEngine === "ragtop" && root.oskVisible

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

  // omarchy-shell ragtop <function>: for keybindings and scripts.
  IpcHandler {
    target: "ragtop"

    function showKeyboard(): string { root.setOskVisible(true); return "ok" }
    function hideKeyboard(): string { root.setOskVisible(false); return "ok" }
    function toggleKeyboard(): string { root.toggleOsk(); return "ok" }
    function keyboardVisible(): string { return root.oskVisible ? "true" : "false" }
    // Presses and releases a key of Ragtop's keyboard by name ("q", "shift",
    // "ctrl", "enter"...), as a tap would. For testing and automation.
    function tapKey(key: string): string {
      if (root.keyboardEngine !== "ragtop" || !keyboardWindow.visible) return "keyboard not shown"
      keyboard.press(key)
      keyboard.release(key)
      return "ok"
    }
    function keyboardState(): string {
      return JSON.stringify({ engine: root.keyboardEngine, visible: root.oskVisible,
                              page: keyboard.page, mods: keyboard.mods, modifierMode: root.modifierMode })
    }
  }
}
