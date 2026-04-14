import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildLocalRuntimeSpawnConfig, resolveLocalTaskModelRecord } from './local_runtime_ipc.js';
import { buildLocalTaskFailure, evaluateLocalTaskPolicyGate } from './local_task_policy.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOCAL_RUNTIME_SCRIPT = path.resolve(__dirname, '../../../python-runtime/python_service/relflowhub_local_runtime.py');

const ASR_TASK_KIND = 'speech_to_text';
const ASR_PROVIDER = 'transformers';
const SUPPORTED_AUDIO_EXTENSIONS = new Set(['.wav']);
const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const MAX_AUDIO_SECONDS = 15 * 60;

function safeString(value) {
  return String(value ?? '').trim();
}

function safeNum(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function safeBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  const token = safeString(value).toLowerCase();
  if (token === '1' || token === 'true' || token === 'yes' || token === 'on') return true;
  if (token === '0' || token === 'false' || token === 'no' || token === 'off') return false;
  return !!fallback;
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
      reject(new Error('local_audio_timeout'));
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
        reject(new Error(safeString(stderr) || `local_audio_runtime_exit_${code}`));
        return;
      }
      try {
        resolve(JSON.parse(String(stdout || '{}')));
      } catch {
        reject(new Error(safeString(stdout) || safeString(stderr) || 'local_audio_invalid_json'));
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

function normalizeAudioExtension(audioPath) {
  return path.extname(safeString(audioPath)).toLowerCase();
}

export function inspectWavAudio(audioPath) {
  const filePath = safeString(audioPath);
  if (!filePath) throw new Error('missing_audio_path');
  const buffer = fs.readFileSync(filePath);
  if (buffer.length < 44) throw new Error('audio_decode_failed');
  if (buffer.toString('ascii', 0, 4) !== 'RIFF' || buffer.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error('audio_decode_failed');
  }

  let offset = 12;
  let fmt = null;
  let dataSize = 0;
  while ((offset + 8) <= buffer.length) {
    const chunkId = buffer.toString('ascii', offset, offset + 4);
    const chunkSize = buffer.readUInt32LE(offset + 4);
    const dataOffset = offset + 8;
    if (chunkId === 'fmt ' && (dataOffset + 16) <= buffer.length) {
      fmt = {
        format_code: buffer.readUInt16LE(dataOffset),
        channel_count: buffer.readUInt16LE(dataOffset + 2),
        sample_rate: buffer.readUInt32LE(dataOffset + 4),
        byte_rate: buffer.readUInt32LE(dataOffset + 8),
        block_align: buffer.readUInt16LE(dataOffset + 12),
        bits_per_sample: buffer.readUInt16LE(dataOffset + 14),
      };
    } else if (chunkId === 'data') {
      dataSize = chunkSize;
      break;
    }
    offset = dataOffset + chunkSize + (chunkSize % 2);
  }

  if (!fmt || !fmt.sample_rate || !fmt.byte_rate || !dataSize) {
    throw new Error('audio_decode_failed');
  }
  const durationSec = dataSize / fmt.byte_rate;
  return {
    audio_format: '.wav',
    file_size_bytes: buffer.length,
    duration_sec: durationSec,
    sample_rate: fmt.sample_rate,
    channel_count: fmt.channel_count,
    bits_per_sample: fmt.bits_per_sample,
    format_code: fmt.format_code,
  };
}

export async function transcribeLocalAudio({
  runtimeBaseDir,
  requestId = '',
  deviceId = '',
  audioPath = '',
  preferredModelId = '',
  language = '',
  timestamps = false,
  capabilityAllowed = true,
  capabilityDenyCode = '',
  killSwitch = null,
  maxAudioBytes = MAX_AUDIO_BYTES,
  maxAudioSeconds = MAX_AUDIO_SECONDS,
  executor = null,
} = {}) {
  const baseDir = safeString(runtimeBaseDir);
  const filePath = safeString(audioPath);
  const fail = ({
    rawDenyCode,
    message = '',
    blockedBy = '',
    ruleIds = [],
    extra = {},
  } = {}) => ({
    ...buildLocalTaskFailure({
      taskKind: ASR_TASK_KIND,
      provider: ASR_PROVIDER,
      rawDenyCode,
      message,
      blockedBy,
      ruleIds,
    }),
    ...extra,
  });
  if (!baseDir) {
    return fail({ rawDenyCode: 'runtime_base_dir_missing' });
  }
  const policyGate = evaluateLocalTaskPolicyGate({
    taskKind: ASR_TASK_KIND,
    provider: ASR_PROVIDER,
    capabilityAllowed,
    capabilityDenyCode,
    killSwitch,
  });
  if (!policyGate.ok) {
    return policyGate;
  }
  if (!filePath) {
    return fail({ rawDenyCode: 'missing_audio_path' });
  }
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    return fail({ rawDenyCode: 'audio_path_not_found' });
  }
  const ext = normalizeAudioExtension(filePath);
  if (!SUPPORTED_AUDIO_EXTENSIONS.has(ext)) {
    return fail({
      rawDenyCode: 'unsupported_audio_format',
      message: `unsupported_audio_format:${ext || 'unknown'}`,
      blockedBy: 'modality',
    });
  }
  const stat = fs.statSync(filePath);
  const sizeLimit = Math.max(1024, Math.min(100 * 1024 * 1024, Number(maxAudioBytes || MAX_AUDIO_BYTES)));
  if (Number(stat.size || 0) > sizeLimit) {
    return fail({
      rawDenyCode: 'audio_file_too_large',
      blockedBy: 'input',
      extra: {
        usage: {
          inputAudioBytes: Number(stat.size || 0),
        },
      },
    });
  }

  let audioInfo;
  try {
    audioInfo = inspectWavAudio(filePath);
  } catch (error) {
    return fail({
      rawDenyCode: safeString(error?.message) || 'audio_decode_failed',
      message: safeString(error?.message) || 'audio_decode_failed',
      blockedBy: 'modality',
    });
  }
  const secondsLimit = Math.max(1, Math.min(3600, Number(maxAudioSeconds || MAX_AUDIO_SECONDS)));
  if (Number(audioInfo.duration_sec || 0) > secondsLimit) {
    return fail({
      rawDenyCode: 'audio_duration_too_long',
      blockedBy: 'input',
      extra: {
        usage: {
          inputAudioBytes: Number(audioInfo.file_size_bytes || stat.size || 0),
          inputAudioSec: Number(audioInfo.duration_sec || 0),
        },
      },
    });
  }

  const modelSelection = resolveLocalTaskModelRecord({
    runtimeBaseDir: baseDir,
    taskKind: ASR_TASK_KIND,
    deviceId,
    preferredModelId,
    providerId: ASR_PROVIDER,
    requireLocalPath: true,
  });
  if (!modelSelection.ok) {
    return fail({
      rawDenyCode: 'local_asr_model_unavailable',
      message: safeString(modelSelection.message) || 'local_asr_model_unavailable',
      blockedBy: 'provider',
      extra: {
        provider: ASR_PROVIDER,
        model_id: safeString(modelSelection.resolved_model_id),
        route_source: safeString(modelSelection.route_source),
        route_reason_code: safeString(modelSelection.reason_code),
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
        provider: 'transformers',
        task_kind: ASR_TASK_KIND,
        model_id: safeString(model.model_id),
        model_path: safeString(model.model_path),
        device_id: safeString(deviceId),
        audio_path: filePath,
        request_id: safeString(requestId),
        options: {
          language: safeString(language),
          timestamps: safeBool(timestamps, false),
        },
      },
    });
    if (!response || typeof response !== 'object' || response.ok !== true) {
      return fail({
        rawDenyCode: safeString(response?.error) || 'local_asr_runtime_failed',
        message: safeString(response?.errorDetail || response?.error || 'local_asr_runtime_failed'),
        blockedBy: 'provider',
        extra: {
          provider: safeString(response?.provider) || 'transformers',
          model_id: safeString(response?.modelId) || safeString(model.model_id),
          route_source: safeString(modelSelection.route_source),
          resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
          usage: response?.usage && typeof response.usage === 'object' ? response.usage : {
            inputAudioBytes: Number(audioInfo.file_size_bytes || 0),
            inputAudioSec: Number(audioInfo.duration_sec || 0),
          },
        },
      });
    }
    return {
      ok: true,
      task_kind: ASR_TASK_KIND,
      capability: policyGate.capability,
      provider: safeString(response.provider) || 'transformers',
      model_id: safeString(response.modelId) || safeString(model.model_id),
      route_source: safeString(modelSelection.route_source),
      resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(response.modelId) || safeString(model.model_id),
      text: safeString(response.text),
      segments: Array.isArray(response.segments) ? response.segments : [],
      language: safeString(response.language),
      latency_ms: Math.max(0, safeNum(response.latencyMs, 0)),
      fallback_mode: safeString(response.fallbackMode),
      usage: response.usage && typeof response.usage === 'object' ? response.usage : {
        inputAudioBytes: Number(audioInfo.file_size_bytes || 0),
        inputAudioSec: Number(audioInfo.duration_sec || 0),
      },
    };
  } catch (error) {
    return fail({
      rawDenyCode: 'local_asr_runtime_failed',
      message: safeString(error?.message || error || 'local_asr_runtime_failed'),
      blockedBy: 'provider',
      extra: {
        provider: 'transformers',
        model_id: safeString(model.model_id),
        route_source: safeString(modelSelection.route_source),
        resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
        usage: {
          inputAudioBytes: Number(audioInfo.file_size_bytes || 0),
          inputAudioSec: Number(audioInfo.duration_sec || 0),
        },
      },
    });
  }
}
