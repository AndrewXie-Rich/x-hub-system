import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  inspectLocalImage,
  ocrLocalImage,
  runLocalVisionTask,
  understandLocalImage,
} from './local_vision.js';

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
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-local-vision-'));
}

function writeJson(filePath, obj) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(obj), 'utf8');
}

function writePng(filePath, { width = 24, height = 18 } = {}) {
  const out = Buffer.alloc(33, 0);
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).copy(out, 0);
  out.writeUInt32BE(13, 8);
  out.write('IHDR', 12, 'ascii');
  out.writeUInt32BE(width, 16);
  out.writeUInt32BE(height, 20);
  out[24] = 8;
  out[25] = 2;
  fs.writeFileSync(filePath, out);
}

function seedRuntimeState(baseDir) {
  writeJson(path.join(baseDir, 'models_state.json'), {
    updatedAt: Date.now() / 1000.0,
    models: [
      {
        id: 'hf-vision',
        name: 'HF Vision',
        backend: 'transformers',
        modelPath: '/models/hf-vision',
        taskKinds: ['vision_understand'],
        inputModalities: ['image'],
        outputModalities: ['text'],
      },
      {
        id: 'hf-ocr',
        name: 'HF OCR',
        backend: 'transformers',
        modelPath: '/models/hf-ocr',
        taskKinds: ['ocr'],
        inputModalities: ['image'],
        outputModalities: ['text', 'spans'],
      },
    ],
  });
}

await run('inspectLocalImage returns width height and pixel metadata', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  const imagePath = path.join(runtimeBaseDir, 'frame.png');
  writePng(imagePath, { width: 40, height: 25 });
  const info = inspectLocalImage(imagePath);
  assert.equal(info.image_format, '.png');
  assert.equal(info.width, 40);
  assert.equal(info.height, 25);
  assert.equal(info.pixel_count, 1000);
});

await run('understandLocalImage denies when ai.vision.local is blocked', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const imagePath = path.join(runtimeBaseDir, 'frame.png');
  writePng(imagePath);
  const out = await understandLocalImage({
    runtimeBaseDir,
    imagePath,
    capabilityAllowed: false,
    capabilityDenyCode: 'permission_denied',
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'permission_denied');
});

await run('understandLocalImage denies when kill-switch disables ai.vision.local', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const imagePath = path.join(runtimeBaseDir, 'frame.png');
  writePng(imagePath);
  const out = await understandLocalImage({
    runtimeBaseDir,
    imagePath,
    killSwitch: {
      disabled_local_capabilities: ['ai.vision.local'],
      reason: 'incident',
    },
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'capability_blocked');
  assert.equal(out.raw_deny_code, 'kill_switch_capability:ai.vision.local');
});

await run('runLocalVisionTask rejects unsupported image format before runtime execution', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const imagePath = path.join(runtimeBaseDir, 'frame.gif');
  fs.writeFileSync(imagePath, 'GIF89a', 'ascii');
  const out = await runLocalVisionTask({
    runtimeBaseDir,
    taskKind: 'vision_understand',
    imagePath,
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'modality_unsupported');
  assert.equal(out.raw_deny_code, 'unsupported_image_format');
});

await run('runLocalVisionTask rejects oversize image dimensions before runtime execution', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const imagePath = path.join(runtimeBaseDir, 'wide.png');
  writePng(imagePath, { width: 160, height: 48 });
  const out = await runLocalVisionTask({
    runtimeBaseDir,
    taskKind: 'vision_understand',
    imagePath,
    maxImageDimension: 64,
  });
  assert.equal(out.ok, false);
  assert.equal(out.deny_code, 'input_too_large');
  assert.equal(out.raw_deny_code, 'image_dimensions_too_large');
  assert.equal(out.usage.inputImageWidth, 160);
  assert.equal(out.usage.inputImageHeight, 48);
});

await run('understandLocalImage normalizes successful runtime preview output', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const imagePath = path.join(runtimeBaseDir, 'frame.png');
  writePng(imagePath, { width: 32, height: 20 });
  let executorCalls = 0;
  const out = await understandLocalImage({
    runtimeBaseDir,
    deviceId: 'terminal_device',
    imagePath,
    prompt: 'describe the scene',
    executor: async ({ request }) => {
      executorCalls += 1;
      assert.equal(String(request?.task_kind || ''), 'vision_understand');
      assert.equal(String(request?.device_id || ''), 'terminal_device');
      assert.equal(String(request?.prompt || ''), 'describe the scene');
      return {
        ok: true,
        provider: 'transformers',
        modelId: 'hf-vision',
        text: '[offline_vision_preview:abc123] image=32x20 prompt=describe the scene',
        spans: [],
        latencyMs: 9,
        fallbackMode: 'image_hash_preview',
        usage: {
          inputImageBytes: 33,
          inputImageWidth: 32,
          inputImageHeight: 20,
          inputImagePixels: 640,
          promptChars: 18,
        },
      };
    },
  });
  assert.equal(out.ok, true);
  assert.equal(out.provider, 'transformers');
  assert.equal(out.model_id, 'hf-vision');
  assert.equal(out.text.includes('32x20'), true);
  assert.equal(out.fallback_mode, 'image_hash_preview');
  assert.equal(out.usage.inputImagePixels, 640);
  assert.equal(executorCalls, 1);
});

await run('ocrLocalImage normalizes successful runtime preview output with spans', async () => {
  const runtimeBaseDir = makeTempRuntimeDir();
  seedRuntimeState(runtimeBaseDir);
  const imagePath = path.join(runtimeBaseDir, 'page.png');
  writePng(imagePath, { width: 96, height: 40 });
  const out = await ocrLocalImage({
    runtimeBaseDir,
    deviceId: 'terminal_device',
    imagePath,
    language: 'en',
    executor: async ({ request }) => {
      assert.equal(String(request?.task_kind || ''), 'ocr');
      assert.equal(String(request?.device_id || ''), 'terminal_device');
      assert.equal(String(request?.options?.language || ''), 'en');
      return {
        ok: true,
        provider: 'transformers',
        modelId: 'hf-ocr',
        text: '[offline_ocr_preview:def456]',
        spans: [
          {
            index: 0,
            text: '[offline_ocr_preview:def456]',
            bbox: {
              x: 0,
              y: 0,
              width: 96,
              height: 40,
            },
          },
        ],
        language: 'en',
        latencyMs: 11,
        fallbackMode: 'image_hash_preview',
        usage: {
          inputImageBytes: 33,
          inputImageWidth: 96,
          inputImageHeight: 40,
          inputImagePixels: 3840,
          promptChars: 0,
        },
      };
    },
  });
  assert.equal(out.ok, true);
  assert.equal(out.provider, 'transformers');
  assert.equal(out.model_id, 'hf-ocr');
  assert.equal(out.language, 'en');
  assert.equal(out.spans.length, 1);
  assert.equal(out.spans[0].bbox.width, 96);
  assert.equal(out.usage.inputImagePixels, 3840);
});
