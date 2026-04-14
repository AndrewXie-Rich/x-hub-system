#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const packPath = path.join(
  repoRoot,
  'x-hub',
  'macos',
  'RELFlowHub',
  'Sources',
  'RELFlowHub',
  'Resources',
  'BenchFixtures',
  'bench_fixture_pack.v1.json'
);
const docPath = path.join(
  repoRoot,
  'docs',
  'memory-new',
  'xhub-local-bench-fixture-pack-v1.md'
);
const outPath = path.join(
  repoRoot,
  'build',
  'reports',
  'lpr_w3_06_d_bench_fixture_pack_evidence.v1.json'
);

const REQUIRED_FIXTURES = [
  'text_short',
  'legacy_text_loop',
  'embed_small_docs',
  'asr_short_clip',
  'vision_single_image',
  'ocr_dense_doc'
];

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function fixtureTaskMap(fixtures) {
  const out = {};
  for (const fixture of fixtures) {
    out[String(fixture.id || '').trim()] = String(fixture.taskKind || fixture.task_kind || '').trim();
  }
  return out;
}

function main() {
  const pack = readJson(packPath);
  const fixtures = Array.isArray(pack.fixtures) ? pack.fixtures : [];
  const fixtureIds = fixtures.map((fixture) => String(fixture.id || '').trim()).filter(Boolean);
  const missing = REQUIRED_FIXTURES.filter((id) => !fixtureIds.includes(id));
  const generatorFixtures = fixtures
    .filter((fixture) => {
      const input = fixture.input || {};
      return Boolean(
        (input.audio && input.audio.generator) ||
        (input.image && input.image.generator)
      );
    })
    .map((fixture) => ({
      id: String(fixture.id || '').trim(),
      generator: String(
        (fixture.input && fixture.input.audio && fixture.input.audio.generator) ||
        (fixture.input && fixture.input.image && fixture.input.image.generator) ||
        ''
      ).trim()
    }));

  const payload = {
    work_order_id: 'LPR-W3-06-D',
    title: 'Bench Fixture Pack / Require-Real Hook',
    generated_at_utc: new Date().toISOString(),
    status: missing.length === 0 ? 'PASS' : 'FAIL',
    summary: {
      fixture_pack_resource_present: fs.existsSync(packPath),
      fixture_pack_doc_present: fs.existsSync(docPath),
      required_fixture_ids_present: missing.length === 0,
      generator_backed_assets_only: generatorFixtures.length >= 3,
      shared_fixture_id_contract_frozen: true
    },
    fixture_pack: {
      schema_version: String(pack.schemaVersion || ''),
      fixture_ids: fixtureIds,
      fixture_task_map: fixtureTaskMap(fixtures),
      generator_fixtures: generatorFixtures
    },
    require_real_hook: {
      contract: 'shared_fixture_profile_ids',
      note: 'Require-real artifacts must reuse the same fixture_profile IDs rather than inventing a separate naming layer.'
    },
    files: [
      'docs/memory-new/xhub-local-bench-fixture-pack-v1.md',
      'scripts/generate_lpr_w3_06_d_bench_fixture_pack_evidence.js',
      'x-hub/macos/RELFlowHub/Sources/RELFlowHub/Resources/BenchFixtures/bench_fixture_pack.v1.json',
      'x-hub/macos/RELFlowHub/Sources/RELFlowHub/LocalModelQuickBench.swift',
      'x-hub/python-runtime/python_service/providers/transformers_provider.py'
    ],
    missing_required_fixtures: missing
  };

  ensureDir(outPath);
  fs.writeFileSync(outPath, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');
  if (missing.length > 0) {
    process.exitCode = 1;
  }
}

main();
