# X-Hub XT UI And Runtime Smoothness Execution Plan v1

Status: active
Owner: XT refactor lane
Last updated: 2026-04-28

## Decision

XT keeps Swift and SwiftUI for the macOS UI. The refactor target is not a full UI rewrite. The target is to make XT smoother by reducing main-thread work, narrowing SwiftUI invalidation, and moving hot runtime work behind smaller services or a future Rust sidecar.

Rust is the preferred future sidecar language for local runtime hot paths. Go is acceptable for daemon/network-only surfaces. Python stays outside the interactive hot path and is only suitable for ML/model/data helper scripts.

## Non-Negotiable Boundaries

1. Hub remains the authority for grants, policy, audit, kill-switch, memory durable truth, and skill authority.
2. XT remains UI, execution plane, local projection, cache, and checkpoint client.
3. XT must fail closed when Hub authority or grants are unavailable.
4. Rust/Go/Python sidecars must not become a second source of truth.
5. Performance work must not weaken auditability, memory routing, skill governance, or pairing security.

## Current Hotspots

1. `x-terminal/Sources/AppModel.swift`
   - Large `@MainActor ObservableObject`.
   - Many unrelated `@Published` fields share one invalidation domain.
   - Broad manual `objectWillChange.send()` calls can trigger coarse redraws.

2. `x-terminal/Sources/Supervisor/SupervisorManager.swift`
   - Very large `@MainActor ObservableObject`.
   - Conversation, heartbeat, voice, memory, doctor, automation, approvals, and runtime boards are coupled.
   - Timers and polling can publish many unrelated fields.

3. `x-terminal/Sources/ContentView.swift` and major panes
   - `AppModel` is injected broadly through `@EnvironmentObject`.
   - Views often observe more state than they actually need.

4. `x-terminal/Sources/Chat/ChatSessionModel.swift`
   - Streaming assistant/tool output mutates `messages` frequently.
   - A single token/chunk can force list-level redraw.

5. `x-terminal/Sources/Hub/HubIPCClient.swift`
   - File IPC and polling fallback surfaces should be treated as fallback, not the primary fast path.

## Success Metrics

1. Idle XT has near-zero repeated `@Published` commits.
2. Chat streaming commits to SwiftUI at no more than 10-20 commits per second per active stream.
3. File IO, JSON encode/decode, Doctor assembly, Memory assembly, Hub polling, and skills scanning do not run on the main actor.
4. Project switching gives immediate UI feedback within 200 ms, with heavy diagnostics completing asynchronously.
5. Supervisor board updates only when an `Equatable` snapshot actually changes.
6. Hub event subscription is the primary runtime update source; timer polling is fallback or coarse health check.

## Phase 0: Instrument Before Large Refactor

### 0.1 Add Signpost Points

Files:
- `x-terminal/Sources/AppModel.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Chat/ChatSessionModel.swift`

Tasks:
1. Add lightweight `os.signpost` or local debug hooks around Hub status refresh, project selection, Doctor report generation, Supervisor heartbeat refresh, memory assembly refresh, and chat streaming UI commit.
2. Keep signposts behind a small helper so production code remains readable.

Acceptance:
- Instruments can show which refresh path owns main-thread time.
- Signposts do not change behavior.

### 0.2 Establish Baseline Runs

Commands:
- `swift build` from `x-terminal`
- Targeted chat and supervisor tests when full build time is high

Manual scenarios:
1. Launch XT, idle for 60 seconds.
2. Switch project.
3. Open Supervisor.
4. Stream a long assistant response.
5. Run a tool command with verbose output.

Acceptance:
- Record visible stutter points and highest-frequency refresh paths.

## Phase 1: Reduce High-Frequency Redraws

### 1.1 Throttle Chat Streaming UI Commits

File:
- `x-terminal/Sources/Chat/ChatSessionModel.swift`

Tasks:
1. Buffer assistant visible streaming text by message id.
2. Flush buffered text every 50 ms instead of every token.
3. Buffer tool stream text by message id.
4. Flush tool stream text every 50 ms.
5. Cancel pending stream flush tasks before final assistant/tool content is materialized.

Acceptance:
- Streaming remains visually live.
- Final assistant/tool content is never overwritten by stale buffered text.
- `messages` changes substantially less during streaming.

Status:
- Completed in work slice `XT-SMOOTH-001`.

Validation:
- `swift build` passed from `x-terminal` on 2026-04-28.
- `swift test --filter ChatSessionModel` passed from `x-terminal` on 2026-04-28 with 113 Swift Testing tests.

### 1.2 Avoid Full Message Array Mutation For Progress Rails

File:
- `x-terminal/Sources/Chat/ChatSessionModel.swift`

Tasks:
1. Keep thinking/progress rail state separate from final message content.
2. Publish progress rail state at a bounded cadence.
3. Clear progress state with id-based helpers.

Acceptance:
- Waiting/progress UI stays responsive.
- The message list is not rewritten for transient progress-only changes.

### 1.3 Add Row-Level Message Projection

Files:
- `x-terminal/Sources/UI/MessageTimeline/MessageTimelineView.swift`
- `x-terminal/Sources/UI/MessageTimeline/ModernChatView.swift`

Tasks:
1. Introduce `MessageRowSnapshot: Identifiable, Equatable`.
2. Build row snapshots once per message update.
3. Pass row snapshots into row views instead of the whole session model where possible.
4. Apply `.equatable()` to heavy rows after snapshots are stable.

Acceptance:
- Updating one streaming row does not recalculate unrelated row presentation.

## Phase 2: Split Observable State Domains

### 2.1 Split AppModel Into Stores

Files:
- `x-terminal/Sources/AppModel.swift`
- `x-terminal/Sources/ContentView.swift`
- UI panes currently using `@EnvironmentObject AppModel`

New stores:
1. `HubConnectionStore`
2. `ProjectSelectionStore`
3. `RuntimeStatusStore`
4. `DoctorStore`
5. `SkillsStore`
6. `NavigationFocusStore`

Tasks:
1. Start with read-mostly projections; keep `AppModel` as compatibility facade.
2. Move one UI area at a time to the focused store.
3. Stop injecting the entire `AppModel` into panes that only need one store.

Acceptance:
- Hub connection updates do not redraw project grids.
- Doctor updates do not redraw chat.
- Focus/sheet changes do not redraw runtime boards.

### 2.2 Split SupervisorManager Presentation Stores

Files:
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/UI/Supervisor/*`

New stores:
1. `SupervisorConversationStore`
2. `SupervisorRuntimeBoardStore`
3. `SupervisorVoiceStore`
4. `SupervisorMemoryStore`
5. `SupervisorAutomationStore`
6. `SupervisorApprovalStore`
7. `SupervisorDoctorStore`

Tasks:
1. Extract immutable `Equatable` board snapshots first.
2. Keep command methods on the manager until the stores stabilize.
3. Move UI panels to observe their own store only.

Acceptance:
- Voice state changes do not redraw approvals.
- Memory refresh does not redraw conversation rows.
- Automation checkpoint updates do not redraw the entire Supervisor control center.

## Phase 3: Move Work Off The Main Actor

### 3.1 Snapshot Builders

New components:
- `DoctorSnapshotBuilder`
- `MemoryAssemblySnapshotBuilder`
- `SkillsRegistrySnapshotBuilder`
- `HubRuntimeSnapshotBuilder`

Tasks:
1. Make builders non-UI services or actors.
2. Return immutable snapshots.
3. On the main actor, assign only if the snapshot changed.

Pattern:

```swift
let next = await builder.build(input)
await MainActor.run {
    if currentSnapshot != next {
        currentSnapshot = next
    }
}
```

Acceptance:
- No heavy file IO, JSON parsing, scanning, or report assembly on the main actor.

### 3.2 Refresh Coordinator

New component:
- `XTRefreshCoordinator`

Tasks:
1. Deduplicate same-key refresh requests.
2. Suppress duplicate in-flight refreshes.
3. Debounce bursty updates.
4. Emit one coalesced snapshot.

Acceptance:
- Rapid Hub events or timers do not create overlapping refresh work.

## Phase 4: Prefer Hub Events Over Polling

Files:
- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Hub/HubAIClient.swift`
- Hub gRPC protocol and server files as needed

Tasks:
1. Use Hub event subscription as the fast path for runtime status, grants, skills, memory projection, and remote route state.
2. Keep timer polling as fallback or slow health check.
3. Coalesce event bursts before publishing UI state.

Acceptance:
- Normal runtime updates do not depend on frequent polling.
- File IPC fallback remains available but is not the main refresh source.

## Phase 5: Rust XT Sidecar

Target folder:
- `x-hub-system/rust-XT`

Initial contents:
1. `Cargo.toml`
2. `src/main.rs`
3. `proto/`
4. `commands/build_xtd.command`
5. `commands/package_xt_runtime.command`
6. `README.md`

Responsibilities:
1. Hub gRPC client and event subscription.
2. Local execution queue.
3. Automation checkpoint/recovery.
4. Skills execution dispatch after Hub authorization.
5. Doctor/runtime/memory projection snapshot assembly.

Swift bridge options:
1. Unix domain socket JSON-RPC for fast iteration.
2. Local gRPC for protocol stability.
3. Stdio JSON-RPC only for short-lived helper mode.

Acceptance:
- XT UI can run without the sidecar for degraded/fallback mode.
- Sidecar never owns grants, audit, durable memory, or skill authority.
- Sidecar commands are packageable from `rust-XT/commands`.

## Execution Order

1. Finish Phase 1.1 chat/tool streaming throttling.
2. Build and run targeted chat tests.
3. Add signpost helper for Phase 0.1.
4. Extract the first `Equatable` runtime snapshot from `AppModel`.
5. Move one small pane from broad `AppModel` observation to a focused snapshot/store.
6. Repeat store extraction for Supervisor boards.
7. Only after redraw and main-thread pressure are under control, scaffold `rust-XT`.

## Current Work Slice

Slice: XT-SMOOTH-001

Scope:
- Plan document.
- Chat assistant/tool streaming UI commit throttling.

Files:
- `docs/memory-new/xhub-xt-ui-runtime-smoothness-execution-plan-v1.md`
- `x-terminal/Sources/Chat/ChatSessionModel.swift`

Validation:
1. `swift build` from `x-terminal`: passed.
2. `swift test --filter ChatSessionModel` from `x-terminal`: passed, 113 tests.
3. Manual long stream and verbose tool output check: pending next interactive run.

Result:
- Assistant visible streaming text now buffers by message id and flushes at a 50 ms cadence.
- Tool stream output now buffers by message id and flushes at a 50 ms cadence.
- Pending stream flushes are cancelled before final assistant/tool content is materialized.
- Duplicate message content writes are skipped.
