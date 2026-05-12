# RHM-079 Route Authority Production Cutover Blocker

RHM-079 makes the current provider/model route production cutover boundary
machine-readable.

The Node bridges currently support prep/candidate/observe modes. They do not
yet expose a separate provider/model production authority switch equivalent to
the scheduler authority switch. Therefore provider/model production authority
must remain blocked.

## Command

```bash
bash tools/route_authority_production_cutover_blocker.command
```

The command may run one prep sustained guard cycle, then reports:

- `production_apply_allowed=false`
- `production_cutover_implemented=false`
- `production_switch_contract_version`
- `safe_prep_only`
- concrete blockers before any future apply/rollback implementation

This is non-mutating and keeps provider/model authority, memory writer
authority, and skills execution authority disabled.

RHM-080 tightens the switch detection contract so prep/candidate keys are
reported separately and do not count as provider/model production authority.
