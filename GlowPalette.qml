import QtQuick
import Quickshell
import Quickshell.Io
import "GlowColors.js" as GlowColors

QtObject {
  id: palette
  property string directory: Quickshell.env("HOME") + "/.local/state/omarchy/current"
  property var colors: ({})
  property FileView colorsFile: FileView {
    path: palette.directory + "/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: palette.colors = GlowColors.parse(text())
    onLoadFailed: palette.colors = ({})
  }
  // Omarchy replaces the whole theme directory, then writes theme.name.
  // That stable marker reattaches the colour watcher after replacement,
  // including switching between themes with identical foundational colours.
  property FileView themeName: FileView {
    path: palette.directory + "/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: palette.colorsFile.reload()
  }
}
