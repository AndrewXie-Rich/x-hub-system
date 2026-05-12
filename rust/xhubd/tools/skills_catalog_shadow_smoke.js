#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const RUNNER = path.join(SCRIPT_DIR, 'run_rust_hub.command');

function safeString(value) {
  return String(value ?? '').trim();
}

function runRust(args, env = {}) {
  const result = spawnSync('bash', [RUNNER, ...args], {
    cwd: ROOT_DIR,
    env: { ...process.env, ...env },
    encoding: 'utf8',
    maxBuffer: 1024 * 1024,
  });
  const stdout = safeString(result.stdout);
  let parsed = null;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    throw new Error(`Rust Hub command did not emit JSON: status=${result.status} args=${args.join(' ')} stdout=${stdout.slice(0, 400)} stderr=${safeString(result.stderr).slice(0, 400)} parse=${error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`Rust Hub command failed: status=${result.status} args=${args.join(' ')} parsed=${JSON.stringify(parsed)}`);
  }
  return parsed;
}

function assertOk(condition, message, details = {}) {
  if (!condition) {
    const suffix = Object.keys(details).length ? ` ${JSON.stringify(details).slice(0, 600)}` : '';
    throw new Error(`${message}${suffix}`);
  }
}

function assertNoSecretLeak(value, label) {
  const raw = JSON.stringify(value);
  assertOk(!raw.includes('sk-skill-secret-that-must-not-leak'), `${label} leaked secret value`);
  assertOk(!/"api_key"\s*:/.test(raw), `${label} leaked api_key field`);
}

function writeValidSkill(skillsDir) {
  const skill = path.join(skillsDir, 'memory-core');
  fs.mkdirSync(skill, { recursive: true });
  fs.writeFileSync(
    path.join(skill, 'SKILL.md'),
    '# Memory Core\nUse memory and model context through Hub policy gates. No execution authority here.\n',
    'utf8'
  );
}

function writeLeakySkill(skillsDir) {
  const skill = path.join(skillsDir, 'leaky');
  fs.mkdirSync(skill, { recursive: true });
  fs.writeFileSync(
    path.join(skill, 'skill.json'),
    `${JSON.stringify({
      id: 'leaky',
      name: 'Leaky',
      capabilities: ['memory'],
      api_key: 'sk-skill-secret-that-must-not-leak',
    }, null, 2)}\n`,
    'utf8'
  );
}

function main() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-skills-shadow-smoke-'));
  const validDir = path.join(tempRoot, 'valid-skills');
  const leakyDir = path.join(tempRoot, 'leaky-skills');
  const dbPath = path.join(tempRoot, 'data', 'hub.sqlite3');
  const env = { HUB_DB_PATH: dbPath };
  fs.mkdirSync(validDir, { recursive: true });
  fs.mkdirSync(leakyDir, { recursive: true });
  writeValidSkill(validDir);
  writeValidSkill(leakyDir);
  writeLeakySkill(leakyDir);

  try {
    const readiness = runRust(['skills', 'readiness', '--skills-dir', validDir], env);
    assertOk(readiness?.readiness?.ready === true, 'valid skills readiness was not ready', readiness);
    assertOk(readiness?.readiness?.execution_authority_in_rust === false, 'Rust unexpectedly owns skill execution', readiness);
    assertOk(readiness?.readiness?.hub_executes_third_party_code === false, 'Hub unexpectedly executes third-party code', readiness);

    const catalog = runRust(['skills', 'catalog', '--skills-dir', validDir], env);
    assertOk(catalog?.catalog?.schema_version === 'xhub.skills_catalog.v1', 'catalog schema mismatch', catalog);
    assertOk(Array.isArray(catalog?.catalog?.entries) && catalog.catalog.entries.length === 1, 'valid catalog count mismatch', catalog);
    assertOk(catalog.catalog.entries[0]?.status === 'accepted', 'valid skill was not accepted', catalog.catalog.entries[0] || {});
    assertOk(catalog.catalog.entries[0]?.requires_pin_or_grant === true, 'skill did not require pin/grant', catalog.catalog.entries[0] || {});

    const deniedPreflight = runRust([
      'skills',
      'preflight',
      '--skills-dir',
      validDir,
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--requested-capabilities',
      'memory',
      '--request-id',
      'skills-preflight-shadow-deny',
    ], env);
    assertOk(deniedPreflight?.preflight?.allowed === false, 'preflight without pin/grant did not deny', deniedPreflight);
    assertOk(JSON.stringify(deniedPreflight).includes('skill_pin_required'), 'denied preflight missing pin reason', deniedPreflight);
    assertOk(JSON.stringify(deniedPreflight).includes('capability_grant_required'), 'denied preflight missing grant reason', deniedPreflight);
    assertOk(deniedPreflight?.preflight?.execution_authority_in_rust === false, 'denied preflight reported execution authority', deniedPreflight);

    const pinned = runRust([
      'skills',
      'pin',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--actor',
      'skills-shadow-smoke',
    ], env);
    assertOk(pinned?.ok === true && pinned?.execution_authority_in_rust === false, 'durable pin failed', pinned);

    const granted = runRust([
      'skills',
      'grant',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--capability',
      'memory',
      '--actor',
      'skills-shadow-smoke',
    ], env);
    assertOk(granted?.ok === true && granted?.execution_authority_in_rust === false, 'durable grant failed', granted);

    const policy = runRust([
      'skills',
      'policy',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
    ], env);
    assertOk(policy?.policy?.pinned === true, 'durable policy did not report pinned skill', policy);
    assertOk(Array.isArray(policy?.policy?.granted_capabilities) && policy.policy.granted_capabilities.includes('memory'), 'durable policy did not report grant', policy);

    const allowedPreflight = runRust([
      'skills',
      'preflight',
      '--skills-dir',
      validDir,
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--requested-capabilities',
      'memory',
      '--request-id',
      'skills-preflight-shadow-allow',
      '--audit-ref',
      'skills-shadow-smoke',
    ], env);
    assertOk(allowedPreflight?.preflight?.schema_version === 'xhub.skills_preflight.v1', 'preflight schema mismatch', allowedPreflight);
    assertOk(allowedPreflight?.preflight?.allowed === true, 'preflight with pin/grant did not allow', allowedPreflight);
    assertOk(allowedPreflight?.preflight?.audit_event?.schema_version === 'xhub.skills_preflight.audit.v1', 'preflight audit schema mismatch', allowedPreflight);
    assertOk(allowedPreflight?.preflight?.execution_authority_in_rust === false, 'allowed preflight reported execution authority', allowedPreflight);

    const audit = runRust([
      'skills',
      'audit',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--limit',
      '10',
    ], env);
    assertOk(audit?.audit?.schema_version === 'xhub.skills_preflight_audit_summary.v1', 'audit summary schema mismatch', audit);
    assertOk(Number(audit?.audit?.total || 0) === 2, 'audit summary total mismatch', audit);
    assertOk(Number(audit?.audit?.allowed || 0) === 1, 'audit summary allowed mismatch', audit);
    assertOk(Number(audit?.audit?.denied || 0) === 1, 'audit summary denied mismatch', audit);
    assertOk(audit?.audit?.detail_json_included === false, 'audit summary exposed detail json', audit);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(audit)), 'audit summary leaked detail_json field', audit);

    const pruned = runRust(['skills', 'audit-prune', '--max-rows', '1'], env);
    assertOk(Number(pruned?.audit_prune?.deleted_rows || 0) >= 1, 'audit prune did not delete old rows', pruned);
    assertOk(Number(pruned?.audit_prune?.remaining_rows || 0) === 1, 'audit prune remaining count mismatch', pruned);

    const revokedGrant = runRust([
      'skills',
      'revoke-grant',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--capability',
      'memory',
      '--actor',
      'skills-shadow-smoke',
    ], env);
    assertOk(revokedGrant?.ok === true && Number(revokedGrant?.revoked_rows || 0) === 1, 'durable grant revoke failed', revokedGrant);

    const unpinned = runRust([
      'skills',
      'unpin',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--actor',
      'skills-shadow-smoke',
    ], env);
    assertOk(unpinned?.ok === true && Number(unpinned?.revoked_rows || 0) === 1, 'durable pin revoke failed', unpinned);

    const revokedPolicy = runRust([
      'skills',
      'policy',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
    ], env);
    assertOk(revokedPolicy?.policy?.pinned === false, 'revoked policy still reported pinned skill', revokedPolicy);
    assertOk(Array.isArray(revokedPolicy?.policy?.granted_capabilities) && revokedPolicy.policy.granted_capabilities.length === 0, 'revoked policy still reported grants', revokedPolicy);

    const revokedPreflight = runRust([
      'skills',
      'preflight',
      '--skills-dir',
      validDir,
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--requested-capabilities',
      'memory',
      '--request-id',
      'skills-preflight-shadow-revoked',
    ], env);
    assertOk(revokedPreflight?.preflight?.allowed === false, 'preflight after revoke did not deny', revokedPreflight);
    assertOk(JSON.stringify(revokedPreflight).includes('skill_pin_required'), 'revoked preflight missing pin reason', revokedPreflight);
    assertOk(JSON.stringify(revokedPreflight).includes('capability_grant_required'), 'revoked preflight missing grant reason', revokedPreflight);

    const policyEvents = runRust([
      'skills',
      'policy-events',
      '--scope-key',
      'project:skills-shadow-smoke',
      '--skill-id',
      'memory-core',
      '--limit',
      '10',
    ], env);
    assertOk(policyEvents?.policy_events?.schema_version === 'xhub.skills_policy_events.v1', 'policy events schema mismatch', policyEvents);
    assertOk(Number(policyEvents?.policy_events?.total || 0) === 4, 'policy event total mismatch', policyEvents);
    assertOk(policyEvents?.policy_events?.detail_json_included === false, 'policy events exposed detail json', policyEvents);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(policyEvents)), 'policy events leaked detail_json field', policyEvents);
    const operations = new Set((policyEvents?.policy_events?.rows || []).map((row) => row.operation));
    for (const operation of ['pin', 'grant', 'revoke_grant', 'unpin']) {
      assertOk(operations.has(operation), `policy events missing ${operation}`, policyEvents);
    }

    const policyEventsPruned = runRust(['skills', 'policy-events-prune', '--max-rows', '2'], env);
    assertOk(policyEventsPruned?.policy_events_prune?.schema_version === 'xhub.skills_policy_events_prune.v1', 'policy events prune schema mismatch', policyEventsPruned);
    assertOk(Number(policyEventsPruned?.policy_events_prune?.deleted_rows || 0) >= 2, 'policy events prune did not delete old rows', policyEventsPruned);
    assertOk(Number(policyEventsPruned?.policy_events_prune?.remaining_rows || 0) === 2, 'policy events prune remaining count mismatch', policyEventsPruned);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(policyEventsPruned)), 'policy events prune leaked detail_json field', policyEventsPruned);

    const policyReadiness = runRust([
      'skills',
      'policy-readiness',
      '--max-preflight-audit-rows',
      '10',
      '--max-policy-event-rows',
      '10',
    ], env);
    assertOk(policyReadiness?.policy_readiness?.schema_version === 'xhub.skills_policy_store_readiness.v1', 'policy readiness schema mismatch', policyReadiness);
    assertOk(policyReadiness?.policy_readiness?.ready === true, 'policy readiness was not ready', policyReadiness);
    assertOk(Number(policyReadiness?.policy_readiness?.preflight_audit_count || 0) === 2, 'policy readiness preflight audit count mismatch', policyReadiness);
    assertOk(Number(policyReadiness?.policy_readiness?.policy_event_count || 0) === 2, 'policy readiness event count mismatch', policyReadiness);
    assertOk(policyReadiness?.policy_readiness?.execution_authority_in_rust === false, 'policy readiness reported execution authority', policyReadiness);
    assertOk(!/"detail_json"\s*:/.test(JSON.stringify(policyReadiness)), 'policy readiness leaked detail_json field', policyReadiness);

    const blockedReadiness = runRust(['skills', 'readiness', '--skills-dir', leakyDir], env);
    assertOk(blockedReadiness?.readiness?.ready === false, 'leaky skills readiness did not fail closed', blockedReadiness);
    assertOk(Number(blockedReadiness?.readiness?.blocked_skill_count || 0) === 1, 'blocked skill count mismatch', blockedReadiness);
    assertNoSecretLeak(blockedReadiness, 'blocked readiness');

    const blockedCatalog = runRust(['skills', 'catalog', '--skills-dir', leakyDir], env);
    assertOk(Number(blockedCatalog?.catalog?.blocked_skill_count || 0) === 1, 'blocked catalog count mismatch', blockedCatalog);
    assertOk(JSON.stringify(blockedCatalog).includes('manifest_secret_pattern_denied'), 'blocked catalog missing deny code', blockedCatalog);
    assertNoSecretLeak(blockedCatalog, 'blocked catalog');

    process.stdout.write(`${JSON.stringify({
      ok: true,
      schema_version: 'xhub.rust_hub.skills_catalog_shadow_smoke.v1',
      command: 'skills-catalog-shadow-smoke',
      readiness_ready: readiness.readiness.ready,
      accepted_skill_count: catalog.catalog.accepted_skill_count,
      blocked_skill_count: blockedCatalog.catalog.blocked_skill_count,
      execution_authority_in_rust: false,
      hub_executes_third_party_code: false,
      requires_pin_or_grant: true,
      secret_manifest_denied: true,
      preflight_denied_without_pin_or_grant: true,
      durable_pin_grant_recorded: true,
      preflight_allowed_with_durable_pin_and_grant: true,
      audit_summary_recorded: true,
      audit_prune_bounded: true,
      durable_pin_grant_revoked: true,
      preflight_denied_after_revoke: true,
      policy_events_recorded: true,
      policy_events_prune_bounded: true,
      policy_store_readiness_ready: true,
      secret_leak: false,
    }, null, 2)}\n`);
  } finally {
    try {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    } catch {}
  }
}

try {
  main();
} catch (error) {
  process.stderr.write(`[skills_catalog_shadow_smoke] ${error?.stack || error?.message || error}\n`);
  process.exit(1);
}
