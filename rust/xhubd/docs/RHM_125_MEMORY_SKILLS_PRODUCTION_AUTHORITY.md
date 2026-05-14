# RHM-125 Memory And Skills Production Authority

## Status

Source-verified on 2026-05-13.

## Purpose

Move the remaining memory writer and skills execution authority into Rust Hub
behind explicit production gates. The default runtime remains fail-closed, but
`xhubd` now exposes production-capable surfaces for:

- canonical memory writes through `POST /memory/write`;
- governed skill execution through `POST /skills/execute`.

## Memory Writer

Rust memory writes require all of these gates:

```text
XHUB_RUST_MEMORY_WRITER_AUTHORITY=1
XHUB_RUST_MEMORY_WRITE_AUTHORITY=1
XHUB_RUST_MEMORY_PRODUCTION_AUTHORITY=1
```

When enabled, the writer stores one JSON memory entry per file under
`<memory_dir>/writes/`. The response returns only refs, summary, paths, and
bounded metadata. Raw detail JSON is not returned. Secret-shaped input is
denied before write.

## Skills Execution

Rust skills execution requires all of these gates:

```text
XHUB_RUST_SKILLS_EXECUTION_AUTHORITY=1
XHUB_RUST_SKILLS_PRODUCTION_EXECUTION=1
XHUB_RUST_SKILLS_EXECUTION_PRODUCTION=1
XHUB_RUST_SKILLS_RUNNER_PRODUCTION_AUTHORITY=1
```

Execution still requires durable pin/grant policy and preflight audit. The
first production surface supports:

- built-in `healthcheck` execution;
- restricted manifest `process` execution with relative entrypoints only;
- optional process runners only when listed in
  `XHUB_RUST_SKILLS_ALLOWED_RUNNERS`.

The runner uses no shell string interpolation and clears inherited environment
variables before launching process skills.

## Verification

```bash
cargo test -p xhub-memory -p xhub-skills -p xhubd
bash tools/memory_skills_production_smoke.command --timeout-ms 30000
```

Verified:

- memory write succeeds only under explicit authority;
- secret-shaped memory write is denied;
- written memory is retrievable;
- skills execution succeeds only after pin/grant preflight;
- secret-shaped skill input is denied;
- no `detail_json`, API key, or secret value is returned;
- temporary `target/debug/xhubd` and `target/release/xhubd` processes are not
  left running.
