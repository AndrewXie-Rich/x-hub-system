import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildLocalRuntimeSpawnConfig, resolveLocalTaskModelRecord } from './local_runtime_ipc.js';
import { buildLocalTaskFailure, evaluateLocalTaskPolicyGate } from './local_task_policy.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOCAL_RUNTIME_SCRIPT = path.resolve(__dirname, '../../../python-runtime/python_service/relflowhub_local_runtime.py');

const VISION_TASK_KIND = 'vision_understand';
const OCR_TASK_KIND = 'ocr';
const VISION_PROVIDER = 'transformers';
const SUPPORTED_TASK_KINDS = new Set([VISION_TASK_KIND, OCR_TASK_KIND]);
const SUPPORTED_IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg']);
const MAX_IMAGE_BYTES = 12 * 1024 * 1024;
const MAX_IMAGE_PIXELS = 20_000_000;
const MAX_IMAGE_DIMENSION = 8192;
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
const JPEG_SOF_MARKERS = new Set([
  0xC0, 0xC1, 0xC2, 0xC3,
  0xC5, 0xC6, 0xC7,
  0xC9, 0xCA, 0xCB,
  0xCD, 0xCE, 0xCF,
]);

function safeString(value) {
  return String(value ?? '').trim();
}

function safeNum(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function defaultRuntimeTaskExecutor({ runtimeBaseDir, request, timeoutMs = 30_000 } = {}) {
  const baseDir = safeString(runtimeBaseDir);
  const payload = JSON.stringify(request || {});
  const spawnConfig = buildLocalRuntimeSpawnConfig({ runtimeBaseDir: baseDir });
  if (!spawnConfig.executable) {
    return Promise.reject(new Error(spawnConfig.error || 'local_runtime_python_unavailable'));
  }
  return new Promise((resolve, reject) => {
    const child = spawn(
      spawnConfig.executable,
      [LOCAL_RUNTIME_SCRIPT, 'run-local-task', '-'],
      {
        env: spawnConfig.env,
        stdio: ['pipe', 'pipe', 'pipe'],
      }
    );

    let stdout = '';
    let stderr = '';
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      try {
        child.kill('SIGKILL');
      } catch {
        // ignore
      }
      reject(new Error('local_vision_timeout'));
    }, Math.max(1000, Number(timeoutMs || 30_000)));

    child.stdout.on('data', (chunk) => {
      stdout += String(chunk || '');
    });
    child.stderr.on('data', (chunk) => {
      stderr += String(chunk || '');
    });
    child.on('error', (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on('close', (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      if (code !== 0) {
        reject(new Error(safeString(stderr) || `local_vision_runtime_exit_${code}`));
        return;
      }
      try {
        resolve(JSON.parse(String(stdout || '{}')));
      } catch {
        reject(new Error(safeString(stdout) || safeString(stderr) || 'local_vision_invalid_json'));
      }
    });

    try {
      child.stdin.write(payload, 'utf8');
      child.stdin.end();
    } catch (error) {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    }
  });
}

function normalizeImageExtension(imagePath) {
  return path.extname(safeString(imagePath)).toLowerCase();
}

function inspectPngImage(buffer) {
  if (buffer.length < 24 || !buffer.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error('image_decode_failed');
  }
  if (buffer.toString('ascii', 12, 16) !== 'IHDR') {
    throw new Error('image_decode_failed');
  }
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  if (!width || !height) throw new Error('image_decode_failed');
  return {
    image_format: '.png',
    width,
    height,
  };
}

function inspectJpegImage(buffer) {
  if (buffer.length < 4 || buffer[0] !== 0xFF || buffer[1] !== 0xD8) {
    throw new Error('image_decode_failed');
  }

  let offset = 2;
  while ((offset + 4) <= buffer.length) {
    while (offset < buffer.length && buffer[offset] === 0xFF) offset += 1;
    if (offset >= buffer.length) break;

    const marker = buffer[offset];
    offset += 1;

    if (marker === 0xD9) break;
    if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if ((offset + 2) > buffer.length) break;

    const segmentLength = buffer.readUInt16BE(offset);
    offset += 2;
    if (segmentLength < 2 || (offset + segmentLength - 2) > buffer.length) break;

    if (JPEG_SOF_MARKERS.has(marker)) {
      if (segmentLength < 7) throw new Error('image_decode_failed');
      const height = buffer.readUInt16BE(offset + 1);
      const width = buffer.readUInt16BE(offset + 3);
      if (!width || !height) throw new Error('image_decode_failed');
      return {
        image_format: '.jpeg',
        width,
        height,
      };
    }

    offset += segmentLength - 2;
  }

  throw new Error('image_decode_failed');
}

export function inspectLocalImage(imagePath) {
  const filePath = safeString(imagePath);
  if (!filePath) throw new Error('missing_image_path');
  const buffer = fs.readFileSync(filePath);
  const ext = normalizeImageExtension(filePath);

  let info;
  if (ext === '.png') {
    info = inspectPngImage(buffer);
  } else if (ext === '.jpg' || ext === '.jpeg') {
    info = inspectJpegImage(buffer);
  } else {
    throw new Error('unsupported_image_format');
  }

  return {
    image_format: safeString(info.image_format) || ext,
    file_size_bytes: buffer.length,
    width: safeNum(info.width, 0),
    height: safeNum(info.height, 0),
    pixel_count: Math.max(0, safeNum(info.width, 0) * safeNum(info.height, 0)),
  };
}

function modelUnavailableCode(taskKind) {
  return safeString(taskKind).toLowerCase() === OCR_TASK_KIND
    ? 'local_ocr_model_unavailable'
    : 'local_vision_model_unavailable';
}

function imageUsagePayload(imageInfo, prompt = '') {
  return {
    inputImageBytes: Math.max(0, safeNum(imageInfo?.file_size_bytes, 0)),
    inputImageWidth: Math.max(0, safeNum(imageInfo?.width, 0)),
    inputImageHeight: Math.max(0, safeNum(imageInfo?.height, 0)),
    inputImagePixels: Math.max(0, safeNum(imageInfo?.pixel_count, 0)),
    promptChars: safeString(prompt).length,
  };
}

export async function runLocalVisionTask({
  taskKind = VISION_TASK_KIND,
  runtimeBaseDir,
  requestId = '',
  deviceId = '',
  imagePath = '',
  prompt = '',
  language = '',
  preferredModelId = '',
  capabilityAllowed = true,
  capabilityDenyCode = '',
  killSwitch = null,
  maxImageBytes = MAX_IMAGE_BYTES,
  maxImagePixels = MAX_IMAGE_PIXELS,
  maxImageDimension = MAX_IMAGE_DIMENSION,
  executor = null,
} = {}) {
  const normalizedTaskKind = safeString(taskKind).toLowerCase();
  const baseDir = safeString(runtimeBaseDir);
  const filePath = safeString(imagePath);
  const promptText = safeString(prompt);
  const languageHint = safeString(language);
  const fail = ({
    rawDenyCode,
    message = '',
    blockedBy = '',
    ruleIds = [],
    extra = {},
  } = {}) => ({
    ...buildLocalTaskFailure({
      taskKind: normalizedTaskKind,
      provider: VISION_PROVIDER,
      rawDenyCode,
      message,
      blockedBy,
      ruleIds,
    }),
    ...extra,
  });

  if (!SUPPORTED_TASK_KINDS.has(normalizedTaskKind)) {
    return fail({
      rawDenyCode: 'local_task_unsupported',
      message: normalizedTaskKind ? `local_task_unsupported:${normalizedTaskKind}` : 'local_task_unsupported',
      blockedBy: 'task',
    });
  }
  if (!baseDir) {
    return fail({ rawDenyCode: 'runtime_base_dir_missing' });
  }

  const policyGate = evaluateLocalTaskPolicyGate({
    taskKind: normalizedTaskKind,
    provider: VISION_PROVIDER,
    capabilityAllowed,
    capabilityDenyCode,
    killSwitch,
  });
  if (!policyGate.ok) {
    return policyGate;
  }
  if (!filePath) {
    return fail({ rawDenyCode: 'missing_image_path' });
  }
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    return fail({ rawDenyCode: 'image_path_not_found' });
  }

  const ext = normalizeImageExtension(filePath);
  if (!SUPPORTED_IMAGE_EXTENSIONS.has(ext)) {
    return fail({
      rawDenyCode: 'unsupported_image_format',
      message: `unsupported_image_format:${ext || 'unknown'}`,
      blockedBy: 'modality',
    });
  }

  const stat = fs.statSync(filePath);
  const sizeLimit = Math.max(1024, Math.min(100 * 1024 * 1024, Number(maxImageBytes || MAX_IMAGE_BYTES)));
  if (Number(stat.size || 0) > sizeLimit) {
    return fail({
      rawDenyCode: 'image_file_too_large',
      blockedBy: 'input',
      extra: {
        usage: {
          inputImageBytes: Number(stat.size || 0),
        },
      },
    });
  }

  let imageInfo;
  try {
    imageInfo = inspectLocalImage(filePath);
  } catch (error) {
    return fail({
      rawDenyCode: safeString(error?.message) || 'image_decode_failed',
      message: safeString(error?.message) || 'image_decode_failed',
      blockedBy: 'modality',
    });
  }

  const dimensionLimit = Math.max(32, Math.min(16_384, Number(maxImageDimension || MAX_IMAGE_DIMENSION)));
  if (Number(imageInfo.width || 0) > dimensionLimit || Number(imageInfo.height || 0) > dimensionLimit) {
    return fail({
      rawDenyCode: 'image_dimensions_too_large',
      blockedBy: 'input',
      extra: {
        usage: imageUsagePayload(imageInfo, promptText),
      },
    });
  }

  const pixelLimit = Math.max(1024, Math.min(100_000_000, Number(maxImagePixels || MAX_IMAGE_PIXELS)));
  if (Number(imageInfo.pixel_count || 0) > pixelLimit) {
    return fail({
      rawDenyCode: 'image_pixels_too_large',
      blockedBy: 'input',
      extra: {
        usage: imageUsagePayload(imageInfo, promptText),
      },
    });
  }

  const modelSelection = resolveLocalTaskModelRecord({
    runtimeBaseDir: baseDir,
    taskKind: normalizedTaskKind,
    deviceId,
    preferredModelId,
    providerId: VISION_PROVIDER,
    requireLocalPath: true,
  });
  if (!modelSelection.ok) {
    return fail({
      rawDenyCode: modelUnavailableCode(normalizedTaskKind),
      message: safeString(modelSelection.message) || modelUnavailableCode(normalizedTaskKind),
      blockedBy: 'provider',
      extra: {
        provider: VISION_PROVIDER,
        model_id: safeString(modelSelection.resolved_model_id),
        route_source: safeString(modelSelection.route_source),
        route_reason_code: safeString(modelSelection.reason_code),
        usage: imageUsagePayload(imageInfo, promptText),
      },
    });
  }
  const model = modelSelection.model;

  const taskExecutor = typeof executor === 'function' ? executor : defaultRuntimeTaskExecutor;
  try {
    const response = await taskExecutor({
      runtimeBaseDir: baseDir,
      timeoutMs: 60_000,
      request: {
        provider: VISION_PROVIDER,
        task_kind: normalizedTaskKind,
        model_id: safeString(model.model_id),
        model_path: safeString(model.model_path),
        device_id: safeString(deviceId),
        image_path: filePath,
        prompt: promptText,
        request_id: safeString(requestId),
        options: {
          language: languageHint,
        },
      },
    });
    if (!response || typeof response !== 'object' || response.ok !== true) {
      return fail({
        rawDenyCode: safeString(response?.error) || 'local_vision_runtime_failed',
        message: safeString(response?.errorDetail || response?.error || 'local_vision_runtime_failed'),
        blockedBy: 'provider',
        extra: {
          provider: safeString(response?.provider) || VISION_PROVIDER,
          model_id: safeString(response?.modelId) || safeString(model.model_id),
          route_source: safeString(modelSelection.route_source),
          resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
          usage: response?.usage && typeof response.usage === 'object'
            ? response.usage
            : imageUsagePayload(imageInfo, promptText),
        },
      });
    }
    return {
      ok: true,
      task_kind: normalizedTaskKind,
      capability: policyGate.capability,
      provider: safeString(response.provider) || VISION_PROVIDER,
      model_id: safeString(response.modelId) || safeString(model.model_id),
      route_source: safeString(modelSelection.route_source),
      resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(response.modelId) || safeString(model.model_id),
      text: safeString(response.text),
      spans: Array.isArray(response.spans) ? response.spans : [],
      language: safeString(response.language),
      latency_ms: Math.max(0, safeNum(response.latencyMs, 0)),
      fallback_mode: safeString(response.fallbackMode),
      usage: response.usage && typeof response.usage === 'object'
        ? response.usage
        : imageUsagePayload(imageInfo, promptText),
    };
  } catch (error) {
    return fail({
      rawDenyCode: 'local_vision_runtime_failed',
      message: safeString(error?.message || error || 'local_vision_runtime_failed'),
      blockedBy: 'provider',
      extra: {
        provider: VISION_PROVIDER,
        model_id: safeString(model.model_id),
        route_source: safeString(modelSelection.route_source),
        resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
        usage: imageUsagePayload(imageInfo, promptText),
      },
    });
  }
}

export async function understandLocalImage(options = {}) {
  return runLocalVisionTask({
    ...options,
    taskKind: VISION_TASK_KIND,
  });
}

export async function ocrLocalImage(options = {}) {
  return runLocalVisionTask({
    ...options,
    taskKind: OCR_TASK_KIND,
  });
}
