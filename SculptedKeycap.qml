import QtQuick
import QtQuick.Shapes

// Adapted from Stan's keycap.svg: a centred curved face over a broader
// skirt. Transparent materials use adjoining vector surfaces so overlapping
// faces cannot multiply their opacity. No per-key captures or texture layers.
Item {
  id: cap
  required property color faceColor
  required property color edgeColor
  required property real edgeWidth
  required property real faceY
  required property real faceHeight
  required property real rounding
  property string material: "solid"
  property color lightColor: faceColor
  property real materialOpacity: 0.5
  readonly property bool clearFace: material === "frosted" || material === "translucent"
  readonly property bool transparentWalls: clearFace || material === "pudding"
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  readonly property color litMaterial: Qt.tint(lightColor,
    Qt.rgba(1, 1, 1, material === "frosted" ? 0.16 : 0.04))
  readonly property color topColor: clearFace ? litMaterial : faceColor
  function topTone(tint) { return alpha(Qt.tint(topColor, tint), clearFace ? materialOpacity : faceColor.a) }
  readonly property real inset: Math.min(6, width * 0.085, faceHeight * 0.17)
  readonly property real rearLeft: inset
  readonly property real rearRight: width - inset
  readonly property real frontLeft: rearLeft
  readonly property real frontRight: rearRight
  readonly property real faceTop: faceY + 0.5
  // A little more front wall without widening the gap between key slots.
  readonly property real front: faceY + faceHeight - 1.5 - Math.min(3, faceHeight * 0.07)
  readonly property real r: Math.min(rounding, width * 0.10, faceHeight * 0.16)
  readonly property real topDip: Math.min(2, faceHeight * 0.055)
  readonly property real bottomBow: Math.min(1.2, faceHeight * 0.028)
  readonly property real skirtTop: Math.min(front-r, faceTop + height - faceHeight)
  readonly property real outerR: Math.min(2, rounding, height * 0.08)
  readonly property color shoulder: Qt.tint(faceColor, Qt.rgba(1, 1, 1, 0.07))
  readonly property color shadow: Qt.tint(faceColor, Qt.rgba(0, 0, 0, 0.45))
  // Curve depth and corner size stay bounded on wide keys such as Space.
  readonly property real curveSpan: Math.max(0, rearRight-rearLeft-2*r)
  readonly property string topCurve:
    "M " + (rearLeft+r) + " " + faceTop
    + " C " + (rearLeft+r+curveSpan/3) + " " + (faceTop+topDip)
    + " " + (rearRight-r-curveSpan/3) + " " + (faceTop+topDip)
    + " " + (rearRight-r) + " " + faceTop
  readonly property string facePath: topCurve
    + " Q " + rearRight + " " + faceTop + " " + rearRight + " " + (faceTop+r)
    + " L " + frontRight + " " + (front-r)
    + " Q " + frontRight + " " + front + " " + (frontRight-r) + " " + front
    + " C " + (frontRight-r-curveSpan/3) + " " + (front+bottomBow)
    + " " + (frontLeft+r+curveSpan/3) + " " + (front+bottomBow)
    + " " + (frontLeft+r) + " " + front
    + " Q " + frontLeft + " " + front + " " + frontLeft + " " + (front-r)
    + " L " + rearLeft + " " + (faceTop+r)
    + " Q " + rearLeft + " " + faceTop + " " + (rearLeft+r) + " " + faceTop + " Z"

  // Same upper edge as the face; the lower skirt surrounds it. Subtracting
  // the face with OddEvenFill leaves no hidden plastic behind clear caps.
  readonly property string skirtPath: topCurve
    + " Q " + rearRight + " " + faceTop + " " + rearRight + " " + (faceTop+r)
    + " L " + (width-0.5) + " " + skirtTop
    + " L " + (width-0.5) + " " + (height-outerR)
    + " Q " + (width-0.5) + " " + (height-0.5) + " " + (width-outerR) + " " + (height-0.5)
    + " L " + outerR + " " + (height-0.5)
    + " Q 0.5 " + (height-0.5) + " 0.5 " + (height-outerR)
    + " L 0.5 " + skirtTop + " L " + rearLeft + " " + (faceTop+r)
    + " Q " + rearLeft + " " + faceTop + " " + (rearLeft+r) + " " + faceTop + " Z"

  // A hidden Shape still owns its paths and live gradient bindings. Create
  // only the material in use; both constructions keep their exact geometry.
  Loader {
    anchors.fill: parent
    sourceComponent: cap.transparentWalls ? clearCap : solidCap
  }

  Component {
    id: solidCap
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      // Outer silhouette follows the reference's sloping shoulders and
      // upright skirt, with small rounded corners at the foot.
      ShapePath {
        strokeWidth: cap.edgeWidth
        strokeColor: Qt.tint(cap.edgeColor, Qt.rgba(0,0,0,0.35))
        fillGradient: LinearGradient {
          x1: 0; y1: cap.faceTop; x2: 0; y2: cap.height
          GradientStop { position: 0; color: cap.shoulder }
          GradientStop { position: 1; color: cap.shadow }
        }
        PathSvg { path: "M " + (cap.rearLeft+cap.r*0.15) + " " + (cap.faceTop+cap.r*0.3)
          + " L 0.5 " + cap.skirtTop + " L 0.5 " + (cap.height-cap.outerR)
          + " Q 0.5 " + (cap.height-0.5) + " " + cap.outerR + " " + (cap.height-0.5)
          + " L " + (cap.width-cap.outerR) + " " + (cap.height-0.5)
          + " Q " + (cap.width-0.5) + " " + (cap.height-0.5) + " " + (cap.width-0.5) + " " + (cap.height-cap.outerR)
          + " L " + (cap.width-0.5) + " " + cap.skirtTop
          + " L " + (cap.rearRight-cap.r*0.15) + " " + (cap.faceTop+cap.r*0.3) + " Z" }
      }
      // Both side walls are visible, with a fixed light source from the left.
      ShapePath {
        strokeWidth: 0
        fillGradient: LinearGradient {
          x1: 0; y1: 0; x2: cap.rearLeft; y2: 0
          GradientStop { position: 0; color: Qt.tint(cap.faceColor, Qt.rgba(1,1,1,0.035)) }
          GradientStop { position: 1; color: Qt.tint(cap.faceColor, Qt.rgba(0,0,0,0.18)) }
        }
        PathSvg { path: "M " + cap.rearLeft + " " + (cap.faceTop+cap.r*0.5)
          + " L 0.5 " + cap.skirtTop + " L 0.5 " + (cap.height-cap.outerR)
          + " L " + cap.frontLeft + " " + (cap.front-cap.r) + " Z" }
      }
      ShapePath {
        strokeWidth: 0
        fillGradient: LinearGradient {
          x1: cap.rearRight; y1: 0; x2: cap.width; y2: 0
          GradientStop { position: 0; color: Qt.tint(cap.faceColor, Qt.rgba(0,0,0,0.20)) }
          GradientStop { position: 1; color: cap.shadow }
        }
        PathSvg { path: "M " + cap.rearRight + " " + (cap.faceTop+cap.r*0.5)
          + " L " + (cap.width-0.5) + " " + cap.skirtTop
          + " L " + (cap.width-0.5) + " " + (cap.height-cap.outerR)
          + " L " + cap.frontRight + " " + (cap.front-cap.r) + " Z" }
      }
      ShapePath {
        strokeWidth: 0
        fillGradient: LinearGradient {
          x1: 0; y1: cap.front; x2: 0; y2: cap.height
          GradientStop { position: 0; color: cap.shoulder }
          GradientStop { position: 0.32; color: cap.faceColor }
          GradientStop { position: 1; color: cap.shadow }
        }
        PathSvg { path: "M " + (cap.frontLeft+cap.r*0.4) + " " + (cap.front-1)
          + " L " + (cap.frontRight-cap.r*0.4) + " " + (cap.front-1)
          + " L " + (cap.width-cap.outerR) + " " + (cap.height-0.5)
          + " L " + cap.outerR + " " + (cap.height-0.5) + " Z" }
      }
      // The curved face and a faint upper-edge reflection carry the dish.
      ShapePath {
        strokeWidth: cap.edgeWidth
        strokeColor: cap.edgeColor
        fillGradient: LinearGradient {
          x1: 0; y1: cap.faceTop; x2: 0; y2: cap.front
          GradientStop { position: 0; color: Qt.tint(cap.faceColor, Qt.rgba(1,1,1,0.09)) }
          GradientStop { position: 0.18; color: cap.faceColor }
          GradientStop { position: 0.65; color: Qt.tint(cap.faceColor, Qt.rgba(0,0,0,0.13)) }
          GradientStop { position: 1; color: Qt.tint(cap.faceColor, Qt.rgba(1,1,1,0.035)) }
        }
        PathSvg { path: cap.facePath }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: Qt.rgba(1,1,1,0.14)
        strokeWidth: 0.7
        PathSvg { path: cap.topCurve }
      }
    }
  }

  Component {
    id: clearCap
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillRule: ShapePath.OddEvenFill
        strokeWidth: 0
        fillGradient: LinearGradient {
          x1: 0; y1: cap.faceTop; x2: 0; y2: cap.height
          GradientStop { position: 0; color: cap.alpha(cap.litMaterial, cap.materialOpacity) }
          GradientStop { position: 1; color: cap.alpha(Qt.darker(cap.litMaterial, 1.5), cap.materialOpacity) }
        }
        PathSvg { path: cap.skirtPath + " " + cap.facePath }
      }
      ShapePath {
        strokeWidth: cap.edgeWidth
        strokeColor: cap.clearFace ? cap.alpha(cap.edgeColor, cap.materialOpacity) : cap.edgeColor
        fillGradient: LinearGradient {
          x1: 0; y1: cap.faceTop; x2: 0; y2: cap.front
          GradientStop { position: 0; color: cap.topTone(Qt.rgba(1,1,1,0.09)) }
          GradientStop { position: 0.18; color: cap.topTone("transparent") }
          GradientStop { position: 0.65; color: cap.topTone(Qt.rgba(0,0,0,0.13)) }
          GradientStop { position: 1; color: cap.topTone(Qt.rgba(1,1,1,0.035)) }
        }
        PathSvg { path: cap.facePath }
      }
      ShapePath {
        fillColor: "transparent"
        strokeColor: Qt.rgba(1,1,1,0.14)
        strokeWidth: 0.7
        PathSvg { path: cap.topCurve }
      }
    }
  }
}
