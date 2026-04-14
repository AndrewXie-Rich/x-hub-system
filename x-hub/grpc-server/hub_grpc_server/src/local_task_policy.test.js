import assert from 'node:assert/strict';

import {
  buildLocalTaskFailure,
  evaluateLocalTaskPolicyGate,
  localTaskCapabilityKey,
  localTaskGovernanceComponentForFailure,
  normalizeLocalTaskDenyCode,
} from './local_task_policy.js';
import { capabilityDbKey, toProtoCapability } from './services.js';

function run(name, fn) {
  try {
    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === 'function') {
      return maybePromise.then(() => {
        process.stdout.write(`ok - ${name}\n`);
      }).catch((error) => {
        process.stderr.write(`not ok - ${name}\n`);
        throw error;
      });
    }
    process.stdout.write(`ok - ${name}\n`);
    return Promise.resolve();
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

await run('capability proto mapping includes local embed audio and vision', async () => {
  assert.equal(toProtoCapability('ai.embed.local'), 'CAPABILITY_AI_EMBED_LOCAL');
  assert.equal(toProtoCapability('ai.audio.local'), 'CAPABILITY_AI_AUDIO_LOCAL');
  assert.equal(toProtoCapability('ai.audio.tts.local'), 'CAPABILITY_AI_AUDIO_LOCAL');
  assert.equal(toProtoCapability('ai.vision.local'), 'CAPABILITY_AI_VISION_LOCAL');
  assert.equal(capabilityDbKey('CAPABILITY_AI_EMBED_LOCAL'), 'ai.embed.local');
  assert.equal(capabilityDbKey('CAPABILITY_AI_AUDIO_LOCAL'), 'ai.audio.local');
  assert.equal(capabilityDbKey('ai.audio.tts.local'), 'ai.audio.local');
  assert.equal(capabilityDbKey('CAPABILITY_AI_VISION_LOCAL'), 'ai.vision.local');
  assert.equal(localTaskCapabilityKey('text_to_speech'), 'ai.audio.tts.local');
});

await run('evaluateLocalTaskPolicyGate normalizes capability and provider kill-switch denies', async () => {
  const capabilityBlocked = evaluateLocalTaskPolicyGate({
    taskKind: 'embedding',
    provider: 'transformers',
    capabilityAllowed: false,
    capabilityDenyCode: 'permission_denied',
  });
  assert.equal(capabilityBlocked.ok, false);
  assert.equal(capabilityBlocked.deny_code, 'capability_blocked');
  assert.equal(capabilityBlocked.raw_deny_code, 'permission_denied');
  assert.equal(capabilityBlocked.governance_component, 'capability');

  const providerBlocked = evaluateLocalTaskPolicyGate({
    taskKind: 'speech_to_text',
    provider: 'transformers',
    killSwitch: {
      disabled_local_providers: ['transformers'],
      reason: 'incident',
    },
  });
  assert.equal(providerBlocked.ok, false);
  assert.equal(providerBlocked.deny_code, 'provider_blocked');
  assert.equal(providerBlocked.raw_deny_code, 'kill_switch_provider:transformers');
  assert.equal(providerBlocked.governance_component, 'grant');

  const ttsBlockedByLegacyAudioKillSwitch = evaluateLocalTaskPolicyGate({
    taskKind: 'text_to_speech',
    provider: 'transformers',
    killSwitch: {
      disabled_local_capabilities: ['ai.audio.local'],
      reason: 'incident',
    },
  });
  assert.equal(ttsBlockedByLegacyAudioKillSwitch.ok, false);
  assert.equal(ttsBlockedByLegacyAudioKillSwitch.capability, 'ai.audio.tts.local');
  assert.equal(ttsBlockedByLegacyAudioKillSwitch.raw_deny_code, 'kill_switch_capability:ai.audio.local');
  assert.equal(ttsBlockedByLegacyAudioKillSwitch.governance_component, 'grant');
});

await run('buildLocalTaskFailure maps modality and input-size deny codes', async () => {
  assert.equal(normalizeLocalTaskDenyCode('audio_duration_too_long'), 'input_too_large');
  assert.equal(normalizeLocalTaskDenyCode('unsupported_audio_format'), 'modality_unsupported');
  assert.equal(normalizeLocalTaskDenyCode('task_not_implemented:transformers:text_to_speech'), 'provider_unavailable');
  assert.equal(normalizeLocalTaskDenyCode('tts_native_runtime_failed'), 'provider_unavailable');
  assert.equal(normalizeLocalTaskDenyCode('native_dependency_error'), 'provider_unavailable');
  assert.equal(normalizeLocalTaskDenyCode('image_dimensions_too_large'), 'input_too_large');
  assert.equal(normalizeLocalTaskDenyCode('unsupported_image_format'), 'modality_unsupported');
  assert.equal(normalizeLocalTaskDenyCode('policy_blocked_secret_image'), 'policy_blocked');

  const failure = buildLocalTaskFailure({
    taskKind: 'text_to_speech',
    provider: 'transformers',
    rawDenyCode: 'audio_duration_too_long',
    blockedBy: 'input',
  });
  assert.equal(failure.deny_code, 'input_too_large');
  assert.equal(failure.raw_deny_code, 'audio_duration_too_long');
  assert.equal(failure.blocked_by, 'input');
  assert.equal(failure.capability, 'ai.audio.tts.local');
  assert.equal(failure.governance_component, 'capability');

  assert.equal(localTaskGovernanceComponentForFailure({
    denyCode: 'policy_blocked',
    rawDenyCode: 'trusted_automation_capabilities_empty_blocked',
    blockedBy: 'policy',
  }), 'grant');
});
