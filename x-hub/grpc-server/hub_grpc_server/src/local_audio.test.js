import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { inspectWavAudio, transcribeLocalAudio } from './local_audio.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-audio-'));
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

function writeWav(filePath, { durationSec = 0.25, sampleRate = 16000 } = {}) {
  const frames = Math.max(1, Math.floor(durationSec * sampleRate));
  const dataSize = frames * 2;
  const out = Buffer.alloc(44 + dataSize, 0);
  out.write('RIFF', 0, 'ascii');
  out.writeUInt32LE(36 + dataSize, 4);
  out.write('WAVE', 8, 'ascii');
  out.write('fmt ', 12, 'ascii');
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(1, 22);
  out.writeUInt32LE(sampleRate, 24);
  out.writeUInt32LE(sampleRate * 2, 28);
  out.writeUInt16LE(2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36, 'ascii');
  out.writeUInt32LE(dataSize, 40);
  fs.writeFileSync(filePath, out);
}

function seedRuntimeState(baseDir) {
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-asr',
        name: 'HF ASR',
        backend: 'transformers',
        modelPath: '/models/hf-asr',
        taskKinds: ['speech_to_text'],
        inputModalities: ['audio'],
        outputModalities: ['text', 'segments'],
      },
    ],
  });
}

await run('inspectWavAudio returns duration and header metadata', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  const audioPath = path.join(runtimeBaseDir, 'clip.wav');
  writeWav(audioPath, { durationSec: 0.5 });
  const info = inspectWavAudio(audioPath);
  assert.equal(info.audio_format, '.wav');
  assert.equal(info.sample_rate, 16000);
  assert.equal(info.channel_count, 1);
  assert.ok(info.duration_sec > 0.49 && info.duration_sec < 0.51);
});

await run('transcribeLocalAudio denies when ai.audio.local is blocked', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const audioPath = path.join(runtimeBaseDir, 'clip.wav');
  writeWav(audioPath);
  const out = await transcribeLocalAudio({
    runtimeBaseDir,
    audioPath,
    capabilityAllowed: false,
    capabilityDenyCode: 'permission_denied',
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'permission_denied');
});

await run('transcribeLocalAudio denies when kill-switch disables ai.audio.local', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const audioPath = path.join(runtimeBaseDir, 'clip.wav');
  writeWav(audioPath);
  const out = await transcribeLocalAudio({
    runtimeBaseDir,
    audioPath,
    killSwitch: {
      disabled_local_capabilities: ['ai.audio.local'],
      reason: 'incident',
    },
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'kill_switch_capability:ai.audio.local');
});

await run('transcribeLocalAudio rejects overlong wav before runtime execution', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const audioPath = path.join(runtimeBaseDir, 'long.wav');
  writeWav(audioPath, { durationSec: 2.0 });
  const out = await transcribeLocalAudio({
    runtimeBaseDir,
    audioPath,
    maxAudioSeconds: 1,
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'input_too_large');
  assert.equal(out.raw_deny_code, 'audio_duration_too_long');
});

await run('transcribeLocalAudio normalizes successful runtime output', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const audioPath = path.join(runtimeBaseDir, 'clip.wav');
  writeWav(audioPath, { durationSec: 0.25 });
  let executorCalls = 0;
  const out = await transcribeLocalAudio({
    runtimeBaseDir,
    deviceId: 'terminal_device',
    audioPath,
    language: 'en',
    timestamps: true,
    executor: async ({ request }) => {
      executorCalls += 1;
      assert.equal(String(request?.task_kind || ''), 'speech_to_text');
      assert.equal(String(request?.device_id || ''), 'terminal_device');
      assert.equal(String(request?.options?.language || ''), 'en');
      assert.equal(!!request?.options?.timestamps, true);
      return {
        ok: true,
        provider: 'transformers',
        modelId: 'hf-asr',
        text: 'buy water',
        segments: [
          {
            index: 0,
            startSec: 0,
            endSec: 0.25,
            text: 'buy water',
          },
        ],
        latencyMs: 12,
        usage: {
          inputAudioBytes: 8044,
          inputAudioSec: 0.25,
          sampleRate: 16000,
          channelCount: 1,
          timestampsRequested: true,
        },
      };
    },
  });
  assert.equal(out.ok, true);
  assert.equal(out.provider, 'transformers');
  assert.equal(out.model_id, 'hf-asr');
  assert.equal(out.text, 'buy water');
  assert.equal(out.segments.length, 1);
  assert.equal(out.latency_ms, 12);
  assert.equal(executorCalls, 1);
});
