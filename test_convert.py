#!/usr/bin/env python3
"""Invariants for the skin -> theme mapping.

Every case here is a bug that actually showed up while benching against the
museum, so they are kept as regressions rather than as illustrations.

    python3 -m unittest test_convert -v
"""

from __future__ import annotations

import io
import unittest
import zipfile

from cliamp_skinner import build, load
from cliamp_skinner.color import (
    POLYCHROME_DEGREES,
    chroma,
    contrast,
    ensure_headroom,
    fit_ramp,
    force_contrast,
    hue_spread,
    lightness,
    oklab_to_rgb,
    rgb_to_oklab,
    set_lightness,
)
from cliamp_skinner.skin import parse_pledit, parse_viscolor
from cliamp_skinner.theme import (
    SLOTS,
    TARGET_BRIGHT_FG,
    TARGET_SPECTRUM,
    SPECTRUM_STEP,
)

BLACK, WHITE = (0, 0, 0), (255, 255, 255)

# Winamp's own default analyzer ramp, top of bar first.
CLASSIC_RAMP = [(239, 49, 16), (222, 214, 0), (0, 222, 0)]


def make_wsz(pledit: str | None = None, viscolor: str | None = None, extra: dict | None = None) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        if pledit is not None:
            zf.writestr("pledit.txt", pledit)
        if viscolor is not None:
            zf.writestr("viscolor.txt", viscolor)
        for name, data in (extra or {}).items():
            zf.writestr(name, data)
    return buf.getvalue()


class ColorMath(unittest.TestCase):
    def test_oklab_round_trip(self):
        for rgb in [(0, 0, 0), (255, 255, 255), (18, 52, 86), (239, 49, 16)]:
            self.assertEqual(oklab_to_rgb(rgb_to_oklab(rgb)), rgb)

    def test_set_lightness_preserves_hue(self):
        red = (200, 30, 30)
        _, a0, b0 = rgb_to_oklab(red)
        _, a1, b1 = rgb_to_oklab(set_lightness(red, 0.75))
        # Hue angle, not chroma: chroma may be reduced to stay in gamut.
        self.assertAlmostEqual(b0 / a0, b1 / a1, places=1)

    def test_force_contrast_reaches_target(self):
        self.assertGreaterEqual(contrast(force_contrast((10, 10, 10), BLACK, 7.0), BLACK), 6.9)

    def test_force_contrast_desaturates_when_hue_cannot_reach(self):
        # Pure red on black tops out near 5.25:1, so 7.0 requires giving up
        # chroma rather than failing.
        out = force_contrast((255, 0, 0), BLACK, 7.0)
        self.assertGreaterEqual(contrast(out, BLACK), 6.9)
        self.assertLess(chroma(out), chroma((255, 0, 0)))


class Ramps(unittest.TestCase):
    def test_polychrome_ramp_keeps_non_monotonic_lightness(self):
        """Winamp's default ramp is separated by hue, not lightness.

        Its yellow is lighter than both neighbours; restacking it into an
        ascending band would destroy the most recognizable thing about it.
        """
        self.assertGreaterEqual(hue_spread(CLASSIC_RAMP), POLYCHROME_DEGREES)
        out = fit_ramp(list(CLASSIC_RAMP), BLACK, min_contrast=TARGET_SPECTRUM, min_step=SPECTRUM_STEP)
        ls = [lightness(c) for c in out]
        self.assertGreater(ls[1], ls[0])
        self.assertGreater(ls[1], ls[2])

    def test_monochrome_ramp_is_spread_and_ordered(self):
        mono = [(0, 20, 0), (0, 40, 0), (0, 60, 0)]
        out = fit_ramp(mono, BLACK, min_contrast=TARGET_SPECTRUM, min_step=SPECTRUM_STEP)
        ls = [lightness(c) for c in out]
        self.assertLess(ls[0], ls[1])
        self.assertLess(ls[1], ls[2])
        for c in out:
            self.assertGreaterEqual(contrast(c, BLACK), TARGET_SPECTRUM - 0.2)

    def test_black_ramp_step_keeps_the_ramp_hue(self):
        """A step that fades to pure black must not resurface as grey."""
        out = fit_ramp([(0, 0, 0), (0, 60, 0), (0, 120, 0)], BLACK,
                       min_contrast=TARGET_SPECTRUM, min_step=SPECTRUM_STEP)
        self.assertGreater(chroma(out[0]), 0.03, f"lifted black step went grey: {out[0]}")

    def test_identical_steps_are_separated(self):
        """Two equal steps must part even when a third makes the ramp polychrome."""
        out = fit_ramp([(200, 160, 120), (200, 160, 120), (60, 90, 100)], BLACK,
                       min_contrast=TARGET_SPECTRUM, min_step=SPECTRUM_STEP)
        self.assertNotEqual(out[0], out[1])


class Backgrounds(unittest.TestCase):
    def test_saturated_background_gains_headroom(self):
        out, changed = ensure_headroom((255, 0, 0), TARGET_BRIGHT_FG)
        self.assertTrue(changed)
        self.assertGreaterEqual(max(contrast(WHITE, out), contrast(BLACK, out)), TARGET_BRIGHT_FG)
        # Still recognizably red, not flattened to grey.
        self.assertGreater(chroma(out), 0.03)

    def test_usable_background_is_left_alone(self):
        out, changed = ensure_headroom(BLACK, TARGET_BRIGHT_FG)
        self.assertFalse(changed)
        self.assertEqual(out, BLACK)


class Parsing(unittest.TestCase):
    def test_pledit_tolerates_case_and_missing_hash(self):
        got = parse_pledit("[Text]\nNormal=#00FCFC\nCurrent=ffffff\nFont=Tahoma\n")
        self.assertEqual(got["normal"], (0, 252, 252))
        self.assertEqual(got["current"], (255, 255, 255))
        self.assertNotIn("font", got)

    def test_viscolor_ignores_comments_and_junk(self):
        got = parse_viscolor("0,0,0\t// bg\nnot a color\n0,252,252   // top\n")
        self.assertEqual(got, [(0, 0, 0), (0, 252, 252)])

    def test_nested_and_uppercase_members_are_found(self):
        data = make_wsz()
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("MySkin/PLEDIT.TXT", "Normal=#112233\nNormalBG=#000000\n")
        skin = load(buf.getvalue(), "nested")
        self.assertEqual(skin.pledit["normal"], (0x11, 0x22, 0x33))


class EndToEnd(unittest.TestCase):
    def build(self, **kw):
        return build(load(make_wsz(**kw), "t"))

    def test_every_slot_clears_its_floor(self):
        theme = self.build(
            pledit="Normal=#007900\nCurrent=#33D52B\nNormalBG=#000000\nSelectedBG=#002F00\n",
            viscolor="\n".join(["0,0,0", "0,0,0"] + [f"0,{v},0" for v in range(102, 6, -6)]),
        )
        for slot, ratio in theme.contrasts().items():
            self.assertGreaterEqual(ratio, 2.8, f"{slot} unreadable at {ratio:.2f}")

    def test_missing_files_still_yield_a_complete_theme(self):
        theme = self.build()
        for slot in SLOTS:
            self.assertIsNotNone(getattr(theme, slot))
        self.assertTrue(theme.invented)
        self.assertIn("no pledit.txt", theme.notes)

    def test_toml_output_is_parseable_and_complete(self):
        import tomllib

        text = self.build(pledit="Normal=#007900\nCurrent=#33D52B\nNormalBG=#000000\n").to_toml()
        parsed = tomllib.loads(text)
        self.assertEqual(set(parsed), set(SLOTS))
        for value in parsed.values():
            self.assertRegex(value, r"^#[0-9a-f]{6}$")


if __name__ == "__main__":
    unittest.main()
