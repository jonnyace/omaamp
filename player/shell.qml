import Quickshell

// Standalone entry point: OmaAmp as its own application.
//
// This directory is a self-contained Quickshell config -- Player.qml and its
// sprite tables sit next to this file rather than being imported from the
// repository root, because Quickshell refuses module paths outside the config
// folder, and the plugin's QML next door depends on omarchy-shell modules that
// do not exist in a standalone process.
//
// Separate from omarchy-shell on purpose: the player decodes bitmaps out of
// arbitrary archives in a 102,000-skin corpus, ~0.4% of which have corrupt
// headers. Run as a shell plugin, a decoder fault would take the bar,
// notifications and the lock screen with it. Here it closes a music player.
ShellRoot {
  Player {
    visible: true
    zoom: Number(Quickshell.env("OMAAMP_ZOOM") || 2)
    // The skin itself comes from ~/.local/state/omaamp/current.json, which
    // the Player watches -- the same channel the bar plugin uses to restyle a
    // running instance, so launch and live-swap are one code path.

    // Closing the window quits the app; there is no panel to hide back into.
    onVisibleChanged: if (!visible) Qt.quit()
  }
}
