pragma Singleton
import QtQuick
// Controlled palette roles, with no file watchers or connection to a session.
QtObject {
  id: root
  property color background: "#05182e"
  property color foreground: "#f6dcac"
  property color accent: "#faa968"
  property color urgent: "#f85525"
  property QtObject popups: QtObject {
    property color background: root.background
    property color text: root.foreground
  }
  property QtObject lock: QtObject {
    property color background: root.background
    property color text: root.foreground
    property color borderActive: root.accent
    property color textError: root.urgent
    property color placeholder: Util.alpha(root.foreground, 0.5)
  }
}
