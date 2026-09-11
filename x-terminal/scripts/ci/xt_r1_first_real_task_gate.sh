#!/usr/bin/env bash
set -euo pipefail

XT_R1_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${XT_R1_ROOT}/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "${XT_R1_ROOT}/.." "${XT_R1_ROOT}"
exec node "${XT_R1_ROOT}/scripts/r1_first_real_task.mjs" "$@"
