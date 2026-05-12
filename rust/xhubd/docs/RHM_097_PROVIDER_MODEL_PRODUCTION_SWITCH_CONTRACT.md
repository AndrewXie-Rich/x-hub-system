# RHM-097 Provider/Model Production Switch Contract

## Goal

Start the provider/model production cutover implementation without immediately
changing production authority.

This slice adds explicit production switches to the Node provider/model route
bridges and adds a Rust Hub session apply/rollback tool that manages only those
provider/model production env keys.

## Behavior

The Node bridges now recognize these provider production keys:

- `XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY`

And these model production keys:

- `XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY`

All remain default-off. Prep/candidate env never implies production authority.

`tools/route_authority_production_session.command` supports:

```bash
--status
--apply
--rollback
```

The tool manages only provider/model route production keys. It does not enable
memory writer authority, skills execution authority, XT file IPC production
surface, or UI changes.

## Guarding

`tools/route_authority_production_cutover_blocker.command` now recognizes the
production switch contract and the session apply/rollback tool. It still keeps
`production_apply_allowed=false` until long soak and manual cutover approval
complete.

## Validation

```bash
node src/rust_provider_route_authority_bridge.test.js
node src/rust_model_route_authority_bridge.test.js
node --check tools/route_authority_production_session.js
bash tools/route_authority_production_session.command --self-test
bash tools/route_authority_production_cutover_blocker.command --skip-prep-sustained
```
