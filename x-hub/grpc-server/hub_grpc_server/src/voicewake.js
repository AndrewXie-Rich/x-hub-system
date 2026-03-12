import fs from 'node:fs';
import path from 'node:path';

import { nowMs } from './util.js';

const STORE_SCHEMA_VERSION = 'hub.voice_wake_profile_store.v1';
const PROFILE_SCHEMA_VERSION = 'xt.supervisor_voice_wake_profile.v1';
const CHANGED_SCHEMA_VERSION = 'hub.voice_wake_profile_changed.v1';
const DEFAULT_PROFILE_ID = 'default';
const DEFAULT_AUDIT_REF = 'hub.voice_wake_profile_sync.v1';
const DEFAULT_TRIGGER_WORDS = ['x hub', 'supervisor'];
const MAX_TRIGGER_COUNT = 6;
const MAX_TRIGGER_LENGTH = 48;

function safeString(value) {
  return String(value || '').trim();
}

function normalizeWakeMode(value) {
  const mode = safeString(value).toLowerCase();
  switch (mode) {
    case 'prompt_phrase_only':
      return 'prompt_phrase_only';
    case 'wake_phrase':
      return 'wake_phrase';
    default:
      return 'wake_phrase';
  }
}

export function sanitizeVoiceWakeTriggerWords(values, fallbackToDefaults = true) {
  const seen = new Set();
  const out = [];
  const items = Array.isArray(values) ? values : String(values || '').split(/[,\n\r;\t|/\\，、]+/);
  for (const raw of items) {
    const cleaned = safeString(raw).toLowerCase().slice(0, MAX_TRIGGER_LENGTH);
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    out.push(cleaned);
    if (out.length >= MAX_TRIGGER_COUNT) break;
  }
  if (out.length === 0 && fallbackToDefaults) {
    return [...DEFAULT_TRIGGER_WORDS];
  }
  return out;
}

export function voiceWakeStorePath(runtimeBaseDir) {
  return path.join(String(runtimeBaseDir || '').trim(), 'voice_wake_profile.json');
}

function writeJsonAtomic(filePath, obj) {
  const out = safeString(filePath);
  if (!out) throw new Error('voice_wake_store_path_missing');
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const tmp = `${out}.tmp_${process.pid}_${Math.random().toString(16).slice(2)}`;
  fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`, 'utf8');
  fs.renameSync(tmp, out);
}

function storeRecordFromObject(obj, fallbackUpdatedAtMs) {
  const root = obj && typeof obj === 'object' ? obj : {};
  const profile = root.profile && typeof root.profile === 'object' ? root.profile : root;
  const updatedRaw = Number(
    profile.updated_at_ms
    ?? profile.updatedAtMs
    ?? root.updated_at_ms
    ?? root.updatedAtMs
    ?? fallbackUpdatedAtMs
    ?? 0
  );
  return {
    schema_version: STORE_SCHEMA_VERSION,
    profile_id: safeString(profile.profile_id || root.profile_id || DEFAULT_PROFILE_ID) || DEFAULT_PROFILE_ID,
    trigger_words: sanitizeVoiceWakeTriggerWords(
      profile.trigger_words
      ?? profile.triggerWords
      ?? root.trigger_words
      ?? root.triggerWords,
      true
    ),
    updated_at_ms: Math.max(0, Number.isFinite(updatedRaw) ? Math.floor(updatedRaw) : 0),
    audit_ref: safeString(profile.audit_ref || root.audit_ref || DEFAULT_AUDIT_REF) || DEFAULT_AUDIT_REF,
  };
}

function readStoreRecord(runtimeBaseDir) {
  const filePath = voiceWakeStorePath(runtimeBaseDir);
  try {
    const raw = fs.readFileSync(filePath, 'utf8');
    return storeRecordFromObject(JSON.parse(raw), nowMs());
  } catch {
    return storeRecordFromObject({}, nowMs());
  }
}

function projectedProfile(record, desiredWakeMode) {
  const wakeMode = normalizeWakeMode(desiredWakeMode);
  return {
    schema_version: PROFILE_SCHEMA_VERSION,
    profile_id: safeString(record.profile_id || DEFAULT_PROFILE_ID) || DEFAULT_PROFILE_ID,
    trigger_words: sanitizeVoiceWakeTriggerWords(record.trigger_words, true),
    updated_at_ms: Math.max(0, Number(record.updated_at_ms || 0) || 0),
    scope: 'paired_device_group',
    source: 'hub_pairing_sync',
    wake_mode: wakeMode,
    requires_pairing_ready: true,
    audit_ref: safeString(record.audit_ref || DEFAULT_AUDIT_REF) || DEFAULT_AUDIT_REF,
  };
}

function changedPayload(record, client) {
  return {
    schema_version: CHANGED_SCHEMA_VERSION,
    profile_id: safeString(record.profile_id || DEFAULT_PROFILE_ID) || DEFAULT_PROFILE_ID,
    trigger_words: sanitizeVoiceWakeTriggerWords(record.trigger_words, true),
    updated_at_ms: Math.max(0, Number(record.updated_at_ms || 0) || 0),
    scope: 'paired_device_group',
    source: 'hub_pairing_sync',
    requires_pairing_ready: true,
    audit_ref: safeString(record.audit_ref || DEFAULT_AUDIT_REF) || DEFAULT_AUDIT_REF,
    changed_by_device_id: safeString(client?.device_id || ''),
    changed_by_app_id: safeString(client?.app_id || ''),
  };
}

export function getVoiceWakeProfile(runtimeBaseDir, desiredWakeMode) {
  const record = readStoreRecord(runtimeBaseDir);
  return {
    record,
    profile: projectedProfile(record, desiredWakeMode),
  };
}

export function setVoiceWakeProfile(runtimeBaseDir, profile, client) {
  const rawProfile = profile && typeof profile === 'object' ? profile : {};
  const desiredWakeMode = rawProfile.wake_mode ?? rawProfile.wakeMode ?? 'wake_phrase';
  const updatedAtMs = nowMs();
  const record = {
    schema_version: STORE_SCHEMA_VERSION,
    profile_id: safeString(rawProfile.profile_id || rawProfile.profileID || DEFAULT_PROFILE_ID) || DEFAULT_PROFILE_ID,
    trigger_words: sanitizeVoiceWakeTriggerWords(
      rawProfile.trigger_words ?? rawProfile.triggerWords,
      true
    ),
    updated_at_ms: updatedAtMs,
    audit_ref: safeString(rawProfile.audit_ref || rawProfile.auditRef || DEFAULT_AUDIT_REF) || DEFAULT_AUDIT_REF,
  };
  writeJsonAtomic(voiceWakeStorePath(runtimeBaseDir), record);
  return {
    record,
    profile: projectedProfile(record, desiredWakeMode),
    changed: changedPayload(record, client),
  };
}
