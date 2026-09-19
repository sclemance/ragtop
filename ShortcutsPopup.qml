import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Touch grid for window management that has no touch equivalent in Omarchy:
// windows have no title bars, and moving or resizing them needs SUPER plus a
// mouse. Launching apps (menu) and switching workspaces (bar) are already
// touchable, so they're left out. Each button runs the same Hyprland
// dispatcher as the matching Omarchy keybinding.
PopupCard {
  id: popup

  readonly property var sections: [
    { title: "Focus", columns: 4, items: [
      { label: "←", lua: 'hl.dsp.focus({ direction = "l" })' },
      { label: "↑", lua: 'hl.dsp.focus({ direction = "u" })' },
      { label: "↓", lua: 'hl.dsp.focus({ direction = "d" })' },
      { label: "→", lua: 'hl.dsp.focus({ direction = "r" })' }
    ] },
    { title: "Swap window", columns: 4, items: [
      { label: "←", lua: 'hl.dsp.window.swap({ direction = "l" })' },
      { label: "↑", lua: 'hl.dsp.window.swap({ direction = "u" })' },
      { label: "↓", lua: 'hl.dsp.window.swap({ direction = "d" })' },
      { label: "→", lua: 'hl.dsp.window.swap({ direction = "r" })' }
    ] },
    { title: "Window", columns: 3, items: [
      { label: "Close", lua: 'hl.dsp.window.close()' },
      { label: "Fullscreen", lua: 'hl.dsp.window.fullscreen({ mode = "fullscreen" })' },
      { label: "Full width", lua: 'hl.dsp.window.fullscreen({ mode = "maximized" })' },
      { label: "Float", lua: 'hl.dsp.window.float({ action = "toggle" })' },
      { label: "Split", lua: 'hl.dsp.layout("togglesplit")' },
      { label: "Pop out", lua: 'hl.dsp.exec_cmd("omarchy-hyprland-window-pop")' }
    ] },
    { title: "Resize", columns: 4, items: [
      { label: "W −", lua: 'hl.dsp.window.resize({ x = -100, y = 0, relative = true })' },
      { label: "W +", lua: 'hl.dsp.window.resize({ x = 100, y = 0, relative = true })' },
      { label: "H −", lua: 'hl.dsp.window.resize({ x = 0, y = -100, relative = true })' },
      { label: "H +", lua: 'hl.dsp.window.resize({ x = 0, y = 100, relative = true })' }
    ] },
    { title: "Move window to workspace", columns: 5, items: [
      { label: "1", lua: 'hl.dsp.window.move({ workspace = "1" })' },
      { label: "2", lua: 'hl.dsp.window.move({ workspace = "2" })' },
      { label: "3", lua: 'hl.dsp.window.move({ workspace = "3" })' },
      { label: "4", lua: 'hl.dsp.window.move({ workspace = "4" })' },
      { label: "5", lua: 'hl.dsp.window.move({ workspace = "5" })' }
    ] },
    { title: "Other", columns: 2, items: [
      { label: "Next window", lua: 'hl.dsp.window.cycle_next()' },
      { label: "Last workspace", lua: 'hl.dsp.focus({ workspace = "previous" })' },
      { label: "Scratchpad", lua: 'hl.dsp.workspace.toggle_special("scratchpad")' },
      { label: "To scratchpad", lua: 'hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })' }
    ] }
  ]

  // One process per tap, so quick repeated taps (focus, resize) aren't dropped.
  Component {
    id: dispatchProc
    Process { onExited: destroy() }
  }

  function dispatch(lua) {
    var proc = dispatchProc.createObject(popup, { command: ["hyprctl", "eval", "hl.dispatch(" + lua + ")"] })
    if (proc) proc.running = true
  }

  contentWidth: popup.fittedContentWidth(Style.space(340))
  contentHeight: popup.fittedContentHeight(column.implicitHeight)

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    Repeater {
      model: popup.sections

      Column {
        id: section
        required property var modelData
        width: column.width
        spacing: Style.space(4)

        Text {
          text: section.modelData.title
          color: popup.bar.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Grid {
          id: grid
          width: parent.width
          columns: section.modelData.columns
          spacing: Style.space(4)
          readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

          Repeater {
            model: section.modelData.items

            Button {
              required property var modelData
              width: grid.cellWidth
              text: modelData.label
              fontSize: Style.font.body
              foreground: popup.bar.foreground
              bordered: true
              onClicked: popup.dispatch(modelData.lua)
            }
          }
        }
      }
    }
  }
}
