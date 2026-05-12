# RHM-037 Ops Soak Runner

Status: implemented 2026-05-07

## Decision

Rust Hub has a sustained warm-daemon soak runner for stutter and long-running
ops regression checks. It starts one temporary `xhubd serve` process, keeps it
warm across repeated cycles, samples readiness, memory, skills, policy-store,
and HTTP metrics endpoints, then writes a persisted JSON report.

This is diagnostics only. It does not switch production authority, does not
execute third-party skills, does not grant OS/network/model access, and does
not change XT UI.

## Implemented Command

```bash
bash "tools/ops_soak_runner.command" --cycles 5 --interval-ms 100 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
```

Longer wall-clock soak:

```bash
bash "tools/ops_soak_runner.command" --duration-ms 60000 --interval-ms 500 --timeout-ms 30000
```

Options:

- `--duration-ms <ms>`: wall-clock soak duration. If set without `--cycles`,
  cycles are effectively unbounded until duration expires.
- `--cycles <n>`: maximum readiness cycles, default 10.
- `--interval-ms <ms>`: delay between cycles, default 500.
- `--timeout-ms <ms>`: daemon startup timeout, default 30000.
- `--max-endpoint-ms <ms>`: per-endpoint latency budget, default 2000.
- `--max-cycle-ms <ms>`: per-cycle latency budget, default 5000.
- `--report-path <path>`: JSON report path, default
  `reports/ops_soak_<UTC>.json`.
- `--port <port>`: local temporary HTTP port.

The response and report schema is:

```text
xhub.rust_hub.ops_soak_report.v1
```

## Gate Coverage

The soak runner verifies:

- one warm daemon starts and stays healthy for repeated cycles,
- `/ready` remains ready and immediate repeated calls hit the readiness cache,
- memory readiness/search stays read-only and secret queries are denied,
- memory snapshot cache and skills catalog cache remain enabled,
- skills readiness and durable pin/grant/preflight policy stay ready,
- Rust skill execution authority remains disabled,
- Rust memory writer authority remains disabled,
- HTTP backpressure and HTTP metrics capabilities remain exposed,
- final `/runtime/http-metrics` is captured for route latency, slow request,
  and request-count evidence,
- endpoint and cycle latency stay inside configured budgets,
- static UI compatibility still reports no product UI changes,
- fixture secrets, personal memory text, and `detail_json` are not returned.

## Report Fields

The persisted report includes:

- `cycles_completed`,
- average and max endpoint latency,
- average and max cycle latency,
- total and slow HTTP request counts,
- final sanitized HTTP metrics snapshot,
- readiness/cache verification booleans,
- memory/skills authority-neutral booleans,
- UI compatibility booleans,
- `node_remains_authority=true`,
- `memory_writer_authority_in_rust=false`,
- `skills_execution_authority_in_rust=false`,
- `secret_leak=false`.

## Authority State

| Area | Rust State |
| --- | --- |
| Warm daemon soak diagnostics | Enabled |
| Memory retrieval | Read-only shadow |
| Memory writer authority | Disabled |
| Skill policy gate | Enabled |
| Skill execution | Disabled |
| Third-party code execution | Disabled |
| Cross-network auth gate | Required |
| XT UI ownership | Unchanged |

## Verification

```bash
node --check "tools/ops_soak_runner.js"
bash "tools/ops_soak_runner.command" --cycles 5 --interval-ms 100 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash "tools/ops_readiness_gate.command" --cycles 3 --interval-ms 250 --timeout-ms 30000 --max-endpoint-ms 2000 --max-cycle-ms 5000
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

The runner is copied into packaged `dist/rust-hub-*` bundles and can be run
from the package without source files.
