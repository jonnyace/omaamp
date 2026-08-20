# OmaAmp

Winamp, on your Omarchy desktop, wearing any of the ~102,000 classic skins in
the [Winamp Skin Museum](https://skins.webamp.org/) — driving whatever is
actually playing.

![OmaAmp wearing three museum skins](docs/hero.png)

*Two museum skins with a live spectrum analyzer, and the docked playlist
wearing the skin's own `pledit.bmp` chrome.*

## What you get

- **The player** — the Winamp 2.x main window as a real desktop app,
  rendered sprite-accurately from any museum skin: LCD digits, bitmap-font
  marquee, seek and volume sliders, shuffle/repeat, and a spectrum analyzer
  colored by the skin's own `viscolor.txt`. Hit **PL** and the playlist
  unfolds beneath it in the skin's `pledit.bmp` chrome, exactly like the
  original's snapped-on playlist — pick a stream, load a TOML playlist, or
  paste any file path / stream URL.
- **The bar widget** — browse the museum's curated top 200 offline or search
  all 102k live, as the museum's own screenshots. One click dresses the
  player *and* writes a matching [cliamp](https://github.com/bjarneo/cliamp)
  terminal theme.
- **The theme maker** — turn any skin into a complete Omarchy theme
  (`colors.toml` + a rendered wallpaper), which Omarchy's template engine
  fans out to your terminal, editor, browser and bar. One Winamp skin themes
  the whole desktop.
- **cliamp integration** — OmaAmp is an MPRIS client (cliamp-first, but it
  drives Spotify, Chromium or mpv too). Opening the player starts a headless
  `cliamp -d` engine when nothing is running, and closing it stops the
  engine it started — closing Winamp stopped the music. A shipped
  `cliamp.toml.tpl` + theme-set hook also makes cliamp follow every Omarchy
  theme switch, like the rest of the themed apps.

## Install

The bar widget installs like any Omarchy plugin:

```bash
omarchy plugin add https://github.com/jonnyace/omaamp.git
omarchy plugin enable io.github.jonnyace.omaamp
```

The desktop app is opt-in, from the plugin checkout:

```bash
cd ~/.config/omarchy/plugins/io.github.jonnyace.omaamp
./install.sh          # `omaamp` on PATH, a launcher tile, Hyprland rules,
                      # the cliamp theme template + hook
```

`install.sh` appends one clearly marked, backed-up rule block to
`~/.config/hypr/hyprland.lua`; `./install.sh --uninstall` removes everything
it added. Skins download on demand and cache under `~/.cache/omaamp/`;
museum entries flagged NSFW are filtered from browse and search.

## Use

- **Bar icon**: left-click opens the skin browser, middle-click launches or
  focuses the player.
- **Browser panel**: *Browse* is the museum's own top ranking (cached,
  offline); typing searches everything. Clicking a skin re-dresses a running
  player live. *Tune* edits the seven derived cliamp colors and holds the
  **Make Omarchy theme** / **Apply to desktop** buttons. *Mine* lists
  installed themes.
- **Player**: opens as its own tile (never hovering over your windows),
  scales in whole-pixel steps up to Winamp's classic double-size, floats
  when you toggle it. The letterbox is transparent — wallpaper shows through
  around the artwork.

```bash
omaamp                  # launch, or focus the running instance
omaamp --skin <md5>     # wear a specific museum skin
omaamp --zoom 3         # bigger pixels
omaamp --no-engine      # don't start a cliamp daemon
omaamp --quit
```

## How it works

**Rendering.** A `.wsz` is a ZIP of sprite sheets cut to fixed offsets
(`main.bmp` 275×116, `cbuttons.bmp` 136×36, `text.bmp` 155×18 …). Those
offsets are not ours to choose — every skin ever made was cut against them —
so `player/sprites.js` encodes the classic spec and nothing else. Surveying
280 skins (~1,900 sheets), Qt decodes 99.6% natively; 15.7% ship
`nums_ex.bmp` instead of `numbers.bmp`, which shifts every digit one cell.

**Why the player is its own process.** It would be less code as an
omarchy-shell plugin, but plugins run unsandboxed inside the single process
that owns the bar, notifications and lock screen — and this program's job is
decoding bitmaps from arbitrary archives, ~0.4% of which have corrupt
headers. As an app, a decoder fault closes a music player. Measured marginal
cost: ~117 MB PSS (most of Qt is already resident for the shell).

**Theme conversion.** Winamp drew its colors over its own artwork; a
terminal draws them on a flat background, so a literal port leaves a large
share of the museum unreadable. The converter (`cliamp_skinner/`) works in
OKLab: backgrounds get lightness headroom while keeping their hue, monochrome
visualizer ramps are re-laid across a contrast-safe band, fade-to-black steps
borrow the ramp's hue instead of surfacing grey, and polychrome ramps —
including Winamp's own red/yellow/green — are left alone, because their
non-monotonic lightness *is* the look. On 200 randomly sampled skins the
result is 98.5% clean; the residual is two-color skins where "collapsed" is
the honest answer. `python3 -m unittest discover -s tools` runs the
regression suite; `tools/bench.py` re-runs the corpus harness.

**Museum API.** `https://api.webamp.org/graphql`, public and unauthenticated.
`sort: MUSEUM` is the site's own curated ranking. Files and screenshots come
from `r2.webampskins.org`, which rejects Python's default urllib user-agent —
send a real one.

## Layout

    player/            the app (self-contained Quickshell config)
    BarWidget.qml
    Panel.qml          the bar plugin
    bin/omaamp         launcher: engine lifecycle, launch-or-focus
    bin/skinner        JSON bridge: museum, conversion, playback, themes
    cliamp_skinner/    the OKLab conversion engine (stdlib-only Python)
    install.sh         desktop-app install / uninstall
    assets/            cliamp theme template + theme-set hook
    tools/             dev tooling: corpus bench, CLI converter, tests

## License

MIT.
