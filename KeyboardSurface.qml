import QtQuick

// The panel Ragtop's keyboard sits on: its background, and how its top edge
// meets the desktop (Setup › Tablet › Edge). The keyboard and the picker nav
// strip each sit on one, so whichever is up looks like the same panel.
//
// `parent` doesn't resolve inside a Gradient or a ShapePath, so everything
// here goes through an id.
Item {
  id: surface

  required property var theme

  // Flat unless the style's background is a gradient, and fading out at the
  // top edge if it asks for that (see KeyboardTheme).
  Rectangle {
    id: backdrop
    anchors.fill: parent
    readonly property real fade: height > 0 ? Math.min(surface.theme.edgeFade, height / 3) / height : 0
    gradient: Gradient {
      GradientStop { position: 0; color: backdrop.fade > 0 ? surface.theme.backgroundClear : surface.theme.backgroundTop }
      GradientStop { position: backdrop.fade; color: surface.theme.backgroundTop }
      GradientStop { position: 1; color: surface.theme.background }
    }
  }

  // Edge: Border. Hyprland's own window border along the top, so the panel
  // is edged like a tiled window; its colour can be a gradient.
  Rectangle {
    id: edge
    visible: surface.theme.edgeBorder > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: surface.theme.edgeBorder
    color: surface.theme.borderColors[0]
    gradient: surface.theme.borderColors.length > 1 ? borderGradient : null

    Gradient {
      id: borderGradient
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: surface.theme.borderColors[0] }
      GradientStop { position: 1; color: surface.theme.borderColors[surface.theme.borderColors.length - 1] }
    }
  }
}
