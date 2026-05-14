# RHM-126 Memory Writer and Skills Execution Live Cutover

RHM-126 promotes the Rust memory writer and governed skills execution surfaces
from production-capable to live-cutover capable.

The default remains fail-closed. Live authority requires all memory writer keys:

```bash
XHUB_RUST_MEMORY_WRITER_AUTHORITY=1
XHUB_RUST_MEMORY_WRITE_AUTHORITY=1
XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY=1
```

and all skills execution keys:

```bash
XHUB_RUST_SKILLS_EXECUTION_AUTHORITY=1
XHUB_RUST_SKILLS_PRODUCTION_EXECUTION=1
XHUB_RUST_SKILLS_EXECUTION_PRODUCTION=1
XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY=1
```

The launchd manager now passes those keys into the daemon plist only when they
are present in the process or `launchctl` session environment. Ops, watchdog,
heartbeat, and live stability gates still fail on these authority changes unless
called with:

```bash
--allow-memory-skills-production
```

For live verification after relaunch:

```bash
bash tools/memory_skills_live_smoke.command --http-base-url http://127.0.0.1:50151
bash tools/daemon_ops_gate.command --allow-memory-skills-production --require-memory-skills-production
```

The live smoke writes one governed memory verification entry, verifies it is
retrievable, pins/grants the built-in `rust-authority-healthcheck` skill, runs
the built-in healthcheck execution path, and verifies secret-shaped memory and
skill inputs are denied without returning `detail_json`.
