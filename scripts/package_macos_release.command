#!/bin/bash
set -euo pipefail

# Build macOS release assets for GitHub Releases.
# The generated DMGs are release artifacts and must not be committed to Git.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
CHECK_CANONICAL_ROOTS=0
CHECK_RELEASE_INPUTS=0
case "${1:-}" in
  "") ;;
  --check-canonical-roots)
    CHECK_CANONICAL_ROOTS=1
    shift
    ;;
  --check-release-inputs)
    CHECK_RELEASE_INPUTS=1
    shift
    ;;
  -h|--help)
    echo "Usage: $0 [--check-canonical-roots|--check-release-inputs]"
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [--check-canonical-roots|--check-release-inputs]" >&2
    exit 64
    ;;
esac
if [ "$#" -ne 0 ]; then
  echo "Unexpected arguments: $*" >&2
  exit 64
fi

RUST_HUB_SOURCE_ROOT="${XHUB_RUST_HUB_SOURCE_ROOT:-$ROOT_DIR/rust/xhubd}"
XT_SOURCE_ROOT="${XTERMINAL_SOURCE_ROOT:-$ROOT_DIR/x-terminal}"
VERIFIED_RELEASE_TAG=""
RELEASE_REMOTE_TRACKING_REF=""
RELEASE_REMOTE=""
RELEASE_REMOTE_BRANCH=""
RELEASE_REMOTE_COMMIT=""
SOURCE_DATE_EPOCH=""
RUST_PACKAGE_OUTPUT_FILE=""
XT_GATE_SCRATCH_DIR=""
FROZEN_WORKTREE_PARENT=""
FROZEN_WORKTREE_ROOT=""
FROZEN_WORKTREE_REGISTERED=0
RELEASE_REMOTE_TAG_OBJECT=""
RELEASE_REMOTE_TAG_COMMIT=""
RELEASE_DOCTOR_REPORT=""
RELEASE_CODESIGN_IDENTITY="${XHUB_RELEASE_CODESIGN_IDENTITY:-}"
RELEASE_PUBLISHING_REMOTE="origin"
RELEASE_TRUSTED_SIGNERS_FILE="$ROOT_DIR/release/trusted_tag_signers.txt"
VERIFIED_RELEASE_SIGNER=""
HUB_DMG_MOUNT_POINT=""
HUB_DMG_MOUNT_ATTACHED=0
COMBINED_DMG_MOUNT_POINT=""
COMBINED_DMG_MOUNT_ATTACHED=0

# Load the guard from the repository path, never from a caller-selected source.
# shellcheck source=../x-terminal/scripts/lib/canonical_root_guard.sh
source "$ROOT_DIR/x-terminal/scripts/lib/canonical_root_guard.sh"
# shellcheck source=../x-terminal/scripts/lib/release_codesign_guard.sh
source "$ROOT_DIR/x-terminal/scripts/lib/release_codesign_guard.sh"

release_flag_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

release_realpath_dir() {
  local path="${1:-}"
  [ -n "$path" ] && [ -d "$path" ] || return 1
  (cd "$path" && pwd -P)
}

release_epoch_build_number() {
  local epoch="$1"
  if date -u -r "$epoch" +%Y%m%d%H%M%S 2>/dev/null; then
    return
  fi
  if date -u -d "@$epoch" +%Y%m%d%H%M%S 2>/dev/null; then
    return
  fi
  echo "[release] Unable to derive build number from SOURCE_DATE_EPOCH." >&2
  return 1
}

assert_canonical_rust_release_root() {
  local candidate_real=""
  local canonical_real=""
  candidate_real="$(release_realpath_dir "$RUST_HUB_SOURCE_ROOT" 2>/dev/null || true)"
  canonical_real="$(release_realpath_dir "$ROOT_DIR/rust/xhubd" 2>/dev/null || true)"

  if [ -z "$candidate_real" ] || [ -z "$canonical_real" ] || [ "$candidate_real" != "$canonical_real" ]; then
    echo "[release] Refusing non-canonical Rust Hub source: $RUST_HUB_SOURCE_ROOT" >&2
    echo "[release] Canonical Rust Hub source: $ROOT_DIR/rust/xhubd" >&2
    exit 1
  fi
  if ! git -C "$ROOT_DIR" ls-files --error-unmatch \
    rust/xhubd/Cargo.toml \
    rust/xhubd/tools/package_rust_hub.command >/dev/null 2>&1; then
    echo "[release] Canonical Rust Hub markers are not tracked by this repository." >&2
    exit 1
  fi
}

assert_canonical_release_roots() {
  assert_canonical_rust_release_root
  xterminal_assert_canonical_root "$ROOT_DIR" "$XT_SOURCE_ROOT"

  if release_flag_enabled "${XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE:-0}"; then
    echo "[release] XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE is forbidden for release builds." >&2
    exit 1
  fi
  if [ -n "${XHUB_RUST_HUB_PACKAGE_DIR:-}" ]; then
    echo "[release] XHUB_RUST_HUB_PACKAGE_DIR is forbidden for release builds." >&2
    echo "[release] The release packages a fresh runtime from: $ROOT_DIR/rust/xhubd" >&2
    exit 1
  fi
}

find_release_remote_tracking_ref() {
  local ref=""
  local symref=""
  local remote_and_branch=""
  local remote=""

  while IFS=$'\t' read -r ref symref; do
    [ -n "$ref" ] || continue
    [ -z "$symref" ] || continue
    case "$ref" in
      refs/remotes/*/HEAD) continue ;;
    esac
    remote_and_branch="${ref#refs/remotes/}"
    remote="${remote_and_branch%%/*}"
    [ -n "$remote" ] && [ "$remote_and_branch" != "$remote" ] || continue
    [ "$remote" = "$RELEASE_PUBLISHING_REMOTE" ] || continue
    if git -C "$ROOT_DIR" remote get-url "$remote" >/dev/null 2>&1; then
      printf '%s\n' "$ref"
      return 0
    fi
  done < <(
    git -C "$ROOT_DIR" for-each-ref \
      --contains HEAD \
      --format='%(refname)%09%(symref)' \
      refs/remotes
  )
  return 1
}

is_canonical_release_remote_url() {
  case "${1:-}" in
    https://github.com/AndrewXie-Rich/x-hub-system.git|\
    git@github.com:AndrewXie-Rich/x-hub-system.git)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

assert_release_trust_roots() {
  local fetch_url=""
  local push_url=""

  fetch_url="$(git -C "$ROOT_DIR" remote get-url "$RELEASE_PUBLISHING_REMOTE" 2>/dev/null || true)"
  push_url="$(git -C "$ROOT_DIR" remote get-url --push "$RELEASE_PUBLISHING_REMOTE" 2>/dev/null || true)"
  if ! is_canonical_release_remote_url "$fetch_url" || \
     ! is_canonical_release_remote_url "$push_url"; then
    echo "[release] Publishing remote URL is not a pinned X Hub canonical URL." >&2
    echo "[release] Fetch: ${fetch_url:-(missing)}" >&2
    echo "[release] Push:  ${push_url:-(missing)}" >&2
    return 1
  fi
  if [ ! -f "$RELEASE_TRUSTED_SIGNERS_FILE" ] || [ -L "$RELEASE_TRUSTED_SIGNERS_FILE" ] || \
     ! git -C "$ROOT_DIR" ls-files --error-unmatch \
       release/trusted_tag_signers.txt >/dev/null 2>&1; then
    echo "[release] Tracked trusted signer registry is missing: $RELEASE_TRUSTED_SIGNERS_FILE" >&2
    return 1
  fi
}

assert_release_signer_allowed() {
  VERIFIED_RELEASE_SIGNER="$(
    git -C "$ROOT_DIR" for-each-ref \
      --format='%(signature:fingerprint)' \
      "refs/tags/$VERIFIED_RELEASE_TAG"
  )"
  if [ -z "$VERIFIED_RELEASE_SIGNER" ]; then
    echo "[release] Verified tag did not expose a signer fingerprint." >&2
    return 1
  fi
  if ! awk '
    /^[[:space:]]*(#|$)/ { next }
    {
      value = $0
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      if (value == expected) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' expected="$VERIFIED_RELEASE_SIGNER" "$RELEASE_TRUSTED_SIGNERS_FILE"; then
    echo "[release] Tag signer is not in the tracked trust registry: $VERIFIED_RELEASE_SIGNER" >&2
    return 1
  fi
}

assert_no_ignored_release_inputs() {
  local ignored_release_inputs=""
  local path=""
  local -a source_roots=(
    x-terminal/Sources
    x-terminal/Tests
    x-terminal/assets
    x-terminal/Package.swift
    x-terminal/Package.resolved
    x-terminal/Info.plist
    x-terminal/X-Terminal.entitlements
    rust/xtd/src
    rust/xtd/tests
    rust/xtd/Cargo.toml
    rust/xtd/Cargo.lock
    rust/xhubd/crates
    rust/xhubd/config
    rust/xhubd/assets
    rust/xhubd/migrations
    rust/xhubd/provenance
    rust/xhubd/docs
    rust/xhubd/skills
    rust/xhubd/tools
    rust/xhubd/Cargo.toml
    rust/xhubd/Cargo.lock
    x-hub/macos/RELFlowHub/Sources
    x-hub/macos/RELFlowHub/Tests
    x-hub/macos/RELFlowHub/Package.swift
    x-hub/macos/RELFlowHub/Package.resolved
    x-hub/grpc-server/hub_grpc_server/src
    x-hub/grpc-server/hub_grpc_server/package.json
    x-hub/grpc-server/hub_grpc_server/package-lock.json
    x-hub/python-runtime/python_service
    protocol
    official-agent-skills
    scripts
  )

  while IFS= read -r -d '' path; do
    ignored_release_inputs+="${path}"$'\n'
  done < <(
    git -C "$ROOT_DIR" ls-files \
      --others \
      --ignored \
      --exclude-standard \
      --directory \
      --no-empty-directory \
      -z \
      -- "${source_roots[@]}"
  )

  if [ -n "$ignored_release_inputs" ]; then
    echo "[release] Refusing ignored/untracked release build inputs:" >&2
    printf '%s' "$ignored_release_inputs" >&2
    echo "[release] Build from a fresh detached worktree at the verified tag." >&2
    return 1
  fi
}

assert_frozen_release_worktree() {
  if [ "${XHUB_RELEASE_FROZEN_WORKTREE:-0}" != "1" ]; then
    return 0
  fi

  local expected_commit="${XHUB_RELEASE_EXPECTED_COMMIT:-}"
  local origin_root="${XHUB_RELEASE_ORIGIN_ROOT:-}"
  local head_commit=""
  local worktree_git=""
  local origin_git=""
  local origin_real=""
  local root_real=""

  if [ -z "$expected_commit" ] || [ -z "$origin_root" ] || [ ! -f "$ROOT_DIR/.git" ]; then
    echo "[release] Frozen-worktree handoff is missing or is not a linked Git worktree." >&2
    return 1
  fi
  root_real="$(release_realpath_dir "$ROOT_DIR" 2>/dev/null || true)"
  origin_real="$(release_realpath_dir "$origin_root" 2>/dev/null || true)"
  if [ -z "$root_real" ] || [ -z "$origin_real" ] || [ "$root_real" = "$origin_real" ]; then
    echo "[release] Frozen release must run from a distinct linked worktree." >&2
    return 1
  fi
  head_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  if [ "$head_commit" != "$expected_commit" ]; then
    echo "[release] Frozen worktree commit mismatch: expected $expected_commit, got $head_commit." >&2
    return 1
  fi
  worktree_git="$(git -C "$ROOT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
  origin_git="$(git -C "$origin_real" rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -z "$worktree_git" ] || [ -z "$origin_git" ] || \
     [ "$(cd "$ROOT_DIR" && cd "$worktree_git" && pwd -P 2>/dev/null || true)" != \
       "$(cd "$origin_real" && cd "$origin_git" && pwd -P 2>/dev/null || true)" ]; then
    echo "[release] Frozen worktree is not attached to the verified repository." >&2
    return 1
  fi
}

assert_release_source_truth() {
  local worktree_status=""
  local tag_object_type=""
  local tag_commit=""
  local head_commit=""
  local remote_and_branch=""

  if ! assert_release_trust_roots; then
    exit 1
  fi

  worktree_status="$(
    git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all
  )"
  if [ -n "$worktree_status" ]; then
    echo "[release] Refusing to release from a dirty worktree (untracked files included):" >&2
    printf '%s\n' "$worktree_status" >&2
    exit 1
  fi

  VERIFIED_RELEASE_TAG="$(
    git -C "$ROOT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true
  )"
  if [ -z "$VERIFIED_RELEASE_TAG" ]; then
    echo "[release] HEAD is not at an exact release tag." >&2
    exit 1
  fi

  tag_object_type="$(
    git -C "$ROOT_DIR" cat-file -t "refs/tags/$VERIFIED_RELEASE_TAG" 2>/dev/null || true
  )"
  if [ "$tag_object_type" != "tag" ]; then
    echo "[release] Refusing lightweight tag: $VERIFIED_RELEASE_TAG" >&2
    echo "[release] Releases require an annotated, cryptographically signed tag." >&2
    exit 1
  fi
  if ! git -C "$ROOT_DIR" verify-tag "$VERIFIED_RELEASE_TAG" >/dev/null; then
    echo "[release] Tag signature verification failed: $VERIFIED_RELEASE_TAG" >&2
    exit 1
  fi
  if ! assert_release_signer_allowed; then
    exit 1
  fi

  tag_commit="$(git -C "$ROOT_DIR" rev-parse "$VERIFIED_RELEASE_TAG^{commit}")"
  head_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  if [ "$tag_commit" != "$head_commit" ]; then
    echo "[release] Verified tag does not resolve to HEAD: $VERIFIED_RELEASE_TAG" >&2
    exit 1
  fi

  RELEASE_REMOTE_TRACKING_REF="$(find_release_remote_tracking_ref || true)"
  if [ -z "$RELEASE_REMOTE_TRACKING_REF" ]; then
    echo "[release] HEAD is not contained by a real remote-tracking ref." >&2
    echo "[release] Fetch the publishing remote and push the release commit before packaging." >&2
    exit 1
  fi
  remote_and_branch="${RELEASE_REMOTE_TRACKING_REF#refs/remotes/}"
  RELEASE_REMOTE="${remote_and_branch%%/*}"
  RELEASE_REMOTE_BRANCH="${remote_and_branch#*/}"
  if [ -z "$RELEASE_REMOTE" ] || [ -z "$RELEASE_REMOTE_BRANCH" ] || \
     [ "$RELEASE_REMOTE_BRANCH" = "$remote_and_branch" ]; then
    echo "[release] Could not resolve the publishing remote branch." >&2
    exit 1
  fi
  if ! git -C "$ROOT_DIR" fetch --quiet --no-tags \
    "$RELEASE_REMOTE" "refs/heads/$RELEASE_REMOTE_BRANCH"; then
    echo "[release] Publishing remote is unreachable or branch is unavailable." >&2
    exit 1
  fi
  RELEASE_REMOTE_COMMIT="$(git -C "$ROOT_DIR" rev-parse FETCH_HEAD)"
  if ! git -C "$ROOT_DIR" merge-base --is-ancestor HEAD "$RELEASE_REMOTE_COMMIT"; then
    echo "[release] HEAD is not contained by the live publishing remote branch." >&2
    echo "[release] Remote: $RELEASE_REMOTE/$RELEASE_REMOTE_BRANCH" >&2
    exit 1
  fi

  local remote_tag_probe=""
  remote_tag_probe="$(mktemp "${TMPDIR:-/tmp}/xhub-release-tag-remote.XXXXXX")"
  if ! git -C "$ROOT_DIR" ls-remote --exit-code "$RELEASE_REMOTE" \
    "refs/tags/$VERIFIED_RELEASE_TAG" \
    "refs/tags/$VERIFIED_RELEASE_TAG^{}" >"$remote_tag_probe"; then
    echo "[release] Signed release tag is not reachable from the publishing remote: $VERIFIED_RELEASE_TAG" >&2
    rm -f "$remote_tag_probe"
    exit 1
  fi
  RELEASE_REMOTE_TAG_OBJECT=""
  RELEASE_REMOTE_TAG_COMMIT=""
  local remote_tag_hash=""
  local remote_tag_ref=""
  while IFS=$'\t' read -r remote_tag_hash remote_tag_ref; do
    case "$remote_tag_ref" in
      "refs/tags/$VERIFIED_RELEASE_TAG") RELEASE_REMOTE_TAG_OBJECT="$remote_tag_hash" ;;
      "refs/tags/$VERIFIED_RELEASE_TAG^{}") RELEASE_REMOTE_TAG_COMMIT="$remote_tag_hash" ;;
    esac
  done < "$remote_tag_probe"
  rm -f "$remote_tag_probe"
  local local_tag_object=""
  local local_tag_commit=""
  local_tag_object="$(git -C "$ROOT_DIR" rev-parse "refs/tags/$VERIFIED_RELEASE_TAG")"
  local_tag_commit="$(git -C "$ROOT_DIR" rev-parse "$VERIFIED_RELEASE_TAG^{commit}")"
  if [ "$RELEASE_REMOTE_TAG_OBJECT" != "$local_tag_object" ] || \
     [ "$RELEASE_REMOTE_TAG_COMMIT" != "$local_tag_commit" ]; then
    echo "[release] Publishing remote tag does not match the verified local tag." >&2
    exit 1
  fi

  SOURCE_DATE_EPOCH="$(
    git -C "$ROOT_DIR" show -s --format=%ct HEAD 2>/dev/null || true
  )"
  case "$SOURCE_DATE_EPOCH" in
    ''|*[!0-9]*)
      echo "[release] Could not derive SOURCE_DATE_EPOCH from the release commit." >&2
      exit 1
      ;;
  esac
  export SOURCE_DATE_EPOCH

  if ! assert_no_ignored_release_inputs; then
    exit 1
  fi
  if ! assert_frozen_release_worktree; then
    exit 1
  fi
}

resolve_packaged_rust_hub() {
  local output_file="$1"
  local package_dir=""
  local package_real=""
  local package_parent=""
  local source_real=""
  local line_count=""

  if [ ! -s "$output_file" ]; then
    echo "[release] Rust Hub packager did not report an output path." >&2
    return 1
  fi
  line_count="$(awk 'END { print NR + 0 }' "$output_file")"
  if [ "$line_count" -ne 1 ]; then
    echo "[release] Rust Hub packager reported an invalid multi-line output path." >&2
    return 1
  fi
  IFS= read -r package_dir < "$output_file" || true
  if [ -z "$package_dir" ]; then
    echo "[release] Rust Hub packager reported an empty output path." >&2
    return 1
  fi

  package_real="$(release_realpath_dir "$package_dir" 2>/dev/null || true)"
  source_real="$(release_realpath_dir "$RUST_HUB_SOURCE_ROOT" 2>/dev/null || true)"
  if [ -z "$package_real" ] || [ -z "$source_real" ]; then
    echo "[release] Rust Hub packager reported a missing package: $package_dir" >&2
    return 1
  fi
  package_parent="$(dirname "$package_real")"
  if [ "$package_parent" != "$source_real/dist" ]; then
    echo "[release] Rust Hub package escaped the canonical dist root: $package_real" >&2
    return 1
  fi
  case "$(basename "$package_real")" in
    rust-hub-*) ;;
    *)
      echo "[release] Rust Hub package has an invalid final name: $package_real" >&2
      return 1
      ;;
  esac
  if [ ! -x "$package_real/bin/xhubd" ] || [ ! -s "$package_real/provenance.json" ]; then
    echo "[release] Rust Hub package is incomplete: $package_real" >&2
    return 1
  fi
  if ! XHUB_PROVENANCE_MANIFEST="$package_real/provenance.json" \
    "$package_real/bin/xhubd" provenance >/dev/null; then
    echo "[release] Rust Hub package provenance verification failed: $package_real" >&2
    return 1
  fi

  printf '%s\n' "$package_real"
}

verify_release_xt_artifact_root() {
  local artifact_root="$1"
  local app="$artifact_root/X-Terminal.app"
  local manifest="$artifact_root/X-Terminal.provenance.json"
  local verifier="$app/Contents/Resources/xtd"

  if [ ! -d "$app" ] || [ -L "$app" ] || \
     [ ! -f "$manifest" ] || [ -L "$manifest" ] || \
     [ ! -x "$verifier" ] || [ -L "$verifier" ]; then
    echo "[release] XT app/provenance/verifier layout is incomplete: $artifact_root" >&2
    return 1
  fi
  xterminal_verify_pinned_codesign "$app" "$ROOT_DIR" 1 >/dev/null
  xterminal_verify_pinned_codesign "$verifier" "$ROOT_DIR" 0 >/dev/null
  "$verifier" provenance verify \
    --manifest "$manifest" \
    --artifact-root "$artifact_root" \
    --repository-root "$ROOT_DIR" \
    --require-release >/dev/null
}

verify_release_hub_app() {
  local app="$1"
  if [ ! -d "$app" ] || [ -L "$app" ]; then
    echo "[release] Hub app is missing or symlinked: $app" >&2
    return 1
  fi
  xterminal_verify_pinned_codesign "$app" "$ROOT_DIR" 1 >/dev/null
}

sign_and_verify_release_disk_image() {
  local dmg="$1"
  if [ ! -f "$dmg" ] || [ -L "$dmg" ]; then
    echo "[release] Disk image is missing or symlinked: $dmg" >&2
    return 1
  fi
  codesign --force --sign "$RELEASE_CODESIGN_IDENTITY" "$dmg"
  xterminal_verify_pinned_codesign "$dmg" "$ROOT_DIR" 0 >/dev/null
}

release_mount_matches_safe_prefix() {
  local mount_point="$1"
  local expected_prefix="$2"
  local temp_root=""
  local parent_root=""

  temp_root="$(release_realpath_dir "${TMPDIR:-/tmp}" 2>/dev/null || true)"
  parent_root="$(
    release_realpath_dir "$(dirname -- "$mount_point")" 2>/dev/null || true
  )"
  if [ -z "$temp_root" ] || [ "$parent_root" != "$temp_root" ]; then
    return 1
  fi
  case "$(basename -- "$mount_point")" in
    "$expected_prefix".*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup_release_mount_best_effort() {
  local mount_point="$1"
  local attached="$2"
  local expected_prefix="$3"
  local label="$4"

  if [ -z "$mount_point" ]; then
    return 0
  fi
  if [ "$attached" = "1" ]; then
    if hdiutil detach "$mount_point" >/dev/null 2>&1; then
      :
    elif release_mount_matches_safe_prefix "$mount_point" "$expected_prefix" && \
         hdiutil detach -force "$mount_point" >/dev/null 2>&1; then
      :
    else
      echo "[release] Warning: $label verification mount is still attached: $mount_point" >&2
    fi
  fi
  if ! rmdir "$mount_point" >/dev/null 2>&1; then
    echo "[release] Warning: could not remove $label verification mount point: $mount_point" >&2
    return 1
  fi
}

detach_hub_dmg_mount() {
  local mount_point="${HUB_DMG_MOUNT_POINT:-}"
  if [ -z "$mount_point" ]; then
    return 0
  fi
  if [ "$HUB_DMG_MOUNT_ATTACHED" = "1" ]; then
    if ! hdiutil detach "$mount_point" >/dev/null; then
      echo "[release] Failed to detach Hub DMG verification mount: $mount_point" >&2
      return 1
    fi
    HUB_DMG_MOUNT_ATTACHED=0
  fi
  if ! rmdir "$mount_point"; then
    echo "[release] Failed to remove Hub DMG verification mount point: $mount_point" >&2
    return 1
  fi
  HUB_DMG_MOUNT_POINT=""
}

detach_combined_dmg_mount() {
  local mount_point="${COMBINED_DMG_MOUNT_POINT:-}"
  if [ -z "$mount_point" ]; then
    return 0
  fi
  if [ "$COMBINED_DMG_MOUNT_ATTACHED" = "1" ]; then
    if ! hdiutil detach "$mount_point" >/dev/null; then
      echo "[release] Failed to detach combined DMG verification mount: $mount_point" >&2
      return 1
    fi
    COMBINED_DMG_MOUNT_ATTACHED=0
  fi
  if ! rmdir "$mount_point"; then
    echo "[release] Failed to remove combined DMG verification mount point: $mount_point" >&2
    return 1
  fi
  COMBINED_DMG_MOUNT_POINT=""
}

assert_external_release_doctor_report() {
  local raw="${XHUB_RELEASE_XT_UNIFIED_DOCTOR_REPORT:-}"
  local parent=""
  local parent_real=""
  local report_real=""
  local forbidden_root=""

  if [ -z "$raw" ]; then
    echo "[release] XHUB_RELEASE_XT_UNIFIED_DOCTOR_REPORT is required." >&2
    echo "[release] Generate a fresh report from the verified diagnostic snapshot first." >&2
    return 1
  fi
  case "$raw" in
    /*) ;;
    *)
      echo "[release] Unified Doctor report must use an absolute external path: $raw" >&2
      return 1
      ;;
  esac
  if [ ! -f "$raw" ] || [ -L "$raw" ]; then
    echo "[release] Unified Doctor report must be a regular non-symlink file: $raw" >&2
    return 1
  fi
  parent="$(dirname "$raw")"
  parent_real="$(release_realpath_dir "$parent" 2>/dev/null || true)"
  if [ -z "$parent_real" ]; then
    echo "[release] Unified Doctor report parent cannot be resolved: $parent" >&2
    return 1
  fi
  report_real="$parent_real/$(basename "$raw")"
  for forbidden_root in "$ROOT_DIR" "${XHUB_RELEASE_ORIGIN_ROOT:-}"; do
    [ -n "$forbidden_root" ] || continue
    forbidden_root="$(release_realpath_dir "$forbidden_root" 2>/dev/null || true)"
    [ -n "$forbidden_root" ] || continue
    case "$report_real" in
      "$forbidden_root"|"$forbidden_root"/*)
        echo "[release] Unified Doctor report must live outside release source trees: $report_real" >&2
        return 1
        ;;
    esac
  done
  RELEASE_DOCTOR_REPORT="$report_real"
}

run_release_in_frozen_worktree() {
  local commit=""
  local rc=0

  commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  FROZEN_WORKTREE_PARENT="$(
    mktemp -d "${TMPDIR:-/tmp}/xhub-release-source.XXXXXX"
  )"
  FROZEN_WORKTREE_ROOT="$FROZEN_WORKTREE_PARENT/worktree"
  echo "[release] Materializing tracked release source: $FROZEN_WORKTREE_ROOT"
  if ! git -C "$ROOT_DIR" worktree add --quiet --detach "$FROZEN_WORKTREE_ROOT" "$commit"; then
    echo "[release] Failed to create detached release worktree." >&2
    return 1
  fi
  FROZEN_WORKTREE_REGISTERED=1

  if env \
    XHUB_RELEASE_FROZEN_WORKTREE=1 \
    XHUB_RELEASE_EXPECTED_COMMIT="$commit" \
    XHUB_RELEASE_ORIGIN_ROOT="$ROOT_DIR" \
    XHUB_RELEASE_DIR="$RELEASE_DIR" \
    XHUB_RELEASE_XT_UNIFIED_DOCTOR_REPORT="$RELEASE_DOCTOR_REPORT" \
    XHUB_RELEASE_CODESIGN_IDENTITY="$RELEASE_CODESIGN_IDENTITY" \
    XHUB_RUST_HUB_SOURCE_ROOT="$FROZEN_WORKTREE_ROOT/rust/xhubd" \
    XTERMINAL_SOURCE_ROOT="$FROZEN_WORKTREE_ROOT/x-terminal" \
    bash "$FROZEN_WORKTREE_ROOT/scripts/package_macos_release.command"; then
    rc=0
  else
    rc=$?
  fi
  return "$rc"
}

cleanup_release_temp_files() {
  if [ -n "$RUST_PACKAGE_OUTPUT_FILE" ] && [ -f "$RUST_PACKAGE_OUTPUT_FILE" ]; then
    rm -f "$RUST_PACKAGE_OUTPUT_FILE"
  fi
  if [ -n "$XT_GATE_SCRATCH_DIR" ] && [ -d "$XT_GATE_SCRATCH_DIR" ]; then
    case "$XT_GATE_SCRATCH_DIR" in
      "${TMPDIR:-/tmp}"/xhub-release-xt-gate.*)
        rm -rf -- "$XT_GATE_SCRATCH_DIR"
        ;;
      *)
        echo "[release] Refusing to clean unexpected XT gate scratch: $XT_GATE_SCRATCH_DIR" >&2
        ;;
    esac
  fi
  if [ -n "$HUB_DMG_MOUNT_POINT" ]; then
    if cleanup_release_mount_best_effort \
      "$HUB_DMG_MOUNT_POINT" \
      "$HUB_DMG_MOUNT_ATTACHED" \
      xhub-hub-dmg-verify \
      "Hub DMG"; then
      HUB_DMG_MOUNT_POINT=""
      HUB_DMG_MOUNT_ATTACHED=0
    fi
  fi
  if [ -n "$COMBINED_DMG_MOUNT_POINT" ]; then
    if cleanup_release_mount_best_effort \
      "$COMBINED_DMG_MOUNT_POINT" \
      "$COMBINED_DMG_MOUNT_ATTACHED" \
      xhub-system-dmg-verify \
      "combined DMG"; then
      COMBINED_DMG_MOUNT_POINT=""
      COMBINED_DMG_MOUNT_ATTACHED=0
    fi
  fi
  if [ "$FROZEN_WORKTREE_REGISTERED" = "1" ] && [ -n "$FROZEN_WORKTREE_ROOT" ]; then
    git -C "$ROOT_DIR" worktree remove --force "$FROZEN_WORKTREE_ROOT" >/dev/null 2>&1 || true
    FROZEN_WORKTREE_REGISTERED=0
  fi
  if [ -n "$FROZEN_WORKTREE_PARENT" ] && [ -d "$FROZEN_WORKTREE_PARENT" ]; then
    case "$FROZEN_WORKTREE_PARENT" in
      "${TMPDIR:-/tmp}"/xhub-release-source.*)
        rm -rf -- "$FROZEN_WORKTREE_PARENT"
        ;;
      *)
        echo "[release] Refusing to clean unexpected frozen-worktree parent: $FROZEN_WORKTREE_PARENT" >&2
        ;;
    esac
  fi
  return 0
}

trap cleanup_release_temp_files EXIT

assert_canonical_release_roots
if [ "$CHECK_CANONICAL_ROOTS" = "1" ]; then
  echo "[release] Canonical root preflight passed."
  echo "[release] Rust Hub: $ROOT_DIR/rust/xhubd"
  echo "[release] X-Terminal: $ROOT_DIR/x-terminal"
  exit 0
fi

if [ "$CHECK_RELEASE_INPUTS" = "1" ]; then
  if ! assert_no_ignored_release_inputs; then
    exit 1
  fi
  echo "[release] Ignored release-input preflight passed."
  exit 0
fi

case "${XHUB_RELEASE_FROZEN_WORKTREE:-0}" in
  0|1) ;;
  *)
    echo "[release] XHUB_RELEASE_FROZEN_WORKTREE is an internal boolean handoff." >&2
    exit 64
    ;;
esac

assert_release_source_truth
if ! assert_external_release_doctor_report; then
  exit 1
fi
xterminal_assert_release_codesign_identity "$RELEASE_CODESIGN_IDENTITY"
xterminal_assert_release_codesign_registry "$ROOT_DIR"

if [ -n "${XHUB_RELEASE_VERSION:-}" ] && \
   [ "$XHUB_RELEASE_VERSION" != "$VERIFIED_RELEASE_TAG" ]; then
  echo "[release] XHUB_RELEASE_VERSION conflicts with verified HEAD tag." >&2
  echo "[release] Requested: $XHUB_RELEASE_VERSION" >&2
  echo "[release] Verified:  $VERIFIED_RELEASE_TAG" >&2
  exit 1
fi
VERSION="$VERIFIED_RELEASE_TAG"

ARCH="${XHUB_RELEASE_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) PLATFORM="macos-arm64" ;;
  x86_64) PLATFORM="macos-x86_64" ;;
  *) PLATFORM="macos-$ARCH" ;;
esac

APP_VERSION="${VERSION#v}"
DERIVED_BUILD_NUMBER="$(release_epoch_build_number "$SOURCE_DATE_EPOCH")"
if [ -n "${XHUB_RELEASE_BUILD_NUMBER:-}" ] && \
   [ "$XHUB_RELEASE_BUILD_NUMBER" != "$DERIVED_BUILD_NUMBER" ]; then
  echo "[release] XHUB_RELEASE_BUILD_NUMBER conflicts with the commit timestamp." >&2
  echo "[release] Requested: $XHUB_RELEASE_BUILD_NUMBER" >&2
  echo "[release] Derived:   $DERIVED_BUILD_NUMBER" >&2
  exit 1
fi
BUILD_NUMBER="$DERIVED_BUILD_NUMBER"
RELEASE_DIR="${XHUB_RELEASE_DIR:-$ROOT_DIR/build/release/$VERSION}"
case "$RELEASE_DIR" in
  /*) ;;
  *) RELEASE_DIR="$ROOT_DIR/$RELEASE_DIR" ;;
esac
mkdir -p "$RELEASE_DIR"
RELEASE_DIR="$(cd "$RELEASE_DIR" && pwd -P)"
HUB_APP="$ROOT_DIR/build/X-Hub.app"
XT_APP="$ROOT_DIR/build/X-Terminal.app"
HUB_DMG="$RELEASE_DIR/X-Hub-${VERSION}-${PLATFORM}.dmg"
XT_DMG="$RELEASE_DIR/X-Terminal-${VERSION}-${PLATFORM}.dmg"
SYSTEM_DMG="$RELEASE_DIR/XHub-System-${VERSION}-${PLATFORM}.dmg"
SYSTEM_STAGE="$ROOT_DIR/build/xhub_system_release_stage"

echo "[release] Version: $VERSION"
echo "[release] Verified signer: $VERIFIED_RELEASE_SIGNER"
echo "[release] Verified remote ref: $RELEASE_REMOTE_TRACKING_REF"
echo "[release] Verified remote tag object: $RELEASE_REMOTE_TAG_OBJECT"
echo "[release] Live remote commit: $RELEASE_REMOTE_COMMIT"
echo "[release] SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
echo "[release] Platform: $PLATFORM"
echo "[release] Output: $RELEASE_DIR"

if [ "${XHUB_RELEASE_FROZEN_WORKTREE:-0}" != "1" ]; then
  if run_release_in_frozen_worktree; then
    exit 0
  else
    rc=$?
    exit "$rc"
  fi
fi

echo "[1/8] Running the release-grade X-Terminal gate..."
XT_GATE_SCRATCH_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/xhub-release-xt-gate.XXXXXX"
)"
XT_GATE_MODE=strict \
XT_GATE_RELEASE_PRESET=1 \
XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE=1 \
XT_GATE_UNIFIED_DOCTOR_REPORT="$RELEASE_DOCTOR_REPORT" \
XT_GATE_SWIFT_SCRATCH_PATH="$XT_GATE_SCRATCH_DIR/swift-scratch" \
  bash "$XT_SOURCE_ROOT/scripts/ci/xt_release_gate.sh"
rm -rf -- "$XT_GATE_SCRATCH_DIR"
XT_GATE_SCRATCH_DIR=""

# The gate may create ignored evidence and build outputs, but it must not alter
# tracked release inputs, HEAD, the verified tag, or live remote reachability.
assert_release_source_truth

echo "[2/8] Packaging Rust Hub runtime from repository source..."
RUST_PACKAGE_OUTPUT_FILE="$(
  mktemp "${TMPDIR:-/tmp}/xhub-release-rust-package.XXXXXX"
)"
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
XHUB_RELEASE_BUILD=1 \
  bash "$RUST_HUB_SOURCE_ROOT/tools/package_rust_hub.command" \
    --output-file "$RUST_PACKAGE_OUTPUT_FILE"
RUST_PACKAGE_DIR="$(resolve_packaged_rust_hub "$RUST_PACKAGE_OUTPUT_FILE")"
rm -f "$RUST_PACKAGE_OUTPUT_FILE"
RUST_PACKAGE_OUTPUT_FILE=""
echo "[release] Rust Hub package: $RUST_PACKAGE_DIR"

echo "[3/8] Building X-Hub.app..."
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
XHUB_APP_VERSION="$APP_VERSION" \
XHUB_BUILD_VERSION="$BUILD_NUMBER" \
XHUB_RUST_HUB_SOURCE_ROOT="$RUST_HUB_SOURCE_ROOT" \
XHUB_RUST_HUB_PACKAGE_DIR="$RUST_PACKAGE_DIR" \
XHUB_ALLOW_EXTERNAL_RUST_HUB_PACKAGE=0 \
XHUB_RELEASE_BUILD=1 \
XHUB_EMBED_RUST_HUB=1 \
REL_FLOW_HUB_CODESIGN_IDENTITY="$RELEASE_CODESIGN_IDENTITY" \
  "$ROOT_DIR/x-hub/tools/build_hub_app.command"
verify_release_hub_app "$HUB_APP"

echo "[4/8] Building X-Terminal.app and Rust XT sidecar..."
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
XTERMINAL_APP_VERSION="$APP_VERSION" \
XTERMINAL_BUILD_VERSION="$BUILD_NUMBER" \
XTERMINAL_RELEASE_BUILD=1 \
XTERMINAL_CODESIGN_IDENTITY="$RELEASE_CODESIGN_IDENTITY" \
  bash "$XT_SOURCE_ROOT/tools/build_xt_with_rust_sidecar.command"
verify_release_xt_artifact_root "$ROOT_DIR/build"

echo "[5/8] Building X-Hub DMG..."
XHUB_DMG_OUTPUT="$HUB_DMG" \
XHUB_DMG_VERSION="$APP_VERSION" \
  "$ROOT_DIR/x-hub/tools/build_hub_dmg.command"
sign_and_verify_release_disk_image "$HUB_DMG"
HUB_DMG_MOUNT_POINT="$(
  mktemp -d "${TMPDIR:-/tmp}/xhub-hub-dmg-verify.XXXXXX"
)"
if ! hdiutil attach -nobrowse -readonly \
  -mountpoint "$HUB_DMG_MOUNT_POINT" \
  "$HUB_DMG" >/dev/null; then
  echo "[release] Failed to attach Hub DMG for final verification: $HUB_DMG" >&2
  exit 1
fi
HUB_DMG_MOUNT_ATTACHED=1
verify_release_hub_app "$HUB_DMG_MOUNT_POINT/X-Hub.app"
detach_hub_dmg_mount

echo "[6/8] Building X-Terminal DMG..."
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
XTERMINAL_DMG_OUTPUT="$XT_DMG" \
XTERMINAL_DMG_VERSION="$APP_VERSION" \
XTERMINAL_RELEASE_BUILD=1 \
XTERMINAL_CODESIGN_IDENTITY="$RELEASE_CODESIGN_IDENTITY" \
  bash "$XT_SOURCE_ROOT/tools/build_xterminal_dmg.command"
xterminal_verify_pinned_codesign "$XT_DMG" "$ROOT_DIR" 0 >/dev/null

echo "[7/8] Building combined XHub-System DMG..."
if [ ! -d "$HUB_APP" ]; then
  echo "Hub app not found: $HUB_APP" >&2
  exit 1
fi
if [ ! -d "$XT_APP" ]; then
  echo "X-Terminal app not found: $XT_APP" >&2
  exit 1
fi

rm -rf "$SYSTEM_STAGE" 2>/dev/null || true
mkdir -p "$SYSTEM_STAGE"

cp -R "$HUB_APP" "$SYSTEM_STAGE/X-Hub.app"
cp -R "$XT_APP" "$SYSTEM_STAGE/X-Terminal.app"
cp -f "$ROOT_DIR/build/X-Terminal.provenance.json" \
  "$SYSTEM_STAGE/X-Terminal.provenance.json"
ln -s "/Applications" "$SYSTEM_STAGE/Applications"
verify_release_hub_app "$SYSTEM_STAGE/X-Hub.app"
verify_release_xt_artifact_root "$SYSTEM_STAGE"

{
  echo "XHub-System $VERSION"
  echo
  echo "Install:"
  echo "1) Copy X-Hub.app, X-Terminal.app, and X-Terminal.provenance.json to Applications"
  echo "2) Launch X-Hub first"
  echo "3) Launch X-Terminal and pair it with X-Hub"
  echo
  echo "Release assets:"
  echo "- The combined DMG is the recommended download for normal users."
  echo "- The separate Hub and X-Terminal DMGs are for advanced users and partial updates."
  echo
  echo "Preview status:"
  echo "- This is a public tech preview unless the GitHub Release notes say otherwise."
  echo "- If the apps are not notarized, macOS may require an explicit user approval on first launch."
} > "$SYSTEM_STAGE/README.txt"

rm -f "$SYSTEM_DMG" 2>/dev/null || true
hdiutil create -volname "XHub-System $VERSION" -srcfolder "$SYSTEM_STAGE" -ov -format UDZO "$SYSTEM_DMG" >/dev/null
sign_and_verify_release_disk_image "$SYSTEM_DMG"

COMBINED_DMG_MOUNT_POINT="$(
  mktemp -d "${TMPDIR:-/tmp}/xhub-system-dmg-verify.XXXXXX"
)"
if ! hdiutil attach -nobrowse -readonly \
  -mountpoint "$COMBINED_DMG_MOUNT_POINT" \
  "$SYSTEM_DMG" >/dev/null; then
  echo "[release] Failed to attach combined DMG for final verification: $SYSTEM_DMG" >&2
  exit 1
fi
COMBINED_DMG_MOUNT_ATTACHED=1
verify_release_hub_app "$COMBINED_DMG_MOUNT_POINT/X-Hub.app"
verify_release_xt_artifact_root "$COMBINED_DMG_MOUNT_POINT"
detach_combined_dmg_mount

# Recheck the signed tag, live remote, clean tracked inputs, and frozen-worktree
# identity after every compiler, packager, and disk-image tool has completed.
assert_release_source_truth

echo "[8/8] Writing SHA256SUMS.txt..."
(
  cd "$RELEASE_DIR"
  shasum -a 256 ./*.dmg > SHA256SUMS.txt
)

echo
echo "[release] Done."
echo "Upload these files to the GitHub Release for $VERSION:"
echo "  $SYSTEM_DMG"
echo "  $HUB_DMG"
echo "  $XT_DMG"
echo "  $RELEASE_DIR/SHA256SUMS.txt"
