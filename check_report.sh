#!/usr/bin/env zsh
# 彻底禁用zsh历史替换（核心修复event not found）
unsetopt HIST_SUBST_PATTERN
unsetopt HIST_VERIFY
set +o histexpand
export TERM=xterm-256color

# 定义报告路径（可传参覆盖）
REPORT_PATH_DEFAULT="/Users/andrew.xie/Documents/AX/x-hub-system/x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json"
REPORT_PATH="${1:-$REPORT_PATH_DEFAULT}"

# 1. 检查文件是否存在（shell层提前验证）
if [[ ! -f "$REPORT_PATH" ]]; then
  echo "❌ 文件不存在：$REPORT_PATH"
  exit 1
fi

# 2. 执行Node.js脚本（关键：分界符NODE前无空格，用<<\NODE隔离）
node - "$REPORT_PATH" <<\NODE
const fs = require('node:fs');
const p = process.argv[2];

// 检查文件存在性
if (!fs.existsSync(p)) {
  console.log('missing', p);
  process.exit(1);
}

// 读取并解析JSON（增加错误捕获，避免JSON解析失败）
let d;
try {
  d = JSON.parse(fs.readFileSync(p, 'utf8'));
} catch (e) {
  console.log('❌ JSON解析失败：', e.message);
  process.exit(2);
}

// 提取事件数据
const ev = Array.isArray(d.events) ? d.events : [];
const codes = [...new Set(
  ev.map(e => String(e.incident_code || '').trim()).filter(Boolean)
)];
const handled = ev.filter(e => String(e.event_type || '').endsWith('.handled'));
const smoke = handled.filter(e => /^audit-smoke-/i.test(String(e.audit_ref || '')));
const requiredCodes = ['grant_pending', 'awaiting_instruction', 'runtime_error'];
const handledByCode = {};
for (const code of requiredCodes) {
  handledByCode[code] = handled.filter(e => String(e.incident_code || '').trim() === code).length;
}
const duplicateRequiredHandled = Object.entries(handledByCode)
  .filter(([, count]) => count > 1)
  .map(([code, count]) => `${code}:${count}`);
const tsValues = ev
  .map(e => Number(
    e.timestamp_ms
    ?? e.handled_at_ms
    ?? e.detected_at_ms
    ?? -1
  ))
  .filter(n => Number.isFinite(n) && n >= 0);
const latestEventMs = tsValues.length > 0 ? Math.max(...tsValues) : null;
const latestEventAgeMs = latestEventMs ? Date.now() - latestEventMs : null;
const sourceObj = d.source && typeof d.source === 'object' ? d.source : {};
const sourceKind = String(sourceObj.kind || d.kind || '').trim();
const sourceGeneratedBy = String(sourceObj.generated_by || d.generated_by || '').trim();
const sourceName = typeof d.source === 'string' ? d.source : '';
const syntheticHints = [];
if (/synthetic/i.test(sourceKind)) syntheticHints.push(`kind:${sourceKind}`);
if (/smoke/i.test(sourceGeneratedBy)) syntheticHints.push(`generated_by:${sourceGeneratedBy}`);
if (smoke.length > 0) syntheticHints.push(`audit_ref_prefix:audit-smoke(${smoke.length})`);

// 输出格式化结果
console.log(JSON.stringify({
  report_path: p,
  events_total: ev.length,
  codes,
  handled_total: handled.length,
  handled_required_by_code: handledByCode,
  duplicate_required_handled: duplicateRequiredHandled,
  smoke_audit_ref_total: smoke.length,
  latest_event_ms: latestEventMs,
  latest_event_age_ms: latestEventAgeMs,
  source_name: sourceName || null,
  source_kind: sourceKind || null,
  source_generated_by: sourceGeneratedBy || null,
  synthetic_hints: syntheticHints
}, null, 2));
NODE

# 恢复zsh默认配置
set -o histexpand
setopt HIST_SUBST_PATTERN
setopt HIST_VERIFY

# 输出提示（单引号隔离固定文本，避免解析）
echo '✅ 脚本执行完成'
