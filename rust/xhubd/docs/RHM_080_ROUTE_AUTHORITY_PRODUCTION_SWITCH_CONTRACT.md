# RHM-080 Route Authority Production Switch Contract

RHM-080 hardens the provider/model route production cutover blocker by making
the switch detector explicit.

Prep and candidate keys are not production authority. They are allowed to
exist in Node bridge source and in launchctl/session environments while Rust
collects readiness evidence:

- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PREP`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CANDIDATE`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_OBSERVE`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE`

Only the explicit production contract keys count as a future provider/model
production switch:

- `XHUB_RUST_PROVIDER_ROUTE_PRODUCTION_AUTHORITY`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_PRODUCTION`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_CUTOVER`
- `XHUB_RUST_PROVIDER_ROUTE_AUTHORITY_APPLY`
- `XHUB_RUST_MODEL_ROUTE_PRODUCTION_AUTHORITY`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PRODUCTION`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_CUTOVER`
- `XHUB_RUST_MODEL_ROUTE_AUTHORITY_APPLY`

The blocker report now includes:

- `production_switch_contract_version`
- expected provider/model production key lists
- matched prep/candidate key lists
- matched production key lists
- `safe_prep_only`

This remains non-mutating. It does not enable provider/model production
authority, memory writer authority, skills execution authority, or any SwiftUI
product UI change.
