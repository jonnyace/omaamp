import QtQuick
import Quickshell.Io
import "sprites.js" as S

// The docked playlist editor: not a window of its own but the pane Winamp
// grew beneath the main window when PL lit up. The frame is built from
// pledit.bmp exactly the way Winamp built it -- fixed corner pieces, tiles
// repeated to fill whatever size the pane is -- and the list inside uses
// pledit.txt's colors and font: bitmap frame, text-mode contents, the
// original's own split.
//
// What it lists is what cliamp's IPC can actually address: the 11 built-in
// radio streams and every TOML playlist in ~/.config/cliamp/playlists/,
// with a paste bar that plays any file path or stream URL immediately.
Item {
  id: root

  property string skinDir: ""
  property string helper: ""
  property real zoom: 2
  property int preferredSkinHeight: S.PLAYLIST_MIN_HEIGHT
  // Owned by the PL button in Player.qml; the pledit close box clears it.
  property bool shown: false
  // The hosting window's focus state, for the active/idle title-bar art.
  property bool windowActive: true
  // Set to the seven theme colors when the player wears the flat TUI face:
  // the pledit bitmaps hide and the pane draws its own chrome to match.
  property var tui: null
  signal heightRequested(int skinPixels, bool commit)
  signal closeRequested()

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

  onTuiChanged: {
    if (tui) {
      bgColor = tui.bg || "#101010"
      fgColor = tui.fg || "#707880"
      currentColor = tui.bright_fg || "#e0e0e0"
      selColor = tui.accent || "#446644"
      fontName = "monospace"
    }
  }

  function applyPledit(text) {
    if (tui) return  // theme colors own the pane in TUI mode
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

  visible: shown
  onShownChanged: if (shown) refresh()

  readonly property real fontPx: 8 * zoom
  readonly property color tuiDim: Qt.alpha(root.fgColor, 0.55)
  readonly property int rowH: 11 * zoom

  // Frame thicknesses, in skin pixels. The flat face needs far less chrome
  // than the bitmap frame's button clusters.
  readonly property int frameTop: tui ? 13 : 20
  readonly property int frameBottom: tui ? 4 : 38
  readonly property int frameLeft: tui ? 4 : 12
  readonly property int frameRight: tui ? 4 : 20

  Item {
    id: frame
    anchors.fill: parent

    // Flat chrome for TUI mode: no frame at all, just cliamp's
    // "── Playlist ──────" separator line above the rows.
    Rectangle {
      anchors.fill: parent
      visible: !!root.tui
      color: root.bgColor
    }

    Row {
      visible: !!root.tui
      x: root.frameLeft * root.zoom + 2 * root.zoom
      // Ends where the rows' own separators end (list inset + label inset).
      width: parent.width - (root.frameLeft + root.frameRight + 8) * root.zoom
      height: root.frameTop * root.zoom
      spacing: 0

      Text {
        id: plHeader
        anchors.verticalCenter: parent.verticalCenter
        text: "── Playlist "
        color: root.tuiDim
        font.family: "monospace"
        font.pixelSize: root.fontPx
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - plHeader.width
        height: Math.max(1, root.zoom)
        color: root.tuiDim
      }
    }

    // ---- Top row: corner, tiles, centred title, corner -------------------
    // (all bitmap chrome hides in TUI mode; the flat strip below takes over)
    SkinSprite {
      id: topLeft
      visible: !root.tui
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: root.windowActive ? S.PLEDIT.topLeft : S.PLEDIT.topLeftIdle
    }

    // Tiles fill the whole strip between the corners; the title sits on top.
    Row {
      anchors.left: topLeft.right
      anchors.right: topRight.left
      spacing: 0
      clip: true

      Repeater {
        model: Math.max(0, Math.ceil((frame.width - 50 * root.zoom) / (25 * root.zoom)))

        SkinSprite {
          visible: !root.tui
          dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
          rect: root.windowActive ? S.PLEDIT.topTile : S.PLEDIT.topTileIdle
        }
      }
    }

    SkinSprite {
      visible: !root.tui
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: root.windowActive ? S.PLEDIT.titleBar : S.PLEDIT.titleBarIdle
      anchors.horizontalCenter: parent.horizontalCenter
    }

    SkinSprite {
      id: topRight
      visible: !root.tui
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: root.windowActive ? S.PLEDIT.topRight : S.PLEDIT.topRightIdle
      anchors.right: parent.right
    }

    // The whole top strip drags the window; the close hotspot wins over it.
    MouseArea {
      width: parent.width
      height: root.frameTop * root.zoom
      onPressed: function(mouse) {
        var cx = frame.width - S.PLEDIT.closeAt[0] * root.zoom
        var cy = S.PLEDIT.closeAt[1] * root.zoom
        if (mouse.x >= cx && mouse.y >= cy && mouse.y <= cy + S.PLEDIT.closeAt[3] * root.zoom) {
          root.closeRequested()
          return
        }
        if (root.Window.window) root.Window.window.startSystemMove()
      }
    }

    // ---- Sides ------------------------------------------------------------
    Column {
      y: root.frameTop * root.zoom
      height: frame.height - (root.frameTop + root.frameBottom) * root.zoom
      clip: true

      Repeater {
        model: Math.max(0, Math.ceil(frame.height / (29 * root.zoom)))

        SkinSprite {
          visible: !root.tui
          dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
          rect: S.PLEDIT.leftTile
        }
      }
    }

    Column {
      anchors.right: parent.right
      y: root.frameTop * root.zoom
      height: frame.height - (root.frameTop + root.frameBottom) * root.zoom
      clip: true

      Repeater {
        model: Math.max(0, Math.ceil(frame.height / (29 * root.zoom)))

        SkinSprite {
          visible: !root.tui
          dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
          rect: S.PLEDIT.rightTile
        }
      }
    }

    // ---- Bottom row ---------------------------------------------------------
    Row {
      anchors.bottom: parent.bottom
      x: S.PLEDIT.bottomLeft[2] * root.zoom
      width: Math.max(0, frame.width - (S.PLEDIT.bottomLeft[2] + S.PLEDIT.bottomRight[2]) * root.zoom)
      spacing: 0
      clip: true

      Repeater {
        model: Math.max(0, Math.ceil(frame.width / (25 * root.zoom)))

        SkinSprite {
          visible: !root.tui
          dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
          rect: S.PLEDIT.bottomTile
        }
      }
    }

    SkinSprite {
      visible: !root.tui
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: S.PLEDIT.bottomLeft
      anchors.bottom: parent.bottom

      // ADD is the one button in this cluster with a real backing action:
      // it focuses the paste bar, which is this build's add-URL/add-file.
      // REM/SEL/MISC manage a queue cliamp's IPC cannot address, so they
      // stay decorative rather than pretending.
      MouseArea {
        x: 9 * root.zoom
        y: 8 * root.zoom
        width: 28 * root.zoom
        height: 26 * root.zoom
        onClicked: entry.forceActiveFocus()
      }
    }

    // Winamp stretched the editor one 29px side tile at a time. This handle
    // changes the floating window's preferred size; in a compositor tile the
    // pane still consumes the space Hyprland assigned to the window.
    MouseArea {
      id: resizeGrip
      z: 20
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: 20 * root.zoom
      height: 20 * root.zoom
      cursorShape: Qt.SizeVerCursor
      property real pressY: 0
      property int pressHeight: S.PLAYLIST_MIN_HEIGHT

      onPressed: function(mouse) {
        pressY = mouse.y
        pressHeight = root.preferredSkinHeight
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        root.heightRequested(
          S.snapPlaylistHeight(pressHeight + (mouse.y - pressY) / root.zoom), false)
      }
      onReleased: root.heightRequested(root.preferredSkinHeight, true)
      onCanceled: root.heightRequested(root.preferredSkinHeight, true)
    }

    SkinSprite {
      visible: !root.tui
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: S.PLEDIT.bottomRight
      anchors.bottom: parent.bottom
      anchors.right: parent.right

      MouseArea {
        // LIST OPTS: reload playlists from disk, so a TOML dropped into
        // ~/.config/cliamp/playlists/ shows up without reopening the pane.
        x: 106 * root.zoom
        y: 8 * root.zoom
        width: 22 * root.zoom
        height: 18 * root.zoom
        onClicked: { root.status = "Playlists reloaded"; root.refresh() }
      }
    }

    // ---- Contents, inside the frame ---------------------------------------
    Rectangle {
      id: content
      x: root.frameLeft * root.zoom
      y: root.frameTop * root.zoom
      width: frame.width - (root.frameLeft + root.frameRight) * root.zoom
      height: frame.height - (root.frameTop + root.frameBottom) * root.zoom
      color: root.bgColor

      Column {
        anchors.fill: parent
        anchors.margins: 2 * root.zoom

        ListView {
          id: list
          width: parent.width
          height: parent.height - entryRow.height - 2 * root.zoom
          clip: true
          model: root.rows
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            required property var modelData
            width: list.width
            height: root.rowH
            // pledit highlights the hovered row with selectedbg; cliamp has
            // no fills at all, it recolors the text instead.
            color: hover.containsMouse && modelData.kind === "track" && !root.tui
              ? root.selColor : "transparent"

            readonly property bool isCurrent: modelData.kind === "track"
              && root.nowTitle.length && modelData.title === root.nowTitle
            readonly property bool isHeader: modelData.kind === "header"

            // cliamp's playing marker, in the gutter the "  " indent leaves.
            Text {
              visible: !!root.tui && parent.isCurrent
              anchors.verticalCenter: parent.verticalCenter
              x: 0
              text: "▶"
              color: root.currentColor
              font.family: "monospace"
              font.pixelSize: root.fontPx
              font.bold: true
            }

            Text {
              id: rowLabel
              anchors.verticalCenter: parent.verticalCenter
              x: parent.isHeader ? 0 : (root.tui ? 2 : 1) * 4 * root.zoom
              text: root.tui && parent.isHeader ? "── " + modelData.label + " " : modelData.label
              textFormat: Text.PlainText
              color: parent.isHeader ? (root.tui ? root.tuiDim : root.selColor)
                   : (root.tui && hover.containsMouse ? root.selColor
                   : parent.isCurrent ? root.currentColor : root.fgColor)
              font.family: root.fontName.length ? root.fontName : "monospace"
              font.pixelSize: root.fontPx
              font.bold: (parent.isHeader && !root.tui) || parent.isCurrent
                || (!!root.tui && hover.containsMouse && !parent.isHeader)
              elide: Text.ElideRight
              width: Math.min(implicitWidth, list.width - x - 4 * root.zoom)
            }

            // Header rows become cliamp's labeled separators: ── NAME ─────
            Rectangle {
              visible: !!root.tui && parent.isHeader
              anchors.verticalCenter: parent.verticalCenter
              x: rowLabel.x + rowLabel.width
              width: Math.max(0, list.width - x - 4 * root.zoom)
              height: Math.max(1, root.zoom)
              color: root.tuiDim
            }

            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: modelData.kind === "track" ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.playRow(modelData)
            }
          }
        }

        // "Open": a path or URL, played immediately -- Winamp's Eject.
        Row {
          id: entryRow
          width: parent.width
          spacing: 2 * root.zoom

          Rectangle {
            width: parent.width - playBtn.width - parent.spacing
            height: root.rowH + 2 * root.zoom
            color: "transparent"
            border.color: root.fgColor
            border.width: root.tui ? 0 : 1

            Text {
              id: prompt
              visible: !!root.tui
              anchors.verticalCenter: parent.verticalCenter
              text: "> "
              color: entry.activeFocus ? root.selColor : root.tuiDim
              font.family: "monospace"
              font.pixelSize: root.fontPx
              font.bold: true
            }

            TextInput {
              id: entry
              anchors.fill: parent
              anchors.margins: 2 * root.zoom
              anchors.leftMargin: root.tui ? prompt.width : 2 * root.zoom
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
            color: playArea.pressed && !root.tui ? root.selColor : "transparent"
            border.color: root.fgColor
            border.width: root.tui ? 0 : 1

            Text {
              anchors.centerIn: parent
              text: root.tui ? "[PLAY]" : "PLAY"
              color: root.tui && playArea.containsMouse ? root.currentColor : root.fgColor
              font.family: root.fontName.length ? root.fontName : "monospace"
              font.pixelSize: root.fontPx
            }

            MouseArea {
              id: playArea
              anchors.fill: parent
              hoverEnabled: true
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
        textFormat: Text.PlainText
        color: root.currentColor
        font.pixelSize: root.fontPx * 0.9
      }
    }
  }

  // Keeps the now-playing highlight honest when changes come from the main
  // window's transport, the bar widget, or the CLI.
  Timer {
    running: root.visible
    interval: 3000
    repeat: true
    onTriggered: root.refresh()
  }
}
