# RHM-130 Production-Aware Active Root Upgrade

RHM-130 hardens package-root upgrades after provider/model routing has moved to
Rust production authority.

## Problem

The earlier active-root upgrade tools always emitted and executed route prep
apply/install commands. That was correct before provider/model cutover, but
after cutover it could overwrite production route session state with prep
fallback settings during a package update.

## Change

`active_root_upgrade_plan.command` and `active_root_upgrade_apply.command` now
detect provider/model production authority from launchctl and the running X-Hub
Node process. When production authority is detected:

- scheduler/root apply and persistent LaunchAgent install still run;
- `route_authority_prep_session` apply/install are skipped;
- scheduler validation forwards memory/skills production allowance to
  `daemon_ops_gate.command`;
- route validation uses `route_authority_production_runtime_guard.command`;
- memory/skills production is required by validation when those keys are
  already active;
- reports include authority detection keys and `route_prep_apply_skipped`.

`--force-route-prep` is available only for legacy prep sessions where
intentionally returning to prep is acceptable.

## Verification

Source validation:

```bash
node --check tools/active_root_upgrade_plan.js
node --check tools/active_root_upgrade_apply.js
bash tools/active_root_upgrade_plan.command --self-test
bash tools/active_root_upgrade_apply.command --self-test
```

Live dry-run validation against the next package root showed:

- `route_authority_mode=production`
- `provider_model_production_authority_detected=true`
- `memory_skills_production_authority_detected=true`
- `route_prep_apply_skipped=true`
- no `route_authority_prep_session` apply step
- validation switches to `route_authority_production_runtime_guard.command`
- scheduler guard passes with `--require-memory-skills-production`

This change does not modify SwiftUI product UI and does not newly enable any
production authority.
