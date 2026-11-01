import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "menu" as Menu
import "picker" as Picker

// What the patched clones ask of their window, in laptop and in tablet mode.
// Tablet mode is set the way Ragtop sets it, by replacing the mode file.
ShellRoot {
  id: test

  Harness { id: t }
  Menu.Entry { id: menu }
  Picker.Entry { id: picker }

  FileView {
    id: modeFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ragtop-mode"
    preload: false
    blockWrites: true
  }
  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/ragtop/settings.conf"
    preload: false
    blockWrites: true
  }
  function setKeyboard(mode) { settingsFile.setText("keyboard=" + mode + "\n") }
  function setMode(mode) { modeFile.setText(mode + "\n") }

  function focus(entry) { return entry.panel.layershell.keyboardFocus }

  // The one screen there is, as Hyprland would describe it, and a surface
  // the size of it.
  readonly property var screen: Quickshell.screens[0]
  function plugIn(entry) {
    entry.panel.hyprland.monitors = { values: [{ name: test.screen.name, scale: 1 }] }
    test.fill(entry, 0)
  }
  // The surface as the compositor would size it with this much of the
  // screen's height reserved by something else.
  function fill(entry, reserved) {
    entry.panel.width = test.screen.width
    entry.panel.height = test.screen.height - reserved
  }

  // Long enough for a watched file to be noticed and the focus prime to run
  // out, with room to spare on a busy machine.
  readonly property int settle: 400

  Component.onCompleted: t.run([
    [test.settle, function() {
      test.plugIn(menu)
      test.plugIn(picker)
      t.equal(menu.panel.layershell.namespace, "omarchy-menu", "the menu keeps its namespace")
      t.equal(menu.panel.visible, false, "laptop, closed: not mapped")
      menu.opened = true
      t.equal(menu.panel.visible, false, "laptop: not mapped until the menu's rows have loaded")
      menu.rowsLoaded = true
      t.equal(menu.panel.visible, true, "laptop, open: mapped")
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "laptop, open: exclusive focus, as stock")
      t.equal(menu.panel.layershell.layer, WlrLayer.Overlay, "laptop, open: on the overlay layer")
      t.equal(menu.panel.exclusionMode, ExclusionMode.Ignore, "laptop, open: covers reserved space, as stock")
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "laptop, open: focus stays exclusive")
      t.equal(menu.panel.contentRevealed, true, "laptop, open at full size: content shown")
      // Omarchy's wait for full-screen geometry is left as it was.
      test.fill(menu, 300)
    }],
    [test.settle, function() {
      t.equal(menu.panel.contentRevealed, false, "laptop, smaller than the screen: content held back, as stock")
      test.fill(menu, 0)
      menu.opened = false
      t.equal(menu.panel.visible, false, "laptop, closed again: unmapped")
      test.setMode("tablet")
    }],

    // Tablet mode: the keyboard reserves the bottom of the screen, and the
    // overlay has to stay out of it rather than run underneath.
    [test.settle, function() {
      t.equal(menu.panel.visible, false, "tablet, closed: not mapped")
      menu.opened = true
      t.equal(menu.panel.visible, true, "tablet, open: mapped")
      t.equal(menu.panel.exclusionMode, ExclusionMode.Normal, "tablet, open: stays out of reserved space")
      t.equal(menu.panel.exclusiveZone, 0, "tablet, open: reserves no space of its own")
      t.equal(menu.panel.layershell.layer, WlrLayer.Overlay, "tablet, open: on the overlay layer")
      // Each open asks for the keyboard exclusively, as Omarchy's own
      // KeyboardPanel does, and then lets go.
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "tablet, just opened: exclusive, to take the keyboard")
      // The keyboard is up, so the surface is shorter than the screen.
      test.fill(menu, 300)
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.OnDemand, "tablet, open: on demand once it has the keyboard, so a touch can reach the on-screen keyboard")
      t.equal(menu.panel.contentRevealed, true, "tablet, open above the keyboard: content shown, though the surface is smaller than the screen")
      // The wait for the screen's scale is Omarchy's, and still holds.
      menu.panel.devicePixelRatio = 2
    }],
    [test.settle, function() {
      t.equal(menu.panel.contentRevealed, false, "tablet, scale not arrived: content held back, as stock")
      menu.panel.devicePixelRatio = 1
    }],
    [test.settle, function() {
      t.equal(menu.panel.contentRevealed, true, "tablet, scale arrived: content shown")
      menu.opened = false
      t.equal(menu.panel.visible, false, "tablet, closed: unmapped")
      menu.opened = true
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "tablet, opened a second time: takes the keyboard again")
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.OnDemand, "tablet, open a second time: on demand again")
      // Closed and reopened faster than the prime runs out.
      menu.opened = false
      menu.opened = true
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "tablet, reopened at once: takes the keyboard again")
      menu.opened = false
    }],
    [test.settle, function() {
      // The moment of exclusive focus has to be spent on a surface that
      // exists, and the surface maps a little after it is asked for.
      menu.panel.backingWindowVisible = false
      menu.opened = true
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "tablet, open but not mapped yet: still asking for the keyboard")
      menu.panel.backingWindowVisible = true
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.OnDemand, "tablet, open and mapped: on demand")
      menu.opened = false
      test.fill(menu, 0)
      test.setMode("laptop")
    }],
    [test.settle, function() {
      t.equal(menu.panel.exclusionMode, ExclusionMode.Ignore, "back in laptop mode: ignores reserved space again")
      // Folding the machine over with an overlay already up.
      menu.opened = true
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "laptop, open: exclusive")
      test.setMode("tablet")
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.OnDemand, "folded to tablet while open: on demand, having the keyboard already")
      t.equal(menu.panel.exclusionMode, ExclusionMode.Normal, "folded to tablet while open: moves out of reserved space")
      test.setMode("laptop")
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "unfolded to laptop while open: exclusive again")
      t.equal(menu.panel.exclusionMode, ExclusionMode.Ignore, "unfolded to laptop while open: covers reserved space again")
      menu.opened = false
      test.setMode("tablet")
    }],
    [test.settle, function() {
      // The image picker is mapped before it has anything to show, and wants
      // no keyboard until its images are in. That is Omarchy's gate and it
      // has to survive in both modes.
      picker.opened = true
      t.equal(picker.panel.visible, true, "tablet, picker loading: mapped")
      t.equal(test.focus(picker), WlrKeyboardFocus.None, "tablet, picker loading: no keyboard focus")
    }],
    [test.settle, function() {
      t.equal(test.focus(picker), WlrKeyboardFocus.None, "tablet, picker still loading: still no keyboard focus")
      picker.imagesLoaded = true
      t.equal(test.focus(picker), WlrKeyboardFocus.Exclusive, "tablet, picker loaded: takes the keyboard, though it mapped long before")
    }],
    [test.settle, function() {
      t.equal(test.focus(picker), WlrKeyboardFocus.OnDemand, "tablet, picker loaded: on demand once it has it")
      picker.imagesLoaded = false
      t.equal(test.focus(picker), WlrKeyboardFocus.None, "tablet, picker loading again: gives the keyboard up")
      picker.imagesLoaded = true
      t.equal(test.focus(picker), WlrKeyboardFocus.Exclusive, "tablet, picker loaded again: takes the keyboard again")
      picker.opened = false
      picker.imagesLoaded = false
      test.setMode("laptop")
    }],
    [test.settle, function() {
      picker.opened = true
      t.equal(test.focus(picker), WlrKeyboardFocus.None, "laptop, picker loading: no keyboard focus, as stock")
      picker.imagesLoaded = true
      t.equal(test.focus(picker), WlrKeyboardFocus.Exclusive, "laptop, picker loaded: exclusive, as stock")
    }],
    [test.settle, function() {
      t.equal(test.focus(picker), WlrKeyboardFocus.Exclusive, "laptop, picker loaded: stays exclusive")
      t.equal(picker.panel.exclusionMode, ExclusionMode.Ignore, "laptop, picker: covers reserved space, as stock")
      picker.opened = false
      test.setKeyboard("on")
    }],
    [test.settle, function() {
      menu.opened = true
      picker.opened = true
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "Always On in laptop mode still primes focus")
      test.fill(menu, 300)
    }],
    [test.settle, function() {
      for (var entry of [menu, picker]) {
        t.equal(test.focus(entry), WlrKeyboardFocus.OnDemand, "Always On in laptop mode: touch-friendly focus")
        t.equal(entry.panel.exclusionMode, ExclusionMode.Normal, "Always On: respects reserved space")
      }
      t.equal(menu.panel.contentRevealed, true, "Always On: content visible above keyboard")
      test.setMode("tablet")
      test.setKeyboard("off")
    }],
    [test.settle, function() {
      for (var entry of [menu, picker]) {
        t.equal(test.focus(entry), WlrKeyboardFocus.Exclusive, "Never in tablet mode: stock focus")
        t.equal(entry.panel.exclusionMode, ExclusionMode.Ignore, "Never: stock reserved-space behavior")
      }
      test.setKeyboard("sensor")
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.OnDemand, "Follow Sensor restores tablet cooperation while open")
      test.setMode("laptop")
    }],
    [test.settle, function() {
      t.equal(test.focus(menu), WlrKeyboardFocus.Exclusive, "Follow Sensor restores stock laptop focus")
    }]
  ])
}
