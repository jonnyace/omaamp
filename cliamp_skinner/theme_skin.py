"""Generate a Winamp skin from the active Omarchy theme.

Museum skins are bitmap art: they cannot follow ``omarchy theme set`` the way
templated apps do. This module closes that gap with a synthetic skin -- the
classic base-2.91 sheets recolored through the theme's palette -- so a user
who wants a player that matches their desktop wears *this* skin, and the
theme-set hook rebuilds it on every switch.

Recoloring is a two-ramp map, per pixel:

* near-grey pixels (the chrome: panels, buttons, bevels) ride a four-stop
  luminance ramp through the theme's background/foreground shades, so the
  window keeps its depth but takes the theme's tone;
* saturated pixels (the gold trim, LEDs, the charting green) are the skin's
  deliberate color, so they ride a black -> accent -> white ramp instead.

Output goes to a fresh directory named by a hash of the palette: the player
caches decoded images per URL, so regenerating in place would show stale art.
A new directory means new URLs means a clean load.
"""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path

from .omarchy_theme import decode_bmp

# Sheets the player draws from. viscolor/pledit are text and built directly.
SHEETS = (
    "main.bmp", "titlebar.bmp", "cbuttons.bmp", "text.bmp", "posbar.bmp",
    "volume.bmp", "balance.bmp", "shufrep.bmp", "monoster.bmp",
    "playpaus.bmp", "numbers.bmp", "nums_ex.bmp", "pledit.bmp",
)

RGB = tuple[int, int, int]


def _hex(color: str) -> RGB:
    v = color.lstrip("#")
    return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))


def _mix(a: RGB, b: RGB, t: float) -> RGB:
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


def _ramp(stops: list[RGB], t: float) -> RGB:
    t = max(0.0, min(1.0, t))
    span = t * (len(stops) - 1)
    i = min(len(stops) - 2, int(span))
    return _mix(stops[i], stops[i + 1], span - i)


def write_bmp(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    """24bpp bottom-up BMP -- the one encoding every decoder agrees on.

    Rows come in as RGB; BMP stores BGR, so each pixel is swapped before the
    row is padded.
    """
    pad = b"\0" * ((4 - (width * 3) % 4) % 4)
    parts = []
    for y in range(height - 1, -1, -1):
        row = bytearray(rows[y])
        row[0::3], row[2::3] = row[2::3], row[0::3]
        parts.append(bytes(row) + pad)
    body = b"".join(parts)
    header = struct.pack(
        "<2sIHHIIiiHHIIiiII",
        b"BM", 54 + len(body), 0, 0, 54,
        40, width, height, 1, 24, 0, len(body), 2835, 2835, 0, 0,
    )
    path.write_bytes(header + body)


def _recolor_row(row: bytes, chrome: list[RGB], vivid: list[RGB]) -> bytes:
    out = bytearray(len(row))
    for x in range(0, len(row), 3):
        r, g, b = row[x], row[x + 1], row[x + 2]
        hi, lo = max(r, g, b), min(r, g, b)
        luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
        saturation = 0.0 if hi == 0 else (hi - lo) / hi
        color = _ramp(vivid if saturation > 0.28 else chrome, luma)
        out[x], out[x + 1], out[x + 2] = color
    return bytes(out)


def build(source_sprites: Path, colors: dict[str, str], out_root: Path) -> Path:
    """Recolor a skin's sheets through an Omarchy palette. Returns the dir.

    ``colors`` is the parsed colors.toml mapping; ``source_sprites`` an
    already-extracted skin directory (base-2.91 in practice).
    """
    chrome = [
        _hex(colors.get("darker_background", "#0e0e14")),
        _hex(colors.get("background", "#101315")),
        _hex(colors.get("muted", "#707880")),
        _hex(colors.get("bright_foreground", colors.get("foreground", "#cacccc"))),
    ]
    accent = _hex(colors.get("accent", "#cacccc"))
    vivid = [_hex(colors.get("darker_background", "#0e0e14")), accent, (255, 255, 255)]

    digest = hashlib.sha1(
        ("|".join(f"{k}={v}" for k, v in sorted(colors.items()))).encode()
    ).hexdigest()[:10]
    out = out_root / f"omarchy-{digest}"
    if (out / "main.bmp").exists():
        return out  # same palette, same art
    out.mkdir(parents=True, exist_ok=True)

    for sheet in SHEETS:
        src = source_sprites / sheet
        if not src.exists():
            continue
        decoded = decode_bmp(src.read_bytes())
        if not decoded:
            continue
        width, height, rows = decoded
        write_bmp(out / sheet, width, height,
                  [_recolor_row(r, chrome, vivid) for r in rows])

    # The two text files are built from the palette directly rather than
    # recolored: they ARE color definitions.
    def h(c: RGB) -> str:
        return "#%02x%02x%02x" % c

    (out / "pledit.txt").write_text(
        "[Text]\n"
        f"Normal={h(_hex(colors.get('foreground', '#cacccc')))}\n"
        f"Current={h(_hex(colors.get('bright_foreground', colors.get('foreground', '#ffffff'))))}\n"
        f"NormalBG={h(_hex(colors.get('background', '#101315')))}\n"
        f"SelectedBG={h(_hex(colors.get('selection', colors.get('accent', '#444444'))))}\n"
    )

    # Classic analyzer semantics from the theme's own signal colors:
    # red at the top of a bar, yellow through the middle, green at the base.
    red = _hex(colors.get("red", "#dc322f"))
    yellow = _hex(colors.get("yellow", "#b58900"))
    green = _hex(colors.get("green", "#859900"))
    bg = _hex(colors.get("background", "#101315"))
    lines = [f"{bg[0]},{bg[1]},{bg[2]}"] * 2
    for i in range(16):
        t = i / 15.0
        c = _ramp([red, yellow, green], t)
        lines.append(f"{c[0]},{c[1]},{c[2]}")
    osc = _hex(colors.get("accent", "#cacccc"))
    lines += [f"{osc[0]},{osc[1]},{osc[2]}"] * 5
    peak = _hex(colors.get("bright_foreground", colors.get("foreground", "#ffffff")))
    lines.append(f"{peak[0]},{peak[1]},{peak[2]}")
    (out / "viscolor.txt").write_text("\n".join(lines) + "\n")

    return out
