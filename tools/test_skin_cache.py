#!/usr/bin/env python3
"""Regressions for the sprite-cache trust boundary."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SKINNER = ROOT / "bin" / "skinner"

loader = importlib.machinery.SourceFileLoader("omaamp_skinner", str(SKINNER))
spec = importlib.util.spec_from_loader(loader.name, loader)
skinner = importlib.util.module_from_spec(spec)
loader.exec_module(skinner)


def archive(entries: list[tuple[str, bytes]], compression=zipfile.ZIP_DEFLATED) -> bytes:
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", compression=compression) as zf:
        for name, payload in entries:
            zf.writestr(name, payload)
    return stream.getvalue()


class SpriteCache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        skinner.SPRITES = Path(self.tmp.name) / "sprites"
        skinner.SKINS = Path(self.tmp.name) / "skins"

    def test_windows_paths_and_last_duplicate_win(self):
        data = archive([
            ("old/MAIN.BMP", b"old"),
            (r"actual\Main.bmp", b"new"),
        ])
        out = skinner.extract_archive(data, "a" * 32)
        self.assertEqual((out / "main.bmp").read_bytes(), b"new")

    def test_balance_borrows_volume_and_manifest_checks_it(self):
        data = archive([("main.bmp", b"main"), ("volume.bmp", b"volume")])
        out = skinner.extract_archive(data, "b" * 32)
        self.assertEqual((out / "balance.bmp").read_bytes(), b"volume")
        manifest = json.loads((out / "manifest.json").read_text())
        self.assertEqual(manifest["files"]["balance.bmp"]["substitute"], "volume.bmp")
        self.assertTrue(skinner._manifest_valid(out, manifest["archive"]))

    def test_a_damaged_immutable_cache_is_replaced_at_a_new_path(self):
        data = archive([("main.bmp", b"main")])
        first = skinner.extract_archive(data, "c" * 32)
        (first / "main.bmp").write_bytes(b"damaged")
        repaired = skinner.extract_archive(data, "c" * 32)
        self.assertNotEqual(repaired, first)
        self.assertEqual((repaired / "main.bmp").read_bytes(), b"main")
        self.assertEqual((first / "main.bmp").read_bytes(), b"damaged")

    def test_unsupported_compression_is_rejected(self):
        data = archive([("main.bmp", b"main")], compression=zipfile.ZIP_BZIP2)
        with self.assertRaisesRegex(ValueError, "unsupported compression"):
            skinner.extract_archive(data, "d" * 32)

    def test_a_skin_without_the_main_window_is_rejected(self):
        data = archive([("text.bmp", b"font")])
        with self.assertRaisesRegex(ValueError, "no main.bmp"):
            skinner.extract_archive(data, "e" * 32)

    def test_local_skin_is_cached_by_content_with_its_display_name(self):
        source = Path(self.tmp.name) / "Local Look.WSZ"
        payload = archive([("main.bmp", b"main")])
        source.write_bytes(payload)
        md5 = skinner.cache_skin_source(str(source))
        self.assertEqual((skinner.SKINS / f"{md5}.wsz").read_bytes(), payload)
        self.assertEqual((skinner.SKINS / f"{md5}.name").read_text(), source.name)

    def test_fallback_overlay_prefers_the_selected_skin(self):
        primary = Path(self.tmp.name) / "primary"
        fallback = Path(self.tmp.name) / "fallback"
        primary.mkdir()
        fallback.mkdir()
        (primary / "main.bmp").write_bytes(b"selected")
        (fallback / "main.bmp").write_bytes(b"baseline")
        (fallback / "cbuttons.bmp").write_bytes(b"controls")
        out = skinner.complete_with_fallback(primary, fallback, "f" * 32)
        self.assertEqual((out / "main.bmp").read_bytes(), b"selected")
        self.assertEqual((out / "cbuttons.bmp").read_bytes(), b"controls")

    def test_region_file_survives_normalization(self):
        data = archive([("main.bmp", b"main"), ("REGION.TXT", b"[Normal]\n")])
        out = skinner.extract_archive(data, "0" * 32)
        self.assertEqual((out / "region.txt").read_bytes(), b"[Normal]\n")


if __name__ == "__main__":
    unittest.main()
