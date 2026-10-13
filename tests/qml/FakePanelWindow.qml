import QtQuick

// Stands in for Quickshell's PanelWindow in the tests. A real one needs a
// Wayland compositor with layer shell, and a test must not put a surface on
// anybody's screen, so the clone's window is loaded with this as its base
// instead (see overlay-window-test.sh for the two substitutions that does).
// It holds what the window is told and does nothing with it, which is all a
// test of what the window asks for needs.
QtObject {
  default property list<QtObject> data
  property bool visible: false
  property var screen: null
  property FakeAnchors anchors: FakeAnchors {}
  // In place of the WlrLayershell attached object.
  property FakeLayershell layershell: FakeLayershell {}
  // In place of the Hyprland singleton.
  property FakeHyprland hyprland: FakeHyprland {}
  property int implicitWidth: 0
  property int implicitHeight: 0
  property int width: 1920
  property int height: 1080
  property var mask: null
  property color color: "white"
  property int exclusionMode: -1
  property int exclusiveZone: -1
  property bool backingWindowVisible: true
  property real devicePixelRatio: 1
  property Item contentItem: Item {}
}
