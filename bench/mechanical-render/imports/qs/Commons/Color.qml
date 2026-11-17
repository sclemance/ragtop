pragma Singleton
import QtQuick
QtObject {
  id: root
property color background: "#1a1b26"
property color foreground: "#a9b1d6"
property color accent: "#7aa2f7"
property color urgent: "#f7768e"
property QtObject popups: QtObject { property color background: root.background; property color text: root.foreground }
}
