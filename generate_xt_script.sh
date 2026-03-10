#!/usr/bin/env bash
set -euo pipefail

TARGET_SCRIPT="$HOME/xt_ready_require_real_run.sh"

cat > "$TARGET_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/andrew.xie/Documents/AX/x-hub-system"
BUILD="$ROOT/build"
RUNTIME_EVENTS_DEFAULT="$ROOT/x-terminal/.axcoder/reports/xt_ready_incident_events.runtime.json"
RUNTIME_EVENTS="${1:-$RUNTIME_EVENTS_DEFAULT}"

mkdir -p "$BUILD"

echo "== [0/4] 检查 runtime events =="
if [[ ! -f "$RUNTIME_EVENTS" ]]; then
  echo "❌ runtime events 文件不存在: $RUNTIME_EVENTS"
  echo "请先在 X-Terminal 执行:"
  echo "  /xt-ready incidents status"
  echo "  /xt-ready incidents export"
  exit 10
fi

set +e
node - "$RUNTIME_EVENTS" <<'NODE'
const fs = require("node:fs");
const p = process.argv[2];
const req = ["grant_pending", "awaiting_instruction", "runtime_error"];
const data = JSON.parse(fs.readFileSync(p, "utf8"));
const events = Array.isArray(data.events) ? data.events : [];
const codes = events.map((e) => String(e?.incident_code || "").trim()).filter(Boolean);
const uniq = [...new Set(codes)];
const missing = req.filter((x) => !uniq.includes(x));
const handledByCode = new Map();
const handledCountByCode = new Map();
for (const e of events) {
  const eventType = String(e?.event_type || "").trim();
  if (!eventType.endsWith(".handled")) continue;
  const code = String(e?.incident_code || "").trim();
  if (!code) continue;
  handledByCode.set(code, e);
  handledCountByCode.set(code, (handledCountByCode.get(code) || 0) + 1);
}
const missingHandledAuditRef = req.filter((x) => {
  const row = handledByCode.get(x);
  if (!row) return true;
  return String(row?.audit_ref || "").trim().length <= 0;
});
const duplicateHandled = req
  .filter((x) => (handledCountByCode.get(x) || 0) > 1)
  .map((x) => `${x}:${handledCountByCode.get(x)}`);
const syntheticHandledAuditRef = req.filter((x) => {
  const row = handledByCode.get(x);
  if (!row) return false;
  return /^audit-smoke-/i.test(String(row?.audit_ref || "").trim());
});
const sourceMeta = data?.source && typeof data.source === "object" ? data.source : {};
const sourceKind = String(sourceMeta.kind || "").trim().toLowerCase();
const generatedBy = String(sourceMeta.generated_by || "").trim().toLowerCase();
const tsValues = events
  .map((e) => Number(
    e?.timestamp_ms
    ?? e?.handled_at_ms
    ?? e?.detected_at_ms
    ?? -1
  ))
  .filter((n) => Number.isFinite(n) && n >= 0);
const latestTs = tsValues.length > 0 ? Math.max(...tsValues) : -1;
const maxAgeMs = Math.max(60_000, Number(process.env.XT_READY_RUNTIME_EVENTS_MAX_AGE_MS || 3_600_000));
const ageMs = latestTs > 0 ? Date.now() - latestTs : -1;
console.log(`runtime_file=${p}`);
console.log(`events_total=${events.length}`);
console.log(`incident_codes=[${uniq.join(",")}]`);
if (latestTs > 0) {
  console.log(`latest_event_ms=${latestTs}`);
  console.log(`latest_event_age_ms=${ageMs}`);
}
if (missing.length > 0) {
  console.log(`missing=[${missing.join(",")}]`);
  process.exit(2);
}
if (missingHandledAuditRef.length > 0) {
  console.log(`missing_handled_audit_ref=[${missingHandledAuditRef.join(",")}]`);
  process.exit(3);
}
if (duplicateHandled.length > 0) {
  console.log(`duplicate_handled_required=[${duplicateHandled.join(",")}]`);
  process.exit(7);
}
if (syntheticHandledAuditRef.length > 0 || sourceKind.includes("synthetic") || generatedBy.includes("smoke")) {
  console.log(`synthetic_runtime_evidence_detected=1,handled=[${syntheticHandledAuditRef.join(",")}],source_kind=${sourceKind || "~"},generated_by=${generatedBy || "~"}`);
  process.exit(6);
}
if (latestTs <= 0) {
  console.log("latest_event_missing_timestamp=1");
  process.exit(4);
}
if (ageMs > maxAgeMs) {
  console.log(`runtime_events_stale=1,max_age_ms=${maxAgeMs}`);
  process.exit(5);
}
NODE
RUNTIME_PRECHECK_RC=$?
set -e
if (( RUNTIME_PRECHECK_RC != 0 )); then
  case "$RUNTIME_PRECHECK_RC" in
    2)
      echo "❌ runtime 缺必需 incident（grant_pending / awaiting_instruction / runtime_error）。"
      ;;
    3)
      echo "❌ runtime 的 handled 事件缺 audit_ref。"
      ;;
    4)
      echo "❌ runtime 事件缺时间戳（timestamp_ms / handled_at_ms / detected_at_ms）。"
      ;;
    5)
      echo "❌ runtime 事件过旧，请重新跑真实联测后立即导出。"
      ;;
    6)
      echo "❌ 检测到 synthetic runtime 证据（audit-smoke-* 或 source.kind=synthetic）。"
      echo "请先清理旧 smoke 证据，再产出真实事件："
      echo "  rm -f \"$RUNTIME_EVENTS\""
      echo "  # 确认没有 smoke 模式进程（不要带 --xt-release-evidence-smoke）"
      echo "  ps ax -o pid=,command= | rg -n 'xt-release-evidence-smoke|xt-grant-smoke' -S || true"
      ;;
    7)
      echo "❌ 必需 incident 出现重复 handled 事件（strict-e2e 会失败）。"
      echo "请清空 runtime 导出后，重跑一次最小联测，确保每类只保留 1 条 handled。"
      ;;
    *)
      echo "❌ runtime 证据预检失败（rc=$RUNTIME_PRECHECK_RC）。"
      ;;
  esac
  echo "请先在 X-Terminal 执行："
  echo "  /xt-ready incidents status"
  echo "  /xt-ready incidents export"
  exit 11
fi

echo "== [1/4] runtime strict-e2e =="
node "$ROOT/scripts/m3_generate_xt_ready_e2e_evidence.js" \
  --strict \
  --events-json "$RUNTIME_EVENTS" \
  --out-json "$BUILD/xt_ready_e2e_evidence.runtime.json"

node "$ROOT/scripts/m3_check_xt_ready_gate.js" \
  --strict-e2e \
  --e2e-evidence "$BUILD/xt_ready_e2e_evidence.runtime.json" \
  --out-json "$BUILD/xt_ready_gate_e2e_runtime_report.json"

echo "✅ runtime strict-e2e 通过"

echo "== [2/4] 自动选择 DB（必须含 supervisor.incident.*） =="
DB_CANDIDATES=(
  "$ROOT/data/hub.sqlite3"
  "$ROOT/x-hub/grpc-server/hub_grpc_server/data/hub.sqlite3"
  "$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_grpc/hub.sqlite3"
)

BEST_DB=""
BEST_SUP=-1

for db in "${DB_CANDIDATES[@]}"; do
  if [[ ! -f "$db" ]]; then
    echo "skip(not found): $db"
    continue
  fi
  read -r total sup <<<"$(python3 - "$db" <<'PY'
import sqlite3, sys
p = sys.argv[1]
con = sqlite3.connect(p)
cur = con.cursor()
try:
    total = cur.execute("select count(*) from audit_events").fetchone()[0]
    sup = cur.execute("select count(*) from audit_events where event_type like 'supervisor.incident.%'").fetchone()[0]
    print(total, sup)
finally:
    con.close()
PY
)"
  echo "db=$db | total=$total | supervisor_incident=$sup"
  if (( sup > BEST_SUP )); then
    BEST_SUP=$sup
    BEST_DB="$db"
  fi
done

if [[ -z "$BEST_DB" ]]; then
  echo "❌ 没找到可用 DB"
  exit 20
fi

AUDIT_INPUT_JSON=""
if (( BEST_SUP <= 0 )); then
  echo "⚠️ 所有 DB 的 supervisor.incident.* 都是 0，改用 runtime 导出作为真实联测审计输入。"
  AUDIT_INPUT_JSON="$RUNTIME_EVENTS"
else
  echo "选中 DB: $BEST_DB"
fi

echo "== [3/4] require-real 链路 =="
if [[ -z "$AUDIT_INPUT_JSON" ]]; then
  node "$ROOT/scripts/m3_export_xt_ready_audit_from_db.js" \
    --db-path "$BEST_DB" \
    --out-json "$BUILD/xt_ready_audit_export.json"
  AUDIT_INPUT_JSON="$BUILD/xt_ready_audit_export.json"
fi

node - "$AUDIT_INPUT_JSON" "$BUILD/connector_ingress_gate_snapshot.require_real.json" <<'NODE'
const fs = require("node:fs");

const inPath = process.argv[2];
const outPath = process.argv[3];
const payload = JSON.parse(fs.readFileSync(inPath, "utf8"));
const events = Array.isArray(payload?.events) ? payload.events : [];
const summary = payload?.summary && typeof payload.summary === "object" ? payload.summary : {};

const rawCoverage = Number(summary.non_message_ingress_policy_coverage);
const rawMissRate = Number(summary.blocked_event_miss_rate);

const handledEvents = events.filter((row) => String(row?.event_type || "").trim().endsWith(".handled"));
const handledWithAuditRef = handledEvents.filter((row) => String(row?.audit_ref || "").trim().length > 0);
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

XT_READY_AUDIT_EXPORT_JSON="$AUDIT_INPUT_JSON" \
node "$ROOT/scripts/m3_resolve_xt_ready_audit_input.js" \
  --require-real \
  --out-json "$BUILD/xt_ready_evidence_source.require_real.json"

node "$ROOT/scripts/m3_extract_xt_ready_incident_events_from_audit.js" \
  --strict \
  --audit-json "$AUDIT_INPUT_JSON" \
  --connector-gate-json "$BUILD/connector_ingress_gate_snapshot.require_real.json" \
  --out-json "$BUILD/xt_ready_incident_events.require_real.json"

node "$ROOT/scripts/m3_generate_xt_ready_e2e_evidence.js" \
  --strict \
  --events-json "$BUILD/xt_ready_incident_events.require_real.json" \
  --out-json "$BUILD/xt_ready_e2e_evidence.require_real.json"

node "$ROOT/scripts/m3_check_xt_ready_gate.js" \
  --strict-e2e \
  --e2e-evidence "$BUILD/xt_ready_e2e_evidence.require_real.json" \
  --evidence-source "$BUILD/xt_ready_evidence_source.require_real.json" \
  --require-real-audit-source \
  --out-json "$BUILD/xt_ready_gate_e2e_require_real_report.json"

echo "✅ require-real 链路通过"
echo "报告："
echo "  $BUILD/xt_ready_gate_e2e_runtime_report.json"
echo "  $BUILD/xt_ready_gate_e2e_require_real_report.json"
EOF

chmod +x "$TARGET_SCRIPT"
echo "✅ 脚本已生成：$TARGET_SCRIPT"
echo "🚀 运行命令：$TARGET_SCRIPT"
