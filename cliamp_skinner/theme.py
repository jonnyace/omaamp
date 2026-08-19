"""Mapping a Winamp skin's palette onto cliamp's seven theme slots.

cliamp's theme surface (from its docs):

    bg          application background (optional)
    accent      titles, track names, seek bars, selections
    bright_fg   primary text and time displays
    fg          muted text, help bars, inactive elements
    green       playing status, success states, spectrum low
    yellow      warnings, spectrum middle
    red         errors, spectrum top

The spectrum halves of green/yellow/red line up exactly with viscolor.txt, and
pledit.txt supplies the text colors, so the *sourcing* is near mechanical. The
work is in what comes after: enforcing that the result is actually legible on a
terminal, which the source material does not guarantee.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .color import (
    RGB,
    average,
    chroma,
    contrast,
    ensure_headroom,
    fit_ramp,
    force_contrast,
    lightness,
    to_hex,
)
from .skin import Skin

# Contrast floors against the background. Text carries the strict targets;
# the spectrum is graphical, so it uses WCAG's lower non-text threshold.
TARGET_BRIGHT_FG = 7.0
TARGET_FG = 4.0
TARGET_ACCENT = 4.5
TARGET_SPECTRUM = 3.0

# Minimum OKLab lightness gap between adjacent spectrum steps, so a monochrome
# viscolor ramp still reads as three distinct bands.
SPECTRUM_STEP = 0.11

SLOTS = ("bg", "accent", "bright_fg", "fg", "green", "yellow", "red")


@dataclass
class Theme:
    bg: RGB
    accent: RGB
    bright_fg: RGB
    fg: RGB
    green: RGB
    yellow: RGB
    red: RGB
    source: str = ""
    # What we had to invent or repair, for the bench harness and the UI's
    # "this skin needed work" badge.
    adjusted: list[str] = field(default_factory=list)
    invented: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def to_toml(self) -> str:
        head = f"# Converted from Winamp skin: {self.source}\n" if self.source else ""
        body = "\n".join(f'{slot} = "{to_hex(getattr(self, slot))}"' for slot in SLOTS)
        return head + body + "\n"

    def contrasts(self) -> dict[str, float]:
        return {
            slot: contrast(getattr(self, slot), self.bg)
            for slot in SLOTS
            if slot != "bg"
        }


def _pick_background(skin: Skin) -> tuple[RGB, bool]:
    bg = skin.pledit.get("normalbg") or skin.pledit.get("mbbg")
    if bg is not None:
        return bg, False
    if skin.artwork:
        # Winamp's chrome is overwhelmingly dark; the darker end of the artwork
        # is a better guess at "background" than the mean, which the bright
        # display area drags upward.
        darkest = sorted(skin.artwork, key=lightness)[: max(1, len(skin.artwork) // 5)]
        return average(darkest) or (0, 0, 0), True
    return (0, 0, 0), True


def _pick_accent(skin: Skin, bg: RGB, bright_fg: RGB, fg: RGB) -> tuple[RGB, bool]:
    """Choose the most accent-like color available.

    ``SelectedBG`` is the obvious candidate by name, but it is a *background*
    tint in Winamp and is often nearly the background itself, whereas cliamp
    uses accent as a foreground highlight. So we score candidates on how
    colorful they are and how well they separate from both the background and
    the primary text, rather than trusting any single key.
    """
    candidates: list[tuple[str, RGB]] = []
    for key in ("mbfg", "selectedbg", "current", "normal"):
        if key in skin.pledit:
            candidates.append((key, skin.pledit[key]))
    if skin.spectrum:
        candidates.append(("spectrum", skin.spectrum[0]))
    if skin.artwork:
        vivid = sorted(skin.artwork, key=chroma, reverse=True)[: max(1, len(skin.artwork) // 20)]
        avg = average(vivid)
        if avg:
            candidates.append(("artwork", avg))

    if not candidates:
        return bright_fg, True

    def score(item: tuple[str, RGB]) -> float:
        _, rgb = item
        # Colorfulness is what makes an accent read as an accent; the contrast
        # terms are capped so a merely-legible vivid color still beats a
        # high-contrast grey.
        value = (
            chroma(rgb) * 6.0
            + min(contrast(rgb, bg), 6.0) * 0.5
            + min(abs(lightness(rgb) - lightness(bright_fg)), 0.3) * 2.0
        )
        # An accent identical to the text it is supposed to stand out from is
        # no accent at all, so reuse of either text color is heavily penalized
        # -- but not forbidden, since a strictly monochrome skin has nothing
        # else to offer and repeating its one color beats inventing one.
        if rgb == bright_fg or rgb == fg:
            value -= 2.0
        return value

    key, best = max(candidates, key=score)
    # Only the artwork average is genuinely invented; the visualizer ramp is a
    # color the skin's author actually chose.
    return best, key == "artwork"


def _pick_spectrum(skin: Skin, bg: RGB) -> tuple[list[RGB], bool]:
    """Return [low, middle, top] for green/yellow/red.

    viscolor.txt runs top-of-bar first, so it is sampled in reverse to match
    cliamp's low/middle/top ordering.

    Winamp analyzers commonly fade to the visualizer background at the bottom of
    the bar, so the tail of the ramp is often literal black -- not a color the
    author chose, just the bar disappearing. Those entries are dropped first,
    because cliamp uses `green` as a real UI color for playing/success states
    and would otherwise inherit the fade instead of the skin's palette.
    """
    vis = list(skin.spectrum)
    while len(vis) > 3 and lightness(vis[-1]) < 0.06:
        vis.pop()
    if len(vis) >= 3:
        top, middle, low = vis[0], vis[len(vis) // 2], vis[-1]
        return [low, middle, top], False

    # No usable ramp: build one from the accent-ish artwork, or fall back to
    # the conventional green/yellow/red the slot names imply.
    if skin.artwork:
        vivid = sorted(skin.artwork, key=chroma, reverse=True)[: max(1, len(skin.artwork) // 20)]
        base = average(vivid)
        if base is not None:
            return [base, base, base], True
    return [(0x85, 0x99, 0x00), (0xB5, 0x89, 0x00), (0xDC, 0x32, 0x2F)], True


def build(skin: Skin) -> Theme:
    """Convert a parsed skin into a legible cliamp theme."""
    invented: list[str] = []
    adjusted: list[str] = []

    bg, bg_invented = _pick_background(skin)
    if bg_invented:
        invented.append("bg")

    # Do this before anything is measured against the background: a saturated
    # mid-tone bg caps how legible every other slot can possibly be, so no
    # amount of foreground work fixes it afterwards.
    bg, bg_darkened = ensure_headroom(bg, TARGET_BRIGHT_FG)
    if bg_darkened and not bg_invented:
        adjusted.append("bg")

    raw_bright = skin.pledit.get("current") or skin.pledit.get("normal")
    if raw_bright is None:
        raw_bright = (0xFF, 0xFF, 0xFF) if lightness(bg) < 0.5 else (0x00, 0x00, 0x00)
        invented.append("bright_fg")

    raw_fg = skin.pledit.get("normal") or skin.pledit.get("current")
    if raw_fg is None:
        # Muted text is the primary text pulled toward the background.
        raw_fg = average([raw_bright, raw_bright, bg]) or raw_bright
        invented.append("fg")

    raw_accent, accent_invented = _pick_accent(skin, bg, raw_bright, raw_fg)
    if accent_invented:
        invented.append("accent")

    ramp, ramp_invented = _pick_spectrum(skin, bg)
    if ramp_invented:
        invented.extend(["green", "yellow", "red"])

    # --- legibility pass -------------------------------------------------
    bright_fg = force_contrast(raw_bright, bg, TARGET_BRIGHT_FG)
    fg = force_contrast(raw_fg, bg, TARGET_FG)
    accent = force_contrast(raw_accent, bg, TARGET_ACCENT)

    raw_ramp = list(ramp)
    ramp = fit_ramp(ramp, bg, min_contrast=TARGET_SPECTRUM, min_step=SPECTRUM_STEP)

    for name, before, after in (
        ("bright_fg", raw_bright, bright_fg),
        ("fg", raw_fg, fg),
        ("accent", raw_accent, accent),
        ("green", raw_ramp[0], ramp[0]),
        ("yellow", raw_ramp[1], ramp[1]),
        ("red", raw_ramp[2], ramp[2]),
    ):
        if before != after and name not in invented:
            adjusted.append(name)

    # If muted and primary text converged, re-separate so the hierarchy cliamp
    # relies on survives.
    if abs(lightness(fg) - lightness(bright_fg)) < 0.08:
        toward_bg = lightness(bg) < lightness(bright_fg)
        fg = force_contrast(fg, bg, TARGET_FG)
        target = lightness(bright_fg) + (-0.12 if toward_bg else 0.12)
        from .color import set_lightness

        candidate = set_lightness(fg, max(0.0, min(1.0, target)))
        if contrast(candidate, bg) >= TARGET_FG - 0.5:
            fg = candidate
            if "fg" not in adjusted and "fg" not in invented:
                adjusted.append("fg")

    return Theme(
        bg=bg,
        accent=accent,
        bright_fg=bright_fg,
        fg=fg,
        green=ramp[0],
        yellow=ramp[1],
        red=ramp[2],
        source=skin.name,
        adjusted=adjusted,
        invented=invented,
        notes=list(skin.notes),
    )
