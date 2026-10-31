pragma Singleton
import QtQuick
QtObject {
  function controlSpec(state, text, accent, urgent) { return { color: Util.alpha(text, 0.4), width: 1 } }
  function color(spec) { return spec.color }
  function top(spec) { return spec.width }
}
