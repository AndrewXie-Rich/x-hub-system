#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function main(argv) {
  const flags = parseFlags(argv);
  if (flags.has('help') || flags.has('h')) {
    process.stdout.write(helpText());
    return 0;
  }
  if (flags.has('self-test')) {
    runSelfTest();
    process.stdout.write('node_scheduler_shadow_compare self-test ok\n');
    return 0;
  }

  const snapshot = snapshotFromFlags(flags);
  const normalized = normalizeSchedulerSnapshot(snapshot);
  const runner = flags.get('runner') || defaultRunnerPath();
  const args = buildCompareArgs(normalized);

  if (flags.has('dry-run')) {
    process.stdout.write(
      JSON.stringify(
        {
          schema_version: 'xhub.node_scheduler_shadow_compare.dry_run.v1',
          ok: true,
          runner,
          args,
          normalized,
        },
        null,
        2
      ) + '\n'
    );
    return 0;
  }

  const result = spawnSync(runner, args, {
    cwd: path.resolve(path.dirname(runner), '..'),
    encoding: 'utf8',
  });

  if (result.error) {
    process.stderr.write(`scheduler shadow compare failed to start: ${result.error.message}\n`);
    return 127;
  }
  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }
  return result.status == null ? 1 : result.status;
}

function parseFlags(argv) {
  const flags = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      throw new Error(`unexpected positional argument: ${token}`);
    }
    const body = token.slice(2);
    if (!body) {
      throw new Error('empty flag is not supported');
    }
    const eq = body.indexOf('=');
    if (eq >= 0) {
      flags.set(body.slice(0, eq), body.slice(eq + 1));
      continue;
    }
    const next = argv[index + 1];
    if (next != null && !next.startsWith('--')) {
      flags.set(body, next);
      index += 1;
    } else {
      flags.set(body, 'true');
    }
  }
  return flags;
}

function snapshotFromFlags(flags) {
  if (flags.has('snapshot-json')) {
    return parseJson(flags.get('snapshot-json'), '--snapshot-json');
  }
  if (flags.has('snapshot-file')) {
    const file = flags.get('snapshot-file');
    const text = file === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(file, 'utf8');
    return parseJson(text, `--snapshot-file ${file}`);
  }

  return {
    in_flight_total: requiredInt(flags, 'node-in-flight-total'),
    queue_depth: requiredInt(flags, 'node-queue-depth'),
    oldest_queued_ms: optionalInt(flags, 'node-oldest-queued-ms'),
  };
}

function normalizeSchedulerSnapshot(snapshot) {
  const paidAi = snapshot.paid_ai || snapshot.paidAI || snapshot.paidAi || snapshot.scheduler || {};
  const source = { ...snapshot, ...paidAi };
  return {
    in_flight_total: readRequiredInt(source, [
      'in_flight_total',
      'inFlightTotal',
      'in_flight',
      'inFlight',
      'inflight',
    ]),
    queue_depth: readRequiredInt(source, ['queue_depth', 'queueDepth', 'queued', 'queued_total']),
    oldest_queued_ms: readOptionalInt(source, ['oldest_queued_ms', 'oldestQueuedMs']),
  };
}

function buildCompareArgs(snapshot) {
  const args = [
    'scheduler',
    'compare',
    '--node-in-flight-total',
    String(snapshot.in_flight_total),
    '--node-queue-depth',
    String(snapshot.queue_depth),
  ];
  if (snapshot.oldest_queued_ms != null) {
    args.push('--node-oldest-queued-ms', String(snapshot.oldest_queued_ms));
  }
  return args;
}

function defaultRunnerPath() {
  return path.join(__dirname, 'run_rust_hub.command');
}

function parseJson(text, label) {
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`invalid JSON from ${label}: ${error.message}`);
  }
}

function requiredInt(flags, key) {
  if (!flags.has(key)) {
    throw new Error(`missing required flag --${key}`);
  }
  return parseInteger(flags.get(key), `--${key}`);
}

function optionalInt(flags, key) {
  if (!flags.has(key)) {
    return null;
  }
  return parseInteger(flags.get(key), `--${key}`);
}

function readRequiredInt(source, keys) {
  for (const key of keys) {
    if (source[key] != null) {
      return parseInteger(source[key], key);
    }
  }
  throw new Error(`snapshot missing required numeric field: ${keys.join('|')}`);
}

function readOptionalInt(source, keys) {
  for (const key of keys) {
    if (source[key] != null) {
      return parseInteger(source[key], key);
    }
  }
  return null;
}

function parseInteger(value, label) {
  const number = typeof value === 'number' ? value : Number.parseInt(String(value), 10);
  if (!Number.isSafeInteger(number)) {
    throw new Error(`${label} must be a safe integer`);
  }
  return number;
}

function helpText() {
  return `Usage:
  node tools/node_scheduler_shadow_compare.js --node-in-flight-total 0 --node-queue-depth 0
  node tools/node_scheduler_shadow_compare.js --snapshot-json '{"paid_ai":{"in_flight_total":0,"queue_depth":0}}'
  node tools/node_scheduler_shadow_compare.js --snapshot-file -

Options:
  --runner <path>              Path to tools/run_rust_hub.command
  --node-in-flight-total <n>   Node scheduler in-flight total
  --node-queue-depth <n>       Node scheduler queue depth
  --node-oldest-queued-ms <n>  Optional oldest queued age
  --snapshot-json <json>       Node scheduler snapshot JSON
  --snapshot-file <path|->     Node scheduler snapshot JSON file, or stdin
  --dry-run                    Print normalized command without running xhubd
  --self-test                  Run local parser/normalizer tests
`;
}

function runSelfTest() {
  const parsed = parseFlags([
    '--snapshot-json',
    '{"paid_ai":{"in_flight_total":2,"queue_depth":3,"oldest_queued_ms":4}}',
    '--dry-run',
  ]);
  assert.equal(parsed.get('dry-run'), 'true');
  const normalized = normalizeSchedulerSnapshot(snapshotFromFlags(parsed));
  assert.deepEqual(normalized, {
    in_flight_total: 2,
    queue_depth: 3,
    oldest_queued_ms: 4,
  });
  assert.deepEqual(buildCompareArgs(normalized), [
    'scheduler',
    'compare',
    '--node-in-flight-total',
    '2',
    '--node-queue-depth',
    '3',
    '--node-oldest-queued-ms',
    '4',
  ]);

  const camel = normalizeSchedulerSnapshot({
    paidAI: { inFlightTotal: '1', queueDepth: '0' },
  });
  assert.deepEqual(camel, {
    in_flight_total: 1,
    queue_depth: 0,
    oldest_queued_ms: null,
  });
}

if (require.main === module) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  buildCompareArgs,
  normalizeSchedulerSnapshot,
  parseFlags,
  snapshotFromFlags,
};
