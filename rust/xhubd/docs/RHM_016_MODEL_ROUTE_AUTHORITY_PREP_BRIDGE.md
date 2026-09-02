# RHM-016 Model Route Authority Prep Bridge

Status: implemented 2026-05-06

## Goal

Wire Node Hub to Rust model-route decisions as a default-off authority prep
bridge while preserving the existing XT product UI and Node execution behavior.

This slice is evidence-only:

- It does not change the model selected by XT.
- It does not change Node `HubAI.Generate` execution routing.
- It does not read or serialize provider auth files or provider secrets.
- It records Rust route-candidate evidence for later cutover decisions.

## Node Bridge

Added Node module:

```text
x-hub-system/x-hub/grpc-server/hub_grpc_server/src/rust_model_route_authority_bridge.js
```

Primary behavior:

- Default-off unless `XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP=1` or
  `XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE=1`.
- HTTP-first when `XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP=1`.
- Uses Rust `GET /model/readiness` as the fail-closed readiness gate by
  default.
- Uses Rust `GET /model/route` or CLI `xhubd model route` for route decisions.
- Compares Rust selected model/route-kind against Node selected
  model/route-kind.
- Falls back to Node behavior on Rust errors by default.
- Rejects route responses containing secret-shaped keys or values.

Important env flags:

```text
XHUB_RUST_MODEL_ROUTE_AUTHORITY_PREP
XHUB_RUST_MODEL_ROUTE_AUTHORITY_CANDIDATE
XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP
XHUB_RUST_MODEL_ROUTE_AUTHORITY_HTTP_BASE_URL
XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_READY
XHUB_RUST_MODEL_ROUTE_AUTHORITY_REQUIRE_NODE_MATCH
XHUB_RUST_MODEL_ROUTE_AUTHORITY_FALLBACK_ON_ERROR
XHUB_RUST_MODEL_ROUTE_AUTHORITY_MIN_COMPARE_REPORTS
XHUB_RUST_MODEL_ROUTE_AUTHORITY_MAX_MISMATCHES
```

## Generate Hook

Node `HubAI.Generate` now accepts an injected `modelRouteAuthorityBridge`.

When candidate mode is enabled, Generate sends this non-secret route preview:

```json
{
  "taskType": "text_generate",
  "modelId": "<node-selected-model-id>",
  "requiredCapabilities": ["text.generate"],
  "privacyMode": "remote-only | local-only",
  "costPreference": "balanced",
  "nodeModelId": "<node-selected-model-id>",
  "nodeRouteKind": "remote | local"
}
```

The hook appends:

```text
ai.generate.model_route_candidate
```

The audit payload schema is:

```text
xhub.rust_model_route_candidate.audit.v1
```

The hook is deliberately non-blocking. Candidate success, mismatch, Rust
unreadiness, daemon failure, timeout, or secret-response rejection must not alter
the Bridge payload, local runtime request, `done.actual_model_id`, or XT UI
state.

## UI Compatibility

This slice is bound by `RHM_015_UI_COMPATIBILITY_PRESERVATION.md`:

- XT remains the product UI.
- Rust browser `/` remains diagnostics only.
- Existing model settings, selector, chat composer, supervisor, and setup
  surfaces stay unchanged.
- Rust candidate evidence can be surfaced later only through the existing XT
  diagnostics/troubleshooting patterns.

## Validation

Node tests:

```bash
node src/rust_model_route_authority_bridge.test.js
node src/rust_provider_route_authority_generate_hook.test.js
node src/rust_provider_route_shadow_compare_service_hook.test.js
node src/rust_provider_route_authority_bridge.test.js
node src/model_route_resolution.test.js
node --check src/services.js
node --check src/rust_model_route_authority_bridge.js
```

Observed result 2026-05-06:

- default-off bridge returns `rust_model_route_authority_disabled`
- HTTP readiness and route path selects `gpt-5.5`
- not-ready readiness fails closed
- Rust/Node model mismatch is reported without changing Node route
- secret material in Rust route response is rejected
- paid Generate path records provider and model route candidate audits
- Bridge AI payload remains unchanged
