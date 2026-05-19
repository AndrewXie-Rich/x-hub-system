#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XT_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
RUST_XTD_DIR="${XT_ROOT}/rust-xtd"
SCRATCH_DIR="${XT_CORE_PROJECTION_SWIFT_SCRATCH:-/private/tmp/xt-core-projection-contract-build}"
FIXTURE_DIR="${XT_CORE_PROJECTION_FIXTURE_DIR:-$(mktemp -d /tmp/xt_core_projection_contract.XXXXXX)}"
KEEP_FIXTURE="${XT_CORE_PROJECTION_KEEP_FIXTURE:-0}"
SWIFT_CHECK_HOME="${XT_CORE_PROJECTION_SWIFT_HOME:-${FIXTURE_DIR}/swift-home}"
SWIFT_CLANG_CACHE="${XT_CORE_PROJECTION_CLANG_MODULE_CACHE:-${FIXTURE_DIR}/clang-module-cache}"

cleanup() {
  if [[ "${KEEP_FIXTURE}" == "1" ]]; then
    printf '[xt-core-projection] keeping fixture dir: %s\n' "${FIXTURE_DIR}"
    return
  fi
  rm -rf "${FIXTURE_DIR}"
}

trap cleanup EXIT

printf '[xt-core-projection] swift root: %s\n' "${ROOT_DIR}"
printf '[xt-core-projection] rust xtd root: %s\n' "${RUST_XTD_DIR}"
printf '[xt-core-projection] swift scratch: %s\n' "${SCRATCH_DIR}"

mkdir -p "${FIXTURE_DIR}"
mkdir -p "${SWIFT_CHECK_HOME}" "${SWIFT_CLANG_CACHE}"
rm -rf "${SCRATCH_DIR}"

printf '[xt-core-projection] cargo test\n'
(
  cd "${RUST_XTD_DIR}" &&
    cargo test
)

printf '[xt-core-projection] render deterministic Rust projection fixtures\n'
(
  cd "${RUST_XTD_DIR}" &&
    cargo run --quiet -- projection sidebar --generated-at-ms 0 > "${FIXTURE_DIR}/project_sidebar.json" &&
    cargo run --quiet -- projection settings-diagnostics --generated-at-ms 0 > "${FIXTURE_DIR}/settings_diagnostics.json"
)

grep -q '"protocol":"xt-core-projection.v1"' "${FIXTURE_DIR}/project_sidebar.json"
grep -q '"surface":"project_sidebar"' "${FIXTURE_DIR}/project_sidebar.json"
grep -q '"xtd_owns_authority":false' "${FIXTURE_DIR}/project_sidebar.json"
grep -q '"surface":"settings_diagnostics"' "${FIXTURE_DIR}/settings_diagnostics.json"
grep -q '"hub_remote_log_tail"' "${FIXTURE_DIR}/settings_diagnostics.json"

printf '[xt-core-projection] swift envelope tests\n'
(
  cd "${ROOT_DIR}" &&
    HOME="${SWIFT_CHECK_HOME}" \
    CLANG_MODULE_CACHE_PATH="${SWIFT_CLANG_CACHE}" \
      swift test --disable-sandbox --scratch-path "${SCRATCH_DIR}" --filter 'XTCoreProjectionEnvelopeTests|XTCoreProjectionClientTests'
)

printf '[xt-core-projection] all checks passed\n'
