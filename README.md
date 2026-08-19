# OmaAmp

Winamp, on your Omarchy desktop, wearing any of the ~102,000 classic skins in
the [Winamp Skin Museum](https://skins.webamp.org/) — driving whatever is
actually playing.

Two halves:

- **The player** (`player/`) — the Winamp 2.x main window as a real floating
  application. It plays nothing itself: it is an MPRIS client, so it drives
  [cliamp](https://github.com/bjarneo/cliamp), Spotify, Chromium or mpv, and it
  coexists with Omarchy's own `omarchy.media` bar widget rather than replacing
  it. Runs as its own process, deliberately — see below.
- **The theme converter** (`cliamp_skinner/`) — turns a skin's palette into a
  cliamp theme, so your terminal player matches the window. A dependency-free
  Python package, so the mapping rules could be tuned against the real corpus
  before any QML existed.

## Install

```bash
./install.sh          # adds `omaamp` to PATH, a launcher tile, Hyprland rules
omaamp --skin <md5>   # wear a specific museum skin
omaamp --zoom 3       # bigger pixels
omaamp --quit
./install.sh --uninstall
```

## Why the player is its own process

It would have been less code as an omarchy-shell plugin. But plugins run
unsandboxed inside the single `omarchy-shell` process (~495 MB here) that also
owns the bar, notifications, OSD, polkit agent and **lock screen** — and this
program's whole job is decoding bitmaps out of arbitrary archives from a
102,000-skin corpus, ~0.4% of which have corrupt headers. As a plugin, a
decoder fault takes down the desktop. As an app, it closes a music player.

Measured cost of the separate process: 271 MB RSS, but only **117 MB PSS** —
most of the Qt runtime is already resident for the shell.

One wrinkle: Quickshell's `appId` is read-only, so every instance is class
`org.quickshell`. Window rules therefore match class *and* title, which is the
same approach Omarchy uses for its own Quickshell windows.

```bash
./convert.py search "matrix" -n 5     # convert museum search results
./convert.py file MySkin.wsz          # convert a local .wsz
./convert.py md5 0098da1c921f...      # convert one museum skin

cliamp theme list                     # themes land in ~/.config/cliamp/themes/
cliamp theme matrix
```

## The skin format

A `.wsz` is a ZIP of sprite sheets cut to fixed offsets (`main.bmp` 275x116,
`cbuttons.bmp` 136x36, `numbers.bmp` 99x13, `text.bmp` 155x18 …). Those offsets
are not ours to choose — every skin ever made was cut against them — so
`player/sprites.js` encodes the classic spec and nothing else.

Surveying 280 skins (~1,900 sheets), Qt decodes **99.6%** natively: 88.9%
24bpp, 6.2% 8bpp, 2.4% RLE8, the rest 16/32/4/1bpp. The remaining ~0.4% have
corrupt headers and are skipped. 15.7% of skins ship `nums_ex.bmp` instead of
`numbers.bmp`, which shifts every digit one cell right.

## Why the theme mapping is not a straight copy

A `.wsz` is a ZIP, and two of its members are plain text carrying almost exactly
what cliamp wants:

| Winamp | cliamp |
| --- | --- |
| `pledit.txt` → `NormalBG` | `bg` |
| `pledit.txt` → `Current` | `bright_fg` |
| `pledit.txt` → `Normal` | `fg` |
| `pledit.txt` → `SelectedBG` / `mbFG` | `accent` |
| `viscolor.txt` → indices 2–17 | `red` / `yellow` / `green` |

`viscolor.txt` even labels itself `[top of spec]` and `[middle of spec]`, and
cliamp documents `red`/`yellow`/`green` as spectrum top/middle/low. The sourcing
is close to 1:1.

What is *not* 1:1 is legibility. Winamp drew these colors over its own bitmap
artwork; cliamp draws them on a flat terminal background. Ported literally, a
large share of the museum comes out unusable. The interesting work is all in
`color.py`, and every rule there came from a failure observed while benching:

- **Backgrounds that cap legibility.** A skin with `NormalBG=#ff0000` allows at
  most 5.25:1 against *any* foreground, so no amount of text adjustment makes it
  readable. The background's lightness is moved until it has headroom, keeping
  its hue — a pure-red background becomes a deep red, not grey.
- **Monochrome visualizer ramps.** Three shades of one green read fine over
  artwork and collapse into a solid block on a terminal. Those are re-laid
  across a lightness band known to clear the contrast floor.
- **Ramps that fade to black.** Winamp analyzers commonly vanish at the bottom
  of the bar, so the darkest step is often literal `#000000`. Lightening it
  yields grey and silently drops the skin's identity, so such a step borrows the
  ramp's own dominant hue.
- **Polychrome ramps must be left alone.** Winamp's own default ramp is
  separated by *hue* (32° / 107° / 143°) and is deliberately non-monotonic in
  lightness — yellow is lighter than both red and green. Restacking it into an
  ascending band would destroy the single most recognizable thing about it. Only
  monochrome ramps get the band treatment.
- **Hues that cannot reach the target.** Pure red on black tops out near 5.25:1.
  Rather than fail, chroma is traded away a step at a time until the text
  clears, then walked back as close to the original as the target allows.

All lightness work happens in OKLab. Adjusting lightness in sRGB or HSL shifts
perceived hue, which would drift a skin away from the palette its author chose.

## Bench

`bench.py` samples random skins from the museum, converts them, and checks the
properties the mapping is supposed to guarantee: every slot clears its contrast
floor, the spectrum stays separable, and the theme does not collapse into one
color. Downloads are cached under `.cache/`.

```bash
./bench.py -n 200 --seed 91 --save-worst 5
```

Current results on 200 randomly sampled skins (seed 91, none used during
tuning): **98.5% clean**. Of the corpus, 95% ship `pledit.txt` and 97.5% ship
`viscolor.txt`; the remaining 6.5% fall back to sampling the skin's artwork.

The residual ~1.5% are near-faithful edge cases rather than defects — skins that
genuinely only contain two colors, where a "collapsed" theme is the honest
result.

## Tests

```bash
python3 -m unittest test_convert -v
```

Every case is a regression for a bug found while benching.

## Layout

    cliamp_skinner/color.py    OKLab, contrast, ramp fitting  <- the real work
    cliamp_skinner/skin.py     .wsz parsing, tolerant by design
    cliamp_skinner/theme.py    slot mapping + legibility pass
    cliamp_skinner/museum.py   Skin Museum GraphQL client
    convert.py                 CLI
    bench.py                   corpus harness
    test_convert.py            regressions

## Notes on the museum API

`https://api.webamp.org/graphql` is public and unauthenticated. `search_skins`
and `search_classic_skins` return bare lists; `skins` returns a connection
(`{nodes{...}}`). Skin files and screenshots come from `r2.webampskins.org`,
which **rejects Python's default urllib user-agent with a 403** — send a real
one. Roughly 1,500 skins carry an `nsfw` flag and are filtered out by default.
