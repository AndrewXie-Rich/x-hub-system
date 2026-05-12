# RHM-070 Scheduler Production Authority Apply

RHM-070 adds an explicit apply/rollback command for scheduler production
authority. It targets the Dock Agent LaunchAgent environment because the Hub
gRPC Node process inherits its environment from the Hub/Dock Agent process.

## Scope

- Enables scheduler authority only.
- Does not enable provider route authority.
- Does not enable model route authority.
- Does not enable Rust memory writer authority.
- Does not enable Rust skills execution authority.
- Does not change SwiftUI product UI files.

## Commands

Inspect:

```bash
bash tools/scheduler_production_authority_apply.command --status
```

Apply environment to the Dock Agent LaunchAgent:

```bash
bash tools/scheduler_production_authority_apply.command --apply
```

Apply and restart Dock Agent so Node Hub inherits the environment:

```bash
bash tools/scheduler_production_authority_apply.command --apply --restart-dock-agent
```

Rollback:

```bash
bash tools/scheduler_production_authority_apply.command --rollback --restart-dock-agent
```

## Safety

The command stores:

- a plist backup under `reports/scheduler_production_authority/`,
- previous values for every managed env key,
- absent-key state so rollback removes keys that did not exist before apply.

The output uses schema `xhub.scheduler_production_authority_apply.v1` and
reports `secret_leak=false`.
