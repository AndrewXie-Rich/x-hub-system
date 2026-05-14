# RHM-082 Active Root Upgrade Apply

RHM-082 adds a dry-run-by-default active-root upgrade orchestrator.

## Command

```bash
bash tools/active_root_upgrade_apply.command --target-root "/path/to/rust-hub-dist"
```

Default mode is dry-run. It prints the scheduler authority, route authority,
validation, and optional X-Hub relaunch steps without mutating launchctl,
LaunchAgents, or the running app.

To apply the session and persistent LaunchAgent root switch:

```bash
bash tools/active_root_upgrade_apply.command --target-root "/path/to/rust-hub-dist" --apply
```

To make the running Node process inherit the target root, the operator must
explicitly add:

```bash
--relaunch-xhub
```

Post-apply guards are also explicit:

```bash
--validate
```

After `--relaunch-xhub`, the tool waits for the X-Hub Node process to appear
with the target `XHUB_RUST_HUB_ROOT` before running validation. The wait can be
tuned with:

```bash
--relaunch-wait-ms 30000 --relaunch-poll-ms 1000
```

If the first `open` lands while macOS is still closing the previous app
instance, the tool retries one more `open` and waits again. Tune that second
wait with:

```bash
--relaunch-retry-wait-ms 15000
```

When provider/model production authority is already active, this tool skips
`route_authority_prep_session` apply/install so a package-root update cannot
overwrite production fallback or cutover keys. In that mode `--validate` runs
`route_authority_production_runtime_guard.command`, requiring memory/skills
production if those keys are already active. `--force-route-prep` exists only
for legacy prep sessions where intentionally returning to prep is acceptable.

This tool never newly enables provider/model production authority, memory
writer authority, or skills execution authority. It preserves the authority
state that is already active while moving the active package root. It does not
touch SwiftUI product files.
