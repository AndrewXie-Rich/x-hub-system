#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const releaseCommandPath = fileURLToPath(
  new URL('../package_macos_release.command', import.meta.url),
);
const releaseCommand = readFileSync(releaseCommandPath, 'utf8');

test('canonical-only preflight exits before release source-truth checks', () => {
  const canonicalCheckIndex = releaseCommand.indexOf(
    'assert_canonical_release_roots\n',
  );
  const canonicalOnlyExitIndex = releaseCommand.indexOf(
    'if [ "$CHECK_CANONICAL_ROOTS" = "1" ]; then',
    canonicalCheckIndex,
  );
  const sourceTruthIndex = releaseCommand.indexOf(
    '\nassert_release_source_truth\n',
    canonicalOnlyExitIndex,
  );

  assert.ok(canonicalCheckIndex >= 0, 'expected canonical-root preflight');
  assert.ok(canonicalOnlyExitIndex > canonicalCheckIndex);
  assert.ok(sourceTruthIndex > canonicalOnlyExitIndex);
  assert.match(
    releaseCommand.slice(canonicalOnlyExitIndex, sourceTruthIndex),
    /exit 0/,
  );
});

test('full releases require a clean worktree including untracked files', () => {
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" status --porcelain=v1 --untracked-files=all/,
  );
  assert.match(releaseCommand, /Refusing to release from a dirty worktree/);
});

test('release version comes from an exact verified annotated tag', () => {
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" describe --tags --exact-match HEAD/,
  );
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" cat-file -t "refs\/tags\/\$VERIFIED_RELEASE_TAG"/,
  );
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" verify-tag "\$VERIFIED_RELEASE_TAG"/,
  );
  assert.match(
    releaseCommand,
    /rev-parse "\$VERIFIED_RELEASE_TAG\^\{commit\}"/,
  );
  assert.match(releaseCommand, /VERSION="\$VERIFIED_RELEASE_TAG"/);
  assert.match(
    releaseCommand,
    /XHUB_RELEASE_VERSION conflicts with verified HEAD tag/,
  );
  assert.doesNotMatch(releaseCommand, /v0\.1\.0-alpha\.1/);
});

test('release commit must be contained by a configured non-symbolic remote ref', () => {
  assert.match(releaseCommand, /git -C "\$ROOT_DIR" for-each-ref/);
  assert.match(releaseCommand, /--contains HEAD/);
  assert.match(releaseCommand, /--format='%\(refname\)%09%\(symref\)'/);
  assert.match(releaseCommand, /refs\/remotes\/\*\/HEAD\) continue/);
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" remote get-url "\$remote"/,
  );
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" fetch --quiet --no-tags/,
  );
  assert.match(releaseCommand, /"refs\/heads\/\$RELEASE_REMOTE_BRANCH"/);
  assert.match(releaseCommand, /rev-parse FETCH_HEAD/);
  assert.match(
    releaseCommand,
    /merge-base --is-ancestor HEAD "\$RELEASE_REMOTE_COMMIT"/,
  );
});

test('commit timestamp is propagated into both package and app builds', () => {
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" show -s --format=%ct HEAD/,
  );
  assert.match(releaseCommand, /export SOURCE_DATE_EPOCH/);
  assert.match(
    releaseCommand,
    /DERIVED_BUILD_NUMBER="\$\(release_epoch_build_number "\$SOURCE_DATE_EPOCH"\)"/,
  );
  assert.match(
    releaseCommand,
    /XHUB_RELEASE_BUILD_NUMBER conflicts with the commit timestamp/,
  );
  assert.match(
    releaseCommand,
    /SOURCE_DATE_EPOCH="\$SOURCE_DATE_EPOCH" \\\n+XHUB_RELEASE_BUILD=1 \\\n+\s+bash "\$RUST_HUB_SOURCE_ROOT\/tools\/package_rust_hub\.command"/,
  );
  assert.match(
    releaseCommand,
    /SOURCE_DATE_EPOCH="\$SOURCE_DATE_EPOCH" \\\n+XHUB_APP_VERSION=/,
  );
  assert.match(
    releaseCommand,
    /SOURCE_DATE_EPOCH="\$SOURCE_DATE_EPOCH" \\\n+XTERMINAL_APP_VERSION=/,
  );
});

test('fresh Rust package is handed to the Hub build by exact path', () => {
  const packageCallIndex = releaseCommand.indexOf(
    '--output-file "$RUST_PACKAGE_OUTPUT_FILE"',
  );
  const outputReadIndex = releaseCommand.indexOf(
    'resolve_packaged_rust_hub "$RUST_PACKAGE_OUTPUT_FILE"',
  );
  const explicitBuildPathIndex = releaseCommand.indexOf(
    'XHUB_RUST_HUB_PACKAGE_DIR="$RUST_PACKAGE_DIR"',
  );

  assert.match(
    releaseCommand,
    /mktemp "\$\{TMPDIR:-\/tmp\}\/xhub-release-rust-package\.XXXXXX"/,
  );
  assert.ok(packageCallIndex >= 0, 'expected package output-file handoff');
  assert.ok(outputReadIndex > packageCallIndex, 'expected exact output read');
  assert.ok(
    explicitBuildPathIndex > outputReadIndex,
    'expected exact package path passed into the Hub build',
  );
  assert.doesNotMatch(
    releaseCommand,
    /find[^\n]*rust-hub-[^\n]*sort[^\n]*tail/,
  );
});

test('release-grade XT gate runs before packaging and source truth is rechecked', () => {
  const firstSourceTruthIndex = releaseCommand.indexOf(
    '\nassert_release_source_truth\n',
  );
  const strictGateIndex = releaseCommand.indexOf(
    'XT_GATE_MODE=strict \\',
  );
  const secondSourceTruthIndex = releaseCommand.indexOf(
    '\nassert_release_source_truth\n',
    firstSourceTruthIndex + 1,
  );
  const rustPackageIndex = releaseCommand.indexOf(
    'bash "$RUST_HUB_SOURCE_ROOT/tools/package_rust_hub.command"',
  );

  assert.ok(firstSourceTruthIndex >= 0, 'expected initial source-truth gate');
  assert.ok(strictGateIndex > firstSourceTruthIndex, 'expected strict XT gate');
  assert.match(
    releaseCommand.slice(strictGateIndex, secondSourceTruthIndex),
    /XT_GATE_RELEASE_PRESET=1[\s\S]*XT_GATE_AUTO_PREPARE_RELEASE_EVIDENCE=1[\s\S]*XT_GATE_UNIFIED_DOCTOR_REPORT="\$RELEASE_DOCTOR_REPORT"[\s\S]*XT_GATE_SWIFT_SCRATCH_PATH="\$XT_GATE_SCRATCH_DIR\/swift-scratch"[\s\S]*bash "\$XT_SOURCE_ROOT\/scripts\/ci\/xt_release_gate\.sh"/,
  );
  assert.ok(
    secondSourceTruthIndex > strictGateIndex,
    'expected source truth to be rechecked after the XT gate',
  );
  assert.ok(
    rustPackageIndex > secondSourceTruthIndex,
    'expected Rust packaging only after both gates pass',
  );
});

test('release source is rematerialized in a detached tracked-only worktree', () => {
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" worktree add --quiet --detach "\$FROZEN_WORKTREE_ROOT" "\$commit"/,
  );
  assert.match(releaseCommand, /XHUB_RELEASE_FROZEN_WORKTREE=1/);
  assert.match(releaseCommand, /XHUB_RELEASE_EXPECTED_COMMIT="\$commit"/);
  assert.match(
    releaseCommand,
    /XHUB_RUST_HUB_SOURCE_ROOT="\$FROZEN_WORKTREE_ROOT\/rust\/xhubd"/,
  );
  assert.match(
    releaseCommand,
    /XTERMINAL_SOURCE_ROOT="\$FROZEN_WORKTREE_ROOT\/x-terminal"/,
  );
  assert.match(
    releaseCommand,
    /XHUB_RELEASE_CODESIGN_IDENTITY="\$RELEASE_CODESIGN_IDENTITY"/,
  );
  assert.match(
    releaseCommand,
    /bash "\$FROZEN_WORKTREE_ROOT\/scripts\/package_macos_release\.command"/,
  );
  assert.match(
    releaseCommand,
    /git -C "\$ROOT_DIR" worktree remove --force "\$FROZEN_WORKTREE_ROOT"/,
  );
});

test('release pins publisher, remote tag object, and tracked signer registry', () => {
  assert.match(releaseCommand, /RELEASE_PUBLISHING_REMOTE="origin"/);
  assert.match(
    releaseCommand,
    /https:\/\/github\.com\/AndrewXie-Rich\/x-hub-system\.git/,
  );
  assert.match(releaseCommand, /release\/trusted_tag_signers\.txt/);
  assert.match(releaseCommand, /%\(signature:fingerprint\)/);
  assert.match(releaseCommand, /git -C "\$ROOT_DIR" ls-remote --exit-code/);
  assert.match(releaseCommand, /RELEASE_REMOTE_TAG_OBJECT/);
  assert.match(releaseCommand, /RELEASE_REMOTE_TAG_COMMIT/);
});

test('ignored material is rejected across Swift, Rust, skills, and release scripts', () => {
  assert.match(releaseCommand, /assert_no_ignored_release_inputs/);
  assert.match(
    releaseCommand,
    /--others[\s\S]*--ignored[\s\S]*--exclude-standard/,
  );
  for (const sourceRoot of [
    'x-terminal/Sources',
    'x-terminal/Tests',
    'rust/xtd/src',
    'rust/xhubd/crates',
    'rust/xhubd/skills',
    'x-hub/macos/RELFlowHub/Sources',
    'official-agent-skills',
    'scripts',
  ]) {
    assert.ok(releaseCommand.includes(sourceRoot), 'missing ' + sourceRoot);
  }
});
