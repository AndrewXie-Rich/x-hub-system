#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');

function parseIntInRange(value, fallback, min, max) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function parseArgs(argv) {
  const out = {
    timeoutMs: 30000,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--timeout-ms':
        out.timeoutMs = parseIntInRange(next, out.timeoutMs, 1000, 120000);
        i += 1;
        break;
      case '--help':
      case '-h':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  return out;
}

function usage() {
  return [
    'model_inventory_shadow_compare_smoke.js',
    '',
    'Options:',
    '  --timeout-ms <ms>    Command timeout, default 30000',
  ].join('\n');
}

function parseJsonLine(stdout) {
  const line = String(stdout || '')
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean)
    .reverse()
    .find((item) => item.startsWith('{'));
  if (!line) throw new Error('missing JSON output');
  return JSON.parse(line);
}

function cleanupPath(target) {
  try {
    fs.rmSync(target, { recursive: true, force: true });
  } catch {
    // ignore cleanup failures
  }
}

function writeFixture(runtimeBaseDir) {
  fs.mkdirSync(runtimeBaseDir, { recursive: true });
  const artifactPath = path.join(runtimeBaseDir, 'local.summary.gguf');
  fs.writeFileSync(artifactPath, 'fixture');
  fs.writeFileSync(path.join(runtimeBaseDir, 'hub_provider_keys.json'), JSON.stringify({
    providers: {
      openai: {
        routing_strategy: 'priority',
        accounts: [
          {
            account_key: 'acct-model-inventory-shadow',
            provider: 'openai',
            api_key: 'sk-model-inventory-shadow-smoke',
            models: ['openai/GPT5.5'],
            provider_host: 'api.openai.com',
            pool_id: 'free',
          },
        ],
      },
    },
  }, null, 2));
  fs.writeFileSync(path.join(runtimeBaseDir, 'models_state.json'), JSON.stringify({
    models: [
      {
        id: 'local.summary',
        name: 'Local Summary',
        backend: 'mlx',
        modelPath: artifactPath,
        capabilities: ['text_generate'],
      },
    ],
  }, null, 2));
  fs.writeFileSync(path.join(runtimeBaseDir, 'ai_runtime_status.json'), JSON.stringify({
    providers: {
      mlx: {
        provider: 'mlx',
        ok: true,
        availableTaskKinds: ['text.generate'],
        runtimeSource: 'fixture',
        runtimeSourcePath: '/tmp/fixture-runtime',
        runtimeResolutionState: 'resolved',
        updatedAtMs: 1000,
      },
    },
  }, null, 2));
}

function toNodeInventoryFixture(inventory) {
  return {
    schemaVersion: inventory.schema_version,
    ok: inventory.ok === true,
    remoteModels: [...(inventory.remote_models || [])].reverse().map((row) => ({
      modelId: row.model_id === 'gpt-5.5' ? 'openai/GPT5.5' : row.model_id,
      provider: String(row.provider || '').toUpperCase(),
      providerHost: row.provider_host,
      familyKey: row.family_key,
      poolId: row.pool_id,
      availabilityState: row.availability_state,
      availableAccountCount: row.available_account_count,
      totalAccountCount: row.total_account_count,
      blockingReasonCode: row.blocking_reason_code,
      nextRetryAtMs: row.next_retry_at_ms,
    })),
    localModels: [...(inventory.local_models || [])].reverse().map((row) => ({
      modelId: row.model_id,
      displayName: row.display_name,
      familyKey: row.family_key,
      artifactPath: row.artifact_path,
      format: row.format,
      artifactSizeBytes: row.artifact_size_bytes,
      checksum: row.checksum,
      quantization: row.quantization,
      runtimeProvider: row.runtime_provider,
      availabilityState: row.availability_state,
      blockingReasonCode: row.blocking_reason_code,
      capabilities: (row.capabilities || []).map((item) => String(item).replaceAll('.', '_')),
      memoryRisk: row.memory_risk,
      duplicateArtifactOf: row.duplicate_artifact_of,
      runtimePreflight: {
        runtimeProvider: row.runtime_preflight?.runtime_provider,
        availabilityState: row.runtime_preflight?.availability_state,
        blockingReasonCode: row.runtime_preflight?.blocking_reason_code,
        runtimeSource: row.runtime_preflight?.runtime_source,
        runtimeSourcePath: row.runtime_preflight?.runtime_source_path,
        supportedFormat: row.runtime_preflight?.supported_format,
        sideEffectFree: row.runtime_preflight?.side_effect_free,
        updatedAtMs: row.runtime_preflight?.runtime_updated_at_ms,
        availableTaskKinds: (row.runtime_preflight?.capability_tags || []).map((item) => String(item).replaceAll('.', '_')),
        missingRequirements: row.runtime_preflight?.runtime_missing_requirements || [],
      },
    })),
  };
}

function runRust(args, env, timeoutMs) {
  const runnerPath = path.join(ROOT_DIR, 'tools', 'run_rust_hub.command');
  return parseJsonLine(execFileSync(
    runnerPath,
    args,
    {
      encoding: 'utf8',
      env,
      timeout: timeoutMs,
      maxBuffer: 10 * 1024 * 1024,
    }
  ));
}

function assertNoSecret(value, label) {
  const raw = JSON.stringify(value);
  if (raw.includes('sk-model-inventory-shadow-smoke')) {
    throw new Error(`${label} leaked provider secret`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }

  const runtimeBaseDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-model-inventory-shadow-runtime-'));
  const dbDir = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-model-inventory-shadow-db-'));
  const rustDbPath = path.join(dbDir, 'rust_hub.sqlite3');
  const env = {
    ...process.env,
    HUB_RUNTIME_BASE_DIR: runtimeBaseDir,
    HUB_DB_PATH: rustDbPath,
    XHUB_RUST_HUB_ROOT: ROOT_DIR,
  };

  try {
    writeFixture(runtimeBaseDir);
    const inventory = runRust(
      ['model', 'inventory', '--runtime-base-dir', runtimeBaseDir, '--now-ms', '1000'],
      env,
      args.timeoutMs
    );
    assertNoSecret(inventory, 'model inventory');

    const nodeInventory = toNodeInventoryFixture(inventory);
    const compare = runRust(
      ['model', 'compare', '--node-inventory-json', JSON.stringify(nodeInventory), '--runtime-base-dir', runtimeBaseDir, '--now-ms', '1000'],
      env,
      args.timeoutMs
    );
    if (compare?.match !== true) {
      throw new Error(`model inventory shadow compare did not match: ${JSON.stringify(compare?.mismatches || [])}`);
    }
    assertNoSecret(compare, 'model inventory compare');

    const reports = runRust(['model', 'reports', '--limit', '5'], env, args.timeoutMs);
    if (Number(reports?.total || 0) < 1 || Number(reports?.mismatched || 0) !== 0) {
      throw new Error(`unexpected model inventory reports summary: ${JSON.stringify(reports)}`);
    }

    const readiness = runRust(
      ['model', 'readiness', '--min-compare-reports', '1', '--max-mismatches', '0', '--limit', '5'],
      env,
      args.timeoutMs
    );
    if (readiness?.ready !== true) {
      throw new Error(`model inventory readiness not ready: ${JSON.stringify(readiness)}`);
    }

    console.log(JSON.stringify({
      ok: true,
      schema_version: 'xhub.model_inventory_shadow_compare_smoke.v1',
      shadow_match: compare.match === true,
      reports_total: reports.total,
      readiness_ready: readiness.ready,
      remote_models: inventory.remote_models?.length || 0,
      local_models: inventory.local_models?.length || 0,
      runtime_base_dir: runtimeBaseDir,
      rust_db_path: rustDbPath,
    }, null, 2));
  } finally {
    cleanupPath(runtimeBaseDir);
    cleanupPath(dbDir);
  }
}

main().catch((error) => {
  console.error(`[model_inventory_shadow_compare_smoke] ${error?.stack || error?.message || error}`);
  process.exit(1);
});
