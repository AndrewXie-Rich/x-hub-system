# RHM-074 Route Authority Cutover Guard

RHM-074 combines the provider route authority plan, selected-model route
authority plan, scheduler production guard, daemon health, and UI compatibility
into one readiness gate.

The guard is non-mutating. It does not enable provider route authority, model
route authority, memory writer authority, or skills execution authority.

## Command

```bash
bash tools/route_authority_cutover_guard.command
```

The result is ready only when:

- scheduler production authority is still effective and persistent
- provider route authority dry-run plan is ready for a manual prep trial
- selected-model route authority dry-run plan is ready for a manual prep trial
- neither plan attempts a production authority change
- UI compatibility remains clean

Reports are written under `reports/route_authority_cutover_guard_*.json`.
