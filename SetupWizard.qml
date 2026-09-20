import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Ragtop's setup, in the shell rather than in a terminal.
//
// Everything install.sh does that doesn't need a terminal happens here: the
// settings rows, read access to the tablet-mode switch, and the patched
// copies of Omarchy's overlays. It writes the same things through the same
// scripts (menu-block.sh, udev-rule.sh, overlay-clones.sh), so a machine set
// up here and one set up from a terminal end up identical.
//
// The one thing it cannot do is install packages. It says which are missing,
// what each is for, and hands over the command — asking a plugin to run a
// package manager is a bigger thing than asking it to write a config file.
//
// It is built from Omarchy's own panel kit (BorderSurface, Button, Toggle,
// its Color/Style/Border tokens) so it looks like the rest of the desktop
// rather than like a guest.
Item {
  id: root

  // Service.qml
  required property var service
  signal finished()

  property int step: 0
  readonly property var steps: ["Welcome", "Dependencies", "Switch access", "Overlays", "Finish"]

  function script(name) {
    return Qt.resolvedUrl(name).toString().replace(/^file:\/\//, "")
  }

  // ---- dependencies -----------------------------------------------------

  // Each package, what it's for, and whether it's here. Ragtop runs without
  // any of them; it just does less, and the wording says exactly what less.
  property var deps: [
    { pkg: "iio-sensor-proxy", need: "Rotation. Without it the screen won't follow the hinge.", ok: false },
    { pkg: "python-pywayland", need: "The on-screen keyboard. Without it no keys are sent.", ok: false },
    { pkg: "python-gobject", need: "Noticing text fields, so the keyboard can come up by itself.", ok: false },
    { pkg: "git", need: "Cloning Omarchy's overlays, if you turn any on below.", ok: false }
  ]
  readonly property var missingDeps: deps.filter(function(d) { return !d.ok })
  property bool checkingDeps: false

  function checkDeps() {
    root.checkingDeps = true
    depsProc.running = true
  }

  Process {
    id: depsProc
    command: ["sh", "-c",
      'command -v monitor-sensor >/dev/null && echo iio-sensor-proxy; ' +
      'python3 -c "import pywayland" 2>/dev/null && echo python-pywayland; ' +
      'python3 -c "import gi" 2>/dev/null && echo python-gobject; ' +
      'command -v git >/dev/null && echo git; true']
    stdout: StdioCollector {
      onStreamFinished: {
        var present = text.split("\n").filter(function(s) { return s !== "" })
        root.deps = root.deps.map(function(d) {
          return { pkg: d.pkg, need: d.need, ok: present.indexOf(d.pkg) !== -1 }
        })
        root.checkingDeps = false
      }
    }
  }

  Process {
    id: copyProc
    command: ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "--",
      "sudo pacman -S --needed " + root.missingDeps.map(function(d) { return d.pkg }).join(" ")]
  }

  // ---- the tablet-mode switch -------------------------------------------

  // "readable", "unreadable", "installed-but-unreadable", "no-switch", or ""
  // while it's being looked at.
  property string switchState: ""
  property bool installingRule: false
  property var ruleLines: []

  Process {
    id: switchStatusProc
    command: ["bash", root.script("udev-rule.sh"), "status"]
    stdout: StdioCollector { onStreamFinished: root.switchState = text.trim() }
  }
  Process {
    id: ruleTextProc
    command: ["bash", root.script("udev-rule.sh"), "rule"]
    stdout: StdioCollector {
      onStreamFinished: root.ruleLines = text.split("\n").filter(function(s) { return s !== "" })
    }
  }
  // Tablet mode by hand, for a machine with no switch or no rule.
  property string manualMode: ""
  function setManualMode(mode) {
    root.manualMode = mode
    modeProc.command = ["bash", root.script("ragtop"), "tablet-mode", "set", mode]
    modeProc.running = true
  }
  Process { id: modeProc }

  Process {
    id: ruleInstallProc
    command: ["bash", root.script("udev-rule.sh"), "install"]
    onExited: {
      root.installingRule = false
      switchStatusProc.running = true
    }
  }

  // ---- Omarchy's overlays -----------------------------------------------

  property var overlays: [
    { id: "menu", label: "Omarchy Menu", detail: "Type to search it by touch.", on: false },
    { id: "emojis", label: "Emoji Picker", detail: "Search emoji by touch.", on: false },
    { id: "clipboard", label: "Clipboard Picker", detail: "Search your clipboard history by touch.", on: false },
    { id: "polkit", label: "Password Prompt", detail: "Type your password when something asks for it.", on: false },
    { id: "image-picker", label: "Image Picker", detail: "Arrows and a Select button for the theme and background pickers.", on: false },
    { id: "lock", label: "Lock Screen", detail: "A keyboard of its own, to unlock without a keyboard.", on: false }
  ]
  readonly property var chosenOverlays: overlays.filter(function(o) { return o.on })
  readonly property bool allOverlays: chosenOverlays.length === overlays.length
  // What is on the machine now, so setup can be run again to change it
  // rather than only to establish it.
  property var installedOverlays: []

  Process {
    id: overlayStatusProc
    command: ["bash", root.script("overlay-clones.sh"), "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var on = text.split("\n")
          .filter(function(l) { return l.indexOf(": installed") !== -1 })
          .map(function(l) { return l.slice(0, l.indexOf(":")) })
        root.installedOverlays = on
        root.overlays = root.overlays.map(function(o) {
          return { id: o.id, label: o.label, detail: o.detail, on: on.indexOf(o.id) !== -1 }
        })
      }
    }
  }

  function setOverlay(id, on) {
    root.overlays = root.overlays.map(function(o) {
      return { id: o.id, label: o.label, detail: o.detail, on: o.id === id ? on : o.on }
    })
  }
  function setAllOverlays(on) {
    root.overlays = root.overlays.map(function(o) {
      return { id: o.id, label: o.label, detail: o.detail, on: on }
    })
  }

  // ---- applying ---------------------------------------------------------

  property bool applying: false
  property string applyError: ""

  readonly property var overlaysToAdd: overlays.filter(function(o) {
    return o.on && root.installedOverlays.indexOf(o.id) === -1
  })
  readonly property var overlaysToDrop: overlays.filter(function(o) {
    return !o.on && root.installedOverlays.indexOf(o.id) !== -1
  })
  readonly property bool overlaysChange: overlaysToAdd.length > 0 || overlaysToDrop.length > 0

  function apply() {
    root.applying = true
    root.applyError = ""
    var ids = function(list) { return list.map(function(o) { return o.id }).join(" ") }
    var parts = ['"$1" add']
    if (root.overlaysToAdd.length > 0) parts.push('"$2" install ' + ids(root.overlaysToAdd))
    if (root.overlaysToDrop.length > 0) parts.push('"$2" remove ' + ids(root.overlaysToDrop))
    parts.push('mkdir -p "$HOME/.local/state/ragtop"')
    parts.push('printf "overlays=%s\\n" "' + ids(root.chosenOverlays)
               + '" > "$HOME/.local/state/ragtop/install.conf"')
    applyProc.command = ["bash", "-c", parts.join(" && "), "--",
                         root.script("menu-block.sh"), root.script("overlay-clones.sh")]
    applyProc.running = true
  }

  Process {
    id: applyProc
    stderr: StdioCollector { onStreamFinished: root.applyError = text.trim() }
    onExited: function(code) {
      root.applying = false
      if (code !== 0) return
      // Clones are only picked up when the shell starts; the settings rows
      // are read live, so a restart is only needed if any were turned on.
      if (root.overlaysChange) restartProc.running = true
      else root.finished()
    }
  }
  Process { id: restartProc; command: ["omarchy-restart-shell"] }

  // ---- the panel --------------------------------------------------------

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.7)
    MouseArea { anchors.fill: parent; onClicked: {} }
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    // Heights flow one way: the body asks for what it needs, the card gives
    // it what the screen allows, and the scroller takes what's left. Sizing
    // the scroller from the card's own height instead would be a loop.
    readonly property real gap: Style.space(12)
    readonly property real chrome: title.implicitHeight + buttons.implicitHeight + 2 + 4 * gap
    width: Math.min(parent.width - 2 * Style.gapsOut, Style.space(560))
    height: Math.min(parent.height - 2 * Style.gapsOut,
                     chrome + body.implicitHeight + 2 * Style.spacing.popupPadding)
    radius: Style.cornerRadius
    color: Color.popups.background
    borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border,
                                          Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding

    Column {
      id: content
      anchors.fill: parent
      anchors.margins: card.padding
      spacing: card.gap

      // Title, and where you are.
      Item {
        width: parent.width
        height: title.implicitHeight

        Text {
          id: title
          text: "Ragtop setup"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: title.verticalCenter
          text: "Step " + (root.step + 1) + " of " + root.steps.length + " · " + root.steps[root.step]
          color: Color.popups.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

      Flickable {
        width: parent.width
        height: card.height - 2 * card.padding - card.chrome
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Loader {
          id: body
          width: parent.width
          sourceComponent: root.step === 0 ? welcomeStep
            : root.step === 1 ? depsStep
            : root.step === 2 ? switchStep
            : root.step === 3 ? overlayStep : finishStep
        }
      }

      PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

      Row {
        id: buttons
        anchors.right: parent.right
        spacing: Style.space(8)

        Button {
          text: root.step === 0 ? "Not now" : "Back"
          bordered: true
          foreground: Color.popups.text
          onClicked: {
            if (root.step === 0) root.finished()
            else root.step = root.step - 1
          }
        }
        Button {
          text: root.step === root.steps.length - 1
            ? (root.applying ? "Applying…" : "Apply") : "Next"
          bordered: true
          foreground: root.step === root.steps.length - 1 ? Color.accent : Color.popups.text
          onClicked: {
            if (root.step < root.steps.length - 1) root.step = root.step + 1
            else if (!root.applying) root.apply()
          }
        }
      }
    }
  }

  // ---- the steps --------------------------------------------------------

  component Body: Text {
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  component Note: Text {
    color: Color.popups.text
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  // Omarchy's shell font is already a monospace family, so a path or a udev
  // rule reads as one without asking for a second font.
  component Mono: Text {
    color: Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WrapAnywhere
  }

  Component {
    id: welcomeStep
    Column {
      spacing: Style.space(10)

      Body {
        width: parent.width
        text: "Ragtop makes this machine work as a tablet: the screen follows the hinge, "
          + "an on-screen keyboard comes up when you need one, and the things that normally "
          + "want a keyboard or a mouse can be done by touch."
      }
      Body {
        width: parent.width
        text: "Setup touches three things outside Ragtop's own folder. Each is optional, "
          + "each is reversible, and nothing happens until the last step."
      }
      Note {
        width: parent.width
        text: "• Settings rows in your Omarchy menu, written as a marked block in "
          + "~/.config/omarchy/extensions/omarchy-menu.jsonc\n"
          + "• Read access to the tablet-mode switch, through a udev rule that needs your password\n"
          + "• Patched copies of Omarchy's own overlays, if you want to type into them by touch\n\n"
          + "It will not install packages for you, and it changes nothing else."
      }
    }
  }

  Component {
    id: depsStep
    Column {
      spacing: Style.space(10)

      Body {
        width: parent.width
        text: root.missingDeps.length === 0
          ? "Everything Ragtop needs is installed."
          : "Ragtop needs these from Arch's own repositories. It works without them — it just does less."
      }

      Repeater {
        model: root.deps

        Row {
          required property var modelData
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: modelData.ok ? "✓" : "✗"
            color: modelData.ok ? Color.accent : Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Column {
            width: parent.width - Style.space(28)
            spacing: 0
            Body { width: parent.width; text: modelData.pkg }
            Note { width: parent.width; text: modelData.need }
          }
        }
      }

      Note {
        width: parent.width
        visible: root.missingDeps.length > 0
        text: "Install them in a terminal, then come back and check again:"
      }
      Mono {
        width: parent.width
        visible: root.missingDeps.length > 0
        text: "sudo pacman -S --needed " + root.missingDeps.map(function(d) { return d.pkg }).join(" ")
      }
      Row {
        spacing: Style.space(8)
        Button {
          text: root.checkingDeps ? "Checking…" : "Check again"
          bordered: true
          foreground: Color.popups.text
          onClicked: root.checkDeps()
        }
        Button {
          visible: root.missingDeps.length > 0
          text: "Copy command"
          bordered: true
          foreground: Color.popups.text
          onClicked: copyProc.running = true
        }
      }
    }
  }

  Component {
    id: switchStep
    Column {
      spacing: Style.space(10)

      readonly property bool offering: root.switchState === "unreadable"
        || root.switchState === "installed-but-unreadable"
      readonly property bool noSwitch: root.switchState === "no-switch"

      Body {
        width: parent.width
        text: parent.noSwitch
          ? "Ragtop can notice a screen being folded back by reading a tablet-mode "
            + "switch — an input device the kernel exposes, like a keyboard or a mouse. "
            + "This machine reports none."
          : "Ragtop knows the screen has been folded back by reading the tablet-mode "
            + "switch — an input device the kernel exposes, like a keyboard or a mouse."
      }
      Body {
        width: parent.width
        visible: parent.offering
        text: "Only root can read it here. This rule tags switch devices — tablet mode, the "
          + "lid, the headphone jack — so whoever is logged in at the machine can read them. "
          + "Keyboards are excluded, which is the difference between this and joining the "
          + "input group."
      }
      Mono {
        width: parent.width
        visible: parent.offering && root.ruleLines.length > 1
        text: root.ruleLines.join("\n")
      }
      Button {
        visible: parent.offering
        text: root.installingRule ? "Waiting for your password…" : "Install the rule"
        bordered: true
        foreground: Color.accent
        onClicked: {
          root.installingRule = true
          ruleInstallProc.running = true
        }
      }
      Note {
        width: parent.width
        visible: parent.offering
        text: "Omarchy's password prompt will ask for your password (polkit, not sudo)."
      }

      Body {
        width: parent.width
        visible: root.switchState === "readable"
        text: "The switch is readable already — nothing to do here."
      }

      // A slate has no hinge to report, and a convertible whose switch stays
      // unreadable is no worse off than one: the rule buys automatic
      // switching and nothing else. Rotation, the keyboard and the overlays
      // don't go through it.
      Body {
        width: parent.width
        visible: parent.noSwitch || parent.offering
        text: parent.noSwitch
          ? "That is ordinary on a tablet with no keyboard — there is no hinge to report. "
            + "Tell Ragtop to stay in tablet mode and it will, for good."
          : "You can also skip it. The rule buys one thing: noticing the hinge by itself. "
            + "Rotation, the keyboard and everything else work without it. Set the mode by "
            + "hand instead."
      }
      Row {
        spacing: Style.space(8)
        visible: parent.noSwitch || parent.offering

        Button {
          text: root.manualMode === "on" ? "Tablet mode: always on ✓" : "Stay in tablet mode"
          bordered: true
          foreground: root.manualMode === "on" ? Color.accent : Color.popups.text
          onClicked: root.setManualMode("on")
        }
        Button {
          text: root.manualMode === "off" ? "Tablet mode: always off ✓" : "Stay in laptop mode"
          bordered: true
          foreground: root.manualMode === "off" ? Color.accent : Color.popups.text
          onClicked: root.setManualMode("off")
        }
      }
      Note {
        width: parent.width
        visible: parent.noSwitch || parent.offering
        text: "Either way it is a setting, not a decision: Setup › Tablet › Tablet Mode "
          + "changes it whenever you like. A detachable that reports a switch when its "
          + "keyboard comes off will be picked up on its own."
      }
    }
  }

  Component {
    id: overlayStep
    Column {
      spacing: Style.space(8)

      Body {
        width: parent.width
        text: "Omarchy's menu, its pickers, its password prompt and its lock screen can't be "
          + "typed into by touch as they ship. Ragtop can run patched copies of them instead."
      }
      Note {
        width: parent.width
        text: "A copy is Omarchy's own code — the password prompt and lock screen included — "
          + "living in your config where anything running as you can change it, and no longer "
          + "taking Omarchy's updates directly (a hook re-copies them after each update). "
          + "Leave them off if in doubt; they can be turned on one at a time later."
      }

      Toggle {
        width: parent.width
        label: "Turn them all on"
        description: "Every overlay below"
        checked: root.allOverlays
        foreground: Color.popups.text
        onClicked: root.setAllOverlays(!root.allOverlays)
      }

      PanelSeparator { width: parent.width; foreground: Color.popups.text }

      Repeater {
        model: root.overlays

        Toggle {
          required property var modelData
          width: parent.width
          label: modelData.label
          description: modelData.detail
          checked: modelData.on
          foreground: Color.popups.text
          onClicked: root.setOverlay(modelData.id, !modelData.on)
        }
      }
    }
  }

  Component {
    id: finishStep
    Column {
      spacing: Style.space(10)

      Body { width: parent.width; text: "Ready. Applying will:" }
      Note {
        width: parent.width
        text: "• add Ragtop's settings to your Omarchy menu, under Setup › Tablet\n"
          + (root.overlaysToAdd.length > 0
             ? "• make patched copies of: " + root.overlaysToAdd.map(function(o) { return o.label }).join(", ") + "\n"
             : "")
          + (root.overlaysToDrop.length > 0
             ? "• put back Omarchy's own: " + root.overlaysToDrop.map(function(o) { return o.label }).join(", ") + "\n"
             : "")
          + (root.overlaysChange
             ? "• restart the Omarchy shell, which is when copies are picked up"
             : "• leave Omarchy's overlays as they are")
      }
      Body {
        width: parent.width
        visible: root.missingDeps.length > 0
        text: "Still missing: " + root.missingDeps.map(function(d) { return d.pkg }).join(", ")
          + ". Setup will finish without them; install them whenever you like and Ragtop "
          + "will pick them up."
      }
      Body {
        width: parent.width
        visible: root.applyError !== ""
        color: Color.urgent
        text: root.applyError
      }
    }
  }

  Component.onCompleted: {
    root.checkDeps()
    switchStatusProc.running = true
    ruleTextProc.running = true
    overlayStatusProc.running = true
  }
}
