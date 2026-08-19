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
  property int zoom: 2
  // Owned by the PL button in Player.qml; the pledit close box clears it.
  property bool shown: false
  // The hosting window's focus state, for the active/idle title-bar art.
  property bool windowActive: true

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
  readonly property int rowH: 11 * zoom

  // Frame thicknesses, in skin pixels.
  readonly property int frameTop: 20
  readonly property int frameBottom: 38
  readonly property int frameLeft: 12
  readonly property int frameRight: 20

  Item {
    id: frame
    anchors.fill: parent

    // ---- Top row: corner, tiles, centred title, corner -------------------
    SkinSprite {
      id: topLeft
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
          dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
          rect: root.windowActive ? S.PLEDIT.topTile : S.PLEDIT.topTileIdle
        }
      }
    }

    SkinSprite {
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: root.windowActive ? S.PLEDIT.titleBar : S.PLEDIT.titleBarIdle
      anchors.horizontalCenter: parent.horizontalCenter
    }

    SkinSprite {
      id: topRight
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
          root.shown = false
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
          dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
          rect: S.PLEDIT.bottomTile
        }
      }
    }

    SkinSprite {
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: S.PLEDIT.bottomLeft
      anchors.bottom: parent.bottom
    }

    SkinSprite {
      dir: root.skinDir; sheet: "pledit.bmp"; zoom: root.zoom
      rect: S.PLEDIT.bottomRight
      anchors.bottom: parent.bottom
      anchors.right: parent.right
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
            color: hover.containsMouse && modelData.kind === "track" ? root.selColor : "transparent"

            readonly property bool isCurrent: modelData.kind === "track"
              && root.nowTitle.length && modelData.title === root.nowTitle

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: modelData.kind === "header" ? 0 : 4 * root.zoom
              text: modelData.label
              color: modelData.kind === "header" ? root.selColor
                   : (parent.isCurrent ? root.currentColor : root.fgColor)
              font.family: root.fontName.length ? root.fontName : "monospace"
              font.pixelSize: root.fontPx
              font.bold: modelData.kind === "header" || parent.isCurrent
              elide: Text.ElideRight
              width: list.width - 8 * root.zoom
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
