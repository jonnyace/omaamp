"""Build a complete Omarchy theme from a Winamp skin.

An Omarchy theme is a directory under ``~/.config/omarchy/themes/<name>/``
holding ``colors.toml`` (the ~28 named colors every template renders from)
plus at least one image in ``backgrounds/``. Given those two, Omarchy's own
engine themes alacritty, btop, foot, ghostty, helix, kitty, neovim, vscode,
chromium, obsidian and Hyprland -- so one skin can dress the whole desktop.

Two problems solved here:

*Palette.* A skin yields four trustworthy anchors (background, text, bright
text, accent) and a visualizer ramp; ``colors.toml`` wants a full ANSI set
including hues most skins never contain. Inventing them naively produces a
garish terminal, so the ANSI hues sit at their conventional OKLab hue angles
while lightness and chroma adapt to the skin -- the terminal stays usable,
but a mossy green skin gets mossy ANSI colors rather than neon ones.

*Wallpaper.* Themes need a background image and skins ship none, so one is
rendered: a vertical gradient between the theme's own background shades with
the skin's main window composited at an integer scale in the centre. Pure
stdlib -- a small BMP decoder and a PNG writer -- because Pillow is not a
dependency this package gets to have.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

from .color import (
    RGB,
    chroma,
    from_lch,
    lightness,
    oklab_to_rgb,
    rgb_to_oklab,
    set_lightness,
    to_hex,
)
from .skin import Skin
from .theme import Theme

# Conventional OKLab hue angles (degrees) for the ANSI palette. Taken from
# where well-liked terminal schemes put these hues, not from sRGB primaries --
# pure #ff0000 red reads as an error, not a color scheme.
ANSI_HUES = {
    "red": 25.0,
    "orange": 55.0,
    "yellow": 95.0,
    "green": 140.0,
    "cyan": 195.0,
    "blue": 260.0,
    "magenta": 330.0,
    "brown": 60.0,
}


def _hue_angle(rgb: RGB) -> float | None:
    _, a, b = rgb_to_oklab(rgb)
    if math.hypot(a, b) < 0.02:
        return None
    return math.degrees(math.atan2(b, a)) % 360


def _at_angle(angle_deg: float, L: float, c: float) -> RGB:
    rad = math.radians(angle_deg)
    return from_lch(L, (math.cos(rad), math.sin(rad)), c)


def build_colors(skin: Skin, theme: Theme) -> dict[str, str]:
    """Derive the full colors.toml mapping from a converted skin theme."""
    bg, fg = theme.bg, theme.fg
    bright, accent = theme.bright_fg, theme.accent
    dark = lightness(bg) < 0.5

    # ANSI lightness/chroma adapt to the skin: colorful skins get colorful
    # terminals, muted skins stay muted -- with floors so nothing goes grey
    # or unreadable.
    base_l = 0.72 if dark else 0.52
    base_c = max(0.09, min(0.17, chroma(accent) * 0.85))

    # Skin hues that already exist take over their nearest ANSI slot, which is
    # what keeps the theme recognizably *this* skin. A slot is claimed when a
    # skin anchor sits within 40 degrees of it.
    candidates = [accent, theme.red, theme.yellow, theme.green, bright]
    ansi: dict[str, RGB] = {}
    for name, angle in ANSI_HUES.items():
        best, best_d = None, 40.0
        for cand in candidates:
            got = _hue_angle(cand)
            if got is None:
                continue
            d = abs(got - angle) % 360
            d = min(d, 360 - d)
            if d < best_d:
                best, best_d = cand, d
        if best is not None:
            # Keep the skin's hue but normalise lightness so the set reads as
            # one palette rather than a ransom note.
            got = _hue_angle(best)
            ansi[name] = _at_angle(got, base_l, max(base_c, chroma(best) * 0.7))
        else:
            ansi[name] = _at_angle(angle, base_l, base_c)
    # Brown is a darker, muted orange in every scheme that carries one.
    ansi["brown"] = _at_angle(ANSI_HUES["brown"], base_l - 0.22, base_c * 0.6)

    def brighter(rgb: RGB) -> RGB:
        return set_lightness(rgb, min(1.0, lightness(rgb) + 0.10))

    # Lightness steps are floored, not just offset: a pure-black skin
    # background has nowhere to go down and offsets of +0.05 from L=0 are
    # still visually black, which turned selection and the elevated
    # backgrounds into the background itself.
    bg_l = lightness(bg)
    if dark:
        sel_l = max(bg_l + 0.10, 0.24)
        lighter_l = max(bg_l + 0.05, 0.14)
    else:
        sel_l = min(bg_l - 0.10, 0.82)
        lighter_l = min(bg_l - 0.05, 0.90)

    colors = {
        "mode": "dark" if dark else "light",
        "accent": accent,
        "selection": set_lightness(accent, sel_l),
        "muted": fg,
        "background": bg,
        "dark_background": set_lightness(bg, max(0.0, bg_l - 0.03)),
        "darker_background": set_lightness(bg, max(0.0, bg_l - 0.06)),
        "lighter_background": set_lightness(bg, lighter_l),
        "foreground": bright,
        "dark_foreground": set_lightness(bright, max(0.0, lightness(bright) - 0.22)),
        "light_foreground": brighter(bright),
        "bright_foreground": brighter(bright),
        **ansi,
    }
    for name in ("red", "yellow", "green", "cyan", "blue", "magenta"):
        colors[f"bright_{name}"] = brighter(ansi[name])

    return {k: (v if isinstance(v, str) else to_hex(v)) for k, v in colors.items()}


def write_colors_toml(path: Path, colors: dict[str, str], source: str) -> None:
    lines = [f"# Generated by OmaAmp from Winamp skin: {source}", ""]
    order = [
        "mode", "", "accent", "selection", "muted", "",
        "background", "dark_background", "darker_background", "lighter_background", "",
        "foreground", "dark_foreground", "light_foreground", "bright_foreground", "",
        "red", "yellow", "orange", "green", "cyan", "blue", "magenta", "brown", "",
        "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta",
    ]
    for key in order:
        if not key:
            lines.append("")
        elif key in colors:
            lines.append(f'{key} = "{colors[key]}"')
    path.write_text("\n".join(lines) + "\n")


# --------------------------------------------------------------------------
# Wallpaper
# --------------------------------------------------------------------------


def decode_bmp(raw: bytes) -> tuple[int, int, list[bytes]] | None:
    """Decode an uncompressed 8/24/32-bit BMP into top-down RGB rows.

    Covers ~95% of skin sheets (the survey in the README); anything else --
    RLE, bitfields, corrupt headers -- returns None and the wallpaper falls
    back to a plain gradient rather than failing the theme.
    """
    if len(raw) < 54 or raw[:2] != b"BM":
        return None
    try:
        pixel_offset = struct.unpack_from("<I", raw, 10)[0]
        header_size = struct.unpack_from("<I", raw, 14)[0]
        width, height = struct.unpack_from("<ii", raw, 18)
        bpp = struct.unpack_from("<H", raw, 28)[0]
        compression = struct.unpack_from("<I", raw, 30)[0]
    except struct.error:
        return None
    if compression != 0 or bpp not in (8, 24, 32) or width <= 0 or height == 0:
        return None

    flipped = height > 0  # positive height = bottom-up storage
    height = abs(height)
    palette: list[bytes] = []
    if bpp == 8:
        start = 14 + header_size
        for i in range(start, min(start + 256 * 4, pixel_offset), 4):
            palette.append(bytes((raw[i + 2], raw[i + 1], raw[i])))
        if not palette:
            return None

    row_bytes = ((width * bpp + 31) // 32) * 4
    rows: list[bytes] = []
    for y in range(height):
        src = pixel_offset + y * row_bytes
        if src + row_bytes > len(raw):
            return None
        out = bytearray()
        if bpp == 8:
            for x in range(width):
                p = raw[src + x]
                out += palette[p] if p < len(palette) else b"\0\0\0"
        else:
            stride = bpp // 8
            for x in range(width):
                o = src + x * stride
                out += bytes((raw[o + 2], raw[o + 1], raw[o]))
        rows.append(bytes(out))
    if flipped:
        rows.reverse()
    return width, height, rows


def write_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    """Minimal truecolor PNG writer: one IDAT, filter 0 on every row."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + row for row in rows)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )


def render_wallpaper(
    path: Path,
    colors: dict[str, str],
    main_bmp: bytes | None,
    *,
    width: int = 2560,
    height: int = 1600,
) -> None:
    """Gradient between the theme's background shades, skin window centred.

    The sprite scale is chosen so the window fills roughly half the screen
    width at a whole-number multiple -- fractional scaling would smear the
    pixel art this whole project exists to preserve.
    """
    def hx(name: str) -> RGB:
        v = colors[name].lstrip("#")
        return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))

    top, bottom = hx("darker_background"), hx("background")

    gradient_rows: list[bytes] = []
    for y in range(height):
        t = y / max(1, height - 1)
        color = bytes(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        gradient_rows.append(color * width)

    decoded = decode_bmp(main_bmp) if main_bmp else None
    if decoded:
        sw, sh, sprite = decoded
        scale = max(1, round(width * 0.45 / sw))
        ox = (width - sw * scale) // 2
        oy = (height - sh * scale) // 2
        for sy in range(sh):
            src = sprite[sy]
            scaled = bytearray()
            for sx in range(sw):
                scaled += src[sx * 3:sx * 3 + 3] * scale
            for repeat in range(scale):
                y = oy + sy * scale + repeat
                if 0 <= y < height:
                    row = bytearray(gradient_rows[y])
                    row[ox * 3:ox * 3 + len(scaled)] = scaled
                    gradient_rows[y] = bytes(row)

    write_png(path, width, height, gradient_rows)


def build_theme_dir(
    dest: Path,
    skin: Skin,
    theme: Theme,
    main_bmp: bytes | None,
    source: str,
) -> dict[str, str]:
    """Write a ready-to-apply Omarchy theme directory. Returns the colors."""
    colors = build_colors(skin, theme)
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "backgrounds").mkdir(exist_ok=True)
    write_colors_toml(dest / "colors.toml", colors, source)
    render_wallpaper(dest / "backgrounds" / "1-omaamp.png", colors, main_bmp)
    return colors
