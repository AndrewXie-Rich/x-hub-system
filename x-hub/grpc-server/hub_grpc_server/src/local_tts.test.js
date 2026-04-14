import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { synthesizeLocalSpeech } from './local_tts.js';

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

function makeTempRuntimeDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-tts-'));
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

function seedRuntimeState(baseDir) {
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-tts',
        name: 'HF TTS',
        backend: 'transformers',
        modelPath: '/models/hf-tts',
        taskKinds: ['text_to_speech'],
        inputModalities: ['text'],
        outputModalities: ['audio'],
      },
    ],
  });
}

await run('synthesizeLocalSpeech denies when ai.audio.tts.local is blocked', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const out = await synthesizeLocalSpeech({
    runtimeBaseDir,
    text: 'hello world',
    capabilityAllowed: false,
    capabilityDenyCode: 'permission_denied',
  });
  assert.equal(out.ok, false);
  assert.equal(out.capability, 'ai.audio.tts.local');
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'permission_denied');
  assert.equal(out.tts_audit?.source_kind, 'failed');
  assert.equal(out.tts_audit?.capability, 'ai.audio.tts.local');
  assert.equal(out.tts_audit?.deny_code, 'capability_blocked');
  assert.equal(out.tts_audit_line.includes('deny=capability_blocked'), true);
});

await run('synthesizeLocalSpeech honors dedicated tts kill-switch and legacy audio alias', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);

  const dedicatedBlocked = await synthesizeLocalSpeech({
    runtimeBaseDir,
    text: 'hello world',
    killSwitch: {
      disabled_local_capabilities: ['ai.audio.tts.local'],
      reason: 'incident',
    },
  });
  assert.equal(dedicatedBlocked.ok, false);
  assert.equal(dedicatedBlocked.capability, 'ai.audio.tts.local');
  assert.equal(dedicatedBlocked.raw_deny_code, 'kill_switch_capability:ai.audio.tts.local');

  const legacyBlocked = await synthesizeLocalSpeech({
    runtimeBaseDir,
    text: 'hello world',
    killSwitch: {
      disabled_local_capabilities: ['ai.audio.local'],
      reason: 'incident',
    },
  });
  assert.equal(legacyBlocked.ok, false);
  assert.equal(legacyBlocked.capability, 'ai.audio.tts.local');
  assert.equal(legacyBlocked.raw_deny_code, 'kill_switch_capability:ai.audio.local');
});

await run('synthesizeLocalSpeech rejects oversized text before runtime execution', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const out = await synthesizeLocalSpeech({
    runtimeBaseDir,
    text: 'a'.repeat(65),
    maxTextChars: 64,
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'input_too_large');
  assert.equal(out.raw_deny_code, 'tts_input_too_large');
});

await run('synthesizeLocalSpeech normalizes successful runtime output', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  let executorCalls = 0;
  const out = await synthesizeLocalSpeech({
    runtimeBaseDir,
    deviceId: 'terminal_device',
    text: '项目进度正常',
    locale: 'zh_CN',
    voiceColor: 'warm',
    speechRate: 1.2,
    executor: async ({ request }) => {
      executorCalls += 1;
      assert.equal(String(request?.task_kind || ''), 'text_to_speech');
      assert.equal(String(request?.device_id || ''), 'terminal_device');
      assert.equal(String(request?.options?.locale || ''), 'zh-CN');
      assert.equal(String(request?.options?.voice_color || ''), 'warm');
      assert.equal(Number(request?.options?.speech_rate || 0), 1.2);
      return {
        ok: true,
        provider: 'transformers',
        modelId: 'hf-tts',
        audioPath: '/tmp/hub_voice.wav',
        audioFormat: 'wav',
        engineName: 'kokoro',
        speakerId: 'zh_warm_f1',
        nativeTTSUsed: false,
        fallbackReasonCode: 'system_voice_compatibility_fallback',
        locale: 'zh-CN',
        voiceColor: 'warm',
        speechRate: 1.2,
        latencyMs: 18,
        usage: {
          inputTextChars: 6,
          outputAudioBytes: 4096,
        },
      };
    },
  });
  assert.equal(out.ok, true);
  assert.equal(out.provider, 'transformers');
  assert.equal(out.model_id, 'hf-tts');
  assert.equal(out.audio_path, '/tmp/hub_voice.wav');
  assert.equal(out.audio_format, 'wav');
  assert.equal(out.engine_name, 'kokoro');
  assert.equal(out.speaker_id, 'zh_warm_f1');
  assert.equal(out.native_tts_used, false);
  assert.equal(out.fallback_reason_code, 'system_voice_compatibility_fallback');
  assert.equal(out.locale, 'zh-CN');
  assert.equal(out.voice_color, 'warm');
  assert.equal(out.speech_rate, 1.2);
  assert.equal(out.latency_ms, 18);
  assert.equal(out.tts_audit?.schema_version, 'xhub.local_tts_audit.v1');
  assert.equal(out.tts_audit?.source_kind, 'fallback_output');
  assert.equal(out.tts_audit?.output_ref_kind, 'audio_path');
  assert.equal(out.tts_audit?.fallback_used, true);
  assert.equal(out.tts_audit?.model_id, 'hf-tts');
  assert.equal(out.tts_audit?.route_source, out.route_source);
  assert.equal(out.tts_audit?.engine_name, 'kokoro');
  assert.equal(out.tts_audit_line.includes('fallback=system_voice_compatibility_fallback'), true);
  assert.equal(executorCalls, 1);
});

await run('synthesizeLocalSpeech honors routed device override model selection', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  writeJson(path.join(runtimeBaseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-tts-default',
        name: 'HF TTS Default',
        backend: 'transformers',
        modelPath: '/models/hf-tts-default',
        taskKinds: ['text_to_speech'],
        inputModalities: ['text'],
        outputModalities: ['audio'],
      },
      {
        id: 'hf-tts-device',
        name: 'HF TTS Device',
        backend: 'transformers',
        modelPath: '/models/hf-tts-device',
        taskKinds: ['text_to_speech'],
        inputModalities: ['text'],
        outputModalities: ['audio'],
      },
    ],
  });
  writeJson(path.join(runtimeBaseDir, 'routing_settings.json'), {
    hubDefaultModelIdByTaskKind: {
      text_to_speech: 'hf-tts-default',
    },
    devicePreferredModelIdByTaskKind: {
      terminal_device: {
        text_to_speech: 'hf-tts-device',
      },
    },
  });

  const out = await synthesizeLocalSpeech({
    runtimeBaseDir,
    deviceId: 'terminal_device',
    text: 'hello world',
    executor: async ({ request }) => {
      assert.equal(String(request?.model_id || ''), 'hf-tts-device');
      return {
        ok: true,
        provider: 'transformers',
        modelId: 'hf-tts-device',
        audioClipRef: 'hub://audio/clip/abc123',
        latencyMs: 9,
        usage: {
          inputTextChars: 11,
        },
      };
    },
  });

  assert.equal(out.ok, true);
  assert.equal(out.model_id, 'hf-tts-device');
  assert.equal(out.audio_clip_ref, 'hub://audio/clip/abc123');
  assert.equal(out.route_source, 'device_override');
  assert.equal(out.resolved_model_id, 'hf-tts-device');
});

await run('synthesizeLocalSpeech normalizes task_not_implemented runtime failures', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const out = await synthesizeLocalSpeech({
    runtimeBaseDir,
    text: 'hello world',
    executor: async () => ({
      ok: false,
      provider: 'transformers',
      modelId: 'hf-tts',
      error: 'task_not_implemented:transformers:text_to_speech',
      errorDetail: 'tts runtime not enabled yet',
      usage: {
        inputTextChars: 11,
      },
    }),
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'provider_unavailable');
  assert.equal(out.raw_deny_code, 'task_not_implemented:transformers:text_to_speech');
  assert.equal(out.message, 'tts runtime not enabled yet');
  assert.equal(out.tts_audit?.source_kind, 'failed');
  assert.equal(out.tts_audit?.model_id, 'hf-tts');
  assert.equal(out.tts_audit?.route_source, out.route_source);
  assert.equal(out.tts_audit?.deny_code, 'provider_unavailable');
  assert.equal(out.tts_audit_line.includes('status=failed'), true);
});
