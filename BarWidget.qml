import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry point for OmaAmp.
//
// Left click opens the skin browser panel; middle click launches (or focuses)
// the player app itself. The app is a separate process on purpose -- see
// player/shell.qml -- so "launch" here is just running the command.
//
// The panel itself lives in Panel.qml; everything here is the contract the bar
// needs to treat this widget as a panel host (open/close/opened, plus the
// popout-switch forwarding that lets clicking another bar icon hand over).
BarWidget {
  id: root
  moduleName: "io.github.jw.omaamp"

  // Resolved once and handed to the panel: the shell's working directory is
  // not the plugin directory, so every helper invocation needs an absolute
  // path built from this file's own location.
  readonly property string helper: Qt.resolvedUrl("bin/skinner").toString().replace("file://", "")

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function launchPlayer() {
    if (root.bar) root.bar.run(root.helper.replace(/skinner$/, "omaamp"))
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("helper" in target) target.helper = root.helper
  }

  readonly property real openPanelIndicatorWidth: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property real openPanelIndicatorHeight: openPanelIndicatorWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      // The bar assigns `bar` and `settings` across more than one binding
      // pass; a second inject after the current one settles keeps the panel
      // from coming up with a null bar on first mount.
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omaamp"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function launchPlayer(): void { root.launchPlayer() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Palette glyph: this is a theme picker that happens to source its
    // palettes from Winamp, and a music note would collide with the media
    // widgets already in the bar.
    text: "󰸌"
    tooltipText: "OmaAmp — Winamp skins"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.launchPlayer()
      else root.togglePanel()
    }
  }
}
