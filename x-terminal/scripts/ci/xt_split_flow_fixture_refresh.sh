#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PROJECT_ROOT="${ROOT_DIR}"
RUNTIME_OUT="${ROOT_DIR}/.axcoder/reports/split_flow_snapshot.runtime.json"
SAMPLE_PATH="${ROOT_DIR}/scripts/fixtures/split_flow_snapshot.sample.json"
XTERMINAL_BIN=""
COPY_TO_SAMPLE=0
SKIP_BUILD=0
RUN_GATE_BASELINE=0
RUN_GATE_STRICT=0

usage() {
  cat <<'EOF'
Usage:
  bash ./scripts/ci/xt_split_flow_fixture_refresh.sh [options]

Options:
  --project-root <path>   Project root for generation (default: repo root)
  --out-json <path>       Runtime fixture output path
  --sample-path <path>    Canonical sample fixture path
  --xterminal-bin <path>  Use prebuilt XTerminal binary for generator
  --copy-to-sample        Canonicalize runtime fixture and overwrite sample fixture
  --skip-build            Skip `swift build`
  --run-gate-baseline     Run baseline gate with runtime regression evidence
  --run-gate-strict       Run strict gate with runtime regression evidence
  -h, --help              Show this help
EOF
}

while (($# > 0)); do
  case "$1" in
    --project-root)
      PROJECT_ROOT="$(cd "${2:?missing value for --project-root}" && pwd)"
      shift 2
      ;;
    --out-json)
      RUNTIME_OUT="$2"
      shift 2
      ;;
    --sample-path)
      SAMPLE_PATH="$2"
      shift 2
      ;;
    --xterminal-bin)
      XTERMINAL_BIN="$2"
      shift 2
      ;;
    --copy-to-sample)
      COPY_TO_SAMPLE=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --run-gate-baseline)
      RUN_GATE_BASELINE=1
      shift
      ;;
    --run-gate-strict)
      RUN_GATE_STRICT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[xt-split-flow-refresh] unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

REPORT_DIR="${PROJECT_ROOT}/.axcoder/reports"
mkdir -p "${REPORT_DIR}"

GENERATOR_ARGS=(
  --project-root "${PROJECT_ROOT}"
  --out-json "${RUNTIME_OUT}"
)
if [[ -n "${XTERMINAL_BIN}" ]]; then
  GENERATOR_ARGS+=(--xterminal-bin "${XTERMINAL_BIN}")
fi
if [[ "${COPY_TO_SAMPLE}" == "1" ]]; then
  GENERATOR_ARGS+=(--copy-to-sample --sample-path "${SAMPLE_PATH}")
fi

if [[ "${SKIP_BUILD}" == "0" ]]; then
  echo "[xt-split-flow-refresh] swift build"
  swift build
fi

echo "[xt-split-flow-refresh] generate runtime fixture -> ${RUNTIME_OUT}"
node "${PROJECT_ROOT}/scripts/generate_split_flow_snapshot_fixture.js" "${GENERATOR_ARGS[@]}"

echo "[xt-split-flow-refresh] validate generated fixture contract"
node "${PROJECT_ROOT}/scripts/check_split_flow_snapshot_fixture_contract.js" \
  --fixture "${RUNTIME_OUT}" \
  --out-json "${REPORT_DIR}/split-flow-runtime-fixture-contract-report.json"

echo "[xt-split-flow-refresh] compare generated fixture against canonical sample"
node "${PROJECT_ROOT}/scripts/check_split_flow_snapshot_generation_regression.js" \
  --generated "${RUNTIME_OUT}" \
  --sample "${SAMPLE_PATH}"

if [[ "${RUN_GATE_BASELINE}" == "1" ]]; then
  if [[ "${RUN_GATE_STRICT}" == "1" ]]; then
    echo "[xt-split-flow-refresh] cannot combine --run-gate-baseline and --run-gate-strict" >&2
    exit 2
  fi
  echo "[xt-split-flow-refresh] run baseline gate with runtime regression evidence"
  XT_GATE_MODE=baseline \
  XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1 \
  XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE=0 \
  XT_SPLIT_FLOW_RUNTIME_FIXTURE="${RUNTIME_OUT}" \
  bash "${PROJECT_ROOT}/scripts/ci/xt_release_gate.sh"
fi

if [[ "${RUN_GATE_STRICT}" == "1" ]]; then
  echo "[xt-split-flow-refresh] run strict gate with runtime regression evidence"
  XT_GATE_MODE=strict \
  XT_GATE_SPLIT_FLOW_RUNTIME_REGRESSION=1 \
  XT_GATE_SPLIT_FLOW_GENERATE_RUNTIME_FIXTURE=0 \
  XT_SPLIT_FLOW_RUNTIME_FIXTURE="${RUNTIME_OUT}" \
  bash "${PROJECT_ROOT}/scripts/ci/xt_release_gate.sh"
fi

echo "[xt-split-flow-refresh] done"
