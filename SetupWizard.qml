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
// what each is for, and hands over the command, since asking a plugin to run a
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

  // Setup › Tablet › System Overlays opens this on the overlays alone: what
  // is on now, ticked; as many changes as you like, none of them made yet;
  // and one Apply for all of them, since each one made restarts the shell.
  // Closing it without applying changes nothing.
  property bool overlaysOnly: false

  property int step: 0
  readonly property var steps: root.overlaysOnly ? ["setup.step.overlays"]
    : ["setup.step.welcome", "setup.step.deps", "setup.step.switch", "setup.step.overlays", "setup.step.finish"]

  function script(name) {
    return Qt.resolvedUrl(name).toString().replace(/^file:\/\//, "")
  }

  // ---- dependencies -----------------------------------------------------

  // Each package, what it's for, and whether it's here. Ragtop runs without
  // any of them. It just does less, and the wording says exactly what less.
  property var deps: [
    { pkg: "iio-sensor-proxy", need: "setup.need.sensor", ok: false },
    { pkg: "python-pywayland", need: "setup.need.pywayland", ok: false },
    { pkg: "python-gobject", need: "setup.need.gobject", ok: false },
    { pkg: "git", need: "setup.need.git", ok: false }
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
      '/usr/bin/python3 -c "import pywayland" 2>/dev/null && echo python-pywayland; ' +
      '/usr/bin/python3 -c "import gi" 2>/dev/null && echo python-gobject; ' +
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

  // Omarchy's own floating terminal, with the command already in it. Setup
  // steps aside while it runs and comes back when it is done, so the check
  // that follows sees what was installed.
  function installInTerminal() {
    root.service.runSetupTerminal("omarchy pkg add "
      + root.missingDeps.map(function(d) { return d.pkg }).join(" "))
  }

  Process {
    id: copyProc
    command: ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "--",
      "omarchy pkg add " + root.missingDeps.map(function(d) { return d.pkg }).join(" ")]
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
    { id: "menu", label: "setup.overlayName.menu", detail: "setup.overlay.menu", on: false },
    { id: "emojis", label: "setup.overlayName.emojis", detail: "setup.overlay.emojis", on: false },
    { id: "clipboard", label: "setup.overlayName.clipboard", detail: "setup.overlay.clipboard", on: false },
    { id: "polkit", label: "setup.overlayName.polkit", detail: "setup.overlay.polkit", on: false },
    { id: "image-picker", label: "setup.overlayName.image-picker", detail: "setup.overlay.image-picker", on: false },
    { id: "lock", label: "setup.overlayName.lock", detail: "setup.overlay.lock", on: false }
  ]
  readonly property var chosenOverlays: overlays.filter(function(o) { return o.on })
  readonly property bool allOverlays: chosenOverlays.length === overlays.length
  // What is on the machine now, so setup can be run again to change it
  // rather than only to establish it. Until it has been read, every toggle
  // shows off, and applying then would take every overlay away: nothing is
  // applied before it has (overlaysRead).
  property var installedOverlays: []
  property bool overlaysRead: false

  Process {
    id: overlayStatusProc
    command: ["bash", root.script("overlay-clones.sh"), "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var on = text.split("\n")
          .filter(function(l) { return l.indexOf(": installed") !== -1 })
          .map(function(l) { return l.slice(0, l.indexOf(":")) })
        root.installedOverlays = on
        root.overlaysRead = true
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

  // Applying hands the work to a transient systemd unit, and lets go.
  //
  // Copying an overlay replaces one of Omarchy's own plugins, and the shell
  // reloads its plugins when that happens, taking this service, this window,
  // and any child process of it down mid-sentence. That is exactly what
  // happened on the first machine this was tried on: the menu and the emoji
  // picker were copied, the shell reloaded, and the rest of the work died
  // with it, leaving nothing recorded. A session of its own was not enough,
  // because the shell still owned the process that started it.
  //
  // So the work goes to `systemd-run --user`, which outlives the shell
  // entirely, and it reports for itself when it is done rather than relying
  // on a window that may no longer exist.
  // Whether Apply has anything to do. The full setup always does: it writes
  // the menu rows and the record even with no overlay changing.
  readonly property bool canApply: root.overlaysRead && !root.applying
    && (!root.overlaysOnly || root.overlaysChange)

  function apply() {
    if (!root.canApply) return
    root.applying = true
    root.applyError = ""
    var ids = function(list) { return list.map(function(o) { return o.id }).join(" ") }
    applyProc.command = ["systemd-run", "--user", "--quiet", "--collect",
                         "--unit", "ragtop-setup-apply",
                         "bash", root.script("setup-apply.sh"),
                         ids(root.overlaysToAdd), ids(root.overlaysToDrop), ids(root.chosenOverlays)]
    applyProc.running = true
  }

  Process {
    id: applyProc
    stderr: StdioCollector { onStreamFinished: root.applyError = text.trim() }
    // This only reports whether the work was handed over, not how it went:
    // the unit outlives this window on purpose, and says for itself when it
    // is finished. Nothing was turned on or off means nothing restarts, so
    // there is nothing to wait for either.
    onExited: function(code) {
      root.applying = false
      if (code === 0) root.finished()
    }
  }

  // ---- the panel --------------------------------------------------------

  // The dimming is drawn over the whole screen but takes no input: the
  // service masks this surface to the card alone. A step that tells you to
  // run a command somewhere else should not also be the thing stopping you
  // from reaching a terminal.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Color.background, 0.7)
  }

  readonly property Item card: cardSurface

  BorderSurface {
    id: cardSurface
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
      anchors.margins: cardSurface.padding
      spacing: cardSurface.gap

      // Title, and where you are.
      Item {
        width: parent.width
        height: title.implicitHeight

        Text {
          // Never rich text. A window title, a layout name and an error
          // string all arrive from outside, and AutoText would sniff markup
          // in them and render it, which for Qt includes fetching a remote
          // image named in an img tag.
          textFormat: Text.PlainText
          id: title
          text: root.overlaysOnly ? root.service.t("setup.overlays.title") : root.service.t("setup.title")
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          // Never rich text. A window title, a layout name and an error
          // string all arrive from outside, and AutoText would sniff markup
          // in them and render it, which for Qt includes fetching a remote
          // image named in an img tag.
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.verticalCenter: title.verticalCenter
          visible: !root.overlaysOnly
          text: root.service.t("setup.stepOf", root.step + 1, root.steps.length, root.service.t(root.steps[root.step]))
          color: Color.popups.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

      Flickable {
        width: parent.width
        height: cardSurface.height - 2 * cardSurface.padding - cardSurface.chrome
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
          text: root.overlaysOnly ? root.service.t("setup.cancel")
            : root.step === 0 ? root.service.t("setup.notNow") : root.service.t("setup.back")
          bordered: true
          foreground: Color.popups.text
          onClicked: {
            if (root.step === 0) root.finished()
            else root.step = root.step - 1
          }
        }
        Button {
          readonly property bool last: root.step === root.steps.length - 1
          text: last
            ? (root.applying ? root.service.t("setup.applying") : root.service.t("setup.apply")) : root.service.t("setup.next")
          bordered: true
          enabled: !last || root.canApply
          opacity: enabled ? 1 : 0.5
          foreground: last ? Color.accent : Color.popups.text
          onClicked: {
            if (!last) root.step = root.step + 1
            else root.apply()
          }
        }
      }
    }
  }

  // ---- the steps --------------------------------------------------------

  component Body: Text {
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  component Note: Text {
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
    color: Color.popups.text
    opacity: 0.65
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  // Omarchy's shell font is already a monospace family, so a path or a udev
  // rule reads as one without asking for a second font.
  component Mono: Text {
    // Never rich text. A window title, a layout name and an error
    // string all arrive from outside, and AutoText would sniff markup
    // in them and render it, which for Qt includes fetching a remote
    // image named in an img tag.
    textFormat: Text.PlainText
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
        text: root.service.t("setup.welcome.body")
      }
      Body {
        width: parent.width
        text: root.service.t("setup.welcome.touches")
      }
      Note {
        width: parent.width
        text: root.service.t("setup.welcome.list")
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
          ? root.service.t("setup.deps.allHere")
          : root.service.t("setup.deps.missing")
      }

      Repeater {
        model: root.deps

        Row {
          required property var modelData
          width: parent.width
          spacing: Style.space(8)

          Text {
            // Never rich text. A window title, a layout name and an error
            // string all arrive from outside, and AutoText would sniff markup
            // in them and render it, which for Qt includes fetching a remote
            // image named in an img tag.
            textFormat: Text.PlainText
            text: modelData.ok ? "✓" : "✗"
            color: modelData.ok ? Color.accent : Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Column {
            width: parent.width - Style.space(28)
            spacing: 0
            Body { width: parent.width; text: modelData.pkg }
            Note { width: parent.width; text: root.service.t(modelData.need) }
          }
        }
      }

      Note {
        width: parent.width
        visible: root.missingDeps.length > 0
        text: root.service.t("setup.deps.how")
      }
      Mono {
        width: parent.width
        visible: root.missingDeps.length > 0
        text: "omarchy pkg add " + root.missingDeps.map(function(d) { return d.pkg }).join(" ")
      }
      Row {
        spacing: Style.space(8)
        Button {
          text: root.checkingDeps ? root.service.t("setup.deps.checking") : root.service.t("setup.deps.checkAgain")
          bordered: true
          foreground: Color.popups.text
          onClicked: root.checkDeps()
        }
        Button {
          visible: root.missingDeps.length > 0
          text: root.service.t("setup.deps.terminal")
          bordered: true
          foreground: Color.accent
          onClicked: root.installInTerminal()
        }
        Button {
          visible: root.missingDeps.length > 0
          text: root.service.t("setup.deps.copy")
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
          ? root.service.t("setup.switch.none")
          : root.service.t("setup.switch.what")
      }
      Body {
        width: parent.width
        visible: parent.offering
        text: root.service.t("setup.switch.rule")
      }
      Mono {
        width: parent.width
        visible: parent.offering && root.ruleLines.length > 1
        text: root.ruleLines.join("\n")
      }
      Button {
        visible: parent.offering
        text: root.installingRule ? root.service.t("setup.switch.waiting") : root.service.t("setup.switch.install")
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
        text: root.service.t("setup.switch.polkit")
      }

      Body {
        width: parent.width
        visible: root.switchState === "readable"
        text: root.service.t("setup.switch.readable")
      }

      // A slate has no hinge to report, and a convertible whose switch stays
      // unreadable is no worse off than one: the rule buys automatic
      // switching and nothing else. Rotation, the keyboard and the overlays
      // don't go through it.
      Body {
        width: parent.width
        visible: parent.noSwitch || parent.offering
        text: parent.noSwitch
          ? root.service.t("setup.switch.tablet")
          : root.service.t("setup.switch.skip")
      }
      Row {
        spacing: Style.space(8)
        visible: parent.noSwitch || parent.offering

        Button {
          text: root.manualMode === "on" ? root.service.t("setup.switch.alwaysOn") : root.service.t("setup.switch.stayTablet")
          bordered: true
          foreground: root.manualMode === "on" ? Color.accent : Color.popups.text
          onClicked: root.setManualMode("on")
        }
        Button {
          text: root.manualMode === "off" ? root.service.t("setup.switch.alwaysOff") : root.service.t("setup.switch.stayLaptop")
          bordered: true
          foreground: root.manualMode === "off" ? Color.accent : Color.popups.text
          onClicked: root.setManualMode("off")
        }
      }
      Note {
        width: parent.width
        visible: parent.noSwitch || parent.offering
        text: root.service.t("setup.switch.either")
      }
    }
  }

  Component {
    id: overlayStep
    Column {
      spacing: Style.space(8)

      Body {
        width: parent.width
        text: root.service.t("setup.overlays.why")
      }
      Note {
        width: parent.width
        text: root.service.t("setup.overlays.catch")
      }

      Toggle {
        width: parent.width
        label: root.service.t("setup.overlays.all")
        description: root.service.t("setup.overlays.allDetail")
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
          label: root.service.t(modelData.label)
          description: root.service.t(modelData.detail)
          checked: modelData.on
          foreground: Color.popups.text
          onClicked: root.setOverlay(modelData.id, !modelData.on)
        }
      }

      // On its own, this is also the last page: what Apply will do, before
      // anything is done.
      PanelSeparator { visible: root.overlaysOnly; width: parent.width; foreground: Color.popups.text }
      Note {
        visible: root.overlaysOnly
        width: parent.width
        text: !root.overlaysRead ? root.service.t("setup.overlays.reading")
          : !root.overlaysChange ? root.service.t("setup.overlays.unchanged")
          : root.service.t("setup.overlays.will") + "\n"
            + (root.overlaysToAdd.length > 0
               ? "• " + root.service.t("setup.finish.add", root.overlaysToAdd.map(function(o) { return root.service.t(o.label) }).join(", ")) + "\n"
               : "")
            + (root.overlaysToDrop.length > 0
               ? "• " + root.service.t("setup.finish.drop", root.overlaysToDrop.map(function(o) { return root.service.t(o.label) }).join(", ")) + "\n"
               : "")
            + "• " + root.service.t("setup.finish.restart")
      }
      Body {
        width: parent.width
        visible: root.overlaysOnly && root.applyError !== ""
        color: Color.urgent
        text: root.applyError
      }
    }
  }

  Component {
    id: finishStep
    Column {
      spacing: Style.space(10)

      Body { width: parent.width; text: root.service.t("setup.finish.ready") }
      Note {
        width: parent.width
        // A line each, whole sentences with the overlays' names put in.
        text: "• " + root.service.t("setup.finish.menu") + "\n"
          + (root.overlaysToAdd.length > 0
             ? "• " + root.service.t("setup.finish.add", root.overlaysToAdd.map(function(o) { return root.service.t(o.label) }).join(", ")) + "\n"
             : "")
          + (root.overlaysToDrop.length > 0
             ? "• " + root.service.t("setup.finish.drop", root.overlaysToDrop.map(function(o) { return root.service.t(o.label) }).join(", ")) + "\n"
             : "")
          + "• " + (root.overlaysChange ? root.service.t("setup.finish.restart") : root.service.t("setup.finish.leave"))
      }
      Body {
        width: parent.width
        visible: root.missingDeps.length > 0
        text: root.service.t("setup.finish.missing", root.missingDeps.map(function(d) { return d.pkg }).join(", "))
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
    overlayStatusProc.running = true
    if (root.overlaysOnly) return
    root.checkDeps()
    switchStatusProc.running = true
    ruleTextProc.running = true
  }
}
