import QtQuick
import Quickshell
import Quickshell.Io
import "sprites.js" as S

// The Winamp playlist editor, reimagined for what cliamp's IPC can actually
// do. The daemon cannot enumerate its live queue, so this window lists what
// *is* addressable -- the 11 built-in radio streams and every TOML playlist
// in ~/.config/cliamp/playlists/ -- and plays any entry immediately through
// the helper's scratch-playlist mechanism. A paste bar at the bottom takes a
// file path or stream URL, which is the "open file" Winamp's Eject offered.
//
// Colours come from the skin's own pledit.txt, which is exactly the file
// Winamp invented for this window: NormalBG/Normal/Current/SelectedBG.
FloatingWindow {
  id: root

  property string skinDir: ""
  property string helper: ""
  property int zoom: 2
  property bool shown: false

  // ---- pledit.txt colours ------------------------------------------------
  property color bgColor: "#000000"
  property color fgColor: "#00ff00"
  property color currentColor: "#ffffff"
  property color selColor: "#0000c6"
  property string fontName: ""

  FileView {
    path: root.skinDir.length ? root.skinDir + "/pledit.txt" : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.applyPledit(text())
    onFileChanged: reload()
  }

  function applyPledit(text) {
    var keys = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = /^\s*(\w+)\s*=\s*(#?[0-9A-Fa-f]{6}|\S.*?)\s*$/.exec(lines[i])
      if (m) keys[m[1].toLowerCase()] = m[2]
    }
    function col(name, fallback) {
      var v = keys[name]
      if (!v) return fallback
      if (v[0] !== "#" && /^[0-9A-Fa-f]{6}$/.test(v)) v = "#" + v
      return /^#[0-9A-Fa-f]{6}$/.test(v) ? v : fallback
    }
    bgColor = col("normalbg", "#000000")
    fgColor = col("normal", "#00ff00")
    currentColor = col("current", "#ffffff")
    selColor = col("selectedbg", "#0000c6")
    fontName = keys["font"] || ""
  }

  // ---- Data ----------------------------------------------------------------
  // Rows: {kind: "header"|"track", label, path, playlist, index}
  property var rows: []
  property string nowTitle: ""
  property string status: ""

  function refresh() {
    if (helper.length && !plProc.running) {
      plProc.command = [helper, "pl"]
      plProc.running = true
    }
  }

  function applyPayload(raw) {
    var d
    try { d = JSON.parse(String(raw)) } catch (e) { return }
    if (!d || d.error) { status = d ? d.error : "helper failed"; return }
    nowTitle = d.now ? String(d.now.title || "") : ""
    var out = [{ kind: "header", label: "STREAMS" }]
    var i
    for (i = 0; i < d.streams.length; i++)
      out.push({ kind: "track", label: (i + 1) + ". " + d.streams[i].title, path: d.streams[i].path, title: d.streams[i].title })
    for (var p = 0; p < d.playlists.length; p++) {
      var pl = d.playlists[p]
      out.push({ kind: "header", label: pl.name.toUpperCase() })
      for (i = 0; i < pl.tracks.length; i++)
        out.push({ kind: "track", label: (i + 1) + ". " + pl.tracks[i].title, playlist: pl.name, index: i, title: pl.tracks[i].title })
    }
    rows = out
  }

  function playRow(row) {
    if (row.kind !== "track" || actProc.running) return
    status = "Loading " + row.title + "…"
    actProc.command = row.playlist !== undefined
      ? [helper, "play-track", row.playlist, String(row.index)]
      : [helper, "play-now", row.path, "--title", row.title]
    actProc.running = true
  }

  function playInput(text) {
    var value = String(text || "").trim()
    if (!value.length || actProc.running) return
    status = "Loading…"
    actProc.command = [helper, "play-now", value]
    actProc.running = true
  }

  Process {
    id: plProc
    running: false
    command: []
    stdout: StdioCollector { id: plOut; waitForEnd: true }
    onExited: function(code) { root.applyPayload(plOut.text) }
  }

  Process {
    id: actProc
    running: false
    command: []
    stdout: StdioCollector { id: actOut; waitForEnd: true }
    onExited: function(code) {
      var d
      try { d = JSON.parse(String(actOut.text)) } catch (e) { d = null }
      root.status = d && d.playing ? "" : (d && d.error ? d.error : "load failed")
      root.refresh()
    }
  }

  onShownChanged: {
    visible = shown
    if (shown) refresh()
  }
  // Track external closes (compositor kill, etc.) back into the toggle state.
  onVisibleChanged: if (!visible && shown) shown = false

  visible: false
  title: "OmaAmp Playlist"
  implicitWidth: S.MAIN_WIDTH * zoom
  implicitHeight: S.MAIN_HEIGHT * 2 * zoom
  minimumSize: Qt.size(S.MAIN_WIDTH, S.MAIN_HEIGHT)
  color: bgColor

  readonly property int pad: 6 * zoom
  readonly property int rowH: 11 * zoom
  readonly property real fontPx: 8 * zoom

  Column {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: root.pad / 2

    // Title strip, Winamp-style centred caption.
    Rectangle {
      width: parent.width
      height: root.rowH
      color: root.selColor

      Text {
        anchors.centerIn: parent
        text: "OMAAMP PLAYLIST" + (root.nowTitle.length ? "  —  " + root.nowTitle : "")
        color: root.currentColor
        font.family: root.fontName.length ? root.fontName : "monospace"
        font.pixelSize: root.fontPx
        elide: Text.ElideRight
        width: parent.width - root.pad * 2
        horizontalAlignment: Text.AlignHCenter
      }

      MouseArea {
        anchors.fill: parent
        onPressed: if (root.Window.window) root.Window.window.startSystemMove()
      }
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - y - entryRow.height - root.pad
      clip: true
      model: root.rows
      boundsBehavior: Flickable.StopAtBounds

      delegate: Rectangle {
        required property var modelData
        width: list.width
        height: root.rowH
        color: hover.containsMouse && modelData.kind === "track" ? root.selColor : "transparent"

        readonly property bool isCurrent: modelData.kind === "track"
          && root.nowTitle.length && modelData.title === root.nowTitle

        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: modelData.kind === "header" ? 0 : root.pad
          text: modelData.label
          color: modelData.kind === "header" ? root.selColor
               : (parent.isCurrent ? root.currentColor : root.fgColor)
          font.family: root.fontName.length ? root.fontName : "monospace"
          font.pixelSize: root.fontPx
          font.bold: modelData.kind === "header" || parent.isCurrent
          elide: Text.ElideRight
          width: list.width - root.pad * 2
        }

        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: modelData.kind === "track" ? Qt.PointingHandCursor : Qt.ArrowCursor
          onDoubleClicked: root.playRow(modelData)
          onClicked: root.playRow(modelData)
        }
      }
    }

    // "Open": a path or URL, played immediately. Winamp's Eject, minus the
    // file dialog a layer-shell-less standalone shell cannot summon.
    Row {
      id: entryRow
      width: parent.width
      spacing: root.pad / 2

      Rectangle {
        width: parent.width - playBtn.width - parent.spacing
        height: root.rowH + 2 * root.zoom
        color: "transparent"
        border.color: root.fgColor
        border.width: 1

        TextInput {
          id: entry
          anchors.fill: parent
          anchors.margins: 2 * root.zoom
          color: root.currentColor
          font.family: root.fontName.length ? root.fontName : "monospace"
          font.pixelSize: root.fontPx
          clip: true
          verticalAlignment: TextInput.AlignVCenter
          onAccepted: { root.playInput(text); text = "" }

          Text {
            anchors.fill: parent
            visible: !entry.text.length && !entry.activeFocus
            text: "file path or stream URL…"
            color: root.fgColor
            opacity: 0.55
            font: entry.font
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Rectangle {
        id: playBtn
        width: 40 * root.zoom
        height: root.rowH + 2 * root.zoom
        color: playArea.pressed ? root.selColor : "transparent"
        border.color: root.fgColor
        border.width: 1

        Text {
          anchors.centerIn: parent
          text: "PLAY"
          color: root.fgColor
          font.family: root.fontName.length ? root.fontName : "monospace"
          font.pixelSize: root.fontPx
        }

        MouseArea {
          id: playArea
          anchors.fill: parent
          onClicked: { root.playInput(entry.text); entry.text = "" }
        }
      }
    }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.margins: 2 * root.zoom
    visible: root.status.length > 0
    text: root.status
    color: root.currentColor
    font.pixelSize: root.fontPx * 0.9
  }

  // The now-playing highlight tracks the engine even when changes come from
  // elsewhere (the main window's transport, the bar widget, the CLI).
  Timer {
    running: root.visible
    interval: 3000
    repeat: true
    onTriggered: root.refresh()
  }
}
