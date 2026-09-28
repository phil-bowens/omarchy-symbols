import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "symbols.js" as Data
import "ComposeTable.js" as Compose

// A picker for the symbols in xcompose-stem, with the rest of Unicode behind
// it. It inserts the symbol the same way the emoji picker does, and shows the
// compose sequence for the one under the cursor, so the shortcut is learned
// in passing. The curated set is searched first; the full Unicode set
// loads on first use, behind the Unicode chip or when a search finds nothing
// in the curated set.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property string group: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var filtered: []
  property bool showingUnicode: false

  // The long tail: [{e, k}] for ~47,000 code points, parsed on first need.
  property var unicode: []
  property bool unicodeLoaded: false
  property bool unicodeWanted: false
  // Compose sequences that are actually active on this machine, read from
  // ~/.XCompose and its includes each time the picker opens. The footer shows
  // these, so it reports what the keyboard does rather than what a data file
  // says: a stock Omarchy sees the system table's sequences, and anyone who
  // has included xcompose-stem sees those.
  property var active: ({})
  property int activeCount: 0
  property bool activeLoaded: false

  readonly property string unicodeChip: "Unicode"
  readonly property string allKey: "0"
  readonly property string unicodeKey: "z"

  // Alt plus this letter selects the chip; shown dimmed on the chip itself.
  function keyForGroup(g) {
    if (g === "") return root.allKey
    if (g === root.unicodeChip) return root.unicodeKey
    return Data.GROUP_KEYS[g] || ""
  }

  function groupForKey(letter) {
    if (letter === root.allKey) return ""
    if (letter === root.unicodeKey) return root.unicodeChip
    for (var g in Data.GROUP_KEYS) if (Data.GROUP_KEYS[g] === letter) return g
    return null
  }

  function selectGroup(next) {
    root.group = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }
  readonly property int resultCap: 1000

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(30), Style.font.body + Style.spacing.controlPaddingY * 2)
  property int chipHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.controlPaddingY)

  // Size with the screen, within limits: a 1366x768 laptop gets most of its
  // height and a comfortable width, a 1440p desktop gets a card that is
  // actually readable rather than the emoji picker's fixed 400 px.
  property int cardWidth: Math.min(panel.width - Style.gapsOut * 2,
    Math.max(Style.space(440), Math.min(Style.space(1100), Math.round(panel.width * 0.42))))
  property int cardHeight: Math.min(panel.height - Style.gapsOut * 2,
    Math.max(Style.space(500), Math.round(panel.height * 0.72)))

  property int cellWidth: Math.max(Style.space(48), Style.font.display + Style.spacing.lg)
  property int cellHeight: cellWidth
  property int columns: Math.max(1, Math.floor((cardWidth - contentMargin * 2) / cellWidth))

  readonly property var current: (cursorActive && selectedIndex >= 0 && selectedIndex < filtered.length)
    ? filtered[selectedIndex] : null

  function open(payloadJson) {
    root.opened = true
    composeProc.running = true
    root.filterText = ""
    root.group = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.phil-bowens.symbols")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function wordsOf(needle) {
    var out = []
    var parts = String(needle || "").trim().toLowerCase().split(/\s+/)
    for (var i = 0; i < parts.length; i++) if (parts[i]) out.push(parts[i])
    return out
  }

  function keywordsMatch(k, words) {
    for (var i = 0; i < words.length; i++)
      if (k.indexOf(words[i]) < 0) return false
    return true
  }

  function codepointOf(ch) {
    var cp = ch.codePointAt(0)
    var hex = cp.toString(16).toUpperCase()
    while (hex.length < 4) hex = "0" + hex
    return "U+" + hex
  }

  // A Unicode entry dressed like a curated one: name from its keyword string,
  // and the compose sequence if the same character is in the curated set.
  function unicodeEntry(item) {
    var name = item.k.replace(/ u\+[0-9a-f]+$/, "")
    return { e: item.e, n: name, c: "Unicode", g: root.unicodeChip, k: item.k }
  }

  function searchCurated(words) {
    var out = []
    for (var i = 0; i < Data.SYMBOLS.length; i++) {
      var item = Data.SYMBOLS[i]
      if (root.group && item.g !== root.group) continue
      if (keywordsMatch(item.k, words)) out.push(item)
    }
    return out
  }

  function searchUnicode(words) {
    var out = []
    for (var i = 0; i < root.unicode.length && out.length < root.resultCap; i++) {
      var item = root.unicode[i]
      if (item && item.e && keywordsMatch(item.k, words)) out.push(unicodeEntry(item))
    }
    return out
  }

  function rebuildDisplay() {
    var words = wordsOf(root.filterText)
    var out = []
    var fromUnicode = false

    if (root.group === root.unicodeChip) {
      fromUnicode = true
    } else {
      out = searchCurated(words)
      // Nothing curated matches a real query: fall through to Unicode.
      if (out.length === 0 && words.length > 0 && !root.group) fromUnicode = true
    }

    if (fromUnicode) {
      if (!root.unicodeLoaded) {
        root.unicodeWanted = true
        out = []
      } else {
        out = searchUnicode(words)
      }
    }

    root.showingUnicode = fromUnicode
    root.filtered = out

    displayModel.clear()
    for (var j = 0; j < out.length; j++)
      displayModel.append({ symbol: out[j].e, index: j })

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = displayModel.count > 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    })
  }

  function move(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      var next = selectedIndex + delta
      if (next < 0) next = 0
      if (next >= displayModel.count) next = displayModel.count - 1
      selectedIndex = next
    }
    resultGrid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function setGroup(next) {
    root.group = (next === root.group) ? "" : next
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  // Tab walks the chips: All, each curated group, Unicode, then All again.
  function cycleGroup(delta) {
    var groups = [""].concat(Data.GROUPS, [root.unicodeChip])
    var at = groups.indexOf(root.group)
    if (at < 0) at = 0
    root.group = groups[(at + delta + groups.length) % groups.length]
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.insert(displayModel.get(index).symbol)
  }

  function insert(symbol) {
    if (!symbol) return
    root.dismiss()
    // Third-party plugins are always installed under
    // ~/.config/omarchy/plugins/<id>/, which is a more dependable way to find
    // a sibling script than resolving a URL against however the QML was loaded.
    var id = (root.manifest && root.manifest.id) || "io.github.phil-bowens.symbols"
    var script = Quickshell.env("HOME") + "/.config/omarchy/plugins/" + id + "/symbols-insert"
    Quickshell.execDetached(["/bin/bash", script, symbol])
  }

  ListModel { id: displayModel }

  Process {
    id: composeProc
    command: ["/bin/bash", Quickshell.env("HOME") + "/.config/omarchy/plugins/"
      + ((root.manifest && root.manifest.id) || "io.github.phil-bowens.symbols") + "/compose-dump"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Compose.parse(text)
        root.active = parsed.bySymbol
        root.activeCount = parsed.count
        root.activeLoaded = true
      }
    }
  }

  // Loaded on first need only; 2.4 MB of JSON is not something to parse at
  // shell start for a picker that usually finds what it wants in the curated
  // set. Once parsed it stays for the session: the manifest keeps this
  // overlay loaded, as the emoji picker's does, so the parse happens once.
  FileView {
    id: unicodeFile
    // The path is only set once the long tail is wanted, which is what
    // makes the load lazy; FileView reads it as soon as it has a path.
    path: root.unicodeWanted || root.unicodeLoaded ? Qt.resolvedUrl("unicode.json").toString() : ""
    onLoadFailed: function(error) { console.warn("symbols: unicode.json failed to load: " + error) }
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.unicode = Array.isArray(data) ? data : []
      } catch (e) {
        root.unicode = []
      }
      root.unicodeLoaded = true
      if (root.unicodeWanted) { root.unicodeWanted = false; root.rebuildDisplay() }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-symbols"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var ctrl = event.modifiers & Qt.ControlModifier
          var pageRows = Math.max(1, Math.floor(resultGrid.height / root.cellHeight))
          var alt = event.modifiers & Qt.AltModifier
          if (alt && event.key >= Qt.Key_0 && event.key <= Qt.Key_Z) {
            var target = root.groupForKey(String.fromCharCode(event.key).toLowerCase())
            if (target !== null) { root.selectGroup(target); event.accepted = true; return }
          }
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.group) root.setGroup(root.group)
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) { root.cycleGroup(-1); event.accepted = true }
          else if (event.key === Qt.Key_Tab) { root.cycleGroup(1); event.accepted = true }
          else if (event.key === Qt.Key_Left || (ctrl && event.key === Qt.Key_H)) { root.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_Right || (ctrl && event.key === Qt.Key_L)) { root.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K)) { root.move(-root.columns); event.accepted = true }
          else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J)) { root.move(root.columns); event.accepted = true }
          else if (event.key === Qt.Key_PageUp) { root.move(-root.columns * pageRows); event.accepted = true }
          else if (event.key === Qt.Key_PageDown) { root.move(root.columns * pageRows); event.accepted = true }
          else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (!ctrl && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        id: layout
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"
          Text {
            id: searchLabel
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - keyHint.width - Style.spacing.md)
            text: root.filterText || "Search symbols…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          // One quiet hint, gone as soon as anything is typed.
          Text {
            id: keyHint
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.filterText
            text: "Alt+letter · Tab"
            color: root.foreground
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Category chips. Click to filter, click again or Escape to clear;
        // Tab and Shift+Tab walk them from the keyboard. Unicode is the long
        // tail and sits last.
        Flow {
          id: chips
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: [""].concat(Data.GROUPS, [root.unicodeChip])
            delegate: Rectangle {
              required property string modelData
              readonly property bool active: root.group === modelData
              height: root.chipHeight
              width: chipRow.implicitWidth + Style.spacing.md * 2
              radius: height / 2
              color: active ? root.selectedBackground : "transparent"
              border.width: active ? 0 : Math.max(1, Style.space(1))
              border.color: root.border

              Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Style.spacing.xs
                Text {
                  textFormat: Text.PlainText
                  text: modelData || "All"
                  color: active ? root.selectedText : root.foreground
                  opacity: active ? 1 : 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.keyForGroup(modelData)
                  color: active ? root.selectedText : root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.baseline: parent.children[0].baseline
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setGroup(parent.modelData)
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - chips.height - root.footerHeight - root.contentSpacing * 3

          GridView {
            id: resultGrid
            anchors.fill: parent
            model: displayModel
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              required property int index
              required property string symbol
              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              width: root.cellWidth
              height: root.cellHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                textFormat: Text.PlainText
                text: parent.symbol
                color: parent.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                anchors.centerIn: parent
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.selectedIndex = index }
                onClicked: { root.cursorActive = true; root.selectedIndex = index; root.activateIndex(index) }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: displayModel.count === 0
            textFormat: Text.PlainText
            text: (root.showingUnicode && !root.unicodeLoaded) ? "Loading Unicode…"
              : "No matches for “" + root.filterText + "”" + (root.group ? " in " + root.group : "")
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        // The footer is the point: the symbol under the cursor, its name and
        // code point, and the compose sequence that would have typed it.
        Rectangle {
          width: parent.width
          height: root.footerHeight
          color: "transparent"
          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md
            Text {
              textFormat: Text.PlainText
              text: root.current
                ? root.current.n + "  " + root.codepointOf(root.current.e)
                : (displayModel.count + (root.showingUnicode && displayModel.count >= root.resultCap ? "+" : "")
                   + " symbols" + (root.group ? " in " + root.group : ""))
              color: root.foreground
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width * 0.6
            }
            Text {
              textFormat: Text.PlainText
              text: !root.current ? ""
                : root.active[root.current.e] ? "Compose " + root.active[root.current.e]
                : (root.activeLoaded ? "no compose sequence" : "")
              color: root.current && root.active[root.current.e] ? root.selectedText : root.foreground
              opacity: root.current && root.active[root.current.e] ? 1 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              width: parent.width * 0.4 - Style.spacing.md
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }
    }
  }
}
