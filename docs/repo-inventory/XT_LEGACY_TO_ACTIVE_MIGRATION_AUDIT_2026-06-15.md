# XT Legacy To Active Migration Audit - 2026-06-15

Status: audit complete; focused migrations are in progress. Active XT source has been changed only by narrow cherry-picks, not by wholesale legacy overwrite.

Update 2026-06-15: P0 profile foundation has now been migrated into active XT after this audit:

- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Sources/Hub/XTHubProfiles.swift`.
- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Tests/XTHubProfilesTests.swift`.
- Wired active `AppModel.swift`, `XTSettingsCenterStore.swift`, `XTSettingsSurfaceProjection.swift`, and `SettingsView.swift` so XT can maintain multiple Hub profiles, switch the active profile, rename it, create/remove profiles, export a safe profile package, and import a safe profile package from clipboard.
- Verified with `swift test --list-tests` for build coverage and `swift test --filter XTHubProfilesTests` for focused execution.

Update 2026-06-15: P0 Rust remote-entry candidate consumption has now been migrated into active XT after this audit:

- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Sources/Hub/RustHubRemoteEntryCandidatesClient.swift`.
- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Tests/RustHubRemoteEntryCandidatesClientTests.swift`.
- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Sources/Hub/RustHubHTTPAccess.swift` and tests because the Rust endpoint can require `Authorization: Bearer <key>` / `X-XHub-Access-Key`.
- Wired active `AppModel.swift` to refresh Rust `/network/remote-entry-candidates` with a short cached doctor fetch and feed the preferred stable remote host into the paired route set.
- Wired active `XTPairedRouteSetSnapshot.swift` so an authoritative Rust remote-entry candidate is represented as `rust_remote_entry_candidate` and can become the stable `internet_tunnel` route.
- Verified with `swift test --filter 'RustHubHTTPAccessTests|RustHubRemoteEntryCandidatesClientTests|HubAIClientRemoteConnectOptionsTests'`.
- Live smoke on this machine: unauthenticated curl returned 401, authenticated request returned `status=200`, `schema=xhub.rust_hub.remote_entry_candidates.v1`, preferred host `andrew.tailbe79cd.ts.net`.

Update 2026-06-15: P0 profile-scoped cache isolation is now migrated into active XT for the main multi-Hub surfaces:

- Skills resolved cache snapshots now carry `hub_profile_id`; active snapshot reads reject mismatched Hub profiles and reject legacy profile-less caches when multiple Hub profiles exist.
- `HubModelManager` resets its volatile authoritative model inventory when the active Hub profile changes.
- `HubRemoteMemorySnapshotCache` keys and metadata now include Hub profile scope, and `HubIPCClient` passes the active scope into remote memory snapshot cache usage.
- `XTConnectivityRepairLedgerStore` now records `hub_profile_id`, filters route health/cooldown calculations to the active Hub profile, and includes Hub profile in its dedupe key.
- Active XT tests now resolve `official-agent-skills` from either the active source tree or the workspace `x-hub-system/official-agent-skills`, avoiding false failures after the source root split.
- Verified with `swift test --filter XTConnectivityRepairLedgerStoreTests`, `swift test --filter HubRemoteMemorySnapshotCacheTests`, `swift test --filter resolvedSkillsCacheStoreIsScopedToActiveHubProfile`, `swift test --filter HubModelManagerFetchTests`, `swift test --filter RustHubHTTPAccessTests`, `swift test --filter RustHubRemoteEntryCandidatesClientTests`, `swift test --filter HubAIClientRemoteConnectOptionsTests`, and `swift test --filter AXSkillsRemoteRegistryTests`.

Update 2026-06-15: P1 Memory Inspector / Writeback Candidate core has now been migrated into active XT after this audit:

- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Sources/UI/Memory/XTMemoryInspectorStore.swift`.
- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift`.
- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Tests/MemoryInspectorTests.swift`.
- Added active `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Tests/MemoryWritebackCandidateQueueTests.swift`.
- Added active `HubIPCClient+RustMemoryObjects.swift` so XT can decode/list/mutate Rust memory objects and review writeback candidates without expanding the already-diverged main `HubIPCClient.swift`.
- Added active `RustHubMemoryReadinessSnapshot.swift` for memory object store / mutation gate / user reveal grant readiness.
- Verified with `swift test --filter 'MemoryInspectorTests|MemoryWritebackCandidateQueueTests'`: 34 tests passed.

Still pending: Memory Inspector / Writeback Candidate UI wiring, focused Rust doctor/readiness expansions, and remaining cache-adjacent follow-ups such as the `HubPaths` pinned override lease and `ToolExecutor` global `skills_pin` behavior.

## Scope

Active roots for this local workspace:

- Hub app / control plane: `/Users/andrew.xie/Documents/AX/x-hub-system/x-hub/`
- Hub Rust kernel: `/Users/andrew.xie/Documents/AX/rust/rust hub`
- Active X-Terminal: `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`
- Legacy X-Terminal under audit: `/Users/andrew.xie/Documents/AX/x-hub-system/x-terminal`

`x-hub/macos/RELFlowHub/` is still the current Hub Swift shell's historical package name. It is not evidence of a separate old Hub product. In contrast, `x-hub-system/x-terminal/` is marked legacy/read-only by `AGENTS.md`; XT behavior changed only there must not be treated as active XT behavior until migrated to `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal`.

## Method

For each changed file under `x-hub-system/x-terminal`, compare:

1. `legacy HEAD`: `git show HEAD:x-terminal/...`
2. `legacy working tree`: current dirty file under `x-hub-system/x-terminal/...`
3. `active XT`: mapped file under `/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/...`

Classification:

- `SYNCED_EXACT`: active XT already byte-matches the legacy working file.
- `ACTIVE_AT_LEGACY_HEAD_MISSING_CHANGE`: active XT byte-matches legacy HEAD, so the legacy working change is not in active XT.
- `ACTIVE_MISSING`: active XT has no mapped file.
- `DIVERGED_MANUAL_REVIEW`: active XT differs from both legacy HEAD and legacy working file; migrate only by focused cherry-pick.

## Summary

Legacy XT dirty scope:

- Total changed/untracked legacy XT files: 63
- Tracked dirty files: 55
- Untracked files: 8

Three-way result:

| Status | Count | Meaning |
|---|---:|---|
| `SYNCED_EXACT` | 4 | Already present in active XT. |
| `ACTIVE_AT_LEGACY_HEAD_MISSING_CHANGE` | 21 | Change is absent from active XT and is usually a focused replay candidate. |
| `DIVERGED_MANUAL_REVIEW` | 29 | Active XT has independent changes; do not copy wholesale. |
| `ACTIVE_MISSING` | 9 | New legacy file does not exist in active XT. |

Main conclusion: some XT work did land in the wrong tree. Hub-side work under `x-hub-system/x-hub/` and Hub Rust work under `rust/rust hub` are still in the intended Hub surfaces, but XT changes under `x-hub-system/x-terminal/` need focused migration to the active XT tree.

## Product Findings

### P0 - Multi-Hub Support Was Not Active; Profile Foundation Migrated

At audit time, the multi-Hub profile model existed only in legacy XT:

- `x-terminal/Sources/Hub/XTHubProfiles.swift` is `ACTIVE_MISSING`.
- `x-terminal/Tests/XTHubProfilesTests.swift` is `ACTIVE_MISSING`.
- legacy `AppModel.swift`, `SettingsView.swift`, `XTSettingsCenterStore.swift`, and `XTSettingsSurfaceProjection.swift` reference `hubProfilesSnapshot`; active XT does not.
- legacy `HubModelManager.swift`, `Supervisor/XTConnectivityRepairLedgerStore.swift`, and skills cache paths scope caches with `XTHubProfilesStorage.activeCacheScopeID()`.

Current state: the profile foundation has been migrated into active XT, including profile create/select/rename/remove/import/export UI and tests. Main profile-scoped cache isolation has also been migrated for skills resolved caches, model inventory, remote memory snapshots, and connectivity repair route health/cooldown. Remaining multi-Hub follow-up is narrower: audit `HubPaths` pinned override lease behavior, `ToolExecutor` global `skills_pin` behavior, and any additional per-project memory inspector/writeback cache introduced by the P1 migration.

### P0/P1 - Rust Remote Entry Candidates Were Not Active; Now Migrated

At audit time, the Rust remote-entry candidate client existed only in legacy XT:

- `x-terminal/Sources/Hub/RustHubRemoteEntryCandidatesClient.swift` is `ACTIVE_MISSING`.
- `x-terminal/Tests/RustHubRemoteEntryCandidatesClientTests.swift` is `ACTIVE_MISSING`.
- legacy `AppModel.swift` calls `RustHubRemoteEntryCandidatesClient.fetch(...)`; active XT has no such call.

Current state: active XT now consumes Rust `/network/remote-entry-candidates`, decodes `xhub.rust_hub.remote_entry_candidates.v1`, sends the Rust HTTP access key when available, and lets an authoritative Rust stable host become the paired route set's stable `internet_tunnel` route. This gives XT a path to use Hub-provided stable domain/tunnel decisions instead of only user-entered domains.

### P0 - Profile-Scoped Cache Isolation Is Mostly Active

Active XT now has the main Hub profile cache isolation migrated:

- `XTResolvedSkillsCacheStore.swift` filters by active `hubProfileID`, rejects stale legacy profile-less caches when multiple profiles exist, and uses explicit Hub base directories for active-cache epoch checks.
- `AXSkillsLibrary+HubCompatibility.swift` writes `hub_profile_id` into resolved skill cache snapshots and filters persisted remote cache fallback by active Hub profile.
- `HubModelManager.swift` resets volatile model inventory on Hub profile change.
- `HubRemoteMemorySnapshotCache.swift` and `HubIPCClient.swift` scope remote memory snapshot cache entries by active Hub profile.
- `XTConnectivityRepairLedgerStore.swift` scopes route status history and cooldown calculations by active Hub profile.

Remaining cache-adjacent items that still need manual review:

- `HubPaths.swift` is `DIVERGED_MANUAL_REVIEW`; active lacks the pinned override semaphore/lease used to serialize tests.
- `ToolExecutor.swift` is `DIVERGED_MANUAL_REVIEW`; legacy changed `skills_pin` behavior so global pins do not refresh current project resolved-skill cache.

Impact: the main user-facing risk of skills/model/memory/route cache data leaking across Hub profiles is now covered by active XT tests. The remaining items are still relevant for test stability and exact skills pin refresh semantics, but they are no longer blockers for basic multi-Hub cache isolation.

### P1 - Memory Inspector / Writeback Candidate Core Is Active; UI Wiring Pending

At audit time, the Rust memory inspection/writeback UX existed only in legacy XT:

- `x-terminal/Sources/UI/Memory/XTMemoryInspectorStore.swift` is `ACTIVE_MISSING`.
- `x-terminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift` is `ACTIVE_MISSING`.
- `x-terminal/Tests/MemoryInspectorTests.swift` is `ACTIVE_MISSING`.
- `x-terminal/Tests/MemoryWritebackCandidateQueueTests.swift` is `ACTIVE_MISSING`.
- legacy `ProjectSettingsView.swift`, `SupervisorPersonalMemoryCenterView.swift`, `HubIPCClient.swift`, and `XTUnifiedDoctor.swift` carry the integration points, but all are divergent in active XT.

Current state: active XT now has the store/protocol/test foundation:

- `XTMemoryInspectorStore` supports project memory object inspection, assistant/user reveal-grant gating, detail/history loading, mutation payloads, and memory selection evidence projection.
- `XTMemoryWritebackCandidateQueueStore` supports candidate list, approve/reject, conflict merge review, maintenance preview/apply, and bounded evidence logging.
- `HubIPCClient+RustMemoryObjects.swift` provides the Rust HTTP contracts and scoped test overrides for memory objects and writeback candidates.

Remaining UI work: active `MemoryInspectorView` is still the old markdown-only view, and active `ProjectSettingsView`, `SupervisorPersonalMemoryCenterView`, and `XTUnifiedDoctor` do not yet expose the migrated Rust memory inspector/writeback candidate surfaces. Migrate those UI integration points in narrow slices because the files are divergent.

### P1 - Rust Readiness / Doctor Expansion Is Diverged

`RustHubReadinessClient.swift` is much larger in legacy and is `DIVERGED_MANUAL_REVIEW`:

- active XT has a smaller readiness client used by settings/model settings.
- legacy adds memory readiness, product process sanity, memory gateway model-call execution gate, and remote-entry related flows.

Impact: migrate endpoint decoders and tests in narrow slices. Do not copy the file wholesale.

### P2 - Voice Token Fix Is Not Active

`VoiceRuntimeTypes.swift` is `ACTIVE_AT_LEGACY_HEAD_MISSING_CHANGE`.

Impact: active may still expose the older machine token vocabulary instead of restored `native_tts` / `system_speech_fallback` tokens.

## File Classification

### Already Synced

- `x-terminal/Sources/ContentView.swift`
- `x-terminal/Tests/AppModelHubSetupFocusTests.swift`
- `x-terminal/Tests/HubInviteOnboardingFlowTests.swift`
- `x-terminal/Tests/XTDeepLinkParserTests.swift`

### Active Missing

- `x-terminal/Sources/Hub/HubContractClient.swift`
- `x-terminal/Sources/Hub/RustHubRemoteEntryCandidatesClient.swift`
- `x-terminal/Sources/Hub/XTHubProfiles.swift`
- `x-terminal/Sources/Project/XTMemoryWritebackCandidateQueueStore.swift`
- `x-terminal/Sources/UI/Memory/XTMemoryInspectorStore.swift`
- `x-terminal/Tests/MemoryInspectorTests.swift`
- `x-terminal/Tests/MemoryWritebackCandidateQueueTests.swift`
- `x-terminal/Tests/RustHubRemoteEntryCandidatesClientTests.swift`
- `x-terminal/Tests/XTHubProfilesTests.swift`

Note: `HubContractClient.swift` being missing needs separate handling. Active XT may have folded that behavior elsewhere; confirm before adding a new file.

Post-audit migration note: `RustHubRemoteEntryCandidatesClient.swift`, `RustHubRemoteEntryCandidatesClientTests.swift`, `RustHubHTTPAccess.swift`, `RustHubHTTPAccessTests.swift`, `XTHubProfiles.swift`, and `XTHubProfilesTests.swift` now exist in active XT. They remain listed here because this classification records the original audit state.

Post-audit migration note: `XTMemoryInspectorStore.swift`, `XTMemoryWritebackCandidateQueueStore.swift`, `MemoryInspectorTests.swift`, and `MemoryWritebackCandidateQueueTests.swift` now exist in active XT, together with active `HubIPCClient+RustMemoryObjects.swift` and `RustHubMemoryReadinessSnapshot.swift`.

### Active At Legacy HEAD, Missing Legacy Change

These are usually safer replay candidates, but still check dependencies:

- `x-terminal/Sources/CoreBridge/XTSettingsSurfaceProjection.swift`
- `x-terminal/Sources/Hub/HubAccessKeysClient.swift`
- `x-terminal/Sources/Hub/HubProviderKeysClient.swift`
- `x-terminal/Sources/Hub/HubRemoteMemorySnapshotCache.swift`
- `x-terminal/Sources/Hub/ProviderKeyManager.swift`
- `x-terminal/Sources/Hub/XTProcessPaths.swift`
- `x-terminal/Sources/Project/AXMemory.swift`
- `x-terminal/Sources/Project/AXMemoryPipeline.swift`
- `x-terminal/Sources/Project/AXProjectContext.swift`
- `x-terminal/Sources/Project/XTResolvedSkillsCacheStore.swift`
- `x-terminal/Sources/Supervisor/XTConnectivityRepairLedgerStore.swift`
- `x-terminal/Sources/UI/Components/XTUIReviewActionState.swift`
- `x-terminal/Sources/UI/Supervisor/SupervisorPersonalMemoryCenterView.swift`
- `x-terminal/Sources/UI/XTDoctorProjectionPresentation.swift`
- `x-terminal/Sources/UI/XTSettingsCenterStore.swift`
- `x-terminal/Sources/Voice/VoiceRuntimeTypes.swift`
- `x-terminal/Tests/AXMemoryPipelineTests.swift`
- `x-terminal/Tests/HubRemoteMemorySnapshotCacheTests.swift`
- `x-terminal/Tests/RustHubReadinessPresentationTests.swift`
- `x-terminal/Tests/SupervisorHeartbeatVoiceTests.swift`
- `x-terminal/Tests/XTDoctorProjectionPresentationTests.swift`

### Diverged, Manual Review Required

Do not copy these over active XT. Cherry-pick only the relevant hunks:

- `x-terminal/Sources/AppModel.swift`
- `x-terminal/Sources/Chat/ChatSessionModel.swift`
- `x-terminal/Sources/Hub/HubAIClient.swift`
- `x-terminal/Sources/Hub/HubIPCClient.swift`
- `x-terminal/Sources/Hub/HubPairingCoordinator.swift`
- `x-terminal/Sources/Hub/HubPaths.swift`
- `x-terminal/Sources/Hub/HubRemoteHostPolicy.swift`
- `x-terminal/Sources/Hub/RustHubReadinessClient.swift`
- `x-terminal/Sources/Hub/XTPairedRouteSetSnapshot.swift`
- `x-terminal/Sources/LLM/HubModelManager.swift`
- `x-terminal/Sources/Project/AXSkillsLibrary+HubCompatibility.swift`
- `x-terminal/Sources/Supervisor/SupervisorDoctor.swift`
- `x-terminal/Sources/Supervisor/SupervisorManager.swift`
- `x-terminal/Sources/Supervisor/SupervisorMemoryAssemblyDiagnostics.swift`
- `x-terminal/Sources/Tools/ToolExecutor.swift`
- `x-terminal/Sources/UI/Components/HubRemoteAccessGuidance.swift`
- `x-terminal/Sources/UI/HubSetupWizardView.swift`
- `x-terminal/Sources/UI/ProjectSettingsView.swift`
- `x-terminal/Sources/UI/SettingsView.swift`
- `x-terminal/Sources/UI/XHubDoctorOutput.swift`
- `x-terminal/Sources/UI/XTUnifiedDoctor.swift`
- `x-terminal/Tests/AppModelHubStartupAutoPairingTests.swift`
- `x-terminal/Tests/HubAIClientRemoteConnectOptionsTests.swift`
- `x-terminal/Tests/HubIPCClientProjectCanonicalMemorySyncTests.swift`
- `x-terminal/Tests/HubPairingCoordinatorTests.swift`
- `x-terminal/Tests/HubRemoteHostPolicyTests.swift`
- `x-terminal/Tests/SupervisorDoctorTests.swift`
- `x-terminal/Tests/XHubDoctorOutputTests.swift`
- `x-terminal/Tests/XTUnifiedDoctorReportTests.swift`

Post-audit migration note: active XT now contains the profile-scoped `HubRemoteMemorySnapshotCache.swift`, `XTResolvedSkillsCacheStore.swift`, and `XTConnectivityRepairLedgerStore.swift` changes plus focused tests. They remain listed here because this classification records the original audit state.

## Recommended Migration Order

1. Baseline active XT build/test before edits.
2. P0 profile foundation - done:
   - add `XTHubProfiles.swift` and tests to active XT,
   - thread minimal `hubProfilesSnapshot` into active `AppModel`, settings projection, and settings UI,
   - keep legacy `x-terminal/` untouched.
3. P0 route foundation - done:
   - add `RustHubRemoteEntryCandidatesClient.swift` and tests,
   - integrate route candidate fetch into active `AppModel` only after profile switching exists.
4. P0 cache isolation:
   - done for `XTResolvedSkillsCacheStore` `hubProfileID` filtering,
   - done for matching `AXSkillsLibrary+HubCompatibility`, `HubModelManager`, `HubRemoteMemorySnapshotCache`, `HubIPCClient`, `XTConnectivityRepairLedgerStore`, and focused tests,
   - remaining follow-up: migrate/review `HubPaths` pinned override lease and `ToolExecutor` global `skills_pin` behavior.
5. P1 memory inspector/writeback:
   - done: add missing stores/tests,
   - done: migrate required Rust memory object and writeback candidate `HubIPCClient` endpoints into a focused extension,
   - remaining: integrate into active `ProjectSettingsView`, `SupervisorPersonalMemoryCenterView`, and `XTUnifiedDoctor` in smaller slices.
6. P1/P2 polish:
   - Rust readiness/doctor expansions,
   - voice token naming,
   - UI review snapshot preservation.

## Reproduce

```bash
git -C /Users/andrew.xie/Documents/AX/x-hub-system diff --name-only -- x-terminal
git -C /Users/andrew.xie/Documents/AX/x-hub-system ls-files --others --exclude-standard -- x-terminal
rg -n "XTHubProfiles|RustHubRemoteEntryCandidatesClient|XTMemoryInspectorStore|XTMemoryWritebackCandidateQueueStore" \
  "/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Sources" \
  "/Users/andrew.xie/Documents/AX/rust/rust xt/swift-xterminal/Tests"
```
