import crypto from 'node:crypto';

const SCHEMA_VERSION = 'xhub.longterm_markdown_edit.v1';
const DEFAULT_PATCH_MODE = 'replace';

function safeStr(v) {
  return String(v || '').trim();
}

function normalizeScopeRef(scope = {}) {
  return {
    device_id: safeStr(scope.device_id),
    user_id: safeStr(scope.user_id),
    app_id: safeStr(scope.app_id),
    project_id: safeStr(scope.project_id),
    thread_id: safeStr(scope.thread_id),
  };
}

function normalizeAllowedSensitivity(list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  const seen = new Set();
  for (const item of list) {
    const s = safeStr(item).toLowerCase();
    if (!s) continue;
    if (!['public', 'internal', 'secret'].includes(s)) continue;
    if (seen.has(s)) continue;
    seen.add(s);
    out.push(s);
  }
  return out;
}

function normalizeRoutePolicy(policy = {}) {
  const p = policy && typeof policy === 'object' ? policy : {};
  return {
    remote_mode: !!p.remote_mode,
    allow_untrusted: !!p.allow_untrusted,
    allowed_sensitivity: normalizeAllowedSensitivity(p.allowed_sensitivity),
  };
}

function countLines(text) {
  const raw = String(text ?? '');
  if (!raw) return 0;
  return raw.split(/\r?\n/).length;
}

function sha256Hex(text) {
  return crypto.createHash('sha256').update(String(text ?? ''), 'utf8').digest('hex');
}

export function normalizeMarkdownPatchMode(value) {
  const mode = safeStr(value || DEFAULT_PATCH_MODE).toLowerCase();
  if (mode === 'replace') return 'replace';
  return '';
}

export function computeLongtermMarkdownVersion({
  doc_id,
  scope_filter,
  scope_ref,
  route_policy,
  markdown,
} = {}) {
  const basis = {
    schema_version: SCHEMA_VERSION,
    doc_id: safeStr(doc_id),
    scope_filter: safeStr(scope_filter || 'all') || 'all',
    scope_ref: normalizeScopeRef(scope_ref || {}),
    route_policy: normalizeRoutePolicy(route_policy || {}),
    markdown: String(markdown ?? ''),
  };
  const hash = sha256Hex(JSON.stringify(basis));
  return `lmv1_${hash.slice(0, 24)}`;
}

export function applyLongtermMarkdownPatch({
  base_markdown,
  patch_mode,
  patch_markdown,
} = {}) {
  const mode = normalizeMarkdownPatchMode(patch_mode);
  if (!mode) throw new Error('unsupported_patch_mode');
  if (mode !== 'replace') throw new Error('unsupported_patch_mode');
  // v1 fail-closed: only full replacement patch is accepted.
  return String(patch_markdown ?? base_markdown ?? '');
}

export function buildLongtermMarkdownPatchCandidate({
  session,
  patch_mode,
  patch_markdown,
  patch_note,
  max_patch_chars,
  max_patch_lines,
} = {}) {
  const sess = session && typeof session === 'object' ? session : null;
  if (!sess) throw new Error('missing_edit_session');

  const patchText = String(patch_markdown ?? '');
  const patchChars = patchText.length;
  const patchLines = countLines(patchText);
  const maxChars = Math.max(1, Number(max_patch_chars || 0));
  const maxLines = Math.max(1, Number(max_patch_lines || 0));

  if (patchChars <= 0) throw new Error('empty_patch');
  if (patchChars > maxChars) throw new Error('patch_limit_exceeded:chars');
  if (patchLines > maxLines) throw new Error('patch_limit_exceeded:lines');

  const mode = normalizeMarkdownPatchMode(patch_mode || DEFAULT_PATCH_MODE);
  if (!mode) throw new Error('unsupported_patch_mode');

  const patchedMarkdown = applyLongtermMarkdownPatch({
    base_markdown: sess.working_markdown,
    patch_mode: mode,
    patch_markdown: patchText,
  });

  const toVersion = computeLongtermMarkdownVersion({
    doc_id: sess.doc_id,
    scope_filter: sess.scope_filter,
    scope_ref: sess.scope_ref || {},
    route_policy: sess.route_policy || {},
    markdown: patchedMarkdown,
  });

  return {
    patch_mode: mode,
    patch_note: patch_note != null ? String(patch_note) : '',
    patch_size_chars: patchChars,
    patch_line_count: patchLines,
    patch_sha256: sha256Hex(patchText),
    patched_markdown: patchedMarkdown,
    from_version: String(sess.working_version || ''),
    to_version: toVersion,
  };
}

