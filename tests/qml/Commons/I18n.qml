pragma Singleton
import QtQuick

// A stand-in for Omarchy's qs.Commons I18n, which its shared OverlayWindow
// reads from 4.5 on to mirror the overlay for right-to-left languages. It is
// here so that import resolves, which without it the 4.5 window cannot: the
// test's stand-in window has no contentItem, so the mirroring this feeds is
// never exercised. The language is left to right.
QtObject {
  readonly property bool rightToLeft: false
}
