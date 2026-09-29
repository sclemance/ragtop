import QtQuick
import qs.Commons
import qs.Ui

// Ragtop's own controls: the inside of a tile that is a window of its own.
// Its window is anchored only to the top of the screen, so nothing the
// keyboard does can move or resize it. That matters more than it sounds:
// while this window shared an edge with the keyboard, every step of the size
// slider relaid it out mid-drag and took the touch grab with it, which made
// the slider unusable.
//
// What is here is what you change while holding the machine, with the
// keyboard still drawn underneath so you can see what each change does.
//
// It is built from Omarchy's own panel kit (BorderSurface, Button,
// ButtonGroup, Toggle, PanelSeparator, PanelSectionHeader and its
// Color/Style/Border tokens), the same way SetupWizard.qml is, so it reads as
// one of Omarchy's popup menus rather than as a panel of Ragtop's own. That
// includes its corners: Style.cornerRadius mirrors Hyprland's
// decoration:rounding, which Omarchy ships at 0, so the card is square here
// and rounds only on a machine whose windows are rounded too.
//
// The colours are Omarchy's popup palette and not the keyboard's theme. The
// keyboard below is themeable down to its key shapes. Its controls are not
// part of that, and a panel that restyled itself with every preset would be
// the one thing on screen you could not recognise.
Item {
  id: panel

  required property var service

  signal dismissed()

  implicitWidth: card.implicitWidth
  implicitHeight: card.implicitHeight

  readonly property string themeName: {
    var name = panel.service.currentTheme
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  // A note that outlived the code it explained, because the trap has not gone
  // anywhere. Every tap target in Omarchy's kit is a MouseArea with an
  // onClicked, which needs Qt to synthesise a mouse press and release out of
  // a touch, and the first touch on a surface that has not been touched yet
  // was measured getting lost somewhere in that synthesis: the first tap on a
  // panel that had only just opened did nothing. What stood here used
  // TapHandlers, which read touch points directly, for exactly that reason.
  // The keyboard has never had the problem because it reads them too.
  //
  // Conforming to Omarchy's components means taking its MouseAreas with them.
  // If the first tap after the gear is opened goes missing again, this is why,
  // and the fix is to keep this window mapped whenever the keyboard is up with
  // its input masked to nothing until it opens (the keyboard surface already
  // masks itself that way), so the surface is warm before it is needed.
  // Service.qml's handle still uses a TapHandler and points here.
  BorderSurface {
    id: card
    anchors.fill: parent
    implicitWidth: Style.space(560)
    implicitHeight: body.implicitHeight + card.contentTopInset + card.contentBottomInset
    radius: Style.cornerRadius
    color: Color.popups.background
    borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border,
                                          Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding

    // The card asks for the height its rows need, and the window gives it
    // what the screen can spare (see toolsWindow.room). Where that is less,
    // this scrolls rather than the last rows being cut off at the edge. It
    // stays inert while everything fits, so a tap on a control is never
    // read as the start of a drag on a panel with nowhere to go.
    Flickable {
      id: scroller
      x: card.contentLeftInset
      y: card.contentTopInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      height: card.height - card.contentTopInset - card.contentBottomInset
      contentHeight: body.implicitHeight
      clip: contentHeight > height
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: body
        width: scroller.width
        spacing: Style.space(8)

        // The theme, stepped rather than listed: the keyboard behind redraws
        // as you go, which is a better way to choose one than reading names.
        PanelSectionHeader {
          text: "Keyboard theme"
          foreground: Color.popups.text
        }

        Row {
          width: parent.width
          spacing: Style.spacing.controlGap

          Button {
            id: themeBack
            width: Style.space(40)
            height: Style.spacing.controlHeight
            bordered: true
            foreground: Color.popups.text
            onClicked: panel.service.stepTheme(-1)
            // Drawn rather than set as a font glyph, the way the keyboard's own
            // keys are, so it never depends on the panel's font carrying an
            // icon. Button sizes itself from its label and this is not one, so
            // the button is given a size of its own.
            KeyIcon {
              anchors.centerIn: parent
              height: Style.font.icon
              name: "left"
              color: Color.popups.text
            }
          }

          Text {
            // Never rich text. A theme name arrives from outside, and AutoText
            // would sniff markup in it and render it, which for Qt includes
            // fetching a remote image named in an img tag.
            textFormat: Text.PlainText
            width: parent.width - 2 * (themeBack.width + Style.spacing.controlGap)
            height: Style.spacing.controlHeight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: panel.themeName
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Button {
            width: themeBack.width
            height: Style.spacing.controlHeight
            bordered: true
            foreground: Color.popups.text
            onClicked: panel.service.stepTheme(1)
            KeyIcon {
              anchors.centerIn: parent
              height: Style.font.icon
              name: "right"
              color: Color.popups.text
            }
          }
        }

        PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

        // Screen rotation, named rather than implied. Automatic follows the
        // machine: it turns in tablet mode and holds still in laptop mode.
        // Three exclusive states, which is what a ButtonGroup is for.
        PanelSectionHeader {
          text: "Screen rotation"
          foreground: Color.popups.text
        }

        ButtonGroup {
          options: [{ value: "auto", label: "Automatic" },
                    { value: "locked", label: "Locked" },
                    { value: "unlocked", label: "Unlocked" }]
          value: panel.service.rotationMode
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          // Nothing here takes keyboard focus: the panel is held rather than
          // tabbed through, and the keyboard underneath is what has the keys.
          focusable: false
          onChanged: function(mode) { panel.service.setRotationMode(mode) }
        }

        PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

        // Which monitor Ragtop lives on. Only where there is more than one,
        // since a row offering a single screen is a row saying nothing.
        PanelSectionHeader {
          visible: panel.service.monitorCount > 1
          text: "Display"
          foreground: Color.popups.text
        }

        ButtonGroup {
          visible: panel.service.monitorCount > 1
          options: panel.service.displayOptions
          value: panel.service.displaySetting
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          focusable: false
          onChanged: function(name) { panel.service.setDisplay(name) }
        }

        // Which board the keyboard draws. Here as well as in the menu because
        // it is a thing you change while looking at the keyboard and deciding
        // you want more of it or less, which is exactly what this panel is for.
        // Auto is not a board but an answer to the question, so it sits with
        // them rather than as a switch beside them.
        PanelSectionHeader {
          text: "Keyboard layout"
          foreground: Color.popups.text
        }

        ButtonGroup {
          options: panel.service.keyboardLayoutOptions
          value: panel.service.keyboardLayout
          foreground: Color.popups.text
          background: Color.popups.background
          accent: Color.accent
          focusable: false
          onChanged: function(name) { panel.service.setKeyboardLayout(name) }
        }

        PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

        // Key size.
        //
        // This one is not Omarchy's PanelSlider, and deliberately. That slider
        // is built for a pointer. It sets no preventStealing, so on a
        // touchscreen the surface underneath can steal the drag. It has no
        // hysteresis, so a thumb resting on a step boundary flips back and
        // forth. And on release it puts its handle back to the value it was
        // given, which here only arrives a moment later through settings.conf,
        // so the handle would spring back and then jump. The geometry and the
        // colours are PanelSlider's, so it looks like Omarchy's sliders, but
        // the handling is the one that was measured against a thumb.
        PanelSectionHeader {
          text: "Keyboard size"
          foreground: Color.popups.text
        }

        Item {
          id: sizeSlider
          width: parent.width
          height: Style.spacing.controlHeight
          readonly property int steps: panel.service.sizeSteps.length
          readonly property int index: Math.max(0,
            panel.service.sizeSteps.indexOf(panel.service.look.sizeAdjust))
          readonly property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))
          readonly property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
          readonly property real span: width - knobSize
          readonly property real stepWidth: steps > 1 ? span / (steps - 1) : span
          // Where the finger has put it, while a finger is on it. The settled
          // value comes back through settings.conf, which is quick but not
          // instant, and a handle that waits for it stutters under the thumb.
          property int dragIndex: -1
          readonly property int shown: dragIndex >= 0 ? dragIndex : index
          // The finger's answer stands until the settled one agrees with it,
          // so a write still in flight cannot look like a spring back.
          onIndexChanged: if (dragIndex === index) dragIndex = -1

          Rectangle {
            id: track
            x: sizeSlider.knobSize / 2
            width: sizeSlider.span
            height: sizeSlider.trackHeight
            radius: Style.cornerRadius > 0 ? height / 2 : 0
            anchors.verticalCenter: parent.verticalCenter
            color: Style.selectedFillFor(Color.popups.text, Color.accent)

            Rectangle {
              width: track.width * (sizeSlider.steps > 1
                ? sizeSlider.shown / (sizeSlider.steps - 1) : 0)
              height: track.height
              radius: track.radius
              color: Color.accent
            }
          }

          Repeater {
            model: sizeSlider.steps

            Rectangle {
              required property int index
              width: Math.max(1, Style.space(2))
              height: sizeSlider.trackHeight + Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              x: sizeSlider.knobSize / 2 + index * sizeSlider.stepWidth - width / 2
              color: Color.popups.background
            }
          }

          BorderSurface {
            id: knob
            width: sizeSlider.knobSize
            height: sizeSlider.knobSize
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: sizeSlider.shown * sizeSlider.stepWidth
            color: Color.popups.text
            borderSpec: Border.flat(Color.popups.background, Math.max(1, Style.space(2)))
            Behavior on x { NumberAnimation { duration: 90 } }
          }

          MouseArea {
            anchors.fill: parent
            preventStealing: true
            // A step is only given up once the finger is well past the middle
            // of the gap, so a wobble at a boundary cannot flip it back and
            // forth. A long drag still crosses several at once.
            function at(mx) {
              var pos = (mx - sizeSlider.knobSize / 2) / sizeSlider.stepWidth
              var current = sizeSlider.dragIndex
              var want = (current < 0 || Math.abs(pos - current) > 0.6) ? Math.round(pos) : current
              return Math.max(0, Math.min(sizeSlider.steps - 1, want))
            }
            function moveTo(i) {
              if (i === sizeSlider.dragIndex) return
              sizeSlider.dragIndex = i
              panel.service.setSize(i)
            }
            onPressed: function(m) { moveTo(at(m.x)) }
            onPositionChanged: function(m) { if (pressed) moveTo(at(m.x)) }
            onReleased: function(m) { moveTo(at(m.x)) }
            onCanceled: sizeSlider.dragIndex = -1
          }
        }

        PanelSeparator { width: parent.width; height: 1; foreground: Color.popups.text }

        // Whether the keyboard comes up by itself on a text field, and the way
        // through to everything that does not belong on a surface you hold.
        Toggle {
          width: parent.width
          label: "Auto-expand keyboard on text fields"
          checked: panel.service.autoShowEnabled
          foreground: Color.popups.text
          accent: Color.accent
          onClicked: panel.service.toggleAutoShow()
        }

        Item {
          width: parent.width
          height: settingsButton.implicitHeight

          Button {
            id: settingsButton
            anchors.right: parent.right
            text: "Settings"
            bordered: true
            foreground: Color.popups.text
            onClicked: { panel.dismissed(); panel.service.openSettings() }
          }
        }
      }
    }
  }
}
