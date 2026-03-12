import fs from 'node:fs';
import path from 'node:path';

const SCANNABLE_EXTENSIONS = new Set([
  '.js',
  '.ts',
  '.mjs',
  '.cjs',
  '.mts',
  '.cts',
  '.jsx',
  '.tsx',
  '.py',
  '.sh',
  '.bash',
  '.zsh',
  '.md',
  '.json',
  '.yaml',
  '.yml',
]);

const SCANNABLE_FILENAMES = new Set([
  'skill.md',
  'package.json',
  'openclaw.plugin.json',
  'agent.plugin.json',
]);

const DEFAULT_MAX_SCAN_FILES = 500;
const DEFAULT_MAX_FILE_BYTES = 1024 * 1024;

const LINE_RULES = [
  {
    rule_id: 'dangerous-exec',
    severity: 'critical',
    message: 'Host command execution primitive detected',
    pattern: /\b(exec|execSync|spawn|spawnSync|execFile|execFileSync)\s*\(/,
    requires_context: /child_process/,
  },
  {
    rule_id: 'dangerous-exec-python',
    severity: 'critical',
    message: 'Python command execution primitive detected',
    pattern: /\b(subprocess\.(Popen|run|call)|os\.system)\s*\(/,
  },
  {
    rule_id: 'dynamic-code-execution',
    severity: 'critical',
    message: 'Dynamic code execution detected',
    pattern: /\beval\s*\(|new\s+Function\s*\(/,
  },
  {
    rule_id: 'shell-pipe-to-shell',
    severity: 'critical',
    message: 'Remote script piping into shell detected',
    pattern: /\b(curl|wget)\b[^\n|]*\|\s*(sh|bash|zsh)\b/i,
  },
  {
    rule_id: 'suspicious-network',
    severity: 'warn',
    message: 'WebSocket connection to non-standard port',
    pattern: /new\s+WebSocket\s*\(\s*["']wss?:\/\/[^"']*:(\d+)/,
  },
  {
    rule_id: 'unsafe-upstream-behavior',
    severity: 'critical',
    message: 'Prompt mutation or unrestricted execution hint detected',
    pattern: /(prompt mutation|dangerously-skip-permissions|--yolo|skip approvals?)/i,
  },
];

const SOURCE_RULES = [
  {
    rule_id: 'potential-exfiltration',
    severity: 'warn',
    message: 'File read combined with network send detected',
    pattern: /\b(readFileSync|readFile|fs\.readFile|open\s*\(|Path\s*\()/,
    requires_context: /\b(fetch|post|requests\.post|requests\.put|http\.request|axios\.post)\b/i,
  },
  {
    rule_id: 'env-harvesting',
    severity: 'critical',
    message: 'Environment variable access combined with network send detected',
    pattern: /\b(process\.env|os\.environ|os\.getenv|getenv\s*\()/,
    requires_context: /\b(fetch|post|requests\.post|requests\.put|http\.request|axios\.post)\b/i,
  },
  {
    rule_id: 'obfuscated-code',
    severity: 'warn',
    message: 'Hex-encoded string sequence detected',
    pattern: /(\\x[0-9a-fA-F]{2}){6,}/,
  },
  {
    rule_id: 'obfuscated-code-base64',
    severity: 'warn',
    message: 'Large base64 payload with decode call detected',
    pattern: /(?:atob|Buffer\.from|base64\.b64decode)\s*\(\s*["'][A-Za-z0-9+/=]{200,}["']/,
  },
  {
    rule_id: 'crypto-mining',
    severity: 'critical',
    message: 'Possible crypto-mining reference detected',
    pattern: /stratum\+tcp|stratum\+ssl|coinhive|cryptonight|xmrig/i,
  },
];

function truncateEvidence(text, maxLen = 160) {
  const raw = String(text || '').trim();
  if (raw.length <= maxLen) return raw;
  return `${raw.slice(0, maxLen)}...`;
}

function safeNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function isAgentSkillScannable(filePath) {
  const basename = path.basename(String(filePath || '')).toLowerCase();
  if (SCANNABLE_FILENAMES.has(basename)) return true;
  return SCANNABLE_EXTENSIONS.has(path.extname(basename));
}

export function scanAgentSkillSource(source, filePath = '') {
  const findings = [];
  const text = String(source || '');
  const lines = text.split('\n');
  const matchedRules = new Set();

  for (const rule of LINE_RULES) {
    if (matchedRules.has(rule.rule_id)) continue;
    if (rule.requires_context && !rule.requires_context.test(text)) continue;
    for (let index = 0; index < lines.length; index += 1) {
      const line = String(lines[index] || '');
      const match = rule.pattern.exec(line);
      if (!match) continue;
      if (rule.rule_id === 'suspicious-network') {
        const port = Number(match[1] || 0);
        if ([80, 443, 8080, 8443, 3000].includes(port)) continue;
      }
      findings.push({
        rule_id: rule.rule_id,
        severity: rule.severity,
        file: String(filePath || ''),
        line: index + 1,
        message: rule.message,
        evidence: truncateEvidence(line),
      });
      matchedRules.add(rule.rule_id);
      break;
    }
  }

  for (const rule of SOURCE_RULES) {
    if (!rule.pattern.test(text)) continue;
    if (rule.requires_context && !rule.requires_context.test(text)) continue;
    const matchedLineIndex = lines.findIndex((line) => rule.pattern.test(String(line || '')));
    findings.push({
      rule_id: rule.rule_id,
      severity: rule.severity,
      file: String(filePath || ''),
      line: matchedLineIndex >= 0 ? matchedLineIndex + 1 : 1,
      message: rule.message,
      evidence: truncateEvidence(matchedLineIndex >= 0 ? lines[matchedLineIndex] : text),
    });
  }

  return findings;
}

function shouldSkipEntry(name) {
  if (!name) return true;
  if (name === 'node_modules') return true;
  return name.startsWith('.');
}

function scanFileWithFindings(filePath, maxFileBytes) {
  const stat = fs.statSync(filePath);
  if (!stat.isFile()) return { scanned: false, findings: [] };
  if (stat.size > maxFileBytes) return { scanned: false, findings: [] };
  const source = fs.readFileSync(filePath, 'utf8');
  return {
    scanned: true,
    findings: scanAgentSkillSource(source, filePath),
  };
}

export function scanAgentSkillDirectoryWithSummary(rootDir, options = {}) {
  const resolvedRoot = path.resolve(String(rootDir || '.'));
  const maxFiles = Math.max(1, safeNumber(options.maxFiles, DEFAULT_MAX_SCAN_FILES));
  const maxFileBytes = Math.max(1, safeNumber(options.maxFileBytes, DEFAULT_MAX_FILE_BYTES));
  const pending = [resolvedRoot];
  const files = [];

  while (pending.length > 0 && files.length < maxFiles) {
    const current = pending.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const name = String(entry?.name || '');
      if (shouldSkipEntry(name)) continue;
      const fullPath = path.join(current, name);
      if (entry.isDirectory()) {
        pending.push(fullPath);
        continue;
      }
      if (!entry.isFile()) continue;
      if (!isAgentSkillScannable(fullPath)) continue;
      files.push(fullPath);
      if (files.length >= maxFiles) break;
    }
  }

  const findings = [];
  let scannedFiles = 0;
  for (const filePath of files) {
    const result = scanFileWithFindings(filePath, maxFileBytes);
    if (!result.scanned) continue;
    scannedFiles += 1;
    findings.push(...result.findings);
  }

  const summary = {
    scanned_files: scannedFiles,
    critical_count: findings.filter((item) => item.severity === 'critical').length,
    warn_count: findings.filter((item) => item.severity === 'warn').length,
    info_count: findings.filter((item) => item.severity === 'info').length,
  };

  return {
    schema_version: 'xhub.agent_skill_vetter_report.v1',
    scanner_version: 'hub.agent.vetter.v1',
    status: evaluateAgentSkillVetterSummary(summary),
    summary,
    findings,
  };
}

export function evaluateAgentSkillVetterSummary(summary) {
  const criticalCount = Math.max(0, safeNumber(summary?.critical_count, 0));
  const warnCount = Math.max(0, safeNumber(summary?.warn_count, 0));
  if (criticalCount > 0) return 'critical';
  if (warnCount > 0) return 'warn_only';
  return 'passed';
}
