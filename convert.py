#!/usr/bin/env python3
"""Convert Winamp skins to cliamp themes.

    ./convert.py file <skin.wsz> [-o DIR]     convert a local skin
    ./convert.py search <term> [-n N] [-o DIR]  convert museum search results
    ./convert.py md5 <md5> [-o DIR]           convert one museum skin

With no -o, themes are written to ~/.config/cliamp/themes/ and are immediately
selectable with `cliamp theme <name>` or the in-player picker (press `t`).
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

from cliamp_skinner import build, download, load, museum, search, to_hex
from cliamp_skinner.theme import SLOTS

DEFAULT_OUT = Path.home() / ".config" / "cliamp" / "themes"


def slugify(name: str) -> str:
    stem = re.sub(r"\.(wsz|zip|wal)$", "", name, flags=re.I)
    slug = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
    return slug or "skin"


def convert(data: bytes, name: str, out_dir: Path, *, quiet: bool = False) -> Path | None:
    try:
        skin = load(data, name=name)
    except (zipfile.BadZipFile, OSError) as exc:
        print(f"  ! {name}: unreadable archive ({exc})", file=sys.stderr)
        return None

    theme = build(skin)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{slugify(name)}.toml"
    path.write_text(theme.to_toml())

    if not quiet:
        swatches = "  ".join(f"{s}={to_hex(getattr(theme, s))}" for s in SLOTS)
        print(f"  {path.name}\n    {swatches}")
        if theme.invented:
            print(f"    invented: {', '.join(sorted(set(theme.invented)))}")
        if theme.adjusted:
            print(f"    adjusted for legibility: {', '.join(theme.adjusted)}")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out", type=Path, default=DEFAULT_OUT, help="output directory")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_file = sub.add_parser("file", help="convert a local .wsz")
    p_file.add_argument("paths", nargs="+", type=Path)

    p_search = sub.add_parser("search", help="convert museum search results")
    p_search.add_argument("term")
    p_search.add_argument("-n", "--count", type=int, default=5)

    p_md5 = sub.add_parser("md5", help="convert one museum skin by md5")
    p_md5.add_argument("md5")

    args = ap.parse_args()

    if args.cmd == "file":
        for path in args.paths:
            print(f"{path}:")
            convert(path.read_bytes(), path.name, args.out)
    elif args.cmd == "search":
        refs = search(args.term, first=args.count)
        if not refs:
            print(f"no skins matched {args.term!r}")
            return 1
        print(f"{len(refs)} skin(s) for {args.term!r}:")
        for ref in refs:
            print(f"{ref.filename}  ({ref.md5[:8]})")
            convert(download(ref), ref.filename or ref.md5, args.out)
    elif args.cmd == "md5":
        data = museum.query(
            'query($m:String!){fetch_skin_by_md5(md5:$m){... on ClassicSkin{md5 filename download_url}}}',
            {"m": args.md5},
        )["fetch_skin_by_md5"]
        if not data:
            print(f"no skin with md5 {args.md5}", file=sys.stderr)
            return 1
        print(f"{data['filename']}:")
        convert(download(data["download_url"]), data["filename"] or args.md5, args.out)

    print(f"\n-> {args.out}\n   apply with:  cliamp theme <name>")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
