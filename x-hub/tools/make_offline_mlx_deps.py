"""Build an offline site-packages bundle for Hub MLX runtime.

Use case
- Teammates have no internet (or only internal network).
- They can install Python, but cannot `pip install` from PyPI.

This script copies the installed distributions for mlx-lm (and its dependency
closure) into a portable folder that can be copied into the user's site-packages.

It is intentionally simple: it relies on packages being installed on *this*
machine already.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from importlib import metadata
from pathlib import Path


def _norm(name: str) -> str:
    return str(name or "").strip().lower().replace("_", "-")


def _dist_requires(dist: metadata.Distribution) -> list[str]:
    reqs = []
    for r in dist.requires or []:
        # e.g. "numpy>=1.26" -> "numpy"
        s = str(r).strip()
        if not s:
            continue
        # Drop optional extras (dev/test) requirements.
        if ";" in s:
            name_part, marker = s.split(";", 1)
            if "extra" in marker:
                continue
            s = name_part.strip()

        name = s.split("[", 1)[0].strip()
        # Strip version specifiers.
        for sym in ("<", ">", "=", "!", "~"):
            if sym in name:
                name = name.split(sym, 1)[0].strip()
        name = name.split(" ", 1)[0].strip()
        if name:
            reqs.append(name)
    return reqs


def _copy_dist_files(dist: metadata.Distribution, dst_site: Path) -> int:
    count = 0
    files = list(dist.files or [])
    if not files:
        return 0
    # dist.locate_file gives full path relative to distribution root.
    for f in files:
        src = Path(dist.locate_file(f))
        # Some entries may be missing on disk; skip.
        if not src.exists():
            continue
        rel = Path(f)
        out = dst_site / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            # Avoid recursively copying directory entries multiple times.
            continue
        shutil.copy2(src, out)
        count += 1
    return count


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="Output folder (will be created/overwritten)")
    ap.add_argument(
        "--roots",
        default="mlx-lm,mlx,mlx-metal",
        help="Comma-separated root dists to include (default: mlx-lm,mlx,mlx-metal)",
    )
    args = ap.parse_args()

    out_dir = Path(args.out).expanduser().resolve()
    dst_site = out_dir / "site-packages"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    dst_site.mkdir(parents=True, exist_ok=True)

    roots = [_norm(x) for x in str(args.roots).split(",") if _norm(x)]
    if not roots:
        print("No roots specified", file=sys.stderr)
        return 2

    # Build dependency closure.
    want: set[str] = set(roots)
    q: list[str] = list(roots)
    seen: set[str] = set()

    while q:
        name = _norm(q.pop(0))
        if not name or name in seen:
            continue
        seen.add(name)
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            print(f"Missing dist: {name} (install it on this machine first)", file=sys.stderr)
            continue
        for dep in _dist_requires(dist):
            dn = _norm(dep)
            if dn and dn not in want:
                want.add(dn)
                q.append(dn)

    # Copy all selected distributions.
    total_files = 0
    copied: list[str] = []
    for name in sorted(want):
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            continue
        n = _copy_dist_files(dist, dst_site)
        total_files += n
        copied.append(f"{name} ({n} files)")

    # Small README.
    readme = out_dir / "README_INSTALL.txt"
    pyver = f"{sys.version_info.major}.{sys.version_info.minor}"
    readme.write_text(
        "\n".join(
            [
                "X-Hub - Offline MLX deps",
                "",
                f"Built with python={sys.executable}",
                f"py_version={pyver}",
                "",
                "Install (on teammate machine):",
                "1) Ensure Python 3.11 is installed (python.org installer recommended)",
                "2) Copy this folder to the teammate machine",
                "3) Run:",
                f"   mkdir -p ~/Library/Python/{pyver}/lib/python/site-packages",
                f"   cp -R site-packages/* ~/Library/Python/{pyver}/lib/python/site-packages/",
                "4) In Hub Settings -> AI Runtime -> Python, set:",
                "   /Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
                "",
                "Included dists:",
                *copied,
                "",
            ]
        ),
        encoding="utf-8",
    )

    print(f"Wrote: {out_dir}")
    print(f"Total files: {total_files}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
