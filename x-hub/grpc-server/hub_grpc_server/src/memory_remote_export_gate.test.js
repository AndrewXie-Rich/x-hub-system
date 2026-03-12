import assert from 'node:assert/strict';

import { evaluatePromptRemoteExportGate, resolveRemoteExportPolicy } from './memory_remote_export_gate.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

function withEnv(tempEnv, fn) {
  const prev = new Map();
  for (const [key, val] of Object.entries(tempEnv || {})) {
    prev.set(key, process.env[key]);
    if (val == null) delete process.env[key];
    else process.env[key] = String(val);
  }
  try {
    return fn();
  } finally {
    for (const [key, val] of prev.entries()) {
      if (val == null) delete process.env[key];
      else process.env[key] = val;
    }
  }
}

run('W5-03/default remote export policy stays fail-closed', () => {
  const policy = resolveRemoteExportPolicy();
  assert.equal(policy.export_class, 'prompt_bundle');
  assert.equal(policy.secret_mode, 'deny');
  assert.equal(policy.on_block, 'downgrade_to_local');
  assert.deepEqual(policy.allow_classes, ['prompt_bundle']);
});

run('W5-03/credential finding is permanent deny before other checks', () => {
  const result = evaluatePromptRemoteExportGate({
    export_class: 'not_allowed_class',
    prompt_text: 'api_key=sk-live-abcdef1234567890 token please',
    policy: {
      secret_mode: 'deny',
      allow_classes: ['another_class'],
      on_block: 'error',
    },
  });

  assert.equal(result.blocked, true);
  assert.equal(result.action, 'error');
  assert.equal(result.gate_reason, 'credential_finding');
  assert.equal(result.deny_code, 'credential_finding');
  assert.equal(result.job_sensitivity, 'secret');
  assert.equal(result.findings_summary.credential_count > 0, true);
  assert.deepEqual(
    result.gate_order.map((x) => x.step),
    ['secondary_dlp', 'credential_check', 'on_block']
  );
});

run('W5-03/secret_mode deny blocks secret prompt_bundle with downgrade action', () => {
  const result = evaluatePromptRemoteExportGate({
    prompt_text: 'User said [private]this is hidden[/private] please send.',
    policy: {
      secret_mode: 'deny',
      allow_classes: ['prompt_bundle'],
      on_block: 'downgrade_to_local',
    },
  });

  assert.equal(result.blocked, true);
  assert.equal(result.action, 'downgrade_to_local');
  assert.equal(result.downgraded, true);
  assert.equal(result.gate_reason, 'secret_mode_deny');
  assert.equal(result.findings_summary.secret_count > 0, true);
});

run('W5-03/allow_classes gate blocks non-whitelisted export class', () => {
  const result = evaluatePromptRemoteExportGate({
    export_class: 'tool_payload',
    prompt_text: 'normal non-sensitive content',
    policy: {
      secret_mode: 'deny',
      allow_classes: ['prompt_bundle'],
      on_block: 'error',
    },
  });

  assert.equal(result.blocked, true);
  assert.equal(result.action, 'error');
  assert.equal(result.gate_reason, 'allow_class_denied');
});

run('W5-03/allow_sanitized mode can sanitize and continue remote export', () => {
  const result = evaluatePromptRemoteExportGate({
    prompt_text: 'Do not leak <private>hidden note</private> to remote.',
    policy: {
      secret_mode: 'allow_sanitized',
      allow_classes: ['prompt_bundle'],
      on_block: 'error',
    },
  });

  assert.equal(result.blocked, false);
  assert.equal(result.action, 'allow');
  assert.equal(result.gate_reason, 'secret_sanitized');
  assert.equal(result.downgraded, true);
  assert.equal(result.prompt_text.includes('[REDACTED_PRIVATE_BLOCK]'), true);
});

run('W5-03/hex ids in project metadata no longer force secret downgrade', () => {
  const digest = '44a5c1a3eea646597383d386305e85c17de235c5a4a832dc212765fba8ba7c59';
  const result = evaluatePromptRemoteExportGate({
    prompt_text: `project_id=${digest}\nrequest_id=${digest}\nsha256:${digest}`,
    policy: {
      secret_mode: 'deny',
      allow_classes: ['prompt_bundle'],
      on_block: 'downgrade_to_local',
    },
  });

  assert.equal(result.blocked, false);
  assert.equal(result.findings_summary.secret_count, 0);
  assert.equal(result.gate_reason, 'allow');
});

run('W5-03/policy env overrides are respected', () => {
  withEnv(
    {
      HUB_REMOTE_EXPORT_SECRET_MODE: 'allow_sanitized',
      HUB_REMOTE_EXPORT_ON_BLOCK: 'error',
      HUB_REMOTE_EXPORT_ALLOW_CLASSES: 'prompt_bundle,tool_payload',
    },
    () => {
      const policy = resolveRemoteExportPolicy({});
      assert.equal(policy.secret_mode, 'allow_sanitized');
      assert.equal(policy.on_block, 'error');
      assert.deepEqual(policy.allow_classes.sort(), ['prompt_bundle', 'tool_payload']);
    }
  );
});
