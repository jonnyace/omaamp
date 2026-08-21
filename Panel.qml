import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Three views over one job: get a Winamp skin's palette onto cliamp.
//
//   Browse  the Skin Museum, as the museum's own screenshots of the Winamp
//           window -- a wall of hex swatches would be unrecognizable, and
//           recognizing the skin is the whole point
//   Tune    the seven colors cliamp actually reads, live
//   Mine    what is installed, including the Omarchy-synced theme
//
// All real work happens in `bin/skinner`, a short-lived subprocess per action.
// Nothing here parses a .wsz or talks to the network: this shell process is
// shared with the bar and every other panel, so blocking it would stutter the
// whole desktop.
Panel {
  id: root
  moduleName: "io.github.jonnyace.omaamp"
  ipcTarget: "omaamp"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Absolute path to the helper, injected by BarWidget.qml.
  property string helper: ""

  property int tab: 0
  readonly property var tabs: ["Player", "Browse", "Tune", "My themes"]

  property var results: []
  property var themes: []
  // Named `colors`, not `palette`: QQuickItem already has a `palette`
  // property, and shadowing it is a silent trap.
  property var colors: ({})
  // Snapshot taken when a palette loads, so Reset can walk back edits that
  // have not been saved yet.
  property var pristineColors: ({})
  property string paletteName: ""
  property string appliedTheme: ""
  property string currentMd5: ""
  // Set once make-theme finishes: the generated Omarchy theme, ready to apply.
  property string omarchyTheme: ""
  property string query: ""
  property int offset: 0
  property string status: ""
  property bool busy: false
  property bool loadedOnce: false
  // Set while a hex field holds focus, so the panel's single-letter shortcuts
  // do not consume what is being typed into it.
  property bool editingHex: false

  readonly property int pageSize: Math.max(6, Number(setting("pageSize", 30)))

  // ---- Mini player (tab 0) ---------------------------------------------
  // The same cliamp-first MPRIS selection the standalone app uses, so the
  // dropdown and the full player always describe the same playback.
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var nowPlayer: {
    var i
    for (i = 0; i < mprisPlayers.length; i++)
      if (mprisPlayers[i] && String(mprisPlayers[i].dbusName || "").indexOf("cliamp") !== -1) return mprisPlayers[i]
    for (i = 0; i < mprisPlayers.length; i++)
      if (mprisPlayers[i] && mprisPlayers[i].isPlaying) return mprisPlayers[i]
    return mprisPlayers.length ? mprisPlayers[0] : null
  }
  readonly property bool nowPlaying: nowPlayer ? nowPlayer.isPlaying === true : false
  readonly property string nowLabel: {
    if (!nowPlayer) return "Nothing playing"
    var t = String(nowPlayer.trackTitle || "")
    var a = String(nowPlayer.trackArtist || "")
    return a.length ? a + " — " + t : (t.length ? t : String(nowPlayer.identity || ""))
  }

  function miniTransport(action) {
    var pl = nowPlayer
    if (!pl) return
    if (action === "toggle") {
      if (pl.canTogglePlaying) pl.togglePlaying()
      else if (pl.isPlaying && pl.canPause) pl.pause()
      else if (pl.canPlay) pl.play()
    } else if (action === "next" && pl.canGoNext) pl.next()
    else if (action === "previous" && pl.canGoPrevious) pl.previous()
    else if (action === "stop") pl.stop()
  }

  // ---- Helper plumbing -------------------------------------------------

  // Two processes, not one queue: a browse fetch takes seconds over the
  // network while applying a theme is near-instant, and sharing a single slot
  // would make every click wait behind whatever the grid is loading.
  function browseRun(args) {
    if (!helper || listProc.running) return
    busy = true
    listProc.command = [helper].concat(args)
    listProc.running = true
  }

  function themeRun(args) {
    if (!helper || themeProc.running) return
    themeProc.command = [helper].concat(args)
    themeProc.running = true
  }

  // With no query, Browse shows the museum's own top ranking from the local
  // cache -- instant and offline. Typing anything searches all 102k live.
  function search() {
    offset = 0
    results = []
    browseRun(query.length ? ["search", query, "--limit", String(pageSize)]
                           : ["featured", "--limit", String(pageSize)])
  }

  function loadMore() {
    if (busy || results.length === 0) return
    offset += pageSize
    var args = query.length ? ["search", query] : ["featured"]
    browseRun(args.concat(["--limit", String(pageSize), "--offset", String(offset)]))
  }

  function refreshThemes() { browseRun(["themes"]) }

  // Selecting a skin is one action end to end: unpack sprites, write the
  // cliamp theme, update the state file the player watches. A running player
  // re-dresses itself on the spot; launching later picks the same skin up.
  function useSkin(md5, name) {
    status = "Wearing " + name + "…"
    themeRun(["use", md5])
  }

  function launchPlayer() {
    if (bar) bar.run(helper.replace(/skinner$/, "omaamp"))
  }

  function applyTheme(name) { themeRun(["apply", name]) }

  // Picking a theme wears it: the flat TUI player face plus the cliamp
  // theme, in one action. Museum skins from Browse switch back to bitmaps.
  function useTheme(name) {
    status = "Wearing " + name + "…"
    themeRun(["use-theme", name])
  }

  function reapplyCurrent() {
    if (appliedTheme.length) applyTheme(appliedTheme)
  }

  function savePalette() {
    if (!paletteName.length) return
    themeRun(["save", paletteName, JSON.stringify(colors)])
  }

  function removeTheme(name) { themeRun(["remove", name]) }

  function makeOmarchyTheme() {
    if (!currentMd5.length) { status = "Pick a skin first"; return }
    status = "Building Omarchy theme…"
    themeRun(["make-theme", currentMd5])
  }

  function applyOmarchyTheme() {
    if (bar && omarchyTheme.length) bar.run("omarchy theme set " + omarchyTheme)
  }

  function syncOmarchy() {
    status = "Reading the current Omarchy theme…"
    themeRun(["sync"])
  }

  function setSlot(slot, value) {
    var next = Model.withSlot(colors, slot, value)
    if (!next) return
    colors = next
  }

  function onListResult(data) {
    busy = false
    if (data.error) { status = data.error; return }
    if (data.themes) { themes = data.themes; return }
    if (data.skins) {
      // Append rather than replace so "load more" extends the wall instead of
      // scrolling the user back to the top.
      results = offset > 0 ? results.concat(data.skins) : data.skins
      status = results.length ? "" : "No skins matched that."
    }
  }

  function onThemeResult(data) {
    if (data.error) { status = data.error; return }
    if (data.removed) { status = data.removed + " removed"; refreshThemes(); return }
    if (data.applied) { appliedTheme = data.applied; status = "Using " + data.applied; return }
    if (data.worn) {
      appliedTheme = data.worn
      status = "Wearing " + data.worn
      colors = data.colors || ({})
      pristineColors = JSON.parse(JSON.stringify(colors))
      paletteName = data.worn
      refreshThemes()
      return
    }
    if (data.md5 && !data.colors && !data.apply) {
      // `current` on open: remember the skin without disturbing the palette.
      currentMd5 = data.md5
      if (!paletteName.length && data.theme) paletteName = data.theme
      return
    }
    if (data.apply) {
      // make-theme finished: surface the apply step instead of auto-switching
      // the entire desktop out from under the user.
      omarchyTheme = data.theme
      status = "Omarchy theme \"" + data.theme + "\" created"
      return
    }
    if (data.theme) {
      colors = data.colors || ({})
      pristineColors = JSON.parse(JSON.stringify(colors))
      paletteName = data.theme
      if (data.md5) currentMd5 = data.md5
      omarchyTheme = ""
      status = Model.repairSummary(data)
      applyTheme(data.theme)
      refreshThemes()
    }
  }

  Process {
    id: listProc
    running: false
    command: []
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function(exitCode) { root.onListResult(Model.parseResult(listOut.text)) }
  }

  Process {
    id: themeProc
    running: false
    command: []
    stdout: StdioCollector { id: themeOut; waitForEnd: true }
    onExited: function(exitCode) { root.onThemeResult(Model.parseResult(themeOut.text)) }
  }

  // Load lazily: 30 screenshot downloads on shell startup would be rude for a
  // panel the user may never open.
  onOpenedChanged: {
    if (!opened || loadedOnce) return
    loadedOnce = true
    search()
    refreshThemes()
    themeRun(["current"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // The Player tab is a compact now-playing card, Wi-Fi-panel sized; the
    // skin-browsing tabs need room for the screenshot wall and keep the
    // large footprint.
    contentWidth: panel.fittedContentWidth(Style.space(root.tab === 0 ? 380 : 640))
    contentHeight: panel.fittedContentHeight(Style.space(root.tab === 0 ? 285 : 560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The search field and the hex fields swallow their own keys; the panel
      // shortcuts would otherwise eat every letter the user typed.
      blocked: searchField.activeFocus || root.editingHex

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.tab = Model.wrap(root.tab + dx, root.tabs.length)
      }
      onTextKey: function(t) {
        if (t === "/") searchField.forceActiveFocus()
        else if (t === "r" || t === "R") root.search()
      }

      Column {
        id: layout
        anchors.fill: parent
        spacing: Style.space(8)

        // ---- Tabs -------------------------------------------------------
        Item {
          width: parent.width
          height: tabRow.implicitHeight

          Row {
            id: tabRow
            spacing: Style.spacing.controlGap

            Repeater {
              model: root.tabs

              Button {
                required property string modelData
                required property int index
                text: modelData
                selected: root.tab === index
                bordered: true
                onClicked: {
                  root.tab = index
                  if (index === 3) root.refreshThemes()
                }
              }
            }
          }

          // The player is its own app; from here it is one click away.
          Button {
            anchors.right: parent.right
            text: "Launch player"
            iconText: "󰐊"
            bordered: true
            tooltipText: "Open the OmaAmp window (middle-click the bar icon does the same)"
            onClicked: root.launchPlayer()
          }
        }

        PanelSeparator { width: parent.width }

        // ---- Search (Browse only) ---------------------------------------
        Row {
          width: parent.width
          spacing: Style.spacing.controlGap
          visible: root.tab === 1

          TextField {
            id: searchField
            width: parent.width - refreshButton.width - Style.spacing.controlGap
            placeholderText: "Search 102,000 Winamp skins…"
            onTextChanged: root.query = text
            onAccepted: root.search()
          }

          PanelActionButton {
            id: refreshButton
            iconText: "󰕐"
            tooltipText: "Search"
            onClicked: root.search()
          }
        }

        // ---- Content ----------------------------------------------------
        Item {
          width: parent.width
          height: Math.max(Style.space(120), layout.height - y)

          // Player: a mini music player, Wi-Fi/Agents-panel shaped -- the
          // dropdown is useful before you ever open the full window.
          Column {
            anchors.fill: parent
            visible: root.tab === 0
            spacing: Style.spacing.lg

            PanelSectionHeader { text: "Now playing" }

            Text {
              width: parent.width
              text: root.nowLabel
              textFormat: Text.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: root.nowPlayer !== null
              text: (root.nowPlaying ? "Playing" : "Paused")
                + (root.nowPlayer && root.nowPlayer.identity ? " · " + root.nowPlayer.identity : "")
              textFormat: Text.PlainText
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.spacing.controlGap

              PanelActionButton {
                iconText: "󰒮"
                tooltipText: "Previous"
                onClicked: root.miniTransport("previous")
              }
              PanelActionButton {
                iconText: root.nowPlaying ? "󰏤" : "󰐊"
                tooltipText: root.nowPlaying ? "Pause" : "Play"
                onClicked: root.miniTransport("toggle")
              }
              PanelActionButton {
                iconText: "󰓛"
                tooltipText: "Stop"
                onClicked: root.miniTransport("stop")
              }
              PanelActionButton {
                iconText: "󰒭"
                tooltipText: "Next"
                onClicked: root.miniTransport("next")
              }
            }

            PanelSeparator { width: parent.width }

            PanelSectionHeader { text: "Volume" }

            PanelSlider {
              width: parent.width
              bar: root.bar
              visible: root.nowPlayer !== null && root.nowPlayer.volumeSupported === true
              value: root.nowPlayer && root.nowPlayer.volumeSupported
                ? Math.max(0, Math.min(1, root.nowPlayer.volume)) : 0
              onMoved: function(v) { if (root.nowPlayer) root.nowPlayer.volume = v }
            }

            PanelSeparator { width: parent.width }

            Row {
              spacing: Style.spacing.controlGap

              Button {
                text: "Open full player"
                bordered: true
                onClicked: root.launchPlayer()
              }

              Button {
                text: "Browse skins"
                bordered: true
                onClicked: root.tab = 1
              }
            }
          }

          // Browse: a wall of the museum's own Winamp-window screenshots.
          Flickable {
            anchors.fill: parent
            visible: root.tab === 1
            clip: true
            contentWidth: width
            contentHeight: grid.height
            boundsBehavior: Flickable.StopAtBounds

            onContentYChanged: {
              if (contentHeight - (contentY + height) < Style.space(120)) root.loadMore()
            }

            Grid {
              id: grid
              width: parent.width
              columns: Math.max(2, Math.floor(width / Style.space(124)))
              spacing: Style.spacing.md

              Repeater {
                model: root.results

                Item {
                  required property var modelData
                  width: Style.space(116)
                  height: Style.space(160)

                  Column {
                    anchors.fill: parent
                    spacing: Style.spacing.xs

                    Rectangle {
                      width: parent.width
                      height: Style.space(132)
                      color: Util.alpha(Color.popups.text, 0.05)
                      border.width: skinMouse.containsMouse ? Math.max(1, Style.space(2)) : 1
                      border.color: skinMouse.containsMouse
                        ? Color.popups.border
                        : Util.alpha(Color.popups.text, 0.15)

                      Image {
                        anchors.fill: parent
                        anchors.margins: Style.spacing.xxs
                        source: modelData.screenshot ? Util.fileUrl(modelData.screenshot) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: false  // these are 275x348 pixel art; keep the pixels
                      }

                      MouseArea {
                        id: skinMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.useSkin(modelData.md5, modelData.name)
                      }
                    }

                    Text {
                      width: parent.width
                      text: modelData.name
                      // Museum-controlled string: PlainText, never AutoText,
                      // or a skin named like markup renders as markup.
                      textFormat: Text.PlainText
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }
                }
              }
            }
          }

          // Tune: the seven values cliamp reads, each editable as hex.
          Flickable {
            anchors.fill: parent
            visible: root.tab === 2
            clip: true
            contentWidth: width
            contentHeight: tuneColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: tuneColumn
              width: parent.width
              spacing: Style.spacing.md

              PanelSectionHeader {
                text: root.paletteName.length ? root.paletteName : "No theme loaded"
              }

              // The whole palette at a glance; edits show here immediately,
              // before anything is saved.
              Row {
                visible: root.paletteName.length > 0
                spacing: 0

                Repeater {
                  model: Model.SLOTS

                  Rectangle {
                    required property string modelData
                    width: Style.space(34)
                    height: Style.space(18)
                    color: root.colors[modelData] || "transparent"
                    border.width: 1
                    border.color: Util.alpha(Color.popups.text, 0.2)
                  }
                }
              }

              Text {
                width: parent.width
                visible: !root.paletteName.length
                text: "Pick a skin in Browse, or sync the current Omarchy theme, then tune it here."
                color: Util.alpha(Color.popups.text, 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: root.paletteName.length ? Model.SLOTS : []

                Row {
                  required property string modelData
                  width: tuneColumn.width
                  spacing: Style.spacing.controlGap

                  Rectangle {
                    width: Style.space(34)
                    height: Style.spacing.controlHeight
                    color: root.colors[modelData] || "transparent"
                    border.width: 1
                    border.color: Util.alpha(Color.popups.text, 0.25)
                  }

                  Text {
                    width: Style.space(74)
                    text: modelData
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    verticalAlignment: Text.AlignVCenter
                    height: Style.spacing.controlHeight
                  }

                  TextField {
                    width: Style.space(110)
                    text: root.colors[modelData] || ""
                    // Urgent text the moment the field stops being a color,
                    // instead of silently ignoring the edit on commit.
                    foreground: text.length === 0 || Model.isHex(text)
                      ? Color.popups.text : Color.urgent
                    onActiveFocusChanged: root.editingHex = activeFocus
                    onAccepted: root.setSlot(modelData, text)
                    onEditingFinished: root.setSlot(modelData, text)
                  }

                  PanelActionButton {
                    iconText: "−"
                    tooltipText: "Darker"
                    onClicked: root.setSlot(modelData, Model.nudge(root.colors[modelData], -0.08))
                  }

                  PanelActionButton {
                    iconText: "+"
                    tooltipText: "Lighter"
                    onClicked: root.setSlot(modelData, Model.nudge(root.colors[modelData], 0.08))
                  }

                  Text {
                    text: Model.slotPurpose(modelData)
                    color: Util.alpha(Color.popups.text, 0.6)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                    height: Style.spacing.controlHeight
                  }
                }
              }

              Row {
                visible: root.paletteName.length > 0
                spacing: Style.spacing.controlGap

                Button {
                  text: "Save and apply"
                  bordered: true
                  onClicked: root.savePalette()
                }

                Button {
                  text: "Reset"
                  bordered: true
                  tooltipText: "Back to the palette as last saved"
                  onClicked: root.colors = JSON.parse(JSON.stringify(root.pristineColors))
                }

                // The deep end: colors.toml + a rendered wallpaper under
                // ~/.config/omarchy/themes/, which Omarchy's template engine
                // fans out to every themed app on the system.
                Button {
                  text: "Make Omarchy theme"
                  bordered: true
                  tooltipText: "Turn this skin into a full desktop theme"
                  onClicked: root.makeOmarchyTheme()
                }

                Button {
                  visible: root.omarchyTheme.length > 0
                  text: "Apply to desktop"
                  bordered: true
                  onClicked: root.applyOmarchyTheme()
                }
              }
            }
          }

          // Mine: what is installed, ours marked.
          Flickable {
            anchors.fill: parent
            visible: root.tab === 3
            clip: true
            contentWidth: width
            contentHeight: mineColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: mineColumn
              width: parent.width
              spacing: Style.spacing.xs

              Row {
                width: parent.width
                spacing: Style.spacing.controlGap
                bottomPadding: Style.spacing.sm

                Text {
                  width: mineColumn.width
                  text: "Picking a theme dresses the flat TUI player and cliamp together. Browse a skin for bitmap art instead."
                  color: Util.alpha(Color.popups.text, 0.6)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Button {
                  id: syncButton
                  text: "Sync to Omarchy theme"
                  bordered: true
                  onClicked: root.syncOmarchy()
                }
              }

              Repeater {
                model: root.themes

                Rectangle {
                  required property var modelData
                  width: mineColumn.width
                  height: Style.spacing.popupRowHeight
                  color: rowMouse.containsMouse
                    ? Util.alpha(Color.popups.text, 0.08)
                    : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.sm
                    anchors.rightMargin: Style.spacing.sm
                    spacing: Style.spacing.controlGap

                    // A strip of the theme's own colors, so the list reads as
                    // themes rather than as a column of filenames.
                    Row {
                      id: swatches
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0
                      visible: !!modelData.colors
                      // Captured here because the inner Repeater's delegate
                      // rebinds `modelData` to the slot name.
                      readonly property var colors: modelData.colors || ({})

                      Repeater {
                        model: Model.SLOTS

                        Rectangle {
                          required property string modelData
                          width: Style.space(9)
                          height: Style.space(16)
                          color: swatches.colors[modelData] || "transparent"
                        }
                      }
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                      textFormat: Text.PlainText
                      color: modelData.name === root.appliedTheme ? Color.accent : Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: !!modelData.converted && !!modelData.source
                      text: modelData.source || ""
                      textFormat: Text.PlainText
                      color: Util.alpha(Color.popups.text, 0.5)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.useTheme(modelData.name)
                  }

                  PanelActionButton {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!modelData.converted && rowMouse.containsMouse
                    iconText: "󰅖"
                    tooltipText: "Remove"
                    onClicked: root.removeTheme(modelData.name)
                  }
                }
              }
            }
          }
        }

        // ---- Status -----------------------------------------------------
        Text {
          width: parent.width
          visible: root.status.length > 0 || root.busy
          // Status frequently embeds museum-controlled names.
          textFormat: Text.PlainText
          text: root.busy ? "Loading…" : root.status
          color: Util.alpha(Color.popups.text, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
