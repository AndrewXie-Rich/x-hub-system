const CREDENTIAL_PATTERNS = [
  { kind: 'token.openai', re: /\bsk-[A-Za-z0-9_-]{10,}\b/g },
  { kind: 'token.github', re: /\bghp_[A-Za-z0-9]{20,}\b/g },
  { kind: 'token.slack', re: /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/g },
  { kind: 'auth.bearer', re: /\bBearer\s+[A-Za-z0-9._-]{16,}\b/gi },
  { kind: 'credential.named', re: /\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp|payment[_\s-]*(pin|code))\b/gi },
];

const SECRET_HINT_PATTERNS = [
  { kind: 'private.tag', re: /<private>[\s\S]*?<\/private>/gi },
  { kind: 'private.marker', re: /\[private\]/gi },
  { kind: 'password.named', re: /\b(password|passcode|authorization[_\s-]*code|auth[_\s-]*code)\b/gi },
  { kind: 'hex.long', re: /\b[0-9a-f]{32,}\b/gi },
];

function safeStr(v) {
  return String(v || '').trim();
}

function collectMatches(text, re, maxMatches = 10) {
  const out = [];
  if (!(re instanceof RegExp)) return out;
  const flags = re.flags.includes('g') ? re.flags : `${re.flags}g`;
  const scan = new RegExp(re.source, flags);
  let match;
  while ((match = scan.exec(text)) && out.length < maxMatches) {
    const raw = String(match[0] || '');
    const start = Math.max(0, Number(match.index || 0));
    out.push({
      excerpt: raw.length > 18 ? `${raw.slice(0, 6)}...${raw.slice(-4)}` : raw,
      offset: start,
      length: raw.length,
    });
  }
  return out;
}

export function analyzeLongtermMarkdownFindings(markdown = '') {
  const text = String(markdown || '');
  const findings = [];

  for (const item of CREDENTIAL_PATTERNS) {
    const matches = collectMatches(text, item.re);
    if (matches.length <= 0) continue;
    findings.push({
      kind: String(item.kind || 'credential'),
      severity: 'credential',
      match_count: matches.length,
      matches,
    });
  }
  for (const item of SECRET_HINT_PATTERNS) {
    const matches = collectMatches(text, item.re);
    if (matches.length <= 0) continue;
    findings.push({
      kind: String(item.kind || 'secret'),
      severity: 'secret',
      match_count: matches.length,
      matches,
    });
  }

  const hasCredential = findings.some((f) => String(f.severity || '') === 'credential');
  const hasSecret = findings.some((f) => String(f.severity || '') === 'secret');
  return {
    findings,
    has_credential: hasCredential,
    has_secret: hasSecret,
  };
}

export function sanitizeLongtermMarkdown(markdown = '') {
  let text = String(markdown || '');
  let redacted = 0;
  const apply = (re, replacement) => {
    const flags = re.flags.includes('g') ? re.flags : `${re.flags}g`;
    const scan = new RegExp(re.source, flags);
    text = text.replace(scan, () => {
      redacted += 1;
      return replacement;
    });
  };

  apply(/<private>[\s\S]*?<\/private>/gi, '[REDACTED_PRIVATE_BLOCK]');
  apply(/\[private\]/gi, '[REDACTED_PRIVATE]');
  apply(/\bsk-[A-Za-z0-9_-]{10,}\b/g, '[REDACTED_OPENAI_TOKEN]');
  apply(/\bghp_[A-Za-z0-9]{20,}\b/g, '[REDACTED_GITHUB_TOKEN]');
  apply(/\bxox[abprs]-[A-Za-z0-9-]{10,}\b/gi, '[REDACTED_SLACK_TOKEN]');
  apply(/\bBearer\s+[A-Za-z0-9._-]{16,}\b/gi, 'Bearer [REDACTED_BEARER]');
  apply(/\b[0-9a-f]{32,}\b/gi, '[REDACTED_HEX_SECRET]');
  apply(/\b(api[_\s-]*key|private[_\s-]*key|secret[_\s-]*token|access[_\s-]*token|jwt|otp|payment[_\s-]*(pin|code)|password|passcode)\b/gi, '[REDACTED_SECRET_KEYWORD]');

  return { markdown: text, redacted_count: redacted };
}

export function normalizeReviewDecision(value) {
  const s = safeStr(value).toLowerCase();
  if (['review', 'approve', 'reject'].includes(s)) return s;
  return '';
}

export function normalizeSecretHandling(value) {
  const s = safeStr(value).toLowerCase();
  if (s === 'sanitize') return 'sanitize';
  if (s === 'deny') return 'deny';
  return '';
}

