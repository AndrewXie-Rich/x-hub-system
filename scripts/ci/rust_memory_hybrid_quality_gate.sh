#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${RUST_MEMORY_HYBRID_QUALITY_GATE_REPORT_DIR:-${ROOT_DIR}/build/reports}"
LOG_DIR="${RUST_MEMORY_HYBRID_QUALITY_GATE_LOG_DIR:-${REPORT_DIR}/rust_memory_hybrid_quality_gate_logs}"
SUMMARY_PATH="${RUST_MEMORY_HYBRID_QUALITY_GATE_SUMMARY_PATH:-${REPORT_DIR}/rust_memory_hybrid_quality_gate_summary.v1.json}"
BENCH_REPORT_PATH="${RUST_MEMORY_HYBRID_QUALITY_BENCH_REPORT_PATH:-${REPORT_DIR}/rust_memory_hybrid_quality_bench_quick.v1.json}"

mkdir -p "${REPORT_DIR}" "${LOG_DIR}"

overall_status="pass"
pass_count=0
fail_count=0

node_check_status="not_run"
node_check_log="${LOG_DIR}/memory_hybrid_quality_bench_node_check.log"
node_check_command="node --check rust/xhubd/tools/memory_hybrid_quality_bench.js"

quick_bench_status="not_run"
quick_bench_log="${LOG_DIR}/memory_hybrid_quality_bench_quick.log"
quick_bench_command="bash rust/xhubd/tools/memory_hybrid_quality_bench.command > \"${BENCH_REPORT_PATH}\""

run_step() {
  local step_id="$1"
  local description="$2"
  local log_path="$3"
  local command="$4"

  echo "[rust-memory-hybrid-quality-gate] start step=${step_id} description=${description}"
  if (
    cd "${ROOT_DIR}"
    bash -lc "${command}"
  ) >"${log_path}" 2>&1; then
    echo "[rust-memory-hybrid-quality-gate] pass step=${step_id} log=${log_path}"
    pass_count=$((pass_count + 1))
    return 0
  fi

  echo "[rust-memory-hybrid-quality-gate] fail step=${step_id} log=${log_path}" >&2
  echo "[rust-memory-hybrid-quality-gate] last_log_lines step=${step_id}" >&2
  tail -n 40 "${log_path}" >&2 || true
  fail_count=$((fail_count + 1))
  overall_status="fail"
  return 1
}

if run_step \
  "node_check" \
  "Memory hybrid quality bench syntax check" \
  "${node_check_log}" \
  "${node_check_command}"; then
  node_check_status="pass"
else
  node_check_status="fail"
fi

if run_step \
  "quick_bench" \
  "Rust memory hybrid quick quality bench" \
  "${quick_bench_log}" \
  "${quick_bench_command}"; then
  quick_bench_status="pass"
else
  quick_bench_status="fail"
fi

export RUST_MEMORY_HYBRID_QUALITY_GATE_OVERALL_STATUS="${overall_status}"
export RUST_MEMORY_HYBRID_QUALITY_GATE_PASS_COUNT="${pass_count}"
export RUST_MEMORY_HYBRID_QUALITY_GATE_FAIL_COUNT="${fail_count}"
export RUST_MEMORY_HYBRID_QUALITY_GATE_NODE_CHECK_STATUS="${node_check_status}"
export RUST_MEMORY_HYBRID_QUALITY_GATE_NODE_CHECK_COMMAND="${node_check_command}"
export RUST_MEMORY_HYBRID_QUALITY_GATE_QUICK_BENCH_STATUS="${quick_bench_status}"
export RUST_MEMORY_HYBRID_QUALITY_GATE_QUICK_BENCH_COMMAND="${quick_bench_command}"

python3 - "${SUMMARY_PATH}" "${BENCH_REPORT_PATH}" "${node_check_log}" "${quick_bench_log}" <<'PY'
import json
import os
import sys
import time

summary_path, bench_report_path, node_check_log, quick_bench_log = sys.argv[1:5]


def load_json_if_exists(path):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


bench_report = load_json_if_exists(bench_report_path) if os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_QUICK_BENCH_STATUS") == "pass" else None
summary = {
    "ok": os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_OVERALL_STATUS") == "pass",
    "schema_version": "xhub.rust_hub.memory_hybrid_quality_gate.v1",
    "command": "rust-memory-hybrid-quality-gate",
    "generated_at_ms": int(time.time() * 1000),
    "profile": "quick",
    "pass_count": int(os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_PASS_COUNT", "0")),
    "fail_count": int(os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_FAIL_COUNT", "0")),
    "production_authority_change": False,
    "steps": [
        {
            "id": "node_check",
            "status": os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_NODE_CHECK_STATUS"),
            "command": os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_NODE_CHECK_COMMAND"),
            "log_path": node_check_log,
        },
        {
            "id": "quick_bench",
            "status": os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_QUICK_BENCH_STATUS"),
            "command": os.environ.get("RUST_MEMORY_HYBRID_QUALITY_GATE_QUICK_BENCH_COMMAND"),
            "log_path": quick_bench_log,
            "report_path": bench_report_path,
        },
    ],
    "bench": {
        "available": isinstance(bench_report, dict),
        "ok": bench_report.get("ok") if isinstance(bench_report, dict) else None,
        "fixture_object_count": bench_report.get("fixture_object_count") if isinstance(bench_report, dict) else None,
        "case_count": bench_report.get("case_count") if isinstance(bench_report, dict) else None,
        "passed_count": bench_report.get("passed_count") if isinstance(bench_report, dict) else None,
        "derived_index_source": bench_report.get("derived_index_source") if isinstance(bench_report, dict) else None,
        "bm25_used": bench_report.get("bm25_used") if isinstance(bench_report, dict) else None,
        "semantic_used": bench_report.get("semantic_used") if isinstance(bench_report, dict) else None,
        "rerank_used": bench_report.get("rerank_used") if isinstance(bench_report, dict) else None,
        "metrics": bench_report.get("metrics") if isinstance(bench_report, dict) else None,
    },
}

os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(summary, handle, indent=2, sort_keys=True)
    handle.write("\n")

print(json.dumps(summary, indent=2, sort_keys=True))
PY

if [[ "${overall_status}" != "pass" ]]; then
  exit 1
fi
