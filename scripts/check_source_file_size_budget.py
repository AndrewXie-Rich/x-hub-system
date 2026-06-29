#!/usr/bin/env python3
"""Fail when source files grow beyond the checked-in size budget."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


DEFAULT_BUDGET_PATH = Path("scripts/source_file_size_budget.v1.json")
DEFAULT_MAX_LINES = 1500
SCAN_ROOTS = (
    (Path("rust/xhubd/crates"), {".rs"}),
    (Path("x-hub/macos/RELFlowHub/Sources"), {".swift"}),
    (Path("x-terminal/Sources"), {".swift"}),
)
SKIP_DIR_NAMES = {".build", ".git", "target", "DerivedData"}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def iter_source_files(root: Path) -> Iterable[Path]:
    base = repo_root()
    for relative_root, suffixes in SCAN_ROOTS:
        scan_root = base / relative_root
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            if not path.is_file() or path.suffix not in suffixes:
                continue
            if any(part in SKIP_DIR_NAMES for part in path.relative_to(base).parts):
                continue
            yield path


def count_lines(path: Path) -> int:
    with path.open("rb") as handle:
        return sum(1 for _ in handle)


def load_budget(path: Path) -> Tuple[int, Dict[str, int]]:
    if not path.exists():
        return DEFAULT_MAX_LINES, {}
    data = json.loads(path.read_text())
    max_lines = int(data.get("default_max_lines", DEFAULT_MAX_LINES))
    budgets = {
        str(key): int(value)
        for key, value in data.get("budgets", {}).items()
    }
    return max_lines, budgets


def write_baseline(path: Path, max_lines: int) -> None:
    base = repo_root()
    budgets = {}
    for source in iter_source_files(base):
        rel = source.relative_to(base).as_posix()
        lines = count_lines(source)
        if lines > max_lines:
            budgets[rel] = lines
    payload = {
        "schema_version": "xhub.source_file_size_budget.v1",
        "default_max_lines": max_lines,
        "policy": "New files above default_max_lines fail. Baseline files fail if they grow.",
        "budgets": dict(sorted(budgets.items())),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n")
    print(f"wrote {path} with {len(budgets)} baseline entries")


def check_budget(path: Path) -> int:
    base = repo_root()
    max_lines, budgets = load_budget(path)
    failures: List[str] = []
    over_budget_count = 0

    for source in sorted(iter_source_files(base)):
        rel = source.relative_to(base).as_posix()
        lines = count_lines(source)
        if lines <= max_lines:
            continue
        over_budget_count += 1
        allowed = budgets.get(rel)
        if allowed is None:
            failures.append(f"new oversized file: {rel} has {lines} lines > {max_lines}")
        elif lines > allowed:
            failures.append(f"oversized file grew: {rel} has {lines} lines > budget {allowed}")

    if failures:
        print("source file size budget failed:")
        for failure in failures:
            print(f"  - {failure}")
        print(f"budget file: {path}")
        return 1

    print(
        f"source file size budget passed: {over_budget_count} files above {max_lines} lines, none grew"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--budget",
        default=str(DEFAULT_BUDGET_PATH),
        help="Budget JSON path relative to repo root",
    )
    parser.add_argument(
        "--max-lines",
        type=int,
        default=DEFAULT_MAX_LINES,
        help="Default max lines for new files when writing a baseline",
    )
    parser.add_argument(
        "--write-baseline",
        action="store_true",
        help="Write the current over-threshold files as the baseline",
    )
    args = parser.parse_args()

    budget_path = repo_root() / args.budget
    if args.write_baseline:
        write_baseline(budget_path, args.max_lines)
        return 0
    return check_budget(budget_path)


if __name__ == "__main__":
    raise SystemExit(main())
