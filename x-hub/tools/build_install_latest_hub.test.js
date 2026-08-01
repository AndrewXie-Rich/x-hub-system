#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const commandSource = fs.readFileSync(
  path.join(SCRIPT_DIR, 'build_install_latest_hub.command'),
  'utf8',
);

function sourceBetween(startMarker, endMarker) {
  const start = commandSource.indexOf(startMarker);
  const end = commandSource.indexOf(endMarker, start + startMarker.length);
  assert.notEqual(start, -1, `missing start marker: ${startMarker}`);
  assert.notEqual(end, -1, `missing end marker: ${endMarker}`);
  return commandSource.slice(start, end);
}

test('provider/model prep guards use the frozen dependency snapshot', () => {
  const guardBlock = sourceBetween(
    'if [ "$CUTOVER_PREP_WARMUP_CYCLES" != "0" ]',
    'local prep_sustained_report=""',
  );
  const snapshotAssignments = guardBlock.match(
    /XHUB_SYSTEM_ROOT="\$BUILD_SNAPSHOT_DIR"/g,
  ) || [];

  assert.equal(snapshotAssignments.length, 2);
  assert.doesNotMatch(guardBlock, /XHUB_SYSTEM_ROOT="\$SOURCE_ROOT"/);
  assert.match(guardBlock, /Warm provider\/model route guards after cold launch/);
  assert.match(guardBlock, /Run provider\/model route sustained cutover guard/);
  assert.match(guardBlock, /--cycles "\$CUTOVER_PREP_WARMUP_CYCLES"/);
  assert.match(guardBlock, /--cycles "\$CUTOVER_PREP_SUSTAINED_CYCLES"/);
  assert.match(
    commandSource,
    /BUILD_SNAPSHOT_DIR="\$\{XHUB_BUILD_SNAPSHOT_DIR:-\$SOURCE_ROOT\/build\/\.xhub-build-src\}"/,
  );
});

test('frozen evidence source requires Node services and npm dependencies', () => {
  const evidenceBlock = sourceBetween(
    'refresh_live_route_compare_evidence() {',
    'verify_live_layered_readiness() {',
  );

  assert.match(
    evidenceBlock,
    /node_source_dir="\$BUILD_SNAPSHOT_DIR\/x-hub\/grpc-server\/hub_grpc_server"/,
  );
  assert.match(evidenceBlock, /node_source_dir\/src\/services\.js/);
  assert.match(evidenceBlock, /node_source_dir\/node_modules/);
  assert.match(evidenceBlock, /require\.resolve\('js-yaml'\)/);
  assert.doesNotMatch(evidenceBlock, /XHUB_SYSTEM_ROOT="\$SOURCE_ROOT"/);
});
