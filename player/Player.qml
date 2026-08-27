import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "sprites.js" as S

// OmaAmp: the Winamp 2.x main window, floating on the desktop.
//
// It plays nothing. Like omarchy.media it is an MPRIS client, so the same
// window drives cliamp, Spotify, Chromium or mpv, and it coexists with the bar
// widget rather than replacing it.
//
// A FloatingWindow (a real xdg-toplevel) rather than a layer-shell panel,
// because Winamp's whole character is that you park it wherever you like.
FloatingWindow {
  id: root

  // Directory of normalised sprite sheets, from `skinner use`.
  property string skinDir: ""
  property bool extendedDigits: false
  property string skinName: ""

  // Launch-time zoom sets the initial window size; after that the skin
  // scales to whatever space the window actually has, at integer steps only
  // -- a tiled OmaAmp fills its tile at 2x or 3x instead of rattling around
  // at launch size or smearing at a fractional one.
  property int baseZoom: 2
  property bool originalSize: false
  // Zoom is chosen in PHYSICAL pixels, not logical ones: on a scale-2 panel
  // a logical zoom of 1.5 is exactly 3 hardware pixels per skin pixel --
  // still perfectly crisp nearest-neighbour. Original mode is exactly one
  // hardware pixel per skin pixel, which is Winamp's native 275x116 size.
  readonly property real dpr: devicePixelRatio > 0 ? devicePixelRatio : 1
  readonly property real preferredZoom: originalSize ? 1 / dpr : baseZoom
  readonly property real zoom: {
    var fitPhys = Math.floor(Math.min(
      width * dpr / S.MAIN_WIDTH,
      height * dpr / S.MAIN_HEIGHT))
    // Large mode keeps the existing adaptive 1.5x headroom in a roomy tile;
    // original mode hard-caps the artwork at one physical pixel per source.
    var capPhys = originalSize
      ? 1
      : Math.max(1, Math.round(baseZoom * dpr * 1.5))
    return Math.max(1, Math.min(capPhys, fitPhys)) / dpr
  }

  // The bar plugin and this app are separate processes; the plugin writes
  // ~/.local/state/omaamp/current.json and this watcher hot-swaps the skin,
  // so picking one in the browser restyles a running player in place.
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omaamp/current.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyState(text())
    onFileChanged: reload()
  }

  function applyState(raw) {
    var state
    try { state = JSON.parse(String(raw)) } catch (e) { return }
    if (!state) return
    originalSize = state.size === "original"
    requestPreferredSize()
    if (state.mode === "tui" && state.colors) {
      tuiMode = true
      tuiColors = state.colors
      skinName = String(state.name || "theme")
      skinDir = ""
      return
    }
    if (!state.dir) return
    tuiMode = false
    skinDir = state.dir
    skinName = String(state.name || "")
    extendedDigits = state.extendedDigits === true
  }

  // The flat face: drawn from the seven cliamp theme colors instead of
  // bitmaps, so "My themes" picks and Tune edits recolor the player live.
  property bool tuiMode: false
  property var tuiColors: ({})
  readonly property color tBg: tuiColors.bg || "#101010"
  readonly property color tFg: tuiColors.fg || "#707880"
  readonly property color tHi: tuiColors.bright_fg || "#e0e0e0"
  readonly property color tAcc: tuiColors.accent || "#8fbcbb"
  readonly property var tRamp: tuiMode
    ? S.tuiVisRamp(tuiColors.red || "#dc322f", tuiColors.yellow || "#b58900", tuiColors.green || "#859900")
    : []

  // ---- Player selection -------------------------------------------------

  readonly property var players: Mpris.players ? Mpris.players.values : []

  // cliamp first, always: it is the engine this app manages, so the window
  // should read it even while it sits stopped next to a Chromium tab that
  // happens to be playing. Anything else is only shown when no cliamp is on
  // the bus at all -- then whatever is playing, then whatever exists.
  readonly property var player: {
    var i
    for (i = 0; i < players.length; i++)
      if (players[i] && String(players[i].dbusName || "").indexOf("cliamp") !== -1) return players[i]
    for (i = 0; i < players.length; i++)
      if (players[i] && players[i].isPlaying) return players[i]
    return players.length ? players[0] : null
  }

  readonly property bool playing: player ? player.isPlaying === true : false

  // Named `trackLabel`, not `title`: FloatingWindow already has a `title`
  // (the window-manager caption), and shadowing it silently breaks both.
  readonly property string trackLabel: {
    if (!player) return "OmaAmp"
    var t = String(player.trackTitle || "")
    var a = String(player.trackArtist || "")
    return a.length ? a + " - " + t : (t.length ? t : String(player.identity || ""))
  }

  property real elapsed: 0
  readonly property real duration: player && player.lengthSupported ? player.length : 0
  readonly property var clock: S.formatClock(seeking ? seekFraction * duration : elapsed)

  // ---- Seek / volume drag state ----------------------------------------
  // While a slider is held, the display follows the thumb rather than the
  // player: committing on every pixel would spam the bus and fight the
  // position updates coming back.
  property bool seeking: false
  property real seekFraction: 0
  property bool holdingVolume: false
  property real volumeFraction: 0

  readonly property real progress: {
    if (seeking) return seekFraction
    if (!duration) return 0
    return Math.max(0, Math.min(1, elapsed / duration))
  }

  readonly property real volumeLevel: {
    if (holdingVolume) return volumeFraction
    return player && player.volumeSupported ? Math.max(0, Math.min(1, player.volume)) : 1
  }

  title: "OmaAmp" + (skinName.length ? " — " + skinName : "")
  implicitWidth: Math.ceil(S.MAIN_WIDTH * preferredZoom)
  implicitHeight: Math.ceil(S.MAIN_HEIGHT * preferredZoom)
  minimumSize: Qt.size(
    Math.ceil(S.MAIN_WIDTH / dpr),
    Math.ceil(S.MAIN_HEIGHT / dpr))
  maximumSize: Qt.size(16384, 16384)

  function requestPreferredSize() {
    // A floating compositor honors this immediately; a tiled compositor keeps
    // its tile while the artwork itself switches scale within it.
    implicitWidth = Math.ceil(S.MAIN_WIDTH * preferredZoom)
    implicitHeight = Math.ceil(S.MAIN_HEIGHT * (playlist_.shown ? 2 : 1) * preferredZoom)
  }

  // Transparent letterbox: in a tile bigger than the skin, the wallpaper
  // shows through around the artwork instead of a black slab.
  color: "transparent"

  // One window, Winamp-docked: toggling PL grows or shrinks the window by
  // a main-window-height so the pane appears attached below the skin. In a
  // tile the compositor ignores the resize request and the pane simply uses
  // the space the tile already grants.
  function togglePlaylist() {
    playlist_.shown = !playlist_.shown
    // implicitHeight is the client-side resize request; a tiling layout
    // ignores it, a floating window honors it.
    implicitHeight = Math.ceil((S.MAIN_HEIGHT * (playlist_.shown ? 2 : 1)) * preferredZoom)
  }

  function transport(action) {
    if (!player) return
    if (action === "play") {
      if (player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
    } else if (action === "pause") {
      if (player.canPause) player.pause()
      else if (player.canTogglePlaying) player.togglePlaying()
    } else if (action === "stop") {
      player.stop()
    } else if (action === "next") {
      if (player.canGoNext) player.next()
    } else if (action === "previous") {
      if (player.canGoPrevious) player.previous()
    }
  }

  function commitSeek() {
    if (player && player.canSeek && duration > 0) player.position = seekFraction * duration
    seeking = false
  }

  function cycleLoop() {
    if (!player || !player.loopSupported) return
    player.loopState = player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                     : player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                     : MprisLoopState.None
  }

  // MPRIS players publish `position` on their own schedule -- some only when
  // it jumps. Sampling on a timer keeps the readout ticking between updates.
  Timer {
    running: root.visible
    interval: 500
    repeat: true
    onTriggered: root.elapsed = root.player && root.player.positionSupported ? root.player.position : 0
  }

  // ---- Analyzer ---------------------------------------------------------

  property var visColors: []
  property var bands: []

  // The skin's own analyzer ramp, so the bars are the colours its author chose
  // rather than a generic gradient.
  FileView {
    path: root.skinDir.length ? root.skinDir + "/viscolor.txt" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.visColors = S.parseViscolor(text())
  }

  // MPRIS carries no spectrum data, so a real analyzer is only possible for a
  // player that exposes one. cliamp streams bands as NDJSON; for anything else
  // the well simply stays empty rather than faking movement.
  readonly property bool spectrumAvailable:
    player && String(player.dbusName || "").indexOf("cliamp") !== -1

  Process {
    running: root.visible && root.spectrumAvailable && root.playing
    command: ["cliamp", "visstream"]
    stdout: SplitParser {
      onRead: function(line) {
        var next = S.parseBands(line)
        if (next) root.bands = next
      }
    }
    onRunningChanged: if (!running) root.bands = []
  }

  // ---- Marquee ----------------------------------------------------------

  property int marqueeOffset: 0
  readonly property bool marqueeNeeded: trackLabel.length > S.TITLE_CELLS
  readonly property string marqueeText: {
    if (!marqueeNeeded) return trackLabel
    var padded = trackLabel + "   ***   "
    var start = marqueeOffset % padded.length
    return (padded + padded).substr(start, S.TITLE_CELLS)
  }

  Timer {
    running: root.visible && root.marqueeNeeded
    interval: 220
    repeat: true
    onTriggered: root.marqueeOffset++
  }

  // Docked stack, centered as one unit: the main window with the playlist
  // grown beneath it when PL is lit -- one window, one tile, like Winamp
  // with the playlist snapped on.
  Column {
    id: stack
    anchors.centerIn: parent
    spacing: 0

    Item {
    visible: !root.tuiMode
    width: S.MAIN_WIDTH * root.zoom
    height: S.MAIN_HEIGHT * root.zoom

    // ---- Background ------------------------------------------------------
    Image {
      anchors.fill: parent
      source: root.skinDir ? "file://" + root.skinDir + "/main.bmp" : ""
      smooth: false
      mipmap: false
      asynchronous: false
    }

    // ---- Title bar -------------------------------------------------------
    SkinSprite {
      dir: root.skinDir
      sheet: "titlebar.bmp"
      zoom: root.zoom
      rect: root.active ? S.TITLEBAR.active : S.TITLEBAR.inactive
      x: S.TITLEBAR.at[0] * root.zoom
      y: S.TITLEBAR.at[1] * root.zoom

      // Undecorated by design, so the title bar has to do the dragging
      // itself. startSystemMove hands the drag to the compositor, which is
      // what makes it behave like a normal window instead of a widget that
      // chases the cursor a frame late.
      MouseArea {
        anchors.fill: parent
        onPressed: if (root.Window.window) root.Window.window.startSystemMove()
      }
    }

    Repeater {
      model: S.WINDOW_BUTTONS

      SkinSprite {
        required property var modelData
        dir: root.skinDir
        sheet: "titlebar.bmp"
        zoom: root.zoom
        rect: area.pressed ? modelData.press : modelData.rect
        x: modelData.at[0] * root.zoom
        y: modelData.at[1] * root.zoom

        MouseArea {
          id: area
          anchors.fill: parent
          onClicked: if (modelData.id === "close") root.visible = false
        }
      }
    }

    // ---- Play / pause / stop indicator ----------------------------------
    SkinSprite {
      dir: root.skinDir
      sheet: "playpaus.bmp"
      zoom: root.zoom
      rect: root.playing ? S.PLAY_STATE.playing
           : (root.player ? S.PLAY_STATE.paused : S.PLAY_STATE.stopped)
      x: S.PLAY_STATE.at[0] * root.zoom
      y: S.PLAY_STATE.at[1] * root.zoom
    }

    // ---- Time readout ----------------------------------------------------
    Repeater {
      model: 4

      SkinSprite {
        required property int index
        dir: root.skinDir
        sheet: root.extendedDigits ? "nums_ex.bmp" : "numbers.bmp"
        zoom: root.zoom
        rect: S.digitRect(root.clock[index], root.extendedDigits)
        x: S.DIGIT_AT[index][0] * root.zoom
        y: S.DIGIT_AT[index][1] * root.zoom
      }
    }

    // ---- Track title, in the skin's own bitmap font -----------------------
    Row {
      x: S.TITLE_AT[0] * root.zoom
      y: S.TITLE_AT[1] * root.zoom
      spacing: 0

      Repeater {
        model: root.marqueeText.split("")

        // Characters with no cell -- spaces above all -- occupy their width
        // and draw nothing, which is what the marquee should do.
        Item {
          required property string modelData
          readonly property var cell: S.charRect(modelData)
          width: S.CHAR.w * root.zoom
          height: S.CHAR.h * root.zoom

          SkinSprite {
            visible: parent.cell !== null
            dir: root.skinDir
            sheet: "text.bmp"
            zoom: root.zoom
            rect: parent.cell || [0, 0, 0, 0]
          }
        }
      }
    }

    // ---- Analyzer --------------------------------------------------------
    Row {
      x: S.VIS.at[0] * root.zoom
      y: S.VIS.at[1] * root.zoom
      spacing: S.VIS_BAR_GAP * root.zoom
      visible: root.bands.length > 0

      Repeater {
        model: S.resample(root.bands, S.visBarCount())

        // Each bar is a stack of single-pixel rows lit from the bottom up,
        // which is how Winamp's analyzer works -- and why the ramp has one
        // colour per row rather than one per bar.
        Column {
          required property real modelData
          spacing: 0
          readonly property int lit: Math.round(Math.max(0, Math.min(1, modelData)) * S.VIS_ROWS)

          Repeater {
            model: S.VIS_ROWS

            // Unlit rows stay in the layout and go transparent rather than
            // being hidden: a Column drops invisible children entirely, which
            // collapsed every bar upward so they hung from the top of the well
            // instead of standing on its floor. Transparent also lets the
            // skin's own analyzer background show through, as Winamp does.
            Rectangle {
              required property int index
              width: S.VIS_BAR_WIDTH * root.zoom
              height: root.zoom
              // Row 0 is the top of the bar, matching the ramp's own order.
              color: index < S.VIS_ROWS - parent.lit
                ? "transparent"
                : (root.visColors.length > index ? root.visColors[index] : "#00dd00")
            }
          }
        }
      }
    }

    // ---- Position slider -------------------------------------------------
    Item {
      x: S.POSBAR.at[0] * root.zoom
      y: S.POSBAR.at[1] * root.zoom
      width: S.POSBAR.background[2] * root.zoom
      height: S.POSBAR.background[3] * root.zoom
      // Nothing to scrub when the player cannot report a length.
      visible: root.duration > 0

      SkinSprite {
        dir: root.skinDir
        sheet: "posbar.bmp"
        zoom: root.zoom
        rect: S.POSBAR.background
      }

      SkinSprite {
        dir: root.skinDir
        sheet: "posbar.bmp"
        zoom: root.zoom
        rect: seekArea.pressed ? S.POSBAR.thumbDown : S.POSBAR.thumb
        x: root.progress * S.POSBAR.travel * root.zoom
      }

      MouseArea {
        id: seekArea
        anchors.fill: parent
        onPressed: function(mouse) {
          root.seeking = true
          root.seekFraction = Math.max(0, Math.min(1, mouse.x / width))
        }
        onPositionChanged: function(mouse) {
          if (pressed) root.seekFraction = Math.max(0, Math.min(1, mouse.x / width))
        }
        onReleased: root.commitSeek()
        onCanceled: root.seeking = false
      }
    }

    // ---- Volume ----------------------------------------------------------
    Item {
      x: S.VOLUME.at[0] * root.zoom
      y: S.VOLUME.at[1] * root.zoom
      width: S.VOLUME.size[0] * root.zoom
      height: S.VOLUME.size[1] * root.zoom
      visible: root.player && root.player.volumeSupported

      // volume.bmp stacks one background frame per loudness step, so the bar
      // itself brightens as it fills.
      SkinSprite {
        dir: root.skinDir
        sheet: "volume.bmp"
        zoom: root.zoom
        rect: S.volumeFrameRect(root.volumeLevel)
      }

      SkinSprite {
        dir: root.skinDir
        sheet: "volume.bmp"
        zoom: root.zoom
        rect: volumeArea.pressed ? S.VOLUME.thumbDown : S.VOLUME.thumb
        x: root.volumeLevel * S.VOLUME.travel * root.zoom
      }

      MouseArea {
        id: volumeArea
        anchors.fill: parent
        function apply(mouse) {
          root.volumeFraction = Math.max(0, Math.min(1, mouse.x / width))
          if (root.player) root.player.volume = root.volumeFraction
        }
        onPressed: function(mouse) { root.holdingVolume = true; apply(mouse) }
        onPositionChanged: function(mouse) { if (pressed) apply(mouse) }
        onReleased: root.holdingVolume = false
        onCanceled: root.holdingVolume = false
      }
    }

    // ---- Mono / stereo ---------------------------------------------------
    // MPRIS says nothing about channel count, so these light with playback
    // rather than pretending to know the stream format.
    SkinSprite {
      dir: root.skinDir
      sheet: "monoster.bmp"
      zoom: root.zoom
      rect: S.MONOSTER.monoOff
      x: S.MONOSTER.monoAt[0] * root.zoom
      y: S.MONOSTER.monoAt[1] * root.zoom
    }

    SkinSprite {
      dir: root.skinDir
      sheet: "monoster.bmp"
      zoom: root.zoom
      rect: root.playing ? S.MONOSTER.stereoOn : S.MONOSTER.stereoOff
      x: S.MONOSTER.stereoAt[0] * root.zoom
      y: S.MONOSTER.stereoAt[1] * root.zoom
    }

    // ---- Shuffle / repeat ------------------------------------------------
    SkinSprite {
      dir: root.skinDir
      sheet: "shufrep.bmp"
      zoom: root.zoom
      rect: (root.player && root.player.shuffle) ? S.SHUFREP.shuffleOn : S.SHUFREP.shuffleOff
      x: S.SHUFREP.shuffleAt[0] * root.zoom
      y: S.SHUFREP.shuffleAt[1] * root.zoom

      MouseArea {
        anchors.fill: parent
        onClicked: if (root.player && root.player.shuffleSupported)
          root.player.shuffle = !root.player.shuffle
      }
    }

    SkinSprite {
      dir: root.skinDir
      sheet: "shufrep.bmp"
      zoom: root.zoom
      rect: (root.player && root.player.loopState !== MprisLoopState.None)
        ? S.SHUFREP.repeatOn : S.SHUFREP.repeatOff
      x: S.SHUFREP.repeatAt[0] * root.zoom
      y: S.SHUFREP.repeatAt[1] * root.zoom

      MouseArea {
        anchors.fill: parent
        onClicked: root.cycleLoop()
      }
    }

    // ---- Playlist toggle ---------------------------------------------------
    SkinSprite {
      dir: root.skinDir
      sheet: "shufrep.bmp"
      zoom: root.zoom
      rect: playlist_.shown ? S.SHUFREP.playlistOn : S.SHUFREP.playlistOff
      x: S.SHUFREP.playlistAt[0] * root.zoom
      y: S.SHUFREP.playlistAt[1] * root.zoom

      MouseArea {
        anchors.fill: parent
        onClicked: root.togglePlaylist()
      }
    }

    // ---- Transport -------------------------------------------------------
    Repeater {
      model: S.BUTTONS

      SkinSprite {
        required property var modelData
        dir: root.skinDir
        sheet: "cbuttons.bmp"
        zoom: root.zoom
        rect: button.pressed ? modelData.press : modelData.rect
        x: modelData.at[0] * root.zoom
        y: modelData.at[1] * root.zoom

        MouseArea {
          id: button
          anchors.fill: parent
          onClicked: {
            if (modelData.id === "play" && root.playing) root.transport("pause")
            else root.transport(modelData.id)
          }
        }
      }
    }
    }

    // ------------------------------------------------------------------
    // The TUI face. Same 275x116 footprint and the same wiring as the
    // sprite skin -- transport, seek, marquee, analyzer, PL -- but drawn
    // the way cliamp draws itself: lines of monospace text in theme colors.
    // No boxes, no buttons: a heavy-line seek bar, a block-character
    // spectrum, glyph transport, bracketed toggles.
    Item {
      id: tui
      visible: root.tuiMode
      width: S.MAIN_WIDTH * root.zoom
      height: S.MAIN_HEIGHT * root.zoom

      readonly property real fs: 7 * root.zoom
      readonly property real pad: 6 * root.zoom
      readonly property real pitch: 12 * root.zoom
      readonly property real innerW: width - 2 * pad
      readonly property color green: root.tuiColors.green || "#859900"
      readonly property color yellow: root.tuiColors.yellow || "#b58900"
      readonly property color red: root.tuiColors.red || "#dc322f"
      readonly property color dim: Qt.alpha(root.tFg, 0.55)

      // Everything is laid out in character cells, like a terminal.
      Text {
        id: cell
        visible: false
        text: "━"
        font.family: "monospace"
        font.pixelSize: tui.fs
      }
      readonly property real cellW: cell.implicitWidth > 0 ? cell.implicitWidth : fs * 0.6
      readonly property int cols: Math.max(20, Math.floor(innerW / cellW))

      readonly property bool paused: root.player
        && root.player.playbackState === MprisPlaybackState.Paused
      readonly property bool streaming: root.playing && root.duration <= 0
      readonly property var volBar: S.tuiVolumeBar(root.volumeLevel, 10)
      readonly property var spectrum: S.tuiSpectrum(root.bands, cols, 3)

      Rectangle {
        anchors.fill: parent
        color: root.tBg
      }

      // Row 0: title, mode label, close. The whole row drags the window.
      Item {
        id: tuiTitle
        x: tui.pad; y: tui.pad
        width: tui.innerW; height: tui.pitch

        MouseArea {
          anchors.fill: parent
          anchors.rightMargin: 3 * tui.cellW
          onPressed: if (root.Window.window) root.Window.window.startSystemMove()
        }

        Text {
          text: "O M A A M P"
          color: root.tAcc
          font.family: "monospace"
          font.pixelSize: tui.fs
          font.bold: true
        }

        Text {
          anchors.right: closeX.left
          anchors.rightMargin: 2 * tui.cellW
          width: Math.min(implicitWidth, tui.innerW - 16 * tui.cellW)
          text: "[" + root.skinName + "]"
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: tui.dim
          font.family: "monospace"
          font.pixelSize: tui.fs
        }

        Text {
          id: closeX
          anchors.right: parent.right
          text: "✕"
          color: closeArea.containsMouse ? root.tHi : tui.dim
          font.family: "monospace"
          font.pixelSize: tui.fs

          MouseArea {
            id: closeArea
            anchors.fill: parent
            anchors.margins: -3 * root.zoom
            hoverEnabled: true
            onClicked: root.visible = false
          }
        }
      }

      // Row 1: ♫ track (the marquee, exactly as cliamp scrolls its title).
      Text {
        x: tui.pad; y: tui.pad + tui.pitch
        width: tui.innerW
        text: "♫ " + root.marqueeText
        textFormat: Text.PlainText
        clip: true
        color: root.tAcc
        font.family: "monospace"
        font.pixelSize: tui.fs
      }

      // Row 2: elapsed / total on the left, play state on the right.
      Item {
        x: tui.pad; y: tui.pad + 2 * tui.pitch
        width: tui.innerW; height: tui.pitch

        Text {
          text: S.tuiTime(root.seeking ? root.seekFraction * root.duration : root.elapsed)
            + " / " + (root.duration > 0 ? S.tuiTime(root.duration)
                       : (root.playing ? "LIVE" : "00:00"))
          color: root.tHi
          font.family: "monospace"
          font.pixelSize: tui.fs
        }

        Row {
          anchors.right: parent.right
          spacing: 0
          readonly property bool lit: root.playing || tui.paused || root.seeking

          Text {
            text: root.seeking ? "⟳" : tui.paused ? "⏸" : tui.streaming ? "●" : root.playing ? "▶" : "■"
            color: parent.lit ? tui.green : tui.dim
            font.family: tui.paused ? "Noto Sans Symbols 2" : "monospace"
            font.pixelSize: tui.fs
            font.bold: parent.lit
          }
          Text {
            text: root.seeking ? " Seeking..." : tui.paused ? " Paused"
                : tui.streaming ? " Streaming" : root.playing ? " Playing" : " Stopped"
            color: parent.lit ? tui.green : tui.dim
            font.family: "monospace"
            font.pixelSize: tui.fs
            font.bold: parent.lit
          }
        }
      }

      // Rows 3-5: the spectrum, cliamp's fractional blocks -- green at the
      // base, yellow, red at the peaks, from the theme's own signal colors.
      Column {
        id: tuiSpec
        x: tui.pad; y: tui.pad + 3 * tui.pitch
        spacing: 0

        Repeater {
          model: 3

          Text {
            required property int index
            text: tui.spectrum.length > index ? tui.spectrum[index] : ""
            color: index === 0 ? tui.red : index === 1 ? tui.yellow : tui.green
            font.family: "monospace"
            font.pixelSize: tui.fs
          }
        }
      }

      // Row 6: the seek bar. cliamp draws a run of ━ cells; in a terminal
      // those touch, but as laid-out text they leave hairline gaps, so the
      // line itself is drawn as a stroke of exactly ━'s weight over the
      // same cell grid. The STREAMING label sits over it, as in cliamp.
      Item {
        id: tuiSeek
        x: tui.pad; y: tuiSpec.y + tuiSpec.height + 4 * root.zoom
        width: tui.innerW; height: tui.pitch

        readonly property real barW: tui.cols * tui.cellW
        readonly property real stroke: Math.max(1, Math.round(tui.fs * 0.18))

        Rectangle {
          y: (cell.implicitHeight - tuiSeek.stroke) / 2
          width: tuiSeek.barW
          height: tuiSeek.stroke
          color: root.duration > 0 ? tui.dim : Qt.alpha(root.tFg, 0.3)
        }

        Rectangle {
          y: (cell.implicitHeight - tuiSeek.stroke) / 2
          width: tui.streaming ? tuiSeek.barW : tuiSeek.barW * root.progress
          height: tuiSeek.stroke
          color: root.tAcc
        }

        Text {
          visible: tui.streaming
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.horizontalCenterOffset: (tuiSeek.barW - tui.innerW) / 2
          text: " STREAMING "
          color: root.tAcc
          font.family: "monospace"
          font.pixelSize: tui.fs

          Rectangle { anchors.fill: parent; z: -1; color: root.tBg }
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.duration > 0
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onPressed: function(m) { root.seeking = true; root.seekFraction = Math.max(0, Math.min(1, m.x / tuiSeek.barW)) }
          onPositionChanged: function(m) { if (pressed) root.seekFraction = Math.max(0, Math.min(1, m.x / tuiSeek.barW)) }
          onReleased: root.commitSeek()
          onCanceled: root.seeking = false
        }
      }

      // Row 7: transport glyphs on the left, VOL bar on the right.
      Item {
        x: tui.pad; y: tuiSeek.y + tui.pitch
        width: tui.innerW; height: tui.pitch

        Row {
          spacing: 2 * tui.cellW

          Repeater {
            model: [
              { glyph: "⏮", action: "previous" },
              { glyph: "▶", action: "play" },
              { glyph: "⏸", action: "pause" },
              { glyph: "■", action: "stop" },
              { glyph: "⏭", action: "next" }
            ]

            Text {
              required property var modelData
              text: modelData.glyph
              color: tArea.containsMouse ? root.tHi : root.tFg
              // The transport symbols only exist in symbol and emoji fonts
              // here; name the outline face so Qt never picks the emoji one.
              font.family: "Noto Sans Symbols 2"
              font.pixelSize: tui.fs

              MouseArea {
                id: tArea
                anchors.fill: parent
                anchors.margins: -2 * root.zoom
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.transport(modelData.action)
              }
            }
          }
        }

        Row {
          anchors.right: parent.right
          spacing: 0

          Text {
            text: "VOL "
            color: root.tHi
            font.family: "monospace"
            font.pixelSize: tui.fs
            font.bold: true
          }

          Item {
            id: volRow
            width: volCells.width
            height: volCells.height

            Row {
              id: volCells
              spacing: 0

              Text {
                text: tui.volBar.fill
                color: tui.green
                font.family: "monospace"
                font.pixelSize: tui.fs
              }
              Text {
                text: tui.volBar.rest
                color: tui.dim
                font.family: "monospace"
                font.pixelSize: tui.fs
              }
            }

            MouseArea {
              anchors.fill: parent
              anchors.margins: -2 * root.zoom
              cursorShape: Qt.PointingHandCursor
              function set(m) {
                var v = Math.max(0, Math.min(1, (m.x - 2 * root.zoom) / (10 * tui.cellW)))
                root.volumeFraction = v
                if (root.player && root.player.volumeSupported) root.player.volume = v
              }
              onPressed: function(m) { root.holdingVolume = true; set(m) }
              onPositionChanged: function(m) { if (pressed) set(m) }
              onReleased: root.holdingVolume = false
              onCanceled: root.holdingVolume = false
            }
          }

          Text {
            text: " " + Math.round(root.volumeLevel * 100) + "%"
            color: tui.dim
            font.family: "monospace"
            font.pixelSize: tui.fs
          }
        }
      }

      // Row 8: cliamp's bracketed toggles, PL at the right.

      Item {
        x: tui.pad; y: tuiSeek.y + 2 * tui.pitch
        width: tui.innerW; height: tui.pitch

        Row {
          spacing: tui.cellW

          TuiToggle {
            label: "Shuffle"
            on: root.player && root.player.shuffle === true
            onClicked: if (root.player && root.player.shuffleSupported) root.player.shuffle = !root.player.shuffle
          }

          TuiToggle {
            label: "Repeat: " + (!root.player || root.player.loopState === MprisLoopState.None ? "Off"
                              : root.player.loopState === MprisLoopState.Track ? "One" : "All")
            on: root.player && root.player.loopState !== MprisLoopState.None
            onClicked: root.cycleLoop()
          }
        }

        TuiToggle {
          anchors.right: parent.right
          label: "PL"
          on: playlist_.shown
          onClicked: root.togglePlaylist()
        }
      }
    }

    PlaylistPane {
      id: playlist_
      skinDir: root.skinDir
      helper: Quickshell.env("OMAAMP_HELPER") || ""
      zoom: root.zoom
      windowActive: root.active === true
      tui: root.tuiMode ? root.tuiColors : null
      width: S.MAIN_WIDTH * root.zoom
      // In a tile, fill whatever space remains under the main window; when
      // floating there is exactly the classic one-main-height pane, because
      // togglePlaylist() resizes the window by that much.
      height: Math.max(S.MAIN_HEIGHT * root.zoom,
                       root.height - S.MAIN_HEIGHT * root.zoom)
    }
  }

  // scripting surface: quickshell ipc -p <player dir> call omaamp playlist
  IpcHandler {
    target: "omaamp"

    function playlist(): void { root.togglePlaylist() }
    function show(): void { root.visible = true }
    function quit(): void { Qt.quit() }
  }

  // One of cliamp's [Toggle] pills: dim brackets, accent label; the
  // whole thing accent-bold when on. Used by the TUI face's bottom row.
  component TuiToggle: Item {
    id: toggle
    property string label: ""
    property bool on: false
    signal clicked()
    width: toggleRow.width
    height: toggleRow.height

    Row {
      id: toggleRow
      spacing: 0

      Text {
        text: "["
        color: toggle.on ? root.tAcc : tui.dim
        font.family: "monospace"; font.pixelSize: tui.fs
        font.bold: toggle.on
      }
      Text {
        text: toggle.label
        color: toggleArea.containsMouse ? root.tHi : root.tAcc
        font.family: "monospace"; font.pixelSize: tui.fs
        font.bold: toggle.on
      }
      Text {
        text: "]"
        color: toggle.on ? root.tAcc : tui.dim
        font.family: "monospace"; font.pixelSize: tui.fs
        font.bold: toggle.on
      }
    }

    MouseArea {
      id: toggleArea
      anchors.fill: parent
      anchors.margins: -2 * root.zoom
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: toggle.clicked()
    }
  }

}
