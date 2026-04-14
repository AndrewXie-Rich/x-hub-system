import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildLocalRuntimeSpawnConfig, resolveLocalTaskModelRecord } from './local_runtime_ipc.js';
import { buildLocalTaskFailure, evaluateLocalTaskPolicyGate } from './local_task_policy.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const LOCAL_RUNTIME_SCRIPT = path.resolve(__dirname, '../../../python-runtime/python_service/relflowhub_local_runtime.py');

const TTS_TASK_KIND = 'text_to_speech';
const TTS_PROVIDER = 'transformers';
const TTS_AUDIT_SCHEMA_VERSION = 'xhub.local_tts_audit.v1';
const MAX_TEXT_CHARS = 6000;
const MIN_SPEECH_RATE = 0.6;
const MAX_SPEECH_RATE = 1.8;

function safeString(value) {
  return String(value ?? '').trim();
}

function safeNum(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function safeBool(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const token = safeString(value).toLowerCase();
  if (token === 'true' || token === '1' || token === 'yes') return true;
  if (token === 'false' || token === '0' || token === 'no') return false;
  return null;
}

function clamp(number, min, max) {
  return Math.max(min, Math.min(max, number));
}

function normalizeLocale(value) {
  return safeString(value).replace(/_/g, '-');
}

function normalizeVoiceColor(value) {
  const token = safeString(value).toLowerCase();
  return token || 'neutral';
}

function normalizeSpeechRate(value) {
  return clamp(safeNum(value, 1.0), MIN_SPEECH_RATE, MAX_SPEECH_RATE);
}

function normalizeOutputRefKind({ audioPath = '', audioClipRef = '' } = {}) {
  if (safeString(audioClipRef)) return 'audio_clip_ref';
  if (safeString(audioPath)) return 'audio_path';
  return 'none';
}

function buildTTSAuditRecord({
  ok = false,
  requestId = '',
  capability = '',
  provider = '',
  requestedModelId = '',
  modelId = '',
  resolvedModelId = '',
  routeSource = '',
  locale = '',
  voiceColor = '',
  speechRate = 1.0,
  audioPath = '',
  audioClipRef = '',
  engineName = '',
  speakerId = '',
  nativeTTSUsed = null,
  fallbackMode = '',
  fallbackReasonCode = '',
  denyCode = '',
  rawDenyCode = '',
} = {}) {
  const normalizedOutputRefKind = normalizeOutputRefKind({ audioPath, audioClipRef });
  const normalizedFallbackMode = safeString(fallbackMode);
  const normalizedFallbackReasonCode = safeString(fallbackReasonCode);
  const fallbackUsed = !!(normalizedFallbackMode || normalizedFallbackReasonCode);
  const normalizedNativeTTSUsed = typeof nativeTTSUsed === 'boolean' ? nativeTTSUsed : null;

  let sourceKind = 'failed';
  if (ok) {
    if (fallbackUsed) {
      sourceKind = 'fallback_output';
    } else if (normalizedNativeTTSUsed === true) {
      sourceKind = 'native_tts';
    } else if (normalizedOutputRefKind === 'audio_clip_ref') {
      sourceKind = 'audio_clip_ref';
    } else if (normalizedOutputRefKind === 'audio_path') {
      sourceKind = 'audio_path';
    } else {
      sourceKind = 'unknown';
    }
  }

  return {
    schema_version: TTS_AUDIT_SCHEMA_VERSION,
    ok: !!ok,
    task_kind: TTS_TASK_KIND,
    request_id: safeString(requestId),
    capability: safeString(capability),
    provider: safeString(provider) || TTS_PROVIDER,
    requested_model_id: safeString(requestedModelId),
    model_id: safeString(modelId),
    resolved_model_id: safeString(resolvedModelId),
    route_source: safeString(routeSource),
    source_kind: sourceKind,
    output_ref_kind: normalizedOutputRefKind,
    engine_name: safeString(engineName),
    speaker_id: safeString(speakerId),
    native_tts_used: normalizedNativeTTSUsed,
    fallback_used: fallbackUsed,
    fallback_mode: normalizedFallbackMode,
    fallback_reason_code: normalizedFallbackReasonCode,
    deny_code: safeString(denyCode),
    raw_deny_code: safeString(rawDenyCode),
    locale: normalizeLocale(locale),
    voice_color: normalizeVoiceColor(voiceColor),
    speech_rate: normalizeSpeechRate(speechRate),
  };
}

function buildTTSAuditLine(record = {}) {
  const fallbackToken = safeString(record.fallback_reason_code || record.fallback_mode) || 'none';
  const modelToken = safeString(record.model_id) || safeString(record.resolved_model_id) || '(none)';
  const routeToken = safeString(record.route_source) || 'default';
  const outputToken = safeString(record.output_ref_kind) || 'none';
  const sourceToken = safeString(record.source_kind) || 'unknown';
  const statusToken = record.ok ? 'ok' : 'failed';
  const providerToken = safeString(record.provider) || TTS_PROVIDER;
  const denyToken = safeString(record.deny_code || record.raw_deny_code) || 'none';
  return [
    'tts_audit',
    `status=${statusToken}`,
    `provider=${providerToken}`,
    `model=${modelToken}`,
    `source=${sourceToken}`,
    `route=${routeToken}`,
    `output=${outputToken}`,
    `fallback=${fallbackToken}`,
    `deny=${denyToken}`,
  ].join(' ');
}

function decorateWithTTSAudit(result, {
  requestId = '',
  requestedModelId = '',
  modelId = '',
  resolvedModelId = '',
  routeSource = '',
  locale = '',
  voiceColor = '',
  speechRate = 1.0,
  audioPath = '',
  audioClipRef = '',
  engineName = '',
  speakerId = '',
  nativeTTSUsed = null,
  fallbackMode = '',
  fallbackReasonCode = '',
} = {}) {
  const audit = buildTTSAuditRecord({
    ok: !!result?.ok,
    requestId,
    capability: safeString(result?.capability),
    provider: safeString(result?.provider),
    requestedModelId,
    modelId,
    resolvedModelId,
    routeSource,
    locale,
    voiceColor,
    speechRate,
    audioPath,
    audioClipRef,
    engineName,
    speakerId,
    nativeTTSUsed,
    fallbackMode,
    fallbackReasonCode,
    denyCode: safeString(result?.deny_code),
    rawDenyCode: safeString(result?.raw_deny_code),
  });
  return {
    ...result,
    tts_audit: audit,
    tts_audit_line: buildTTSAuditLine(audit),
  };
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
      reject(new Error('local_tts_timeout'));
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
        reject(new Error(safeString(stderr) || `local_tts_runtime_exit_${code}`));
        return;
      }
      try {
        resolve(JSON.parse(String(stdout || '{}')));
      } catch {
        reject(new Error(safeString(stdout) || safeString(stderr) || 'local_tts_invalid_json'));
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

export async function synthesizeLocalSpeech({
  runtimeBaseDir,
  requestId = '',
  deviceId = '',
  text = '',
  locale = '',
  voiceColor = '',
  speechRate = 1.0,
  preferredModelId = '',
  capabilityAllowed = true,
  capabilityDenyCode = '',
  killSwitch = null,
  maxTextChars = MAX_TEXT_CHARS,
  executor = null,
} = {}) {
  const baseDir = safeString(runtimeBaseDir);
  const normalizedRequestedModelId = safeString(preferredModelId);
  const inputText = safeString(text);
  const normalizedLocale = normalizeLocale(locale);
  const normalizedVoiceColor = normalizeVoiceColor(voiceColor);
  const normalizedSpeechRate = normalizeSpeechRate(speechRate);
  const fail = ({
    rawDenyCode,
    message = '',
    blockedBy = '',
    ruleIds = [],
    extra = {},
  } = {}) => ({
    ...buildLocalTaskFailure({
      taskKind: TTS_TASK_KIND,
      provider: TTS_PROVIDER,
      rawDenyCode,
      message,
      blockedBy,
      ruleIds,
    }),
    ...extra,
  });

  if (!baseDir) {
    return decorateWithTTSAudit(
      fail({ rawDenyCode: 'runtime_base_dir_missing' }),
      {
        requestId,
        requestedModelId: normalizedRequestedModelId,
        locale: normalizedLocale,
        voiceColor: normalizedVoiceColor,
        speechRate: normalizedSpeechRate,
      }
    );
  }

  const policyGate = evaluateLocalTaskPolicyGate({
    taskKind: TTS_TASK_KIND,
    provider: TTS_PROVIDER,
    capabilityAllowed,
    capabilityDenyCode,
    killSwitch,
  });
  if (!policyGate.ok) {
    return decorateWithTTSAudit(policyGate, {
      requestId,
      requestedModelId: normalizedRequestedModelId,
      locale: normalizedLocale,
      voiceColor: normalizedVoiceColor,
      speechRate: normalizedSpeechRate,
    });
  }

  if (!inputText) {
    return decorateWithTTSAudit(
      fail({ rawDenyCode: 'missing_text', blockedBy: 'input' }),
      {
        requestId,
        requestedModelId: normalizedRequestedModelId,
        locale: normalizedLocale,
        voiceColor: normalizedVoiceColor,
        speechRate: normalizedSpeechRate,
      }
    );
  }

  const textLimit = Math.max(64, Math.min(20_000, Number(maxTextChars || MAX_TEXT_CHARS)));
  if (inputText.length > textLimit) {
    return decorateWithTTSAudit(
      fail({
        rawDenyCode: 'tts_input_too_large',
        blockedBy: 'input',
        extra: {
          usage: {
            inputTextChars: inputText.length,
          },
        },
      }),
      {
        requestId,
        requestedModelId: normalizedRequestedModelId,
        locale: normalizedLocale,
        voiceColor: normalizedVoiceColor,
        speechRate: normalizedSpeechRate,
      }
    );
  }

  const modelSelection = resolveLocalTaskModelRecord({
    runtimeBaseDir: baseDir,
    taskKind: TTS_TASK_KIND,
    deviceId,
    preferredModelId,
    providerId: TTS_PROVIDER,
    requireLocalPath: true,
  });
  if (!modelSelection.ok) {
    return decorateWithTTSAudit(
      fail({
        rawDenyCode: 'local_tts_model_unavailable',
        message: safeString(modelSelection.message) || 'local_tts_model_unavailable',
        blockedBy: 'provider',
        extra: {
          provider: TTS_PROVIDER,
          model_id: safeString(modelSelection.resolved_model_id),
          route_source: safeString(modelSelection.route_source),
          route_reason_code: safeString(modelSelection.reason_code),
          usage: {
            inputTextChars: inputText.length,
          },
        },
      }),
      {
        requestId,
        requestedModelId: normalizedRequestedModelId,
        modelId: safeString(modelSelection.resolved_model_id),
        resolvedModelId: safeString(modelSelection.resolved_model_id),
        routeSource: safeString(modelSelection.route_source),
        locale: normalizedLocale,
        voiceColor: normalizedVoiceColor,
        speechRate: normalizedSpeechRate,
      }
    );
  }
  const model = modelSelection.model;
  const taskExecutor = typeof executor === 'function' ? executor : defaultRuntimeTaskExecutor;

  try {
    const response = await taskExecutor({
      runtimeBaseDir: baseDir,
      timeoutMs: 60_000,
      request: {
        provider: TTS_PROVIDER,
        task_kind: TTS_TASK_KIND,
        model_id: safeString(model.model_id),
        model_path: safeString(model.model_path),
        device_id: safeString(deviceId),
        request_id: safeString(requestId),
        text: inputText,
        options: {
          locale: normalizedLocale,
          language: normalizedLocale,
          voice_color: normalizedVoiceColor,
          speech_rate: normalizedSpeechRate,
        },
      },
    });
    if (!response || typeof response !== 'object' || response.ok !== true) {
      return decorateWithTTSAudit(
        fail({
          rawDenyCode: safeString(response?.error) || 'local_tts_runtime_failed',
          message: safeString(response?.errorDetail || response?.error || 'local_tts_runtime_failed'),
          blockedBy: 'provider',
          extra: {
            provider: safeString(response?.provider) || TTS_PROVIDER,
            model_id: safeString(response?.modelId) || safeString(model.model_id),
            route_source: safeString(modelSelection.route_source),
            resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
            usage: response?.usage && typeof response.usage === 'object'
              ? response.usage
              : { inputTextChars: inputText.length },
          },
        }),
        {
          requestId,
          requestedModelId: normalizedRequestedModelId,
          modelId: safeString(response?.modelId) || safeString(model.model_id),
          resolvedModelId: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
          routeSource: safeString(modelSelection.route_source),
          locale: normalizeLocale(response?.locale || response?.language) || normalizedLocale,
          voiceColor: normalizeVoiceColor(response?.voiceColor || response?.voice_color) || normalizedVoiceColor,
          speechRate: normalizeSpeechRate(response?.speechRate || response?.speech_rate || normalizedSpeechRate),
          engineName: safeString(response?.engineName || response?.engine_name),
          speakerId: safeString(response?.speakerId || response?.speaker_id),
          nativeTTSUsed: safeBool(response?.nativeTTSUsed ?? response?.native_tts_used),
          fallbackMode: safeString(response?.fallbackMode || response?.fallback_mode),
          fallbackReasonCode: safeString(response?.fallbackReasonCode || response?.fallback_reason_code),
        }
      );
    }

    const audioPath = safeString(response.audioPath || response.audio_path);
    const audioClipRef = safeString(response.audioClipRef || response.audio_clip_ref);
    if (!audioPath && !audioClipRef) {
      return decorateWithTTSAudit(
        fail({
          rawDenyCode: 'tts_audio_output_missing',
          message: 'tts_audio_output_missing',
          blockedBy: 'provider',
          extra: {
            provider: safeString(response?.provider) || TTS_PROVIDER,
            model_id: safeString(response?.modelId) || safeString(model.model_id),
            route_source: safeString(modelSelection.route_source),
            resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
            usage: response?.usage && typeof response.usage === 'object'
              ? response.usage
              : { inputTextChars: inputText.length },
          },
        }),
        {
          requestId,
          requestedModelId: normalizedRequestedModelId,
          modelId: safeString(response?.modelId) || safeString(model.model_id),
          resolvedModelId: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
          routeSource: safeString(modelSelection.route_source),
          locale: normalizeLocale(response?.locale || response?.language) || normalizedLocale,
          voiceColor: normalizeVoiceColor(response?.voiceColor || response?.voice_color) || normalizedVoiceColor,
          speechRate: normalizeSpeechRate(response?.speechRate || response?.speech_rate || normalizedSpeechRate),
          engineName: safeString(response?.engineName || response?.engine_name),
          speakerId: safeString(response?.speakerId || response?.speaker_id),
          nativeTTSUsed: safeBool(response?.nativeTTSUsed ?? response?.native_tts_used),
          fallbackMode: safeString(response?.fallbackMode || response?.fallback_mode),
          fallbackReasonCode: safeString(response?.fallbackReasonCode || response?.fallback_reason_code),
        }
      );
    }

    return decorateWithTTSAudit({
      ok: true,
      task_kind: TTS_TASK_KIND,
      capability: policyGate.capability,
      provider: safeString(response.provider) || TTS_PROVIDER,
      model_id: safeString(response.modelId) || safeString(model.model_id),
      route_source: safeString(modelSelection.route_source),
      resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(response.modelId) || safeString(model.model_id),
      audio_path: audioPath,
      audio_clip_ref: audioClipRef,
      audio_format: safeString(response.audioFormat || response.audio_format),
      engine_name: safeString(response.engineName || response.engine_name),
      speaker_id: safeString(response.speakerId || response.speaker_id),
      locale: normalizeLocale(response.locale || response.language) || normalizedLocale,
      voice_color: normalizeVoiceColor(response.voiceColor || response.voice_color) || normalizedVoiceColor,
      speech_rate: normalizeSpeechRate(response.speechRate || response.speech_rate || normalizedSpeechRate),
      latency_ms: Math.max(0, safeNum(response.latencyMs, 0)),
      native_tts_used: safeBool(response.nativeTTSUsed ?? response.native_tts_used),
      fallback_mode: safeString(response.fallbackMode || response.fallback_mode),
      fallback_reason_code: safeString(response.fallbackReasonCode || response.fallback_reason_code),
      usage: response.usage && typeof response.usage === 'object'
        ? response.usage
        : { inputTextChars: inputText.length },
    }, {
      requestId,
      requestedModelId: normalizedRequestedModelId,
      modelId: safeString(response.modelId) || safeString(model.model_id),
      resolvedModelId: safeString(modelSelection.resolved_model_id) || safeString(response.modelId) || safeString(model.model_id),
      routeSource: safeString(modelSelection.route_source),
      locale: normalizeLocale(response.locale || response.language) || normalizedLocale,
      voiceColor: normalizeVoiceColor(response.voiceColor || response.voice_color) || normalizedVoiceColor,
      speechRate: normalizeSpeechRate(response.speechRate || response.speech_rate || normalizedSpeechRate),
      audioPath,
      audioClipRef,
      engineName: safeString(response.engineName || response.engine_name),
      speakerId: safeString(response.speakerId || response.speaker_id),
      nativeTTSUsed: safeBool(response.nativeTTSUsed ?? response.native_tts_used),
      fallbackMode: safeString(response.fallbackMode || response.fallback_mode),
      fallbackReasonCode: safeString(response.fallbackReasonCode || response.fallback_reason_code),
    });
  } catch (error) {
    return decorateWithTTSAudit(
      fail({
        rawDenyCode: 'local_tts_runtime_failed',
        message: safeString(error?.message || error || 'local_tts_runtime_failed'),
        blockedBy: 'provider',
        extra: {
          provider: TTS_PROVIDER,
          model_id: safeString(model.model_id),
          route_source: safeString(modelSelection.route_source),
          resolved_model_id: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
          usage: {
            inputTextChars: inputText.length,
          },
        },
      }),
      {
        requestId,
        requestedModelId: normalizedRequestedModelId,
        modelId: safeString(model.model_id),
        resolvedModelId: safeString(modelSelection.resolved_model_id) || safeString(model.model_id),
        routeSource: safeString(modelSelection.route_source),
        locale: normalizedLocale,
        voiceColor: normalizedVoiceColor,
        speechRate: normalizedSpeechRate,
      }
    );
  }
}
