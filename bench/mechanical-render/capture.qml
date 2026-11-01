import QtQuick
import qs.Commons
Item {
 id: board
 width:1536; height:1152
 property int captureCase: 0
 onCaptureCaseChanged: {
  Color.background = captureCase % 2 ? "#eff1f5" : "#1a1b26"
  Color.foreground = captureCase % 2 ? "#4c4f69" : "#a9b1d6"
  Color.accent = captureCase % 2 ? "#1e66f5" : "#7aa2f7"
 }
 Rectangle { anchors.fill: parent; color: Color.background }
 Repeater { model: 32
  Rectangle { required property int index; x:index*48; width:24; height:board.height; color:index%2 ? "#435573" : "#807060"; opacity:0.35 }
 }
 Repeater {
  model:144
  Item {
   id: cell
   required property int index
   x:(index%12)*128; y:Math.floor(index/12)*96
   width:128; height:96
   readonly property string material: ["solid","pudding","frosted","translucent"][index%4]
   readonly property bool lit: Math.floor(board.captureCase/2)%2 === 0
   readonly property bool shine: Math.floor(board.captureCase/4)%2 === 0
   readonly property real capScale: [0.65,0.85,1][Math.floor(index/48)]
   KeyboardTheme { id: skin
    look: Object.assign({"shape": "rounded", "relief": "raised", "fill": "surface", "size": 100, "keyTransparency": 0, "labels": "normal", "depth": 8, "chamfer": 8, "keyColor": "", "labelColor": "", "keyFillAlpha": "auto", "borderWidth": 1, "radius": 5, "corners": "auto", "specialKeys": "off", "backlight": "accent", "keycapMaterial": "solid", "keycapProfile": "sculpted", "wallOpacity": 50, "backlightMotion": "ripple", "animateBacklight": true}, {keycapMaterial:cell.material, shineThrough:cell.shine, backlight:cell.lit ? "accent" : "off", sizeNudge:cell.capScale})
    glowPalette: {"mode": "dark", "accent": "#509475", "selection": "#32473B", "muted": "#53685B", "background": "#111c18", "dark_background": "#0c1512", "darker_background": "#090f0d", "lighter_background": "#23372B", "foreground": "#C1C497", "dark_foreground": "#81B8A8", "light_foreground": "#D6D5BC", "bright_foreground": "#F7E8B2", "red": "#FF5345", "yellow": "#459451", "orange": "#a2734b", "green": "#549e6a", "cyan": "#2DD5B7", "blue": "#509475", "magenta": "#D2689C", "brown": "#513925", "bright_red": "#db9f9c", "bright_yellow": "#E5C736", "bright_green": "#63b07a", "bright_cyan": "#8CD3CB", "bright_blue": "#ACD4CF", "bright_magenta": "#75bbb3"}
   }
   KeyboardKey {
    id: cap
    x:6; y:6; width:[42,72,116][Math.floor(cell.index/16)%3]*cell.capScale; height:64*cell.capScale
    theme:skin
    kind:["normal","latched","locked"][Math.floor(cell.index/4)%3]
    pressed:Math.floor(cell.index/12)%2 === 1
    label: "A"; hint:"é"; hintLeft:"#"
    labelKind:cell.index%5===0 ? "drawn" : "char"; icon:"settings"
    hintIcon:cell.index%7===0 ? "right" : ""
    rippleEnabled: board.captureCase >= 8
    glowGap:8
   }
   // Freeze actual ripple properties at deterministic positions. No wall
   // clock timing enters image comparisons. Geometry/materials stay real.
   function freezeWave() {
    for (var i=0;i<cap.children.length;i++) {
     var child=cap.children[i]
     if (child.item && child.item.pulse !== undefined) {
      child.item.settle()
      child.item.neighbourWave = !cap.pressed
      child.item.amount = [0,0.5,1][Math.floor(cell.index/4)%3]
     }
    }
   }
  }
  id:cells
 }
 function freezeWaves() { for(var i=0;i<cells.count;i++) cells.itemAt(i).freezeWave() }
}
