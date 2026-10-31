import QtQuick
import qs.Commons
import "GlowWave.js" as Wave
Item {
 id: board
 width:1280; height:360
 property bool pattern:false
 property bool motion:false
 property int rate:0
 property int sequence:0
 property int held:-1
 property int presses:0
 KeyboardTheme { id:skin; look:{"shape": "rounded", "relief": "raised", "fill": "surface", "size": 100, "keyTransparency": 0, "labels": "normal", "depth": 8, "chamfer": 8, "keyColor": "", "labelColor": "", "keyFillAlpha": "auto", "borderWidth": 1, "radius": 5, "corners": "auto", "specialKeys": "off", "backlight": "accent", "keycapMaterial": "solid", "keycapProfile": "sculpted", "wallOpacity": 50, "backlightMotion": "ripple", "animateBacklight": true}; glowPalette:{"mode": "dark", "accent": "#509475", "selection": "#32473B", "muted": "#53685B", "background": "#111c18", "dark_background": "#0c1512", "darker_background": "#090f0d", "lighter_background": "#23372B", "foreground": "#C1C497", "dark_foreground": "#81B8A8", "light_foreground": "#D6D5BC", "bright_foreground": "#F7E8B2", "red": "#FF5345", "yellow": "#459451", "orange": "#a2734b", "green": "#549e6a", "cyan": "#2DD5B7", "blue": "#509475", "magenta": "#D2689C", "brown": "#513925", "bright_red": "#db9f9c", "bright_yellow": "#E5C736", "bright_green": "#63b07a", "bright_cyan": "#8CD3CB", "bright_blue": "#ACD4CF", "bright_magenta": "#75bbb3"} }
 Rectangle { anchors.fill:parent; color:Color.background }
 Repeater {
  model:board.pattern ? 32 : 0
  Rectangle {
   required property int index
   x:index*40; width:20; height:board.height
   color:index%2 ? "#435573" : "#807060"
  }
 }
 Repeater {
  id:keys
  model:80
  KeyboardKey {
   id:cap
   required property int index
   x:10+(index%16)*79; y:10+Math.floor(index/16)*68
   width:68; height:55
   theme:skin; glowGap:11
   label:String.fromCharCode(97+index%26)
   hint:index%3===0 ? "é" : ""
   hintLeft:index%4===0 ? "#" : ""
   labelKind:index%9===0 ? "drawn" : "char"
   icon:index%18===0 ? "settings" : "right"
   rippleEnabled:board.motion && skin.ripple
   pressed:index===board.held
   onPressedChanged: if (pressed && rippleEnabled) Wave.spread(keys,cap,79,68)
  }
 }
 Timer {
  interval:board.rate ? Math.round(1000/board.rate) : 1000
  running:board.rate>0; repeat:true
  onTriggered: {
   board.held=(board.sequence*17+23)%80
   board.sequence++; board.presses++
   release.restart()
  }
 }
 Timer { id:release; interval:45; onTriggered:board.held=-1 }
 onRateChanged: { held=-1; release.stop() }
 function debugState() {
  var k=keys.itemAt(35)
  return JSON.stringify({motion:board.motion,held:board.held,pressed:k.pressed,enabled:k.rippleEnabled,lit:k.backlit,visible:k.visible,base:String(skin.accent),alternate:String(skin.rippleColor),color:String(k.backlightColor),children:k.children.map(function(c) {return c.item && c.item.amount!==undefined ? {amount:c.item.amount,pressed:c.item.pressed,active:c.item.active,pressColor:String(c.item.pressColor)} : {active:c.active} })})
 }
 function runningCount() {
  var n=0
  for (var i=0;i<keys.count;i++) {
   var k=keys.itemAt(i)
   for (var j=0;j<k.children.length;j++) {
    var c=k.children[j]
    if (c.item && c.item.pulse!==undefined && c.item.running) n++
   }
  }
  return n
 }
}
