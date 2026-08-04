#!/usr/bin/env python3
"""Create and verify fail-closed X-Terminal doctor snapshot inventories."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Iterable


SCHEMA_VERSION = "xhub.xt_doctor_diagnostic_snapshot_inventory.v1"
COMPONENT = "x-terminal"
REQUIRED_MARKERS = (
    "x-terminal/Package.swift",
    "x-terminal/tools/build_xterminal_app.command",
)


class InventoryError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise InventoryError(message)


def run_git(repo_root: Path, args: Iterable[str], *, allow_failure: bool = False) -> bytes:
    result = subprocess.run(
        ["git", "-C", os.fspath(repo_root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0 and not allow_failure:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        fail(f"git {' '.join(args)} failed: {detail or f'exit {result.returncode}'}")
    return result.stdout if result.returncode == 0 else b""


def resolve_existing_directory(raw_path: str, label: str) -> Path:
    path = Path(raw_path).expanduser()
    try:
        metadata = path.lstat()
    except OSError as error:
        fail(f"{label} is unavailable: {path}: {error}")
    if stat.S_ISLNK(metadata.st_mode):
        fail(f"{label} must not be a symlink: {path}")
    if not stat.S_ISDIR(metadata.st_mode):
        fail(f"{label} is not a directory: {path}")
    return Path(os.path.realpath(path))


def assert_canonical_repo(repo_root_raw: str) -> tuple[Path, Path, str]:
    repo_root = resolve_existing_directory(repo_root_raw, "repository root")
    git_root_raw = run_git(repo_root, ["rev-parse", "--show-toplevel"])
    git_root = Path(os.path.realpath(os.fsdecode(git_root_raw).strip()))
    if git_root != repo_root:
        fail(f"repository root is not the canonical Git worktree root: {repo_root}")

    marker_output = run_git(
        repo_root,
        ["ls-files", "--error-unmatch", *REQUIRED_MARKERS],
        allow_failure=True,
    )
    marker_paths = {line for line in os.fsdecode(marker_output).splitlines() if line}
    if marker_paths != set(REQUIRED_MARKERS):
        fail("canonical X-Terminal markers are not tracked by the repository")

    component_root = resolve_existing_directory(
        os.fspath(repo_root / COMPONENT), "canonical X-Terminal root"
    )
    expected_component_root = Path(os.path.realpath(repo_root / COMPONENT))
    if component_root != expected_component_root:
        fail("canonical X-Terminal root does not resolve inside the repository")

    head_output = run_git(repo_root, ["rev-parse", "--verify", "HEAD"], allow_failure=True)
    source_git_head = os.fsdecode(head_output).strip() or "UNBORN"
    return repo_root, component_root, source_git_head


def sha256_regular_file(path: Path, label: str) -> str:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        fail(f"cannot open {label}: {path}: {error}")
    digest = hashlib.sha256()
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            fail(f"{label} is not a regular file: {path}")
        with os.fdopen(descriptor, "rb", closefd=False) as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
    finally:
        os.close(descriptor)
    return digest.hexdigest()


def normalize_relative_path(path: str) -> str:
    candidate = PurePosixPath(path)
    if not path or candidate.is_absolute() or path != candidate.as_posix():
        fail(f"inventory contains a non-canonical relative path: {path!r}")
    if any(part in ("", ".", "..") for part in candidate.parts):
        fail(f"inventory contains an unsafe relative path: {path!r}")
    return path


def canonical_entries(repo_root: Path, component_root: Path) -> dict[str, str]:
    output = run_git(
        repo_root,
        [
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            COMPONENT,
        ],
    )
    entries: dict[str, str] = {}
    component_prefix = f"{COMPONENT}/"
    for encoded_path in output.split(b"\0"):
        if not encoded_path:
            continue
        repo_relative_path = os.fsdecode(encoded_path)
        if not repo_relative_path.startswith(component_prefix):
            fail(f"git returned a path outside {COMPONENT}: {repo_relative_path!r}")
        relative_path = normalize_relative_path(repo_relative_path[len(component_prefix) :])
        source_path = repo_root / Path(repo_relative_path)
        try:
            metadata = source_path.lstat()
        except FileNotFoundError:
            # A tracked deletion is part of the current worktree state and is
            # therefore intentionally absent from its diagnostic snapshot.
            continue
        except OSError as error:
            fail(f"cannot inspect canonical source file {repo_relative_path}: {error}")
        if stat.S_ISLNK(metadata.st_mode):
            fail(f"canonical source symlinks are not allowed: {repo_relative_path}")
        if not stat.S_ISREG(metadata.st_mode):
            fail(f"canonical source entry is not a regular file: {repo_relative_path}")
        resolved_parent = Path(os.path.realpath(source_path.parent))
        if resolved_parent != component_root and component_root not in resolved_parent.parents:
            fail(f"canonical source path escapes {COMPONENT}: {repo_relative_path}")
        if relative_path in entries:
            fail(f"duplicate canonical source path: {relative_path}")
        entries[relative_path] = sha256_regular_file(source_path, "canonical source file")

    for marker in REQUIRED_MARKERS:
        relative_marker = marker[len(component_prefix) :]
        if relative_marker not in entries:
            fail(f"canonical source marker is missing from the worktree: {marker}")
    if not entries:
        fail("canonical X-Terminal source inventory is empty")
    return entries


def snapshot_entries(snapshot_root: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for current_root_raw, directory_names, file_names in os.walk(
        snapshot_root, topdown=True, followlinks=False
    ):
        current_root = Path(current_root_raw)
        for directory_name in list(directory_names):
            directory_path = current_root / directory_name
            try:
                metadata = directory_path.lstat()
            except OSError as error:
                fail(f"cannot inspect snapshot directory {directory_path}: {error}")
            if stat.S_ISLNK(metadata.st_mode):
                fail(
                    "snapshot symlinks are not allowed: "
                    + (directory_path.relative_to(snapshot_root).as_posix())
                )
            if not stat.S_ISDIR(metadata.st_mode):
                fail(
                    "snapshot entry is not a directory: "
                    + (directory_path.relative_to(snapshot_root).as_posix())
                )

        for file_name in file_names:
            file_path = current_root / file_name
            relative_path = normalize_relative_path(
                file_path.relative_to(snapshot_root).as_posix()
            )
            try:
                metadata = file_path.lstat()
            except OSError as error:
                fail(f"cannot inspect snapshot file {relative_path}: {error}")
            if stat.S_ISLNK(metadata.st_mode):
                fail(f"snapshot symlinks are not allowed: {relative_path}")
            if not stat.S_ISREG(metadata.st_mode):
                fail(f"snapshot entry is not a regular file: {relative_path}")
            if relative_path in entries:
                fail(f"duplicate snapshot path: {relative_path}")
            entries[relative_path] = sha256_regular_file(file_path, "snapshot file")
    return entries


def inventory_fingerprint(entries: dict[str, str]) -> str:
    digest = hashlib.sha256()
    for relative_path, file_hash in sorted(entries.items()):
        digest.update(relative_path.encode("utf-8", errors="surrogateescape"))
        digest.update(b"\0")
        digest.update(file_hash.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def describe_mismatch(expected: dict[str, str], actual: dict[str, str], label: str) -> None:
    expected_paths = set(expected)
    actual_paths = set(actual)
    missing = sorted(expected_paths - actual_paths)
    extra = sorted(actual_paths - expected_paths)
    changed = sorted(
        path for path in expected_paths & actual_paths if expected[path] != actual[path]
    )
    if not (missing or extra or changed):
        return

    details = []
    if missing:
        details.append("missing=" + ",".join(missing[:8]))
    if extra:
        details.append("extra=" + ",".join(extra[:8]))
    if changed:
        details.append("changed=" + ",".join(changed[:8]))
    fail(f"{label} inventory mismatch ({'; '.join(details)})")


def assert_inventory_outside_source_roots(
    inventory_path_raw: str, snapshot_root: Path, repo_root: Path
) -> Path:
    inventory_path = Path(inventory_path_raw).expanduser().absolute()
    inventory_real_parent = Path(os.path.realpath(inventory_path.parent))
    inventory_real = inventory_real_parent / inventory_path.name
    if inventory_real == snapshot_root or snapshot_root in inventory_real.parents:
        fail("inventory must be stored outside the X-Terminal snapshot root")
    if inventory_real == repo_root or repo_root in inventory_real.parents:
        fail("inventory must be stored outside the canonical repository root")
    return inventory_real


def build_payload(
    repo_root: Path, source_git_head: str, entries: dict[str, str]
) -> dict[str, object]:
    sorted_entries = [
        {"path": relative_path, "sha256": entries[relative_path]}
        for relative_path in sorted(entries)
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "component": COMPONENT,
        "source_repo_root_realpath": os.fspath(repo_root),
        "source_git_head": source_git_head,
        "file_count": len(sorted_entries),
        "inventory_sha256": inventory_fingerprint(entries),
        "files": sorted_entries,
    }


def write_payload_atomic(inventory_path: Path, payload: dict[str, object]) -> None:
    inventory_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=inventory_path.parent,
            prefix=f".{inventory_path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temporary_path = handle.name
            json.dump(payload, handle, ensure_ascii=True, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, inventory_path)
        temporary_path = None
    finally:
        if temporary_path:
            try:
                os.unlink(temporary_path)
            except FileNotFoundError:
                pass


def parse_manifest(inventory_path: Path) -> tuple[dict[str, object], dict[str, str]]:
    try:
        metadata = inventory_path.lstat()
    except OSError as error:
        fail(f"snapshot inventory is unavailable: {inventory_path}: {error}")
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        fail(f"snapshot inventory must be a regular non-symlink file: {inventory_path}")
    try:
        with inventory_path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"cannot read snapshot inventory {inventory_path}: {error}")
    if not isinstance(payload, dict):
        fail("snapshot inventory root must be a JSON object")
    if payload.get("schema_version") != SCHEMA_VERSION:
        fail("snapshot inventory schema_version is unsupported")
    if payload.get("component") != COMPONENT:
        fail("snapshot inventory component is not x-terminal")
    files = payload.get("files")
    if not isinstance(files, list):
        fail("snapshot inventory files must be an array")

    entries: dict[str, str] = {}
    for index, item in enumerate(files):
        if not isinstance(item, dict) or set(item) != {"path", "sha256"}:
            fail(f"snapshot inventory file entry {index} is malformed")
        relative_path_raw = item.get("path")
        file_hash = item.get("sha256")
        if not isinstance(relative_path_raw, str):
            fail(f"snapshot inventory file entry {index} has an invalid path")
        relative_path = normalize_relative_path(relative_path_raw)
        if (
            not isinstance(file_hash, str)
            or len(file_hash) != 64
            or any(character not in "0123456789abcdef" for character in file_hash)
        ):
            fail(f"snapshot inventory file entry {relative_path} has an invalid SHA-256")
        if relative_path in entries:
            fail(f"snapshot inventory contains a duplicate path: {relative_path}")
        entries[relative_path] = file_hash

    if payload.get("file_count") != len(entries):
        fail("snapshot inventory file_count does not match files")
    if payload.get("inventory_sha256") != inventory_fingerprint(entries):
        fail("snapshot inventory fingerprint does not match files")
    return payload, entries


def prepare_context(args: argparse.Namespace) -> tuple[Path, Path, Path, str, dict[str, str]]:
    repo_root, component_root, source_git_head = assert_canonical_repo(args.repo_root)
    snapshot_root = resolve_existing_directory(args.snapshot_root, "diagnostic snapshot root")
    if snapshot_root == repo_root or repo_root in snapshot_root.parents:
        fail("diagnostic snapshot root must be outside the canonical repository root")
    inventory_path = assert_inventory_outside_source_roots(
        args.inventory, snapshot_root, repo_root
    )
    source_entries = canonical_entries(repo_root, component_root)
    return repo_root, snapshot_root, inventory_path, source_git_head, source_entries


def create_inventory(args: argparse.Namespace) -> None:
    repo_root, snapshot_root, inventory_path, source_git_head, source_entries = prepare_context(args)
    actual_entries = snapshot_entries(snapshot_root)
    describe_mismatch(source_entries, actual_entries, "diagnostic snapshot")
    payload = build_payload(repo_root, source_git_head, source_entries)
    write_payload_atomic(inventory_path, payload)
    print(
        f"[xt-doctor-snapshot] inventory_created={inventory_path} "
        f"file_count={len(source_entries)} inventory_sha256={payload['inventory_sha256']}"
    )


def verify_inventory(args: argparse.Namespace) -> None:
    repo_root, snapshot_root, inventory_path, source_git_head, source_entries = prepare_context(args)
    payload, manifest_entries = parse_manifest(inventory_path)
    if payload.get("source_repo_root_realpath") != os.fspath(repo_root):
        fail("snapshot inventory was not created from this canonical repository root")
    if payload.get("source_git_head") != source_git_head:
        fail("snapshot inventory Git HEAD does not match the canonical repository")
    describe_mismatch(source_entries, manifest_entries, "canonical source vs manifest")
    actual_entries = snapshot_entries(snapshot_root)
    describe_mismatch(manifest_entries, actual_entries, "diagnostic snapshot")
    print(
        f"[xt-doctor-snapshot] inventory_verified={inventory_path} "
        f"file_count={len(actual_entries)} inventory_sha256={payload['inventory_sha256']}"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create or verify an exact X-Terminal doctor diagnostic snapshot inventory."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("create", "verify"):
        command_parser = subparsers.add_parser(command)
        command_parser.add_argument("--repo-root", required=True)
        command_parser.add_argument("--snapshot-root", required=True)
        command_parser.add_argument("--inventory", required=True)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "create":
            create_inventory(args)
        else:
            verify_inventory(args)
    except InventoryError as error:
        print(f"[xt-doctor-snapshot] FAIL: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
