import assert from 'node:assert/strict';

import {
  deriveSkillCapabilitySemantics,
  validateSkillCapabilityHints,
} from './skill_capability_derivation.js';

function run(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    process.stderr.write(`not ok - ${name}\n`);
    throw err;
  }
}

run('derives repo read semantics from legacy capability-only input', () => {
  const derived = deriveSkillCapabilitySemantics({
    skill_id: 'repo.git.status',
    capabilities_required: ['repo.read.status'],
  });

  assert.deepEqual(derived.intent_families, ['repo.read']);
  assert.deepEqual(derived.capability_families, ['repo.read']);
  assert.deepEqual(derived.capability_profiles, ['observe_only']);
  assert.equal(derived.grant_floor, 'none');
  assert.equal(derived.approval_floor, 'none');
});

run('derives privileged browser semantics for agent-browser fallback manifests', () => {
  const derived = deriveSkillCapabilitySemantics({
    skill_id: 'agent-browser',
    capabilities_required: ['browser.read', 'device.browser.control', 'web.fetch'],
    risk_level: 'high',
    requires_grant: true,
  });

  assert.ok(derived.intent_families.includes('browser.observe'));
  assert.ok(derived.intent_families.includes('browser.interact'));
  assert.ok(derived.intent_families.includes('browser.secret_fill'));
  assert.ok(derived.capability_families.includes('browser.observe'));
  assert.ok(derived.capability_families.includes('browser.interact'));
  assert.ok(derived.capability_families.includes('browser.secret_fill'));
  assert.ok(derived.capability_families.includes('web.live'));
  assert.ok(derived.capability_profiles.includes('observe_only'));
  assert.ok(derived.capability_profiles.includes('browser_research'));
  assert.ok(derived.capability_profiles.includes('browser_operator'));
  assert.ok(derived.capability_profiles.includes('browser_operator_with_secrets'));
  assert.equal(derived.grant_floor, 'privileged');
  assert.equal(derived.approval_floor, 'owner_confirmation');
});

run('fails closed when official capability hints diverge from canonical derivation', () => {
  const input = {
    skill_id: 'agent-browser',
    publisher_id: 'xhub.official',
    source_id: 'builtin:catalog',
    risk_level: 'high',
    requires_grant: true,
    capabilities_required: ['browser.read', 'device.browser.control', 'web.fetch'],
    intent_families: ['repo.read'],
    approval_floor_hint: 'local_approval',
  };

  const derived = deriveSkillCapabilitySemantics(input);
  const validation = validateSkillCapabilityHints(input, derived);

  assert.equal(validation.checked, true);
  assert.equal(validation.isOfficial, true);
  assert.equal(validation.isHighRisk, true);
  assert.equal(validation.fail_closed, true);
  assert.ok(validation.mismatches.some((entry) => entry.field === 'intent_families'));
  assert.ok(validation.mismatches.some((entry) => entry.field === 'approval_floor_hint'));
});
