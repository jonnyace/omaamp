"""Color math for mapping Winamp skin palettes onto cliamp's seven theme slots.

Winamp drew its colors over its own bitmap artwork, so a skin author only ever
had to make them legible against that art. cliamp draws them on a flat terminal
background, which is why a literal 1:1 port produces unreadable themes for a
large share of the museum -- monochrome visualizer ramps collapse into the
background, and selection colors chosen as a subtle tint of the artwork stop
being visible at all.

Everything here works in OKLab. Nudging lightness in sRGB (or HSL) shifts the
perceived hue, which would drift a skin away from the palette its author chose;
OKLab lets us change how light a color is while holding its hue and chroma, so
the port still reads as the same skin.
"""

from __future__ import annotations

import math
import re
from typing import Iterable

RGB = tuple[int, int, int]

_HEX_RE = re.compile(r"^#?([0-9a-fA-F]{6})$")


# --------------------------------------------------------------------------
# Parsing / formatting
# --------------------------------------------------------------------------


def parse_hex(value: str | None) -> RGB | None:
    """Parse ``#rrggbb`` (with or without the ``#``). Returns None if unusable.

    Skin text files are hand-authored and inconsistent, so this is deliberately
    forgiving about whitespace and a missing leading ``#``.
    """
    if not value:
        return None
    m = _HEX_RE.match(value.strip())
    if not m:
        return None
    h = m.group(1)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def to_hex(rgb: RGB) -> str:
    r, g, b = (max(0, min(255, int(round(c)))) for c in rgb)
    return f"#{r:02x}{g:02x}{b:02x}"


# --------------------------------------------------------------------------
# sRGB <-> linear <-> OKLab
# --------------------------------------------------------------------------


def _srgb_to_linear(c: float) -> float:
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c: float) -> float:
    c = 0.0 if c < 0.0 else (1.0 if c > 1.0 else c)
    v = 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    return v * 255.0


def rgb_to_oklab(rgb: RGB) -> tuple[float, float, float]:
    r, g, b = (_srgb_to_linear(c) for c in rgb)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in (l, m, s))
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def oklab_to_rgb(lab: tuple[float, float, float]) -> RGB:
    L, a, b = lab
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = (v**3 for v in (l_, m_, s_))
    return (
        round(_linear_to_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
        round(_linear_to_srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
        round(_linear_to_srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)),
    )


def lightness(rgb: RGB) -> float:
    """OKLab L: 0 is black, ~1.0 is white. Perceptual, unlike WCAG luminance."""
    return rgb_to_oklab(rgb)[0]


def chroma(rgb: RGB) -> float:
    _, a, b = rgb_to_oklab(rgb)
    return math.hypot(a, b)


# --------------------------------------------------------------------------
# Contrast
# --------------------------------------------------------------------------


def relative_luminance(rgb: RGB) -> float:
    r, g, b = (_srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: RGB, b: RGB) -> float:
    """WCAG contrast ratio, 1.0 (identical) to 21.0 (black on white)."""
    la, lb = relative_luminance(a), relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def set_lightness(rgb: RGB, L: float) -> RGB:
    """Rebuild a color at OKLab lightness ``L``, keeping hue and chroma.

    Very light or very dark targets can push a saturated hue outside sRGB. We
    scale chroma back until it fits rather than letting the channel clamp do it,
    because clamping shifts hue -- a dark saturated red would clip toward pure
    red and stop matching the rest of the skin's palette.
    """
    _, a, b = rgb_to_oklab(rgb)
    L = max(0.0, min(1.0, L))
    scale = 1.0
    for _ in range(24):
        cand = oklab_to_rgb((L, a * scale, b * scale))
        # In gamut if a round-trip survives without the channel clamp biting.
        if all(0 <= c <= 255 for c in oklab_to_rgb((L, a * scale, b * scale))):
            back = rgb_to_oklab(cand)
            if abs(back[0] - L) < 0.02:
                return cand
        scale *= 0.85
    return oklab_to_rgb((L, 0.0, 0.0))


def force_contrast(fg: RGB, bg: RGB, target: float, *, max_steps: int = 48) -> RGB:
    """Return ``fg`` adjusted just enough to clear ``target`` contrast on ``bg``.

    Moves away from the background in whichever direction has headroom, by
    binary search on OKLab lightness, and stops as soon as the target is met so
    a skin's palette is disturbed as little as possible. Returns the best
    attempt if the target is simply unreachable in that hue.
    """
    if contrast(fg, bg) >= target:
        return fg

    bg_L = lightness(bg)
    # Prefer moving away from the background; near mid-grey backgrounds have
    # little headroom either way, so try both and keep whichever gets further.
    directions = [1.0] if bg_L < 0.5 else [-1.0]
    directions.append(-directions[0])

    best, best_ratio = fg, contrast(fg, bg)
    for direction in directions:
        lo, hi = lightness(fg), 1.0 if direction > 0 else 0.0
        candidate = None
        for _ in range(max_steps):
            mid = (lo + hi) / 2
            trial = set_lightness(fg, mid)
            if contrast(trial, bg) >= target:
                candidate, hi = trial, mid
            else:
                lo = mid
            if abs(hi - lo) < 1e-4:
                break
        if candidate is not None:
            return candidate
        edge = set_lightness(fg, 1.0 if direction > 0 else 0.0)
        if contrast(edge, bg) > best_ratio:
            best, best_ratio = edge, contrast(edge, bg)

    # A saturated hue can be physically unable to reach a high target: pure red
    # on black tops out around 5.25:1 no matter how it is lightened. Trade
    # chroma away a step at a time, since unreadable text costs the user more
    # than a slightly muted one, and stop at the first shade that clears.
    hue = _hue_of(fg)
    if hue is not None:
        L_edge = 1.0 if lightness(bg) < 0.5 else 0.0
        c = chroma(fg)
        for _ in range(12):
            c *= 0.75
            trial = from_lch(L_edge, hue, c)
            if contrast(trial, bg) >= target:
                # Pull back toward the original lightness while it still clears.
                return _least_change(fg, trial, bg, target)
            if contrast(trial, bg) > best_ratio:
                best, best_ratio = trial, contrast(trial, bg)
    return best


def _least_change(original: RGB, fallback: RGB, bg: RGB, target: float) -> RGB:
    """Walk ``fallback`` back toward ``original`` as far as ``target`` allows."""
    hue = _hue_of(fallback) or _hue_of(original)
    if hue is None:
        return fallback
    lo, hi = 0.0, 1.0  # 0 = fallback, 1 = original
    L0, L1 = lightness(fallback), lightness(original)
    C0, C1 = chroma(fallback), chroma(original)
    best = fallback
    for _ in range(24):
        mid = (lo + hi) / 2
        trial = from_lch(L0 + (L1 - L0) * mid, hue, C0 + (C1 - C0) * mid)
        if contrast(trial, bg) >= target:
            best, lo = trial, mid
        else:
            hi = mid
        if hi - lo < 1e-3:
            break
    return best


def _dominant_hue(colors: list[RGB]) -> tuple[float, float] | None:
    """Unit (a, b) direction of the most colorful member, or None if all grey."""
    best, peak = None, 0.0
    for c in colors:
        _, a, b = rgb_to_oklab(c)
        ch = math.hypot(a, b)
        if ch > peak:
            best, peak = (a / ch, b / ch), ch
    return best if peak >= 0.02 else None


def hue_spread(colors: list[RGB]) -> float:
    """Largest pairwise hue difference in the ramp, in degrees.

    Used to tell a monochrome ramp from a polychrome one, which need opposite
    treatments -- see ``fit_ramp``.
    """
    angles = []
    for c in colors:
        _, a, b = rgb_to_oklab(c)
        if math.hypot(a, b) >= 0.02:
            angles.append(math.degrees(math.atan2(b, a)) % 360)
    if len(angles) < 2:
        return 0.0
    spread = 0.0
    for i, x in enumerate(angles):
        for y in angles[i + 1 :]:
            d = abs(x - y) % 360
            spread = max(spread, min(d, 360 - d))
    return spread


# Above this much hue variation, a ramp's steps are already told apart by color
# and must not be re-stacked by lightness.
POLYCHROME_DEGREES = 25.0


def fit_ramp(
    colors: list[RGB],
    bg: RGB,
    *,
    min_contrast: float,
    min_step: float,
) -> list[RGB]:
    """Make every step of a visualizer ramp visible against ``bg``.

    Winamp ramps come in two kinds and they need opposite handling.

    *Polychrome* ramps -- including Winamp's own default, which runs red at the
    top of the bar through yellow to green at the bottom -- separate their steps
    by hue. Their lightness is deliberately non-monotonic (that default is
    L=0.62 red, 0.86 yellow, 0.78 green), so stacking them into an ascending
    lightness band would flatten the single most recognizable thing about the
    skin. These are left in place and only lifted clear of the background.

    *Monochrome* ramps -- three shades of one green -- have nothing but
    lightness to tell their steps apart, and frequently fade to pure black at
    the bottom of the bar. There, lightness is re-laid across a band that is
    known to clear ``min_contrast``, in list order, and a step too dark to carry
    a hue borrows the ramp's dominant one so a green skin stays green.
    """
    if not colors:
        return colors

    if hue_spread(colors) >= POLYCHROME_DEGREES:
        lifted = [force_contrast(c, bg, min_contrast) for c in colors]
        return _separate_pairs(lifted, bg, min_contrast, min_step)

    hue = _dominant_hue(colors)
    chromas = [chroma(c) for c in colors]
    peak_chroma = max(chromas) if chromas else 0.0

    # Find the lightness at which this ramp's hue first clears the contrast
    # floor, and build the band outward from there.
    probe = colors[max(range(len(chromas)), key=chromas.__getitem__)]
    span = min_step * (len(colors) - 1)
    bg_L = lightness(bg)

    if bg_L < 0.5:
        lo = _first_visible(probe, bg, min_contrast, upward=True)
        lo = min(lo, 1.0 - span)
        band = [lo + min_step * i for i in range(len(colors))]
    else:
        hi = _first_visible(probe, bg, min_contrast, upward=False)
        hi = max(hi, span)
        band = [hi - min_step * i for i in range(len(colors))]
        band.reverse()

    # The band runs dark-to-light in list order. That is already the semantic
    # order here: the caller passes the ramp low-intensity first, and for a
    # monochrome ramp Winamp encodes intensity as brightness.

    out: list[RGB] = []
    for i, (target_L, original, ch) in enumerate(zip(band, colors, chromas)):
        target_L = max(0.0, min(1.0, target_L))
        own_hue = _hue_of(original)
        direction = own_hue or hue
        if direction is None:
            # Genuinely greyscale ramp; leave it grey.
            out.append(set_lightness(original, target_L))
            continue

        # Chroma is re-laid across the band alongside lightness. These ramps
        # encode intensity with both at once -- a step fading toward black also
        # fades toward grey -- so carrying the original chroma onto a step that
        # has been lifted a long way produces a washed-out color that no longer
        # matches the skin.
        position = i / max(1, len(colors) - 1)
        target_c = peak_chroma * (0.55 + 0.45 * position)
        out.append(from_lch(target_L, direction, max(ch, target_c) if own_hue else target_c))
    return out


def _separate_pairs(
    colors: list[RGB], bg: RGB, min_contrast: float, min_step: float
) -> list[RGB]:
    """Nudge apart any two ramp steps that are alike in both hue and lightness.

    A ramp can be polychrome overall -- one step far from the others -- while
    two of its steps remain identical. The whole-ramp hue spread does not catch
    that, so each pair is checked on its own and only the colliding ones move.
    """
    out = list(colors)
    for i in range(len(out)):
        for j in range(i + 1, len(out)):
            if hue_spread([out[i], out[j]]) >= POLYCHROME_DEGREES:
                continue
            gap = abs(lightness(out[j]) - lightness(out[i]))
            if gap >= min_step:
                continue
            # Move the later step, so earlier ones stay closest to the source.
            base = lightness(out[i])
            for direction in (1.0, -1.0):
                target = base + direction * min_step
                if 0.0 <= target <= 1.0:
                    trial = set_lightness(out[j], target)
                    if contrast(trial, bg) >= min_contrast:
                        out[j] = trial
                        break
    return out


def ensure_headroom(bg: RGB, target: float) -> tuple[RGB, bool]:
    """Push a background far enough toward an extreme to support ``target``.

    A saturated mid-tone background caps how legible *any* text on it can be:
    pure red tops out at 5.25:1 against white, so an AAA target is unreachable
    no matter what the foreground does. Skin authors could get away with that
    because Winamp drew text over artwork rather than a flat fill.

    The background's hue is kept and only its lightness moves, so the skin still
    reads as itself -- a pure-red background becomes a deep red, not grey.
    Darkening is tried first, since that is what a terminal background usually
    wants to be.
    """
    white, black = (255, 255, 255), (0, 0, 0)
    if max(contrast(white, bg), contrast(black, bg)) >= target:
        return bg, False

    start = lightness(bg)
    best, best_ratio = bg, max(contrast(white, bg), contrast(black, bg))
    for extreme, probe in ((0.0, white), (1.0, black)):
        lo, hi = (extreme, start) if extreme < start else (start, extreme)
        candidate = None
        for _ in range(40):
            mid = (lo + hi) / 2
            trial = set_lightness(bg, mid)
            if contrast(probe, trial) >= target:
                candidate = trial
                # Keep as close to the original lightness as the target allows.
                if extreme < start:
                    lo = mid
                else:
                    hi = mid
            else:
                if extreme < start:
                    hi = mid
                else:
                    lo = mid
            if hi - lo < 1e-4:
                break
        if candidate is not None:
            return candidate, True
        edge = set_lightness(bg, extreme)
        if contrast(probe, edge) > best_ratio:
            best, best_ratio = edge, contrast(probe, edge)
    return best, True


def _hue_of(rgb: RGB, min_chroma: float = 0.02) -> tuple[float, float] | None:
    _, a, b = rgb_to_oklab(rgb)
    c = math.hypot(a, b)
    return (a / c, b / c) if c >= min_chroma else None


def from_lch(L: float, hue: tuple[float, float], c: float) -> RGB:
    """Build a color from lightness, a unit hue direction, and chroma.

    Chroma is walked back until the result fits in sRGB, rather than letting the
    per-channel clamp do it, since clamping skews the hue.
    """
    L = max(0.0, min(1.0, L))
    for _ in range(24):
        lab = (L, hue[0] * c, hue[1] * c)
        rgb = oklab_to_rgb(lab)
        back = rgb_to_oklab(rgb)
        if abs(back[0] - L) < 0.02 and abs(math.hypot(back[1], back[2]) - c) < 0.02:
            return rgb
        c *= 0.85
    return oklab_to_rgb((L, 0.0, 0.0))


def _first_visible(sample: RGB, bg: RGB, target: float, *, upward: bool) -> float:
    """Lowest (or highest) OKLab lightness at which ``sample`` clears ``target``."""
    lo, hi = (lightness(bg), 1.0) if upward else (0.0, lightness(bg))
    best = hi if upward else lo
    for _ in range(40):
        mid = (lo + hi) / 2
        if contrast(set_lightness(sample, mid), bg) >= target:
            best = mid
            if upward:
                hi = mid
            else:
                lo = mid
        else:
            if upward:
                lo = mid
            else:
                hi = mid
        if hi - lo < 1e-4:
            break
    return best


def average(colors: Iterable[RGB]) -> RGB | None:
    """Mean color in linear light, which is where averaging is meaningful."""
    acc = [0.0, 0.0, 0.0]
    n = 0
    for c in colors:
        for i in range(3):
            acc[i] += _srgb_to_linear(c[i])
        n += 1
    if not n:
        return None
    return tuple(round(_linear_to_srgb(v / n)) for v in acc)  # type: ignore[return-value]
