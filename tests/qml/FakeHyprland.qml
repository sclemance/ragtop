import QtQuick

// Stands in for the Hyprland singleton, which has no compositor to ask in a
// test. Holds the monitors a test gives it.
QtObject {
  property var monitors: ({ values: [] })
  property var focusedMonitor: null
  function refreshMonitors() {}
}
