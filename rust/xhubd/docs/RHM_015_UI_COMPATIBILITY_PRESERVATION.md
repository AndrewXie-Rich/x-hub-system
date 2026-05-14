# RHM-015 UI Compatibility Preservation Contract

Status: active contract, created 2026-05-06

## Decision

Rust Hub is a backend rewrite, not a product UI replacement. The existing XT
and Hub user-facing UI must remain the product surface. The Rust browser page at
`GET /` is only a local diagnostic page for daemon readiness and bridge
inspection.

Any cutover that changes XT layout, labels, navigation, picker behavior,
settings workflow, account management workflow, or user-visible model state
copy must be treated as a separate product/UI change and must not be bundled
into the Rust backend migration.

## Non-Negotiable Rules

1. **Default UI stays XT.** Users keep opening and operating the existing Swift
   XT app and existing Hub setup/settings flows.
2. **Rust browser page is diagnostics only.** It must not become the place where
   users manage accounts, skills, models, grants, projects, or supervisor
   settings.
3. **Rust bridges are default-off until gated.** Rust data can be consumed by XT
   only through explicit opt-in environment variables, defaults keys, or
   documented bridge flags.
4. **Fallback must preserve the current UI path.** If Rust daemon is down,
   schema is invalid, readiness is false, or secret material is detected, XT
   must fall back to the existing Node/Swift path rather than showing an
   incomplete Rust-only UI.
5. **No secret expansion into UI.** XT and browser diagnostics must not read or
   render provider keys, refresh tokens, account passwords, raw auth files, or
   imported provider secrets.
6. **Rust may improve truth, not surprise users.** Rust blocker reason codes may
   improve accuracy for quota/scope/runtime/capability states, but existing
   locations and interaction patterns remain stable.
7. **Authority changes require separate gates.** Inventory display, route
   decision preview, provider route authority, scheduler authority, skill
   execution, and memory writer authority are separate cutovers.

## Product Surfaces That Must Stay Stable

| Surface | Files | Preservation Requirement |
| --- | --- | --- |
| Model settings | `x-terminal/Sources/UI/ModelSettingsView.swift` | Keep current model list, truth cards, provider/local grouping, load states, and refresh flow. |
| Model selector | `x-terminal/Sources/UI/ModelSelectorView.swift` | Keep picker location, selection behavior, visible unavailable models, and fallback choices. |
| Project settings | `x-terminal/Sources/UI/ProjectSettingsView.swift` | Keep project model policy controls and governance copy placement. |
| Supervisor settings | `x-terminal/Sources/UI/SupervisorSettingsView.swift` | Keep supervisor model picker, model inventory truth, and capability state presentation. |
| Dock input / chat model picker | `x-terminal/Sources/UI/MessageTimeline/DockInputView.swift`, `x-terminal/Sources/UI/TerminalChatView.swift` | Keep user model choice and active request lifecycle unchanged. |
| Hub setup wizard | `x-terminal/Sources/UI/HubSetupWizardView.swift` | Keep onboarding path and provider/account setup flow unchanged until explicit product work. |
| Settings guidance | `x-terminal/Sources/UI/XTSettingsGuidancePresentation.swift` | Keep current guidance hierarchy while allowing Rust truth to feed status text. |
| Supervisor persona center | `x-terminal/Sources/UI/Supervisor/SupervisorPersonaCenterView.swift` | Keep available model source shape and persona model assignments stable. |
| Rust diagnostic page | `rust hub/crates/xhubd/src/main.rs` `GET /` | Keep as diagnostic/readiness page only; no product settings ownership. |

## Allowed Rust Data Replacements

| Data | Rust Source | Allowed UI Use | Cutover State |
| --- | --- | --- | --- |
| Model inventory | `GET /model/inventory`, `xhubd model inventory` | Feed visible model inventory and truth cards. | Default-off live bridge exists. |
| Model inventory readiness | `GET /model/readiness` | Gate whether Rust inventory can be trusted. | Evidence-only, default-off. |
| Model route decision | `GET/POST /model/route`, `xhubd model route` | Preview route decisions and prepare authority cutover. | Read-only prep only. |
| Provider route decision | `GET /provider/route`, provider route bridge | Audit/observe selected provider account parity. | Default-off authority prep exists. |
| Scheduler status | `GET /scheduler/status` | Feed scheduler status panels without changing queue UI. | Default-off read bridge exists. |
| Scheduler authority | `POST /scheduler/claim` and lifecycle endpoints | Only after readiness gates and fallback behavior pass. | Separate authority cutover. |
| Skills catalog/gate | Future Rust skill APIs | Display and policy gates only until execution authority is approved. | Not product authority yet. |
| Memory read/write | Future Rust memory APIs | Read path can be previewed; writer authority must remain explicit. | Not product writer authority yet. |

## Disallowed Bundled Changes

Do not bundle these with Rust backend migration tasks:

- Replacing XT with a browser app.
- Moving model/account/skill management into the Rust diagnostic page.
- Renaming visible states without a UX copy review.
- Hiding unavailable paid or local models that the old UI showed.
- Collapsing quota, scope, runtime, and capability blockers into a generic
  unavailable state.
- Changing default selected model behavior without route parity evidence.
- Making Rust route or scheduler authority default-on.
- Adding UI text that explains internal bridge flags or daemon mechanics to
  normal users.

## Required Failure Behavior

XT must keep the old UI path and show stable user-facing states when:

1. Rust daemon is not running.
2. Rust HTTP request times out.
3. Rust returns a non-2xx status.
4. Rust response schema is not expected.
5. Rust response contains possible secret material.
6. Rust readiness is false.
7. Rust inventory is empty while Node/Swift inventory is not empty.
8. Rust route decision differs from Node/XT selected model during a prep phase.
9. Local runtime status is stale or missing.
10. Provider account quota/scope/auth state is blocked.

## Implementation Checklist For Every Rust UI Bridge

Before coding:

- [ ] Identify the exact existing UI files touched.
- [ ] Identify the old data source and fallback path.
- [ ] Identify the Rust endpoint or snapshot schema.
- [ ] Confirm the Rust bridge is default-off.
- [ ] Confirm no user-visible copy/layout change is required.
- [ ] Add or update a field contract doc if XT consumes new Rust fields.

While coding:

- [ ] Keep public Swift view structure and navigation stable.
- [ ] Add a small bridge object instead of putting HTTP calls directly in view
  bodies.
- [ ] Reject invalid schema and secret material before projection.
- [ ] Preserve unavailable models and blocker truth.
- [ ] Keep fallback behavior local to the manager/projection layer.
- [ ] Do not read provider auth files from XT.

Before merge:

- [ ] Add fixture coverage for ready, quota blocked, missing scope, runtime
  missing, capability mismatch, empty Rust response, invalid schema, HTTP
  failure, and secret detection.
- [ ] Run focused Swift tests.
- [ ] Run Rust endpoint smoke for the matching Rust API.
- [ ] Confirm screenshots or manual inspection for touched UI surfaces if view
  layout changed.
- [ ] Update this plan/status with the exact command outputs.

## Test Gates

Rust package UI preservation gate:

```bash
bash "tools/ui_compatibility_no_product_ui_change_gate.command"
```

This static gate fails if the Rust Hub package embeds Swift UI source, if the
Rust browser root page starts using product-management wording, or if the
backend/readiness docs no longer state the default-off and writer-authority
boundaries.

Focused XT tests:

```bash
swift test --filter 'XTModelInventoryTruthPresentationTests|XTVisibleHubModelInventoryTests|XTRustModelInventoryProjectionTests|XTRustModelInventoryLiveBridgeTests|HubModelManagerFetchTests'
```

Rust model inventory gates:

```bash
bash "tools/model_inventory_shadow_compare_runner.command" --runs 3 --min-compare-reports 3 --expect-ready --expect-zero-mismatch
bash "tools/model_inventory_shadow_compare_runner.command" --use-existing-runtime --runtime-base-dir /path/to/runtime_base_dir --runs 10 --min-compare-reports 10 --expect-ready --expect-zero-mismatch
```

Rust model route prep gate:

```bash
bash "tools/model_route_http_smoke.command" --timeout-ms 30000
```

Rust daemon diagnostics:

```bash
bash "tools/xhubd_daemon.command" start --profile local
bash "tools/xhubd_daemon.command" ready --profile local
curl -fsS -I http://127.0.0.1:50151/
curl -fsS -I http://127.0.0.1:50151/ready
```

## Route Authority Prep Requirements

The next Node/XT model route authority prep bridge may be implemented only if:

1. RHM-012 fixture inventory evidence is ready.
2. RHM-013 existing-runtime evidence is ready.
3. RHM-014 `/model/route` HTTP smoke passes.
4. This UI preservation contract is referenced in the work claim.
5. The bridge is default-off and emits an audit/preview result before it can
   change selected model authority.
6. A mismatch falls back to current Node/XT selection.

## Definition Of Done

For each Rust backend cutover that touches UI data:

- Existing XT UI surfaces still compile and appear in the same place.
- Existing fallback path still works when Rust is unavailable.
- Rust truth can be enabled independently.
- Secret material is rejected before projection.
- Machine-readable reason codes are preserved through presentation.
- Focused Swift tests and Rust evidence runners pass.
- The Rust browser page remains diagnostic-only.
