# RHM-081 Active Root Upgrade Plan

RHM-081 adds a non-mutating package/root alignment plan for smoother Rust Hub
updates.

Packaged tools default to their own dist root. A running X-Hub Node process and
launchctl session may still point at the previous source or package root via
`XHUB_RUST_HUB_ROOT`. That is expected during a staged update, but it can make
guards report a root mismatch.

## Command

```bash
bash tools/active_root_upgrade_plan.command
```

The report includes:

- current launchctl `XHUB_RUST_HUB_ROOT`
- running X-Hub Node process root
- target root validity
- whether the active root is aligned with the target root
- provider/model and memory/skills production authority detection
- apply commands for scheduler authority and, only when safe, provider/model
  prep env
- validation commands
- rollback commands back to the current active root

The command does not apply env, relaunch X-Hub, change provider/model
production authority, change memory writer authority, execute skills, or touch
SwiftUI product files.

After provider/model routing has production authority, the plan intentionally
skips `route_authority_prep_session` apply/install commands. Validation uses
`route_authority_production_runtime_guard.command` instead of the prep guard,
and it adds `--require-memory-skills-production` when memory writer / skills
execution production keys are already active.
