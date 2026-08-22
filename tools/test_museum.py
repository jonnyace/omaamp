#!/usr/bin/env python3
"""Tests for user-facing Skin Museum references."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cliamp_skinner import museum


MD5 = "5e4f10275dcb1fb211d4a8b4f1bda236"


class SkinReferences(unittest.TestCase):
    def test_accepts_literal_id(self):
        self.assertEqual(museum.skin_md5(MD5.upper()), MD5)

    def test_accepts_copied_museum_link(self):
        self.assertEqual(
            museum.skin_md5(f"  https://skins.webamp.org/skin/{MD5}  "),
            MD5,
        )

    def test_accepts_trailing_slash_query_and_fragment(self):
        self.assertEqual(
            museum.skin_md5(
                f"https://skins.webamp.org/skin/{MD5}/?ref=share#player"
            ),
            MD5,
        )

    def test_rejects_lookalike_host(self):
        with self.assertRaisesRegex(ValueError, "skins.webamp.org"):
            museum.skin_md5(f"https://skins.webamp.org.example/skin/{MD5}")

    def test_rejects_insecure_or_wrong_path(self):
        for value in (
            f"http://skins.webamp.org/skin/{MD5}",
            f"https://skins.webamp.org/download/{MD5}",
            f"https://user@skins.webamp.org/skin/{MD5}",
        ):
            with self.subTest(value=value), self.assertRaises(ValueError):
                museum.skin_md5(value)


if __name__ == "__main__":
    unittest.main()
