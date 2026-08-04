import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(new URL('./package_rust_hub.command', import.meta.url));
const script = readFileSync(scriptPath, 'utf8');

test('supports an optional exact package-path handoff file', () => {
  assert.match(script, /OUTPUT_FILE=""/);
  assert.match(script, /--output-file\)/);
  assert.match(script, /OUTPUT_FILE="\$2"/);
  assert.match(script, /if \[ -n "\$OUTPUT_FILE" \]; then/);
  assert.match(script, /printf '%s\\n' "\$FINAL_DIR" > "\$OUTPUT_TMP_FILE"/);
  assert.match(script, /mv "\$OUTPUT_TMP_FILE" "\$OUTPUT_FILE"/);
});

test('builds in a disposable unique staging directory before an atomic final rename', () => {
  assert.match(script, /STAGING_DIR="\$\(mktemp -d "\$DIST_ROOT\/\.rust-hub-stage\.XXXXXX"\)"/);
  assert.match(script, /FINAL_DIR="\$DIST_ROOT\/rust-hub-\$STAMP-\$STAGING_SUFFIX"/);
  assert.match(script, /if \[ -e "\$FINAL_DIR" \]; then/);
  assert.match(script, /DIST_DIR="\$STAGING_DIR"/);
  assert.match(script, /mv "\$STAGING_DIR" "\$FINAL_DIR"/);
  assert.doesNotMatch(script, /DIST_DIR="\$ROOT_DIR\/dist\/rust-hub-\$STAMP"/);
  assert.doesNotMatch(script, /mkdir -p "\$FINAL_DIR/);
});

test('cleans abandoned staging without deleting an unexpected path', () => {
  assert.match(script, /trap cleanup EXIT/);
  assert.match(script, /"\$DIST_ROOT"\/\.rust-hub-stage\.\*\)/);
  assert.match(script, /rm -rf -- "\$STAGING_DIR"/);
});

test('derives the visible package timestamp from SOURCE_DATE_EPOCH when supplied', () => {
  assert.match(script, /if \[ -z "\$\{SOURCE_DATE_EPOCH:-\}" \]; then/);
  assert.match(script, /date -u -r "\$SOURCE_DATE_EPOCH" \+%Y%m%dT%H%M%SZ/);
  assert.match(script, /date -u -d "@\$SOURCE_DATE_EPOCH" \+%Y%m%dT%H%M%SZ/);
  assert.match(script, /STAMP="\$\(release_stamp\)"/);
});

test('publishes the handoff only after provenance verification and finalization', () => {
  const verifyIndex = script.indexOf('"$DIST_DIR/bin/xhubd" provenance >/dev/null');
  const renameIndex = script.indexOf('mv "$STAGING_DIR" "$FINAL_DIR"');
  const outputIndex = script.indexOf("printf '%s\\n' \"$FINAL_DIR\" > \"$OUTPUT_TMP_FILE\"");
  const publishIndex = script.indexOf('mv "$OUTPUT_TMP_FILE" "$OUTPUT_FILE"');

  assert.ok(verifyIndex >= 0, 'expected packaged provenance verification');
  assert.ok(renameIndex > verifyIndex, 'expected final rename after provenance verification');
  assert.ok(outputIndex > renameIndex, 'expected package-path output after final rename');
  assert.ok(publishIndex > outputIndex, 'expected atomic package-path publication');
});

test('generates provenance outside the package so the full inventory is closed', () => {
  assert.match(
    script,
    /PROVENANCE_OUTPUT_TMP="\$\(mktemp "\$DIST_ROOT\/\.rust-hub-provenance\.XXXXXX"\)"/,
  );
  assert.match(
    script,
    /provenance --package-manifest > "\$PROVENANCE_OUTPUT_TMP"/,
  );
  assert.match(
    script,
    /mv "\$PROVENANCE_OUTPUT_TMP" "\$DIST_DIR\/provenance\.json"/,
  );
  assert.doesNotMatch(script, /\$DIST_DIR\/provenance\.json\.tmp/);
});

test('release mode rejects dirty or cached identities and verifies the exact manifest', () => {
  assert.match(script, /XHUB_RELEASE_BUILD/);
  assert.match(script, /status --porcelain=v1 --untracked-files=all/);
  assert.match(script, /EXPECTED_GIT_COMMIT="\$\(git -C "\$ROOT_DIR" rev-parse HEAD\)"/);
  assert.match(
    script,
    /node "\$ROOT_DIR\/tools\/verify_release_package_identity\.js"/,
  );
  assert.match(script, /--expected-commit "\$EXPECTED_GIT_COMMIT"/);
  assert.match(script, /--expected-source-root "\$ROOT_DIR"/);
  assert.match(script, /--expected-source-date-epoch "\$SOURCE_DATE_EPOCH"/);
});
