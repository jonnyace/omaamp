"""Convert Winamp skins into cliamp themes."""

from .color import contrast, to_hex
from .museum import SkinRef, browse, download, search, total_skins
from .skin import Skin, load
from .theme import SLOTS, Theme, build

__all__ = [
    "SLOTS", "Skin", "SkinRef", "Theme",
    "browse", "build", "contrast", "download", "load", "search",
    "to_hex", "total_skins",
]
