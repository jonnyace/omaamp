#!/usr/bin/env python3
"""Run the converter over a random sample of the museum and grade the output.

    ./bench.py [-n 200] [--seed 7] [--workers 8] [--save-worst 12]

The point is to tune the mapping rules against the real corpus rather than a
handful of skins: ~100k archives written over 25 years, many of them missing
files, mis-cased, or fading their visualizer to black. Downloads are cached
under .cache/ so repeat runs only re-grade.

Grades check the properties the mapping is supposed to guarantee:
  * every slot clears its contrast floor against the chosen background
  * the spectrum stays ordered low -> top and its steps stay separable
  * the theme doesn't collapse into near-identical colors
"""

from __future__ import annotations

import argparse
import concurrent.futures as futures
import random
import statistics
import sys
import zipfile
from collections import Counter
from pathlib import Path

from cliamp_skinner import build, load, museum
from cliamp_skinner.color import (
    POLYCHROME_DEGREES,
    chroma,
    contrast,
    hue_spread,
    lightness,
)
from cliamp_skinner.theme import (
    SLOTS,
    TARGET_ACCENT,
    TARGET_BRIGHT_FG,
    TARGET_FG,
    TARGET_SPECTRUM,
    SPECTRUM_STEP,
)

CACHE = Path(__file__).parent / ".cache"
TARGETS = {
    "bright_fg": TARGET_BRIGHT_FG,
    "fg": TARGET_FG,
    "accent": TARGET_ACCENT,
    "green": TARGET_SPECTRUM,
    "yellow": TARGET_SPECTRUM,
    "red": TARGET_SPECTRUM,
}


def fetch(ref: museum.SkinRef) -> bytes | None:
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{ref.md5}.wsz"
    if path.exists():
        return path.read_bytes()
    try:
        data = museum.download(ref)
    except Exception:
        return None
    path.write_bytes(data)
    return data


def sample(n: int, seed: int, workers: int) -> list[museum.SkinRef]:
    """Pull refs from random windows across the whole catalog."""
    total = museum.total_skins()
    rng = random.Random(seed)
    page = 40
    offsets = [rng.randrange(0, max(1, total - page)) for _ in range((n // page) + 1)]
    refs: dict[str, museum.SkinRef] = {}
    with futures.ThreadPoolExecutor(workers) as pool:
        for got in pool.map(lambda o: museum.browse(first=page, offset=o), offsets):
            for ref in got:
                refs[ref.md5] = ref
    out = list(refs.values())
    rng.shuffle(out)
    return out[:n]


def grade(theme) -> list[str]:
    """Return the list of properties this theme violates."""
    fails = []
    ratios = theme.contrasts()
    for slot, target in TARGETS.items():
        # Half a point of slack: the search converges to the target, and a
        # rounding step to 8-bit channels can shave a hair off.
        if ratios[slot] < target - 0.5:
            fails.append(f"contrast:{slot}")

    # The ramp's three steps must be tellable apart, but they are allowed to do
    # that by hue instead of lightness -- Winamp's own red/yellow/green ramp is
    # deliberately non-monotonic in lightness, so a lightness-only check would
    # flag the canonical case as broken.
    ramp = [theme.green, theme.yellow, theme.red]
    ls = [lightness(c) for c in ramp]
    if hue_spread(ramp) < POLYCHROME_DEGREES:
        if not (ls[0] < ls[1] < ls[2] or ls[0] > ls[1] > ls[2]):
            fails.append("ramp:unordered")
        if min(abs(ls[1] - ls[0]), abs(ls[2] - ls[1])) < SPECTRUM_STEP - 0.02:
            fails.append("ramp:crowded")

    seen = [getattr(theme, s) for s in SLOTS]
    if len({tuple(c) for c in seen}) < len(seen) - 1:
        fails.append("theme:collapsed")
    return fails


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--count", type=int, default=200)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--save-worst", type=int, default=0, help="write N failing themes to out/")
    args = ap.parse_args()

    print(f"sampling {args.count} skins from the museum...", file=sys.stderr)
    refs = sample(args.count, args.seed, args.workers)
    print(f"got {len(refs)} refs; downloading...", file=sys.stderr)

    with futures.ThreadPoolExecutor(args.workers) as pool:
        blobs = list(pool.map(fetch, refs))

    sources = Counter()
    fails = Counter()
    invented = Counter()
    adjusted = Counter()
    ratios: dict[str, list[float]] = {s: [] for s in TARGETS}
    accent_chroma: list[float] = []
    bad: list[tuple[museum.SkinRef, object, list[str]]] = []
    ok = 0

    for ref, data in zip(refs, blobs):
        if data is None:
            sources["download failed"] += 1
            continue
        try:
            skin = load(data, name=ref.filename or ref.md5)
        except (zipfile.BadZipFile, OSError, ValueError):
            sources["unreadable archive"] += 1
            continue

        sources["has pledit.txt"] += bool(skin.has_text_colors)
        sources["has viscolor.txt"] += bool(skin.has_spectrum)
        sources["fell back to artwork"] += bool(skin.artwork)
        sources["parsed"] += 1

        theme = build(skin)
        for slot in TARGETS:
            ratios[slot].append(theme.contrasts()[slot])
        accent_chroma.append(chroma(theme.accent))
        for slot in set(theme.invented):
            invented[slot] += 1
        for slot in set(theme.adjusted):
            adjusted[slot] += 1

        problems = grade(theme)
        if problems:
            for p in problems:
                fails[p] += 1
            bad.append((ref, theme, problems))
        else:
            ok += 1

    n = sources["parsed"]
    print(f"\n{'='*62}\nCORPUS  ({len(refs)} sampled)")
    for k, v in sources.most_common():
        pct = f"{100*v/n:5.1f}%" if n and k != "parsed" else ""
        print(f"  {v:5}  {pct:7} {k}")

    print(f"\nGRADE   {ok}/{n} clean ({100*ok/max(1,n):.1f}%)")
    if fails:
        for k, v in fails.most_common():
            print(f"  {v:5}  {100*v/n:5.1f}%  {k}")
    else:
        print("  no violations")

    print("\nCONTRAST  (target / min / median achieved)")
    for slot, target in TARGETS.items():
        vals = ratios[slot]
        if vals:
            print(f"  {slot:10} {target:5.1f}  {min(vals):6.2f}  {statistics.median(vals):6.2f}")

    if accent_chroma:
        grey = sum(1 for c in accent_chroma if c < 0.03)
        print(f"\nACCENT    {grey}/{len(accent_chroma)} nearly greyscale "
              f"({100*grey/len(accent_chroma):.1f}%), median chroma {statistics.median(accent_chroma):.3f}")

    if invented or adjusted:
        print("\nREPAIRS   slot: invented / adjusted")
        for slot in SLOTS:
            i, a = invented.get(slot, 0), adjusted.get(slot, 0)
            if i or a:
                print(f"  {slot:10} {i:5} ({100*i/n:4.1f}%) / {a:5} ({100*a/n:4.1f}%)")

    if args.save_worst and bad:
        out = Path(__file__).parent / "out" / "failures"
        out.mkdir(parents=True, exist_ok=True)
        print(f"\nWORST     writing {min(args.save_worst, len(bad))} to {out}/")
        for ref, theme, problems in bad[: args.save_worst]:
            (out / f"{ref.md5[:8]}.toml").write_text(
                theme.to_toml() + "# fails: " + ", ".join(problems) + f"\n# {ref.museum_url}\n"
            )
            print(f"  {ref.md5[:8]}  {ref.filename[:38]:40} {', '.join(problems)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
