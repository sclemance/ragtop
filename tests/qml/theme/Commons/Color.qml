pragma Singleton
import QtQuick
// Controlled palette roles, with no file watchers or connection to a session.
QtObject {
  property color background: "#05182e"
  property color foreground: "#f6dcac"
  property color accent: "#faa968"
  property color urgent: "#f85525"
  property QtObject popups: QtObject {
    property color background: Color.background
    property color text: Color.foreground
  }
  property QtObject lock: QtObject {
    property color background: Color.background
    property color text: Color.foreground
    property color borderActive: Color.accent
    property color textError: Color.urgent
    property color placeholder: Util.alpha(Color.foreground, 0.5)
  }
}
