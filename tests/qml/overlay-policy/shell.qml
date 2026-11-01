import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: test
  Harness { id: t }
  Gate0 { id: gate0 }
  Gate1 { id: gate1 }
  Gate2 { id: gate2 }
  Gate3 { id: gate3 }
  Gate4 { id: gate4 }
  FileView {
    id: settings
    path: Quickshell.env("HOME") + "/.config/ragtop/settings.conf"
    preload: false
    blockWrites: true
  }
  FileView {
    id: mode
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ragtop-mode"
    preload: false
    blockWrites: true
  }
  function check(want, description) {
    for (var gate of [gate0, gate1, gate2, gate3, gate4]) {
      t.equal(gate.askedFocus, want ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive, description + ": focus")
      t.equal(gate.exclusion, want ? ExclusionMode.Normal : ExclusionMode.Ignore, description + ": geometry")
    }
  }
  Component.onCompleted: t.run([
    [400, function() {
      test.check(false, "missing settings default to Automatic in laptop mode")
      settings.setText("keyboard=on\n")
    }],
    [3400, function() {
      test.check(true, "Always On discovered after settings file first appears")
      mode.setText("tablet\n")
    }],
    [400, function() {
      test.check(true, "Always On in tablet mode")
      settings.setText("keyboard=off\n")
    }],
    [400, function() {
      test.check(false, "Never in tablet mode")
      mode.setText("laptop\n")
    }],
    [400, function() {
      test.check(false, "Never in laptop mode")
      settings.setText("keyboard=sensor\n")
    }],
    [400, function() {
      test.check(false, "Automatic in laptop mode")
      mode.setText("tablet\n")
    }],
    [400, function() {
      test.check(true, "Automatic in tablet mode")
      settings.setText("keyboard=invalid\n")
    }],
    [400, function() {
      test.check(true, "unknown setting defaults to Automatic")
      mode.setText("laptop\n")
    }],
    [400, function() {
      test.check(false, "unknown setting follows device mode")
      settings.setText("keyboard=off\nother=on\n keyboard = on \n")
    }],
    [400, function() {
      test.check(true, "trimmed last setting wins, matching desktop parser")
      settings.setText("other=on\n")
    }],
    [400, function() {
      test.check(false, "removed setting defaults to Automatic")
      mode.setText("tablet\n")
    }],
    [400, function() {
      test.check(true, "default Automatic follows tablet mode")
      gate4.imagesLoaded = false
      t.equal(gate4.askedFocus, WlrKeyboardFocus.None, "loading image picker takes no focus")
      gate4.imagesLoaded = true
      gate4.opened = false
      t.equal(gate4.askedFocus, WlrKeyboardFocus.None, "closed image picker takes no focus")
    }]
  ])
}
