import { analyzeLongtermMarkdownFindings, sanitizeLongtermMarkdown } from './memory_markdown_review.js';

const DEFAULT_EXPORT_CLASS = 'prompt_bundle';
const DEFAULT_ALLOW_CLASSES = Object.freeze([DEFAULT_EXPORT_CLASS]);
const DEFAULT_SECRET_MODE = 'deny';
const DEFAULT_ON_BLOCK = 'downgrade_to_local';

const ALLOWED_SECRET_MODES = new Set(['deny', 'allow_sanitized']);
const ALLOWED_ON_BLOCK = new Set(['downgrade_to_local', 'error']);
const ALLOWED_SENSITIVITY = new Set(['public', 'internal', 'secret']);

function normalizeCode(v, fallback = '') {
  const raw = String(v || '').trim().toLowerCase();
  if (!raw) return fallback;
  return raw.replace(/[^a-z0-9._:-]/g, '_');
}

function normalizeList(raw) {
  if (Array.isArray(raw)) {
    return raw
      .map((v) => normalizeCode(v, ''))
      .filter(Boolean);
  }
  const text = String(raw || '').trim();
  if (!text) return [];
  return text
    .split(',')
    .map((v) => normalizeCode(v, ''))
    .filter(Boolean);
}

function parsePolicyJsonFromEnv() {
  const raw = String(process.env.HUB_REMOTE_EXPORT_POLICY_JSON || '').trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function normalizeSecretMode(raw, fallback) {
  const mode = normalizeCode(raw, fallback);
  if (ALLOWED_SECRET_MODES.has(mode)) return mode;
  return '';
}

function normalizeOnBlock(raw, fallback) {
  const mode = normalizeCode(raw, fallback);
  if (ALLOWED_ON_BLOCK.has(mode)) return mode;
  return '';
}

function summarizeFindings(findings) {
  const rows = Array.isArray(findings) ? findings : [];
  const summaryItems = [];
  let credentialCount = 0;
  let secretCount = 0;

  for (const item of rows) {
    const severity = normalizeCode(item?.severity || '', '');
    const kind = normalizeCode(item?.kind || '', severity || 'finding');
    const matchCount = Math.max(1, Number(item?.match_count || 1));
    summaryItems.push({ kind, severity: severity || 'unknown', match_count: matchCount });
    if (severity === 'credential') credentialCount += matchCount;
    else if (severity === 'secret') secretCount += matchCount;
  }

  return {
    findings: summaryItems,
    finding_count: summaryItems.length,
    credential_count: credentialCount,
    secret_count: secretCount,
  };
}

function classifyJobSensitivity({ hint, promptText, hasCredential, hasSecret }) {
  const normalizedHint = normalizeCode(hint, '');
  if (hasCredential || hasSecret) return 'secret';
  if (ALLOWED_SENSITIVITY.has(normalizedHint)) return normalizedHint;

  const text = String(promptText || '');
  if (/\[(canonical memory|working set)\]/i.test(text)) return 'internal';
  if (/\bmemory\b/i.test(text)) return 'internal';
  return 'public';
}

function shouldBlockBySecretMode({ jobSensitivity, hasSecret, secretMode }) {
  if (secretMode === 'deny') {
    return jobSensitivity === 'secret' || !!hasSecret;
  }
  return false;
}

export function resolveRemoteExportPolicy(input = {}) {
  const defaults = {
    export_class: DEFAULT_EXPORT_CLASS,
    allow_classes: [...DEFAULT_ALLOW_CLASSES],
    secret_mode: DEFAULT_SECRET_MODE,
    on_block: DEFAULT_ON_BLOCK,
  };

  const envJson = parsePolicyJsonFromEnv();
  const envRaw = {
    export_class: process.env.HUB_REMOTE_EXPORT_CLASS,
    allow_classes: process.env.HUB_REMOTE_EXPORT_ALLOW_CLASSES,
    secret_mode: process.env.HUB_REMOTE_EXPORT_SECRET_MODE,
    on_block: process.env.HUB_REMOTE_EXPORT_ON_BLOCK,
  };
  const inObj = input && typeof input === 'object' ? input : {};

  const merged = {
    ...defaults,
    ...(envJson && typeof envJson === 'object' ? envJson : {}),
    ...envRaw,
    ...inObj,
  };

  const exportClass = normalizeCode(merged.export_class, DEFAULT_EXPORT_CLASS) || DEFAULT_EXPORT_CLASS;
  const allowClasses = normalizeList(merged.allow_classes);
  const allowClassSet = new Set((allowClasses.length ? allowClasses : DEFAULT_ALLOW_CLASSES).map((v) => normalizeCode(v, '')));

  const secretMode = normalizeSecretMode(merged.secret_mode, DEFAULT_SECRET_MODE) || DEFAULT_SECRET_MODE;
  const onBlock = normalizeOnBlock(merged.on_block, DEFAULT_ON_BLOCK) || DEFAULT_ON_BLOCK;

  return {
    export_class: exportClass,
    allow_classes: Array.from(allowClassSet),
    secret_mode: secretMode,
    on_block: onBlock,
  };
}

export function evaluatePromptRemoteExportGate(input = {}) {
  const inObj = input && typeof input === 'object' ? input : {};
  const policy = resolveRemoteExportPolicy(inObj.policy || {});
  const exportClass = normalizeCode(inObj.export_class, policy.export_class) || policy.export_class;
  const promptText = String(inObj.prompt_text || inObj.prompt || '');
  const gateOrder = [];

  let dlp;
  try {
    dlp = analyzeLongtermMarkdownFindings(promptText);
    gateOrder.push({ step: 'secondary_dlp', passed: true });
  } catch {
    gateOrder.push({ step: 'secondary_dlp', passed: false, reason: 'secondary_dlp_error' });
    const action = policy.on_block === 'downgrade_to_local' ? 'downgrade_to_local' : 'error';
    return {
      blocked: true,
      downgraded: action === 'downgrade_to_local',
      action,
      deny_code: 'secondary_dlp_error',
      gate_reason: 'secondary_dlp_error',
      export_class: exportClass,
      job_sensitivity: 'secret',
      prompt_text: promptText,
      policy,
      findings_summary: {
        findings: [],
        finding_count: 0,
        credential_count: 0,
        secret_count: 0,
      },
      gate_order: gateOrder,
    };
  }

  const findings = Array.isArray(dlp?.findings) ? dlp.findings : [];
  const findingsSummary = summarizeFindings(findings);
  const hasCredential = !!dlp?.has_credential || findingsSummary.credential_count > 0;
  const hasSecret = !!dlp?.has_secret || findingsSummary.secret_count > 0;
  const jobSensitivity = classifyJobSensitivity({
    hint: inObj.job_sensitivity_hint,
    promptText,
    hasCredential,
    hasSecret,
  });

  let blocked = false;
  let gateReason = 'allow';
  let nextPrompt = promptText;
  let sanitized = false;

  // 2) credential finding check (hard deny)
  if (hasCredential) {
    blocked = true;
    gateReason = 'credential_finding';
    gateOrder.push({ step: 'credential_check', passed: false, reason: gateReason });
  } else {
    gateOrder.push({ step: 'credential_check', passed: true });
  }

  // 3) secret_mode check
  if (!blocked) {
    if (!ALLOWED_SECRET_MODES.has(policy.secret_mode)) {
      blocked = true;
      gateReason = 'secret_mode_invalid';
      gateOrder.push({ step: 'secret_mode', passed: false, reason: gateReason, mode: policy.secret_mode });
    } else if (shouldBlockBySecretMode({ jobSensitivity, hasSecret, secretMode: policy.secret_mode })) {
      blocked = true;
      gateReason = 'secret_mode_deny';
      gateOrder.push({ step: 'secret_mode', passed: false, reason: gateReason, mode: policy.secret_mode });
    } else if (policy.secret_mode === 'allow_sanitized' && hasSecret) {
      const sanitizedPrompt = sanitizeLongtermMarkdown(promptText);
      const redactedCount = Math.max(0, Number(sanitizedPrompt?.redacted_count || 0));
      nextPrompt = String(sanitizedPrompt?.markdown || promptText);
      sanitized = redactedCount > 0;
      if (!sanitized) {
        blocked = true;
        gateReason = 'secret_sanitize_required';
        gateOrder.push({ step: 'secret_mode', passed: false, reason: gateReason, mode: policy.secret_mode });
      } else {
        gateOrder.push({
          step: 'secret_mode',
          passed: true,
          mode: policy.secret_mode,
          redacted_count: redactedCount,
        });
      }
    } else {
      gateOrder.push({ step: 'secret_mode', passed: true, mode: policy.secret_mode });
    }
  }

  // 4) allow_classes check
  if (!blocked) {
    if (!Array.isArray(policy.allow_classes) || !policy.allow_classes.includes(exportClass)) {
      blocked = true;
      gateReason = 'allow_class_denied';
      gateOrder.push({ step: 'allow_classes', passed: false, reason: gateReason });
    } else {
      gateOrder.push({ step: 'allow_classes', passed: true });
    }
  }

  // 5) on_block
  let action = 'allow';
  if (blocked) {
    if (policy.on_block === 'downgrade_to_local') {
      action = 'downgrade_to_local';
    } else if (policy.on_block === 'error') {
      action = 'error';
    } else {
      action = 'error';
      gateReason = gateReason === 'allow' ? 'on_block_invalid' : gateReason;
    }
    gateOrder.push({ step: 'on_block', passed: false, action });
  } else {
    gateOrder.push({ step: 'on_block', passed: true, action });
  }

  return {
    blocked,
    downgraded: blocked ? action === 'downgrade_to_local' : sanitized,
    action,
    deny_code: blocked ? gateReason || 'remote_export_blocked' : '',
    gate_reason: blocked ? gateReason || 'remote_export_blocked' : sanitized ? 'secret_sanitized' : 'allow',
    export_class: exportClass,
    job_sensitivity: jobSensitivity,
    prompt_text: nextPrompt,
    policy,
    findings_summary: findingsSummary,
    gate_order: gateOrder,
  };
}
