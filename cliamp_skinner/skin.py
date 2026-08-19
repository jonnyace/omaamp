"""Reading a Winamp ``.wsz`` skin.

A ``.wsz`` is a plain ZIP of bitmaps plus two hand-authored text files that
happen to carry exactly the colors cliamp needs:

  pledit.txt    playlist editor colors -- text, background, selection
  viscolor.txt  24 RGB triples driving the visualizer

Neither file is guaranteed present, correct, or consistently cased, and the
archives frequently nest everything one directory deep. Everything here is
tolerant by design: the museum holds ~100k skins authored over 25 years by
people who were not writing against a spec.
"""

from __future__ import annotations

import io
import re
import struct
import zipfile
from dataclasses import dataclass, field

from .color import RGB, average, parse_hex

# viscolor.txt is 24 lines. Winamp's own layout, which skin authors followed:
#   0-1    visualizer background
#   2-17   spectrum analyzer, index 2 at the top of the bar down to 17
#   18-22  oscilloscope
#   23     peak dot
VIS_SPECTRUM = slice(2, 18)

_KV_RE = re.compile(r"^\s*([A-Za-z]\w*)\s*=\s*(#?[0-9A-Fa-f]{6})\s*$", re.M)
_VIS_RE = re.compile(r"^\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})")


@dataclass
class Skin:
    """The colors we could recover from one skin archive."""

    name: str
    pledit: dict[str, RGB] = field(default_factory=dict)
    spectrum: list[RGB] = field(default_factory=list)
    artwork: list[RGB] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    @property
    def has_text_colors(self) -> bool:
        return bool(self.pledit)

    @property
    def has_spectrum(self) -> bool:
        return len(self.spectrum) >= 3


def _decode(raw: bytes) -> str:
    # Skins predate UTF-8's dominance; cp1252 is the realistic fallback and
    # never raises, so a stray byte can't cost us the whole file.
    for enc in ("utf-8", "cp1252"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1", errors="replace")


def parse_pledit(text: str) -> dict[str, RGB]:
    """Pull the ``Key=#rrggbb`` pairs out of pledit.txt, ignoring ``Font=``."""
    out: dict[str, RGB] = {}
    for key, value in _KV_RE.findall(text):
        rgb = parse_hex(value)
        if rgb is not None:
            out[key.lower()] = rgb
    return out


def parse_viscolor(text: str) -> list[RGB]:
    """Pull the RGB triples out of viscolor.txt, in file order.

    Trailing ``// comment`` text is normal and ignored; so are any lines that
    aren't a triple, which is how authors left notes in the file.
    """
    out: list[RGB] = []
    for line in text.splitlines():
        m = _VIS_RE.match(line.split("//")[0])
        if m:
            out.append(tuple(min(255, int(v)) for v in m.groups()))  # type: ignore[arg-type]
    return out


def _bmp_colors(raw: bytes, limit: int = 4000) -> list[RGB]:
    """Sample pixels from an uncompressed BMP.

    Only used as a fallback when a skin ships no color text files, so this
    covers the common encodings (8/24/32-bit, uncompressed) and gives up rather
    than growing a full BMP decoder for the rare RLE case.
    """
    if len(raw) < 54 or raw[:2] != b"BM":
        return []
    try:
        pixel_offset = struct.unpack_from("<I", raw, 10)[0]
        header_size = struct.unpack_from("<I", raw, 14)[0]
        width, height = struct.unpack_from("<ii", raw, 18)
        bpp = struct.unpack_from("<H", raw, 28)[0]
        compression = struct.unpack_from("<I", raw, 30)[0]
    except struct.error:
        return []
    if compression != 0 or bpp not in (8, 24, 32) or not width or not height:
        return []

    height = abs(height)
    palette: list[RGB] = []
    if bpp == 8:
        start = 14 + header_size
        for i in range(start, min(start + 256 * 4, pixel_offset), 4):
            b, g, r = raw[i], raw[i + 1], raw[i + 2]
            palette.append((r, g, b))
        if not palette:
            return []

    row_bytes = ((width * bpp + 31) // 32) * 4
    step = max(1, (width * height) // limit)
    out: list[RGB] = []
    idx = 0
    for y in range(height):
        row = pixel_offset + y * row_bytes
        if row + row_bytes > len(raw):
            break
        for x in range(width):
            idx += 1
            if idx % step:
                continue
            if bpp == 8:
                p = raw[row + x]
                if p < len(palette):
                    out.append(palette[p])
            else:
                off = row + x * (bpp // 8)
                if off + 3 <= len(raw):
                    out.append((raw[off + 2], raw[off + 1], raw[off]))
    return out


def load(data: bytes, name: str = "skin") -> Skin:
    """Read a ``.wsz`` from bytes. Raises ``zipfile.BadZipFile`` if unreadable."""
    zf = zipfile.ZipFile(io.BytesIO(data))
    # Flatten: archives commonly nest their contents in a folder, and casing is
    # inconsistent across skins ("PLEDIT.TXT", "Pledit.txt", "pledit.txt").
    members: dict[str, str] = {}
    for entry in zf.namelist():
        if entry.endswith("/"):
            continue
        members.setdefault(entry.rsplit("/", 1)[-1].lower(), entry)

    skin = Skin(name=name)

    if "pledit.txt" in members:
        skin.pledit = parse_pledit(_decode(zf.read(members["pledit.txt"])))
        if not skin.pledit:
            skin.notes.append("pledit.txt present but unparseable")
    else:
        skin.notes.append("no pledit.txt")

    if "viscolor.txt" in members:
        vis = parse_viscolor(_decode(zf.read(members["viscolor.txt"])))
        skin.spectrum = vis[VIS_SPECTRUM] if len(vis) >= 18 else vis
        if not skin.has_spectrum:
            skin.notes.append(f"viscolor.txt had only {len(vis)} colors")
    else:
        skin.notes.append("no viscolor.txt")

    # Artwork is only sampled when we'll actually need it to invent a palette.
    if not skin.has_text_colors or not skin.has_spectrum:
        for candidate in ("main.bmp", "pledit.bmp", "titlebar.bmp"):
            if candidate in members:
                pixels = _bmp_colors(zf.read(members[candidate]))
                if pixels:
                    skin.artwork = pixels
                    break
        if not skin.artwork:
            skin.notes.append("no readable artwork to sample")

    return skin


def artwork_average(skin: Skin) -> RGB | None:
    return average(skin.artwork) if skin.artwork else None
