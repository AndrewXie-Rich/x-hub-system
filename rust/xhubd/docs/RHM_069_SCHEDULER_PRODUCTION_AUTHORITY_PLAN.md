# RHM-069 Scheduler Production Authority Plan

RHM-069 adds a production-authority cutover plan for the Rust scheduler bridge.
It does not mutate Node Hub, launchd, XT, memory, provider routing, model
routing, or skill execution by default.

## Scope

- Target authority: paid AI scheduler claims through Rust `xhubd`.
- Production switch: `XHUB_RUST_SCHEDULER_AUTHORITY=1` in the Node Hub process
  environment, with readiness-gated HTTP-first Rust daemon access.
- UI behavior: unchanged.
- Provider/model route authority: unchanged.
- Memory writer authority: unchanged.
- Skill execution authority: unchanged.
- XT file-IPC authority: unchanged.

## Command

```bash
bash tools/scheduler_production_authority_plan.command
```

The command emits JSON using schema
`xhub.scheduler_production_authority_plan.v1`. The output includes:

- `env_to_set` and shell `export` commands for the Node Hub production process.
- `rollback_unset_commands`.
- validation commands that must pass before applying the env change.
- blocked authorities that must remain fail-closed.
- `apply_performed=false`.
- `secret_leak=false`.

Run the authority gates before applying the production env:

```bash
bash tools/scheduler_production_authority_plan.command --run-gates --expect-ready
```

## Apply Boundary

This slice intentionally does not edit LaunchAgents or restart Node Hub. That
keeps the production mutation explicit and auditable. After `--run-gates` emits
`ready_for_scheduler_authority_apply=true`, the next slice can add an explicit
apply command that writes the Node Hub environment and performs a rollbackable
restart.

## Rollback

Rollback is env-based:

```bash
unset XHUB_RUST_SCHEDULER_AUTHORITY
unset XHUB_RUST_SCHEDULER_AUTHORITY_REQUIRE_READY
unset XHUB_RUST_SCHEDULER_AUTHORITY_HTTP
unset XHUB_RUST_SCHEDULER_AUTHORITY_HTTP_BASE_URL
```

The full rollback list is included in command output.
