#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HUB_RUNTIME_BASE_DIR="${HUB_RUNTIME_BASE_DIR:-$HOME/Library/Containers/com.rel.flowhub/Data/RELFlowHub}"
HUB_HOST="${HUB_HOST:-127.0.0.1}"
HUB_PORT="${HUB_PORT:-50061}"
HUB_PAIRING_PORT="${HUB_PAIRING_PORT:-50062}"
HUB_PAID_AI_QUEUE_TIMEOUT_MS="${HUB_PAID_AI_QUEUE_TIMEOUT_MS:-30000}"
STRESS_MODEL_ID="${STRESS_MODEL_ID:-}"

TMP_DIR="${TMP_DIR:-/tmp/hub_paid_ai_bench_$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$TMP_DIR"
FAILED_CASES=0

run_case() {
  local label="$1"
  local global="$2"
  local per_project="$3"
  local projects="$4"
  local report="$TMP_DIR/${label}.json"

  echo
  echo "[bench] case=$label global=$global per_project=$per_project projects=$projects"

  local -a args=(npm run stress-paid-local --prefix "$ROOT_DIR" -- --projects "$projects" --label "$label" --json-out "$report")
  if [[ -n "$STRESS_MODEL_ID" ]]; then
    args+=(--model "$STRESS_MODEL_ID")
  fi

  set +e
  HUB_RUNTIME_BASE_DIR="$HUB_RUNTIME_BASE_DIR" \
  HUB_HOST="$HUB_HOST" \
  HUB_PORT="$HUB_PORT" \
  HUB_PAIRING_PORT="$HUB_PAIRING_PORT" \
  HUB_PAID_AI_GLOBAL_CONCURRENCY="$global" \
  HUB_PAID_AI_PER_PROJECT_CONCURRENCY="$per_project" \
  HUB_PAID_AI_QUEUE_TIMEOUT_MS="$HUB_PAID_AI_QUEUE_TIMEOUT_MS" \
    "${args[@]}"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    FAILED_CASES=$((FAILED_CASES + 1))
    echo "[bench] warning: case=$label exited rc=$rc"
  fi
  return 0
}

run_case "baseline_g1_p1_n8" 1 1 8
run_case "exp_g2_p1_n8" 2 1 8
run_case "exp_g3_p1_n10" 3 1 10

python3 - "$TMP_DIR/baseline_g1_p1_n8.json" "$TMP_DIR/exp_g2_p1_n8.json" "$TMP_DIR/exp_g3_p1_n10.json" <<'PY'
import json, os, sys

def load(fp):
    if not os.path.exists(fp):
        return {
            'label': os.path.basename(fp).replace('.json', ''),
            'projects': None,
            'global': None,
            'per_project': None,
            'ok': None,
            'total': None,
            'queue_avg': None,
            'queue_p90': None,
            'queue_max': None,
            'wall_avg': None,
            'wall_p90': None,
            'duration': None,
            'path': fp,
            'missing': True,
        }
    with open(fp, 'r', encoding='utf-8') as f:
        d = json.load(f)
    qw = d.get('queue_wait_ms') or {}
    wl = d.get('wall_ms') or {}
    rr = d.get('result') or {}
    cc = d.get('concurrency') or {}
    return {
        'label': d.get('label') or d.get('run_id'),
        'projects': cc.get('projects'),
        'global': cc.get('global'),
        'per_project': cc.get('per_project'),
        'ok': rr.get('ok'),
        'total': rr.get('total'),
        'queue_avg': qw.get('avg'),
        'queue_p90': qw.get('p90'),
        'queue_max': qw.get('max'),
        'wall_avg': wl.get('avg'),
        'wall_p90': wl.get('p90'),
        'duration': d.get('duration_ms'),
        'path': fp,
        'missing': False,
    }

def fmt(v):
    return '-' if v is None else str(v)

rows = [load(x) for x in sys.argv[1:]]
print("\n=== Paid AI Queue Benchmark Summary ===")
header = f"{'case':20} {'g/p':7} {'ok':7} {'q_avg':8} {'q_p90':8} {'q_max':8} {'w_avg':8} {'w_p90':8} {'dur_ms':8}"
print(header)
print('-' * len(header))
for r in rows:
    gp = f"{fmt(r['global'])}/{fmt(r['per_project'])}"
    ok = f"{fmt(r['ok'])}/{fmt(r['total'])}"
    print(f"{r['label'][:20]:20} {gp:7} {ok:7} {fmt(r['queue_avg']):8} {fmt(r['queue_p90']):8} {fmt(r['queue_max']):8} {fmt(r['wall_avg']):8} {fmt(r['wall_p90']):8} {fmt(r['duration']):8}")

base = rows[0]
print("\n=== Delta vs baseline ===")
for r in rows[1:]:
    if r.get('missing'):
        print(f"- {r['label']}: report missing")
        continue
    if base['queue_p90'] is None or r['queue_p90'] is None:
        print(f"- {r['label']}: queue_p90 delta unavailable")
        continue
    dq = r['queue_p90'] - base['queue_p90']
    dw = (r['wall_p90'] - base['wall_p90']) if (base['wall_p90'] is not None and r['wall_p90'] is not None) else None
    print(f"- {r['label']}: queue_p90 delta={dq} ms, wall_p90 delta={dw if dw is not None else 'n/a'} ms")

first_existing = next((r['path'] for r in rows if not r.get('missing')), rows[0]['path'])
print(f"\n[bench] json reports in: {first_existing.rsplit('/', 1)[0]}")
PY

if [[ "$FAILED_CASES" -ne 0 ]]; then
  echo "[bench] completed with failed cases: $FAILED_CASES"
  exit 2
fi
