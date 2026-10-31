import QtQuick

// Suggestions and held-key cards are supporting controls. Follow Omarchy's
// default flat keyboard look, keeping only the main board's size adjustment.
KeyboardTheme {
  id: support
  property real keyboardScale: 1
  look: ({
    shape: "omarchy", corners: "auto", radius: "auto", relief: "flat",
    fill: "light", keyTransparency: 0, keyFillAlpha: "auto",
    keyColor: "", labelColor: "", borderWidth: "auto",
    size: 100, sizeNudge: support.keyboardScale, labels: "normal",
    specialKeys: "darker", contrast: "normal", depth: 4, chamfer: 8,
    backlight: "off", animateBacklight: false, backlightMotion: "off",
    backlightPressColor: "", keycapMaterial: "solid", keycapProfile: "standard",
    wallOpacity: 50
  })
}
