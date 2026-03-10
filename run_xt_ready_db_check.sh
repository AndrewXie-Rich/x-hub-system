#!/usr/bin/env zsh
# Mac OS 专属 - 基于指定DB执行xt_ready require-real链路检查
# 禁用zsh历史替换，避免解析错误
set +o histexpand
unsetopt HIST_SUBST_PATTERN
unsetopt HIST_VERIFY
export TERM=xterm-256color

# ====================== 核心配置 ======================
# 项目根目录（确保路径统一）
PROJECT_ROOT="/Users/andrew.xie/Documents/AX/x-hub-system"
# 指定的最佳数据库路径
BEST_DB="/Users/andrew.xie/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_grpc/hub.sqlite3"
# 输出目录（自动创建）
BUILD_DIR="${PROJECT_ROOT}/build"

# ====================== 前置检查 ======================
# 切换到项目根目录
cd "${PROJECT_ROOT}" || {
  echo "❌ 项目目录不存在：${PROJECT_ROOT}"
  exit 1
}

# 检查数据库文件是否存在
if [[ ! -f "${BEST_DB}" ]]; then
  echo "❌ 指定的数据库文件不存在：${BEST_DB}"
  exit 1
fi

# 创建build目录（确保输出目录存在）
mkdir -p "${BUILD_DIR}"
echo "✅ 前置检查完成，开始执行链路检查..."
echo "========================================"

# ====================== 计算最近10分钟时间戳 ======================
echo "🔍 计算最近10分钟时间戳（FROM_MS）..."
FROM_MS=$(python3 - <<\PY
import time
# 最近10分钟（600秒）的时间戳（毫秒）
from_ms = int((time.time() - 600) * 1000)
print(from_ms)
PY
)
echo "✅ FROM_MS = ${FROM_MS}"

# ====================== 执行Node.js脚本链路 ======================
# 1. 导出审计数据
echo "📥 执行：导出审计数据到DB"
node ./scripts/m3_export_xt_ready_audit_from_db.js \
  --db-path "${BEST_DB}" \
  --from-ms "${FROM_MS}" \
  --out-json "${BUILD_DIR}/xt_ready_audit_export.db_real.json"

# 检查上一步是否执行成功
if [[ $? -ne 0 ]]; then
  echo "❌ 导出审计数据失败，退出执行"
  exit 1
fi

# 2. 解析审计输入（修复原代码的换行错误）
echo "🔧 执行：解析审计输入"
XT_READY_AUDIT_EXPORT_JSON="${BUILD_DIR}/xt_ready_audit_export.db_real.json" \
node ./scripts/m3_resolve_xt_ready_audit_input.js \
  --require-real \
  --out-json "${BUILD_DIR}/xt_ready_evidence_source.db_real.json"

if [[ $? -ne 0 ]]; then
  echo "❌ 解析审计输入失败，退出执行"
  exit 1
fi

# 3. 从审计导出构建 connector ingress gate snapshot（source=audit）
echo "🧩 执行：构建connector ingress gate快照"
node - "${BUILD_DIR}/xt_ready_audit_export.db_real.json" "${BUILD_DIR}/connector_ingress_gate_snapshot.db_real.json" <<'NODE'
const fs = require("node:fs");

const inPath = process.argv[2];
const outPath = process.argv[3];
const payload = JSON.parse(fs.readFileSync(inPath, "utf8"));
const events = Array.isArray(payload?.events) ? payload.events : [];
const summary = payload?.summary && typeof payload.summary === "object" ? payload.summary : {};

const rawCoverage = Number(summary.non_message_ingress_policy_coverage);
const rawMissRate = Number(summary.blocked_event_miss_rate);

const handledEvents = events.filter((row) => String(row?.event_type || "").trim().endsWith(".handled"));
const handledWithAuditRef = handledEvents.filter((row) => {
  const ext = (() => {
    try {
      return JSON.parse(String(row?.ext_json || "{}"));
    } catch {
      return {};
    }
  })();
  const auditRef = String(ext?.audit_ref || row?.audit_ref || row?.event_id || "").trim();
  return auditRef.length > 0;
});
const detectedEvents = events.filter((row) => String(row?.event_type || "").trim().endsWith(".detected"));
const inferredCoverage = handledEvents.length > 0 ? handledWithAuditRef.length / handledEvents.length : 0;
const inferredMissRate = detectedEvents.length > 0
  ? Math.max(0, detectedEvents.length - handledEvents.length) / detectedEvents.length
  : 0;

const coverage = Number.isFinite(rawCoverage) && rawCoverage >= 0 ? rawCoverage : inferredCoverage;
const missRate = Number.isFinite(rawMissRate) && rawMissRate >= 0 ? rawMissRate : inferredMissRate;
const measuredAt = Date.now();
const pass = coverage >= 1 && missRate < 0.01;

const out = {
  schema_version: "xt_ready_connector_ingress_gate_fetch.v1",
  fetched_at_ms: measuredAt,
  request: {
    base_url: "local://audit-derived",
    route_path: "connector_ingress_gate_snapshot",
    source: "audit",
    url: "local://audit-derived/connector_ingress_gate_snapshot?source=audit",
  },
  source_used: "audit",
  data_ready: true,
  audit_row_count: events.length,
  scan_entry_count: 0,
  snapshot: {
    schema_version: "xhub.connector.non_message_ingress_gate.v1",
    measured_at_ms: measuredAt,
    pass,
    incident_codes: [],
    thresholds: {
      non_message_ingress_policy_coverage_min: 1,
      blocked_event_miss_rate_max_exclusive: 0.01,
    },
    checks: [
      {
        key: "non_message_ingress_policy_coverage",
        pass: coverage >= 1,
        comparator: ">=",
        expected: 1,
        actual: coverage,
      },
      {
        key: "blocked_event_miss_rate",
        pass: missRate < 0.01,
        comparator: "<",
        expected: 0.01,
        actual: missRate,
      },
    ],
    metrics: {
      non_message_ingress_policy_coverage: coverage,
      blocked_event_miss_rate: missRate,
    },
  },
  summary: {
    non_message_ingress_policy_coverage: coverage,
    blocked_event_miss_rate: missRate,
  },
};

fs.writeFileSync(outPath, `${JSON.stringify(out, null, 2)}\n`, "utf8");
console.log(`ok - connector ingress gate snapshot derived (source=audit, out=${outPath})`);
NODE

if [[ $? -ne 0 ]]; then
  echo "❌ 构建connector ingress gate快照失败，退出执行"
  exit 1
fi

# 4. 提取事件数据（带connector gate快照）
echo "📤 执行：提取incident事件"
node ./scripts/m3_extract_xt_ready_incident_events_from_audit.js \
  --strict \
  --audit-json "${BUILD_DIR}/xt_ready_audit_export.db_real.json" \
  --connector-gate-json "${BUILD_DIR}/connector_ingress_gate_snapshot.db_real.json" \
  --out-json "${BUILD_DIR}/xt_ready_incident_events.db_real.json"

if [[ $? -ne 0 ]]; then
  echo "❌ 提取incident事件失败，退出执行"
  exit 1
fi

# 5. 生成E2E证据
echo "📊 执行：生成E2E证据"
node ./scripts/m3_generate_xt_ready_e2e_evidence.js \
  --strict \
  --events-json "${BUILD_DIR}/xt_ready_incident_events.db_real.json" \
  --out-json "${BUILD_DIR}/xt_ready_e2e_evidence.db_real.json"

if [[ $? -ne 0 ]]; then
  echo "❌ 生成E2E证据失败，退出执行"
  exit 1
fi

# 6. 检查xt_ready网关（修复原代码的换行错误）
echo "✅ 执行：检查xt_ready网关"
node ./scripts/m3_check_xt_ready_gate.js \
  --strict-e2e \
  --e2e-evidence "${BUILD_DIR}/xt_ready_e2e_evidence.db_real.json" \
  --evidence-source "${BUILD_DIR}/xt_ready_evidence_source.db_real.json" \
  --require-real-audit-source \
  --out-json "${BUILD_DIR}/xt_ready_gate_e2e_db_real_report.json"

if [[ $? -ne 0 ]]; then
  echo "❌ 检查xt_ready网关失败，退出执行"
  exit 1
fi

# ====================== 输出报告结果 ======================
echo "========================================"
echo "📋 报告结果解析："
node -e "
const fs = require('node:fs');
const reportPath = '${BUILD_DIR}/xt_ready_gate_e2e_db_real_report.json';
try {
  const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  console.log('✅ ok =', report.ok);
  console.log('❌ errors =', report.errors || []);
} catch (e) {
  console.error('❌ 解析报告失败：', e.message);
  process.exit(1);
}
"

# ====================== 收尾 ======================
echo "========================================"
echo "🎉 所有链路执行完成！"
echo "📁 报告文件：${BUILD_DIR}/xt_ready_gate_e2e_db_real_report.json"

# 恢复zsh默认配置
set -o histexpand
setopt HIST_SUBST_PATTERN
setopt HIST_VERIFY
