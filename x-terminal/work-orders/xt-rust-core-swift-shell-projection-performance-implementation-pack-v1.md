# XT Rust Core + Swift Shell Projection Performance Implementation Pack v1

- status: active
- priority: P0/P1 bridge
- createdAt: 2026-05-15
- scope: `rust/rust xt/` only
- product thesis: one XT product = Rust core + Swift shell
- primary goal: remove structural SwiftUI jank without changing the current user-facing UI

## Implementation Progress

- 2026-05-16: Added Swift compatibility projection stores for Project Sidebar and
  Settings/Supervisor surfaces so the current UI can render from narrow snapshots
  while preserving layout and copy.
- 2026-05-16: Added `xtd projection` fixture envelopes plus Swift
  `XTCoreProjectionEnvelope` decoding/tests. This establishes the Rust-core to
  Swift-shell projection contract without moving Hub-owned authority into XT.
- 2026-05-17: Added `XTCoreProjectionClient` coverage and packaged `xtd` into
  `X-Terminal.app/Contents/Resources/xtd` via the XT build scripts. The app bundle
  now carries the Rust sidecar while Swift still treats it as a projection source,
  not an authority source.
- 2026-05-17: Hardened Hub pairing tests to assert parsed `connection.json`
  fields instead of JSON pretty-print whitespace. This keeps the Hub/XT pairing
  gate focused on contract fields rather than serializer formatting.
- Contract gate: `swift-xterminal/scripts/ci/xt_core_projection_contract_gate.sh`

Validation:

- `cargo test` in `rust-xtd`
- `swift test --scratch-path /private/tmp/xt-core-projection-test-build --filter XTCoreProjectionEnvelopeTests`
- `bash swift-xterminal/scripts/ci/xt_core_projection_contract_gate.sh`
- `./commands/xt_smooth_guard.command`
- `XTERMINAL_RELEASE_DISABLE_WMO=1 ./commands/build_xt.command`
- `build/X-Terminal.app/Contents/Resources/xtd projection sidebar --generated-at-ms 0`
- `build/X-Terminal.app/Contents/Resources/xtd projection settings-diagnostics --generated-at-ms 0`
- `swift test --disable-sandbox --scratch-path /private/tmp/xt-core-projection-contract-build --filter HubPairingCoordinatorTests`
- `swift test --disable-sandbox --scratch-path /private/tmp/xt-core-projection-contract-build --filter AXSkillsCompatibilityTests`
- `swift test --disable-sandbox --scratch-path /private/tmp/xt-core-projection-contract-build --filter 'XTHeartbeatMemoryProjectionStoreTests|HubModelManagerFetchTests|ModelSettingsRouteTruthPresentationTests|RustHubReadinessPresentationTests'`

## Executive Summary

XT should be maintained as one product, not as separate "Swift XT" and "Rust XT" products.

The target architecture is:

```text
XT = Rust core + Swift shell

Rust core:
  owns decisions, state machines, strategy, aggregation, diagnostics, routing truth,
  projection shaping, refresh scheduling, and IPC-facing interfaces.

Swift shell:
  owns native macOS presentation, windows, menus, controls, accessibility,
  text input, system permission affordances, and command dispatch.
```

This work order does not ask anyone to move UI into Rust. It asks the team to move
expensive judgement, state derivation, policy, diagnostics, log shaping, and refresh
coordination out of SwiftUI view bodies and broad `ObservableObject` surfaces.

The desired end state is that Swift renders small, stable, screen-specific projection
snapshots produced by a Rust-backed core pipeline.

## User-Facing Non-Negotiable

The current UI must remain recognizably the same.

Do not use this work order as permission to redesign XT. The first successful delivery
should feel like the same app, only smoother.

Required UI preservation rules:

- Keep the existing primary surfaces: Work, Supervisor, Review, Control.
- Keep the existing sidebar navigation layout and labels.
- Keep Settings, Project Settings, Model Settings, Supervisor Settings, and Control
  Center in their current locations.
- Keep current cards, pills, section names, buttons, warnings, and approval surfaces
  unless a copy change is explicitly required by a migrated projection.
- Keep existing user workflows:
  - select project from sidebar
  - open project settings
  - open AI model settings
  - view diagnostics
  - approve pending tools/grants
  - inspect route truth
  - continue project work in the chat timeline
- Avoid layout churn while migrating data sources. A Swift view should be able to
  swap from Swift-derived data to Rust-derived projection without visual redesign.

## Problem Statement

Current XT performance issues are structural, not only local SwiftUI mistakes.

Recent tactical fixes reduced visible jank by:

- shortening retained inactive surface lifetimes
- avoiding full hidden project sidebar rendering
- changing long scroll containers from `VStack` to `LazyVStack`
- truncating large diagnostics logs
- coalescing model refreshes

Those changes help, but they do not solve the root problem:

Swift still owns too much product logic and derives too many UI states directly in
view trees, `ObservableObject` snapshots, and broad AppModel pathways.

The result is that common UI actions can trigger excessive main-thread work:

- Sidebar switching can construct heavy project rows, governance summaries, and
  selected-project supplemental metadata.
- Settings scrolling can re-layout large diagnostics strings and broad status surfaces.
- Model and settings surfaces can trigger duplicate refreshes.
- Broad `EnvironmentObject` changes can invalidate too much UI.
- SwiftUI `body` code can call helpers that perform non-trivial aggregation.
- AppModel acts as global fact store, UI projection source, and side-effect hub at
  the same time.

## Target Architecture

### New Boundary

Introduce an explicit projection boundary:

```text
Swift user action
  -> XT command
  -> Rust core reducer / scheduler / aggregator
  -> screen-specific projection snapshot or patch
  -> Swift projection store
  -> SwiftUI render only
```

Swift views should not assemble governance truth, route truth, model truth, doctor
truth, memory truth, or long diagnostics detail from raw stores during `body`.

### Projection Rules

Every Rust-backed UI projection must be:

- small: only data needed by one surface
- stable: deterministic and Equatable-friendly
- segmented: sidebar, settings, model route, approvals, diagnostics, and project
  details must update independently
- capped: logs and long text must be summarized, tailed, or paginated before reaching
  SwiftUI
- versioned: include `revision`, `generatedAtMs`, and a `source`/`freshness` hint
- command-friendly: every button/action maps to an explicit command id or action enum
- testable: projection builders must have unit tests independent of SwiftUI

## Current Hot Spots To Migrate First

### 1. Project Sidebar Projection

Current Swift surface:

- `swift-xterminal/Sources/UI/ProjectSidebarView.swift`
- `swift-xterminal/Sources/Project/XTProjectListStore.swift`
- related helpers in `AppModel`, `AXProjectRegistry`, governance presentation, and
  session summary presentation

Problem:

Project rows can ask Swift/AppModel to derive governance and session summary data.
Even with `.equatable()`, the selected row can still be expensive and broad store
updates can invalidate the whole sidebar.

Target projection:

```swift
struct XTCoreProjectSidebarProjection: Equatable, Codable {
    var revision: UInt64
    var selectedProjectId: String?
    var projectCountText: String
    var rows: [XTCoreProjectSidebarRowProjection]
}

struct XTCoreProjectSidebarRowProjection: Equatable, Codable, Identifiable {
    var id: String
    var displayName: String
    var rootPath: String
    var isSelected: Bool
    var statusDigest: String?
    var resumeBadgeText: String?
    var resumeHelpText: String?
    var executionTierToken: String?
    var executionTierLabel: String?
    var executionTierColorToken: String?
    var supervisorTierToken: String?
    var supervisorTierLabel: String?
    var supervisorTierColorToken: String?
}
```

Swift keeps the same row layout. It stops calling:

- `appModel.resolvedProjectGovernance(for:)`
- `appModel.sessionSummaryPresentation(projectId:)`
- broad governance derivation helpers from row `body`

Acceptance:

- Switching away from Work does not construct a hidden full project `List`.
- Sidebar row body renders from row projection only.
- Project selection still works through existing command path.
- Existing context menu actions still work.
- UI text and row shape remain visually the same.

### 2. Settings Diagnostics Projection

Current Swift surface:

- `swift-xterminal/Sources/UI/SettingsView.swift`
- `swift-xterminal/Sources/UI/XTUnifiedDoctor.swift`
- `swift-xterminal/Sources/UI/XHubDoctorOutput.swift`
- `AXRouteRepairLogStore`
- `HubProviderKeysClient`
- runtime snapshots and route truth helpers

Problem:

Settings can receive large logs and assemble multiple diagnostic lines in Swift.
Large text and repeated derived status lines make scrolling stutter.

Target projection:

```swift
struct XTCoreSettingsDiagnosticsProjection: Equatable, Codable {
    var revision: UInt64
    var generatedAtMs: Int64
    var connectionStateLabel: String
    var connectionTone: XTCoreTone
    var officialSkillsSummary: XTCoreStatusLine?
    var doctorSummary: XTCoreDoctorSummaryProjection
    var diagnosticsLines: [String]
    var routeRepairSummary: XTCoreRouteRepairSummaryProjection?
    var routeRepairRecentLines: [String]
    var hubRemoteLogTail: XTCoreLogTailProjection
}

struct XTCoreLogTailProjection: Equatable, Codable {
    var title: String
    var text: String
    var truncated: Bool
    var totalBytes: Int
    var displayedBytes: Int
    var fullLogPath: String?
}
```

Rust/core must cap log text before Swift sees it.

Acceptance:

- Settings Diagnostics section visually matches current layout.
- No full remote log string is stored in Swift UI state.
- `hubRemoteLogTail.text` is bounded by a product constant.
- Route repair lines are capped before render.
- Existing "open report", "run self-check", and "rerun repair" actions remain.

### 3. Hub Model Inventory And Route Truth Projection

Current Swift surface:

- `swift-xterminal/Sources/LLM/HubModelManager.swift`
- `swift-xterminal/Sources/UI/ModelSettingsView.swift`
- `swift-xterminal/Sources/UI/SettingsView.swift`
- `swift-xterminal/Sources/UI/SupervisorSettingsView.swift`
- `swift-xterminal/Sources/UI/MessageTimeline/DockInputView.swift`

Problem:

Multiple surfaces can call `fetchModels()`. Coalescing in Swift helps, but the real
owner should be the core scheduler. Model inventory and route truth are product state,
not view lifecycle side effects.

Target projection:

```swift
struct XTCoreModelRouteProjection: Equatable, Codable {
    var revision: UInt64
    var generatedAtMs: Int64
    var hubInteractive: Bool
    var inventorySummary: XTCoreModelInventorySummary
    var roleRoutes: [XTCoreRoleRouteProjection]
    var selectedRoleDetail: XTCoreRoleRouteDetailProjection?
    var providerKeySummary: XTCoreStatusLine?
    var rustHubReadiness: XTCoreStatusLine
    var diagnostics: XTCoreStatusLine?
}
```

The Rust/core scheduler owns:

- refresh cadence
- in-flight refresh de-duplication
- local-first snapshot
- remote overlay
- provider key summary shaping
- readiness summary shaping

Manual refresh buttons still exist. They dispatch a force-refresh command.

Acceptance:

- Model Settings looks the same.
- Manual refresh still forces a refresh.
- Opening Settings, Supervisor Settings, Model Settings, and Dock Input in quick
  succession does not start duplicate refreshes.
- Swift views observe projection state instead of invoking model inventory reads in
  `onAppear` except through bridge commands.

### 4. Pending Approval / Grant Projection

Current Swift surface:

- `swift-xterminal/Sources/Tools/XTPendingApprovalPresentation.swift`
- `swift-xterminal/Sources/Tools/XTToolAuthorization.swift`
- `swift-xterminal/Sources/UI/PendingToolApprovalView.swift`
- message timeline pending approval section
- guarded automation / trusted automation helpers

Problem:

Approval UI must preserve governance truth, but the presentation is too tightly tied
to Swift-side interpretation of runtime state.

Target projection:

```swift
struct XTCorePendingApprovalProjection: Equatable, Codable {
    var revision: UInt64
    var items: [XTCorePendingApprovalItemProjection]
    var batchSummary: String
    var canApproveLocally: Bool
    var blockedByGovernance: Bool
    var blockedReasonTitle: String?
    var blockedReasonDetail: String?
    var requiredGrantLevel: String?
    var primaryAction: XTCoreApprovalAction?
}
```

Acceptance:

- Existing approval cards and buttons remain visually consistent.
- The confusing loop where local approval does not unblock governed skill state must
  have a single explicit projection reason.
- No local button should imply success if governance will still block execution.

## Rust Core Work Packages

The current `rust-xtd` is a scaffold:

- `rust-xtd/src/main.rs`
- commands: `health`, `version`, `run-once`

The implementation should grow it incrementally rather than attempt a full rewrite.

### Package A: Core Crate Shape

Add modules under `rust-xtd/src/`:

```text
core/
  mod.rs
  command.rs
  event.rs
  projection.rs
  scheduler.rs
  snapshot.rs
projection/
  sidebar.rs
  settings_diagnostics.rs
  model_route.rs
  approvals.rs
ipc/
  protocol.rs
  jsonl.rs
```

Initial CLI commands:

```bash
xtd health
xtd projection sidebar --input <fixture-or-state-dir>
xtd projection settings-diagnostics --input <fixture-or-state-dir>
xtd projection model-route --input <fixture-or-state-dir>
xtd projection approvals --input <fixture-or-state-dir>
```

Do not depend on Swift to validate projection correctness.

### Package B: Projection Protocol

Define a versioned JSON protocol first.

Minimum envelope:

```json
{
  "protocol": "xt-core-projection.v1",
  "surface": "project_sidebar",
  "revision": 1,
  "generated_at_ms": 0,
  "payload": {}
}
```

Required fields:

- `protocol`
- `surface`
- `revision`
- `generated_at_ms`
- `payload`

Swift bridge must reject unknown major protocol versions and surface a safe fallback.

### Package C: Swift Bridge Stores

Add Swift stores that are narrow and screen-specific:

```text
Sources/CoreBridge/XTCoreProjectionClient.swift
Sources/CoreBridge/XTCoreProjectionEnvelope.swift
Sources/CoreBridge/XTCoreProjectSidebarProjectionStore.swift
Sources/CoreBridge/XTCoreSettingsDiagnosticsProjectionStore.swift
Sources/CoreBridge/XTCoreModelRouteProjectionStore.swift
Sources/CoreBridge/XTCorePendingApprovalProjectionStore.swift
```

Rules:

- Stores publish one projection each.
- Stores must suppress identical snapshots.
- Stores must expose loading/error/fallback states.
- Stores must not expose raw large logs.
- Stores must be usable with fixture JSON in tests.

### Package D: Compatibility Adapters

Before Rust owns everything, add Swift compatibility builders that produce the same
projection structs from existing Swift state.

This is the migration bridge:

```text
current Swift facts -> Swift compatibility projection -> unchanged Swift UI
future Rust facts   -> Rust projection JSON          -> unchanged Swift UI
```

This keeps UI consistent while moving ownership behind the projection boundary.

## Swift Migration Rules

### Rule 1: Keep UI Components, Swap Data Inputs

Do not rewrite pages from scratch.

Preferred migration pattern:

```text
Existing View
  old: reads AppModel/store helpers directly
  new: reads projection store
  same: layout, labels, buttons, icons, actions
```

### Rule 2: No Heavy Work In `body`

SwiftUI `body` and row body code must not:

- read files
- parse doctor reports
- compute route truth
- derive governance summaries
- scan project memory
- build large attributed strings repeatedly
- call helpers with hidden IO
- render uncapped logs

### Rule 3: Commands Instead Of Side Effects In Views

View lifecycle hooks should dispatch intent:

```swift
projectionClient.requestRefresh(.modelRoute, reason: .surfaceAppeared)
```

They should not directly perform:

```swift
await modelManager.fetchModels()
```

Manual user refresh remains:

```swift
projectionClient.requestRefresh(.modelRoute, reason: .manual, force: true)
```

### Rule 4: Narrow Invalidation

Avoid broad `EnvironmentObject` invalidation. A view should observe the smallest store
that can satisfy its render needs.

If a screen only needs model route projection, it must not observe project list,
settings center, and navigation focus stores unless needed for actual UI behavior.

## UI Consistency Acceptance Checklist

Run this checklist for every migrated surface:

- Screenshot before/after at the same window size.
- Primary navigation labels unchanged.
- Settings section labels unchanged.
- Button titles unchanged unless the work order explicitly changes them.
- Approval copy still states whether local approval is sufficient.
- Project row spacing and tier badges remain visually consistent.
- Model route cards keep their role layout and picker affordance.
- Diagnostics still show the same high-level sections.
- Empty/loading/error states remain understandable and do not flash repeatedly.
- Keyboard focus and text input behavior unchanged.
- No new marketing/landing page or decorative redesign.

Recommended screenshot sizes:

- `1440x900`
- `1280x800`
- narrow window around `900x700`

## Performance Acceptance Gates

Add or extend gates. A completion claim is weak without at least one measurable gate.

### Required Existing Gates

```bash
./commands/xt_smooth_guard.command
swift build
swift test --filter XTSettingsCenterStoreTests
swift test --filter XTNavigationFocusStoreTests
swift test --filter HubModelManagerFetchTests
env XTERMINAL_RELEASE_DISABLE_WMO=1 ./commands/build_xt.command
```

### New Suggested Gates

Add scripts under:

```text
swift-xterminal/scripts/ci/
```

Suggested scripts:

```text
xt_core_projection_contract_gate.sh
xt_core_projection_fixture_gate.sh
xt_swift_ui_no_heavy_body_gate.sh
xt_settings_log_bound_gate.sh
```

Minimum checks:

- Projection JSON fixtures decode in Swift.
- Rust projection commands emit valid envelopes.
- Swift projection stores suppress identical snapshots.
- Settings diagnostics projection never includes uncapped log text.
- Sidebar row projection does not require AppModel governance calls in row body.

## Implementation Milestones

### Milestone 0: Baseline And Inventory

Goal: document current hot paths without changing behavior.

Tasks:

- Inventory every `fetchModels()` caller and classify as lifecycle refresh or manual
  refresh.
- Inventory every SwiftUI `body` path that calls governance, doctor, route truth,
  session summary, model route, or log helpers.
- Record baseline user-visible flows:
  - Work -> Control -> Settings switching
  - Settings diagnostics scrolling
  - Model Settings open and refresh
  - Supervisor Settings scrolling
  - Project sidebar selection
- Capture current screenshots for comparison.

Deliverables:

- A short markdown report under `work-orders/evidence/` or `docs/`.
- No UI changes.

### Milestone 1: Projection Types And Swift Compatibility Stores

Goal: introduce the projection boundary without Rust ownership yet.

Tasks:

- Add projection structs in Swift.
- Add compatibility builders from current Swift state.
- Add projection stores for sidebar, settings diagnostics, model route, approvals.
- Add tests that compare old derived fields to projection fields.
- Keep existing UI layout.

Acceptance:

- UI renders from projection stores in at least one target surface.
- No product behavior change.
- Build and existing focused tests pass.

Recommended first target:

- `ProjectSidebarView`

Reason:

- It is a narrow surface.
- It is visible during many interactions.
- It has clear row-level fields.

### Milestone 2: Rust Projection Protocol And Fixtures

Goal: Rust can generate projection envelopes from fixtures.

Tasks:

- Add Rust protocol envelope structs.
- Add Rust CLI projection subcommands.
- Add JSON fixtures representing current project list, settings diagnostics, and
  model inventory states.
- Add Rust tests for projection builders.
- Add Swift decode tests for Rust fixture output.

Acceptance:

- `cargo test` passes.
- Swift can decode fixture projections.
- Protocol version mismatch has safe fallback behavior.

### Milestone 3: Sidebar Projection Rust Ownership

Goal: move project sidebar row derivation behind the projection boundary.

Tasks:

- Rust or core bridge reads project registry facts.
- Rust emits `project_sidebar` projection.
- Swift `ProjectSidebarView` renders rows from projection.
- Context menu actions remain Swift commands.
- Selection remains controlled by the existing selected project command path.

Acceptance:

- Same UI appearance.
- No row `body` calls governance/session summary derivation.
- Project selection and context menu actions still work.
- Sidebar switching is smooth in release build.

### Milestone 4: Settings Diagnostics Projection Rust Ownership

Goal: move diagnostics aggregation and log shaping out of Swift.

Tasks:

- Rust/core produces diagnostics lines, doctor summary, route repair summary, and log
  tail projection.
- Swift `SettingsView` reads bounded projection data only.
- Full logs are opened by path or explicit command, not embedded in UI state.

Acceptance:

- Settings diagnostics scroll does not stutter on large logs.
- Full log text is never directly rendered unless explicitly opened outside the
  SwiftUI layout.
- Existing user actions remain.

### Milestone 5: Model Route Projection And Refresh Scheduler

Goal: stop lifecycle-triggered duplicate model refreshes.

Tasks:

- Move model inventory refresh scheduling into core.
- Swift lifecycle hooks request projection refresh, not direct model fetch.
- Manual refresh sends force command.
- Route truth and provider key summary are projection fields.

Acceptance:

- Opening multiple settings surfaces quickly does not trigger duplicate model reads.
- Manual refresh still updates immediately.
- Model Settings UI remains visually unchanged.
- `HubModelManager` is reduced or becomes a compatibility facade.

### Milestone 6: Approval Projection

Goal: make governed approval truth explicit and avoid approval loops.

Tasks:

- Core produces pending approval projection with governance block reasons.
- Swift approval UI renders from projection.
- Local approval button state matches whether local approval can actually unblock.
- Governed-skill blocked states show a single clear reason and next action.

Acceptance:

- No repeated "approve but still blocked with same dialog" loop without explanation.
- Approval surface copy stays consistent with current product language.
- Tests cover blocked-by-governance and local-approval-sufficient cases.

### Milestone 7: AppModel Slimming

Goal: AppModel stops being the broad projection source.

Tasks:

- Move screen projections to narrow stores.
- Keep AppModel for:
  - window coordination
  - command dispatch
  - selected project bridging
  - backward compatibility during migration
- Remove direct view calls into broad AppModel derivation helpers.

Acceptance:

- Major surfaces can update independently.
- Broad AppModel changes do not invalidate unrelated settings/model/sidebar UI.
- No user-visible workflow regressions.

## Test Plan

### Unit Tests

Add tests for:

- Rust projection builders
- Swift projection decoding
- Swift projection store duplicate suppression
- log tail capping
- project sidebar row projection equality
- model refresh coalescing and force-refresh bypass
- approval projection blocked reason rendering

### UI/Behavior Tests

Use existing focused tests where possible:

```bash
swift test --filter XTSettingsCenterStoreTests
swift test --filter XTNavigationFocusStoreTests
swift test --filter HubModelManagerFetchTests
swift test --filter ProjectSettingsGovernanceUITests
swift test --filter MessageTimelineWindowingSupportTests
```

### Build/Release Tests

```bash
./commands/xt_smooth_guard.command
swift build
env XTERMINAL_RELEASE_DISABLE_WMO=1 ./commands/build_xt.command
```

### Manual Smoke

Run the release app:

```bash
open "/Users/andrew.xie/Documents/AX/rust/rust xt/build/X-Terminal.app"
```

Smoke flows:

- Work -> Control -> Settings -> Supervisor switching.
- Project sidebar project selection.
- Settings diagnostics scroll from top to bottom.
- Model Settings open, manual refresh, role picker open/close.
- Supervisor Settings scroll and section switch.
- Pending approval surface if a fixture or live state is available.

## Rollback Strategy

Every projection migration must keep a Swift compatibility fallback.

If Rust projection fails:

- Swift store should mark projection as stale/error.
- UI should render the previous good projection if available.
- If no previous projection exists, render existing safe loading/empty state.
- Do not crash or blank the main surface.

Do not delete old Swift derivation helpers until:

- Rust projection path is covered by tests.
- Swift compatibility path is covered by tests.
- release build passes.
- manual smoke confirms UI consistency.

## Out Of Scope

This work order does not include:

- visual redesign
- new landing page
- replacing SwiftUI with a web UI
- moving macOS native controls into Rust
- changing Hub authority boundaries
- changing grant security policy
- changing user-facing governance labels
- collapsing Supervisor, Work, Review, and Control into one surface

## Definition Of Done

The work order is complete when:

- Swift UI surfaces render from small projection stores for sidebar, settings
  diagnostics, model route, and pending approvals.
- Rust core or `rust-xtd` owns projection shaping for at least the first three target
  surfaces.
- Swift views no longer perform heavy governance/doctor/route/log/model derivation in
  `body`.
- Lifecycle-triggered duplicate model refreshes are eliminated by a core scheduler.
- Logs and diagnostics are bounded before reaching SwiftUI.
- The release app visually matches the pre-migration UI for the covered surfaces.
- Existing focused tests and release build pass.
- A future AI can add another projection surface by following the same protocol,
  store, fixture, and UI adapter pattern.
