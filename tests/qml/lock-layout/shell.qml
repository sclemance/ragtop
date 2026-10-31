import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "Layouts.js" as Data

ShellRoot {
  id: root
  Harness { id: t }
  TestCase { id: input; name: "LockInteraction"; when: false; optional: true }
  property Window stage: Window {
    width: 768; height: 1366; visible: true
    Item {
      id: host
      anchors.fill: parent
      property real fieldHeight: 67
      property bool inputEnabled: true
      property bool authenticatingPassword: false
      property string passwordText: ""
      property string submitted: ""
      function wakeRequested() {}
      function passwordTextEdited(text) { passwordText = text }
      function submitPassword(text) { submitted = text }
      Loader {
        id: loader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        source: "LockKeyboard.qml"
        onLoaded: item.view = host
      }
    }
  }
  readonly property var board: loader.item
  function keys(item) {
    var found = []
    for (var i = 0; i < item.children.length; i++) {
      var c = item.children[i]
      if (c.modelData !== undefined && c.labelColor !== undefined) found.push(c)
      found = found.concat(keys(c))
    }
    return found
  }
  function bounds(name) {
    var key = keys(board).filter(function(k) { return k.modelData === name })[0]
    var at = key.mapToItem(host, 0, 0)
    return [at.x, at.y, key.width, key.height]
  }
  function sameBounds(a, b) { return a.every(function(v, i) { return Math.abs(v - b[i]) < 0.01 }) }
  property var backspace: []
  property var enter: []
  property real targetHeight: 0
  property int resizeSerial: 0

  Component.onCompleted: {
    var steps = [[100, function() { t.ok(!!board, "real lock keyboard loaded with inert password view") }]]
    ;['us','fr','de'].forEach(function(language) {
      ;[768,1366].forEach(function(height) {
        steps.push([0, function() {
          stage.width = height === 768 ? 1366 : 768
          stage.height = height
          board.style = board.cleanStyle({sizeNudge:1})
          board.applyLayout(Data.layouts[language])
          board.page = 'letters'
        }])
        steps.push([20, function() {
          t.equal(board.showNumberRow, height === 1366, language + ' adaptive row at height ' + height)
          t.equal(board.pages.letters.length, height === 1366 ? 5 : 4, 'correct number of letter rows')
          t.ok(!board.showNumberRow || board.height <= board.availableHeight, 'extra row fits below password field reserve')
          root.backspace = bounds('backspace'); root.enter = bounds('enter')
          root.targetHeight = board.keyHeight
          if (board.showNumberRow) t.equal(board.pages.letters[0].join(''), '1234567890', 'number row contains all digits once')
        }])
        ;['symbols','more','letters'].forEach(function(page) {
          steps.push([0, function() { board.page = page }])
          steps.push([10, function() {
            t.ok(sameBounds(bounds('backspace'), root.backspace), language + '/' + height + '/' + page + ' Backspace bounds stable')
            t.ok(sameBounds(bounds('enter'), root.enter), language + '/' + height + '/' + page + ' Enter bounds stable')
            t.equal(board.keyHeight, root.targetHeight, 'page switching never shrinks targets')
            t.equal(board.pages[page].length, board.pages.letters.length, 'page heights match')
            var digit = keys(board).filter(function(k) { return k.modelData === '4' })[0]
            if (digit) {
              var hint = digit.children.filter(function(c) { return c.hint !== undefined })[0]
              t.equal(hint.text, Data.layouts[language].digits['4'][0], 'visible number hint matches active layout')
            }
            t.ok(keys(board).every(function(k) {
              var at=k.mapToItem(board,0,0)
              return at.x >= -0.01 && at.x+k.width <= board.width+0.01 && k.height >= 30
            }), 'keys stay within keyboard bounds')
          }])
        })
      })
    })
    steps.push([0, function() {
      board.applyLayout(Data.layouts.us)
      t.equal(board.variantsFor('4').join(''), '$', 'US number alternatives come from real keymap')
      board.applyLayout(Data.layouts.fr)
      t.ok(board.variantsFor('4').indexOf("'") !== -1 && board.variantsFor('4').indexOf('{') !== -1, 'French number alternatives use unshifted and AltGr levels')
      t.ok(board.variantsFor('2').indexOf('é') !== -1, 'French number accents are reachable')
      board.applyLayout(Data.layouts.de)
      t.ok(board.variantsFor('2').indexOf('"') !== -1, 'German 2 shows its own symbol')
      board.applyLayout(Data.layouts.fr)
      host.passwordText = ''
      board.press('shift'); board.press('4')
      t.equal(host.passwordText, '4', 'Shift still types a digit directly')
      t.ok(!board.shift, 'digit consumes one-shot Shift')
      board.press('shift'); board.press('shift'); board.press('2')
      t.equal(host.passwordText, '42', 'Caps still types digits directly')
      board.press('shift')
      board.openPopup('2', keys(board).filter(function(k) { return k.modelData === '2' })[0])
      board.popup = Object.assign({}, board.popup, {index:board.variantsFor('2').indexOf('é')})
      board.choosePopup()
      t.equal(host.passwordText, '42é', 'held number accent reaches inert password view exactly')
      board.press('space'); board.press('a')
      t.equal(host.passwordText, '42é a', 'passphrase space and letter preserved')
      board.press('backspace')
      t.equal(host.passwordText, '42é ', 'Backspace still deletes')
      board.press('enter')
      t.equal(host.submitted, '42é ', 'Enter submits exact test string to inert view')
      t.equal(host.passwordText, '', 'submit clears local field')
      host.authenticatingPassword = true
      board.press('1')
      t.equal(host.passwordText, '', 'keys disabled during authentication')
      host.authenticatingPassword = false
    }])
    steps.push([0, function() {
      board.applyLayout(Data.layouts.us)
      board.shift = false; board.capsLock = false
      host.passwordText = ''
      board.page = 'symbols'
    }])
    steps.push([20, function() {
      var key = keys(board).filter(function(k) { return k.modelData === '1' })[0]
      t.equal(board.variantsFor('1').join(''), '!', 'hold excludes the base digit and retains one alternate')
      board.openPopup('1', key)
      t.ok(board.popup !== null, 'single alternate opens a hold card')
      t.equal(board.popup.items[board.popup.index], '!', 'printed digit alternate is selected for stationary hold')
      var p = board.popup
      board.selectAt(p.startX + 1, p.startY + 1)
      board.choosePopup()
      t.equal(host.passwordText, '!', 'stationary hold with finger jitter types alternate, not base')
      board.openPopup('1', key)
      board.selectAt(board.popup.x, board.popup.y - board.popup.cellHeight * 2)
      board.choosePopup()
      t.equal(host.passwordText, '!', 'moving well above the card cancels without inserting anything')
      board.page = 'letters'
    }])
    steps.push([20, function() {
      var key = keys(board).filter(function(k) { return k.modelData === 'e' })[0]
      t.ok(board.variantsFor('e').indexOf('e') === -1, 'letter hold excludes base letter')
      board.openPopup('e', key)
      t.equal(board.popup.index, -1, 'accent card has no unsolicited selection')
      board.choosePopup()
      t.equal(host.passwordText, '!e', 'stationary accent hold is still a slow tap')
      board.openPopup('e', key)
      var p = board.popup
      board.selectAt(p.x + p.cellWidth / 2, p.y + p.cellHeight / 2)
      board.choosePopup()
      t.equal(host.passwordText, '!eé', 'moving onto accent cell types the chosen character')
      board.openPopup('e', key)
      p = board.popup
      board.selectAt(p.x + p.cellWidth / 2, p.y + p.cellHeight / 2)
      board.selectAt(p.x, p.y + p.cellHeight * 3)
      board.choosePopup()
      t.equal(host.passwordText, '!eé', 'entering then leaving accent card cancels')
      board.shift = true
      t.ok(board.variantsFor('e').indexOf('E') === -1 && board.variantsFor('e').indexOf('É') !== -1, 'uppercase card excludes base but keeps uppercase accents')
      board.shift = false
      board.openPopup('e', key)
      root.resizeSerial = board.interactionSerial
      stage.width = stage.width - 20
    }])
    steps.push([20, function() {
      t.ok(board.popup === null && board.interactionSerial > root.resizeSerial, 'width change invalidates popup and pending release')
      var key = keys(board).filter(function(k) { return k.modelData === 'e' })[0]
      board.openPopup('e', key)
      host.inputEnabled = false
      t.equal(board.popup, null, 'disabled authentication input cancels a pending choice')
      host.inputEnabled = true
      board.choosePopup()
      t.equal(host.passwordText, '!eé', 'reenabling input does not resurrect canceled choice')
      host.passwordText = 'a😀'
      board.press('backspace')
      t.equal(host.passwordText, 'a', 'Backspace never leaves half a supplementary Unicode character')
      board.press('backspace')
      t.equal(host.passwordText, '', 'ordinary Backspace remains unchanged')
      board.layoutPunctuation = ['¿','؟']
      t.ok(board.variantsFor('?').indexOf('¿') !== -1 && board.variantsFor('?').indexOf('؟') !== -1, 'language punctuation is reachable through punctuation holds')
      t.ok(board.variantsFor('?').indexOf('?') === -1, 'punctuation hold excludes base mark')
      // A narrow, large-key board previously let an accent card overflow.
      stage.width = 320
      board.style = board.cleanStyle({sizeNudge:1.6})
    }])
    steps.push([20, function() {
      var key = keys(board).filter(function(k) { return k.modelData === 'e' })[0]
      board.openPopup('e', key)
      var p = board.popup
      t.ok(p.x >= board.padding - 0.01 && p.x + p.items.length * p.cellWidth <= board.width - board.padding + 0.01, 'hold card fits narrow screen with large keys')
      board.cancelInteraction()
      board.style = board.cleanStyle({sizeNudge:1})
    }])
    steps.push([0, function() {
      t.equal(board.cleanChar('😀'), '😀', 'one supplementary character passes metadata validation')
      t.equal(board.cleanChar('ab'), '', 'two ordinary characters do not pass as one key')
      t.equal(board.cleanChar('\ud83d'), '', 'lone surrogate is rejected')
      t.equal(board.cleanChar('\u0085'), '', 'C1 controls are rejected')
      var invalid = Object.assign({}, Data.layouts.us, {rows: [[['ab','AB']], [['c','C']], [['d','D']]]})
      t.ok(!board.validLayout(invalid), 'letter rows reject multiple-character key metadata')
      var clean = board.cleanDigits({'4':["'","'",'{','4','\n','bad',null], 'x':['!'], '1':'!','2':['é']})
      t.equal(JSON.stringify(clean), JSON.stringify({'2':['é'],'4':["'",'{']}), 'number metadata checked, bounded and deduplicated')
      var old = Object.assign({}, Data.layouts.fr); delete old.digits
      board.applyLayout(old)
      t.equal(board.variantsFor('4').length, 0, 'missing foreign metadata never invents US symbols')
      board.applyLayout(null)
      t.equal(board.variantsFor('4').join(''), '$', 'invalid layout falls back to US letters and symbols together')
      board.applyLayout(Data.layouts.us)
      stage.width = 768; stage.height = 1366
    }])
    steps.push([20, function() {
      root.targetHeight = board.keyHeight
      // Same width and scale, only height changes: targets are never squeezed
      // to fit the additional row. Body rows stay fixed relative to the bottom.
      root.backspace = bounds('backspace'); root.enter = bounds('enter')
      board.openPopup('1', keys(board).filter(function(k) { return k.modelData === '1' })[0])
      stage.height = 768
    }])
    steps.push([20, function() {
      t.ok(!board.showNumberRow && board.popup === null, 'short view removes row and dismisses stale popup')
      t.equal(board.keyHeight, root.targetHeight, 'compact fallback preserves target height')
      var a = bounds('backspace'), b = bounds('enter')
      t.ok(Math.abs(a[0]-root.backspace[0])<0.01 && Math.abs((a[1]-768)-(root.backspace[1]-1366))<0.01, 'Backspace remains anchored when extra row disappears')
      t.ok(Math.abs(b[0]-root.enter[0])<0.01 && Math.abs((b[1]-768)-(root.enter[1]-1366))<0.01, 'Enter remains anchored when extra row disappears')
    }])
    steps.push([0, function() {
      board.applyLayout(Data.layouts.us)
      board.page = 'symbols'
      board.shift = false; board.capsLock = false
      stage.width = 1366; stage.height = 768
      host.passwordText = ''
    }])
    steps.push([40, function() {
      var key = keys(board).filter(function(k) { return k.modelData === '1' })[0]
      input.mousePress(key)
      t.equal(host.passwordText, '', 'real pointer press defers digit while hold is possible')
    }])
    steps.push([500, function() {
      var key = keys(board).filter(function(k) { return k.modelData === '1' })[0]
      t.ok(board.popup !== null, 'real 420ms hold opens alternate card')
      input.mouseRelease(key)
      t.equal(host.passwordText, '!', 'real hold and release types exactly one alternate')
      input.mouseClick(key)
      t.equal(host.passwordText, '!1', 'real short tap still types base digit')
      board.page = 'letters'
    }])
    steps.push([20, function() {
      var key = keys(board).filter(function(k) { return k.modelData === 'q' })[0]
      input.mousePress(key)
      t.equal(host.passwordText, '!1', 'character without alternatives also waits for release')
      input.mouseRelease(key)
      t.equal(host.passwordText, '!1q', 'plain character commits on release exactly once')
      host.passwordText = 'abcdefghi'
      var back = keys(board).filter(function(k) { return k.modelData === 'backspace' })[0]
      input.mousePress(back)
    }])
    steps.push([650, function() {
      t.ok(host.passwordText.length < 8, 'real Backspace hold repeats')
      host.authenticatingPassword = true
      host.passwordText = 'preserve'
    }])
    steps.push([150, function() {
      host.authenticatingPassword = false
      var back = keys(board).filter(function(k) { return k.modelData === 'backspace' })[0]
      input.mouseRelease(back)
    }])
    steps.push([200, function() {
      t.equal(host.passwordText, 'preserve', 'authentication cancels repeat permanently, including after re-enable')
      host.passwordText = ''
      board.page = 'symbols'
    }])
    steps.push([20, function() {
      var key = keys(board).filter(function(k) { return k.modelData === '1' })[0]
      input.mousePress(key)
      stage.width = 1200
    }])
    steps.push([500, function() {
      var key = keys(board).filter(function(k) { return k.modelData === '1' })[0]
      input.mouseRelease(key)
      t.equal(host.passwordText, '', 'geometry change cancels pending real hold and release')
    }])
    t.run(steps)
  }
}
