#!/bin/bash
# Patched authentication adapter plus real password keyboard, offscreen.
# No PolkitAgent, authentication request or desktop key sender is created.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
for tree in "$old_omarchy" "$new_omarchy" "$rc_omarchy" "$rel_omarchy"; do
  make_sandbox "$tree"
  clones install polkit
  if [[ $rc != 0 ]]; then echo "not ok - polkit clone installs: $err"; failed=1; continue; fi
  harness="$sandbox/polkit-keyboard"
  mkdir -p "$harness" "$sandbox/home/.config/ragtop"
  printf 'keyboard=on\n' >"$sandbox/home/.config/ragtop/settings.conf"
  cp "$tests_dir/qml/polkit-keyboard/shell.qml" "$tests_dir/qml/Harness.qml" \
    "$repo/LockKeyboard.qml" "$repo/LockKeyIcon.qml" "$repo/KeyContrast.js" "$harness/"
  cp -r "$tests_dir/qml/theme/Commons" "$harness/Commons"
  sandboxed /usr/bin/python3 - "$plugins/tester.polkit/PolkitAgent.qml" "$harness" "$tests_dir/qml/extract.py" "$repo/Service.qml" <<'PY'
from pathlib import Path
import re,sys,subprocess
source,harness,extract,service=map(Path,sys.argv[1:])
s=source.read_text()
focus=re.search(r'^    WlrLayershell.keyboardFocus: (.+)$',s,re.M).group(1)
exclusion=re.search(r'^    exclusionMode: (.+)$',s,re.M).group(1)
start=s.index('    FileView { id: ragtopMode;')
block=s[start:s.index('    BorderSurface {\n      id: card',start)]
block=block.replace('"file://" + Quickshell.env("HOME") + "/.config/omarchy/plugins/sclemance.ragtop/LockKeyboard.qml"','Qt.resolvedUrl("LockKeyboard.qml")')
header='''import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
Item {
  id: root
  property alias keyboard: ragtopPasswordKeyboard.item
  property alias adapter: ragtopPasswordView
  property alias password: passwordInput.text
  property bool dialogVisible: true
  property bool responseRequired: true
  property bool closing: false
  property bool submitted: false
  property bool errorFlash: false
  property real cardHeight: 70
  property string received: ""
  property int requests: 0
  function refocus() {}
  Item { id: panel; anchors.fill: parent }
  Item { id: keyCatcher }
  QtObject { id: passwordInput; property string text: "" }
  QtObject { id: polkitAgent; property var flow: QtObject {
    property bool isResponseRequired: root.responseRequired
    function submit(text) { root.received = text; root.requests++ }
  } }
  // FROM SOURCE: submitResponse
'''
template=harness/'Gate.qml.in'
template.write_text(header+'  readonly property int askedFocus: '+focus+'\n  readonly property int exclusion: '+exclusion+'\n'+block+'\n}\n')
subprocess.run([sys.executable,str(extract),str(source),str(template),str(harness/'Gate.qml')],check=True)
(harness/'Sender.qml.in').write_text('''import QtQuick
Item {
  id: root
  property bool oskVisible: true
  property bool tourLowered: false
  property string pickerNamespace: "omarchy-image-selector"
  property var patchedOverlays: []
  function layerEvent(name) { events.rawEvent({ name: name, data: "omarchy-polkit" }) }
  QtObject { id: events; signal rawEvent(var event) }
  // LAYER TRACKER
  property bool hyphenJoined: false
  property double lastKeysAt: 0
  property string sent: ""
  property int recorded: 0
  function noteTyped(text) { root.recorded++ }
  function updateContext() {}
  QtObject { id: keyboardHelper; function write(text) { root.sent += text } }
  // FROM SOURCE: passwordOpen keysShown writeKeys
}
''')
subprocess.run([sys.executable,str(extract),str(service),str(harness/'Sender.qml.in'),str(harness/'Sender.qml')],check=True)
service_text=service.read_text()
tracker=service_text.split('  property string lastLayoutName: ""',1)[1].split('  // ----',1)[0]
start=tracker.index('  Connections {')
end=tracker.index('\n  }',start)+len('\n  }')
tracker=tracker[start:end].replace('target: Hyprland','target: events')
sender=harness/'Sender.qml'
sender.write_text(sender.read_text().replace('  // LAYER TRACKER',tracker))
PY
  run_qml QT_QUICK_BACKEND=software
  clones remove polkit
  [[ $rc == 0 ]] || { echo "not ok - polkit clone remains removable: $err"; failed=1; }
done
finish
