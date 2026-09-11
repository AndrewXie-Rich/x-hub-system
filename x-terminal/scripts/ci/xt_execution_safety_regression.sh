#!/usr/bin/env bash
set -euo pipefail

XT_EXECUTION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${XT_EXECUTION_ROOT}/scripts/lib/canonical_root_guard.sh"
xterminal_assert_canonical_root "${XT_EXECUTION_ROOT}/.." "${XT_EXECUTION_ROOT}"
XT_EXECUTION_WORK="$(mktemp -d "${TMPDIR:-/tmp}/xt-execution-check.XXXXXX")"

xcrun swiftc -parse-as-library -D XT_EXECUTION_REGRESSION_MAIN \
  -module-cache-path "${XT_EXECUTION_WORK}/module-cache" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/ProcessCapture.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/ProcessOutputMonitor.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/ShellSession.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/LocalExecutionPolicy.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/ToolSandboxPolicy.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/XTManagedProcessLog.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/XTManagedProcessPaths.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/XTManagedProcessStore.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Tools/PathGuard.swift" \
  "${XT_EXECUTION_ROOT}/Sources/XTStoreWriteSupport.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Supervisor/SupervisorStoreWriteSupport.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Voice/SupervisorVoiceTimingPolicy.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Models/SandboxProvider.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Models/VirtualPathMapper.swift" \
  "${XT_EXECUTION_ROOT}/Sources/Models/LocalSandboxProvider.swift" \
  "${XT_EXECUTION_ROOT}/Tests/ExecutionSafetyRegression.swift" \
  "${XT_EXECUTION_ROOT}/Tests/ManagedProcessSafetyRegression.swift" \
  -o "${XT_EXECUTION_WORK}/execution-safety-regression"

"${XT_EXECUTION_WORK}/execution-safety-regression"
