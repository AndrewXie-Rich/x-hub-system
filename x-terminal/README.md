# X-Terminal

`x-terminal/` is the active terminal surface for X-Hub.

It is where interaction, session runtime, supervisor workflows, readiness checks, and tool execution UX live. It is not the trust anchor.

Release scope note: this module README explains the active terminal implementation surface and operator entrypoints. Public release claims still follow the validated-mainline-only scope defined in the repository root `README.md`, `RELEASE.md`, and the open-source release templates.

## Validated Scope Reminder

For GitHub-facing claims, the current validated public mainline is limited to:

- `XT-W3-23 -> XT-W3-24 -> XT-W3-25`

Validated public statements stay limited to:

- `XT memory UX adapter backed by Hub truth-source`
- `Hub-governed multi-channel gateway`
- `Hub-first governed automations`

Anything else in `x-terminal/` should be read as active implementation context, internal operator material, or in-progress delivery surface unless it is explicitly included in the validated release slice above.

## What This Module Owns

- Hub pairing UX and terminal-side diagnostics
- Session runtime and tool routing
- Supervisor orchestration and readiness/doctor flows
- Terminal-local tests, probes, and release gates
- Repo-local skills used by the active terminal implementation

## Design Position

X-Terminal is intentionally powerful but not sovereign.

It can present rich runtime state, guide the user through pairing and readiness, and execute governed flows, but trust, grants, and final policy authority remain in `x-hub/`.

## Secure Hub Pairing Transport

Active implementation context, not an expansion of the validated release slice:

- Native discovery, remote device presence, access-key management, and Hub contract reads use verified HTTPS for network hosts. Plain HTTP is restricted to strict loopback endpoints, such as an operator-established SSH tunnel. HTTPS never falls back to HTTP after a certificate or connection failure.
- Native requests disable redirects, shared cookies, cached credentials, and proxies. Certificate chain, validity, and hostname checks remain mandatory. Discovery keeps the endpoint that was actually verified rather than replacing it with `hub_host_hint`.
- `axhubctl` must support `transport-policy` and return `pairing_https_required_v1`. Rebuild/repackage XT with the current bundled tool or explicitly select the current canonical tool; older tools fail with `pairing_transport_tool_upgrade_required`. Reinstall the current client kit when its credentials helper is absent or incompatible.
- The shared gRPC credentials builder no longer catches TLS errors and falls back to `createInsecure()`. Missing mode defaults to TLS; invalid modes and network plaintext fail closed. gRPC and pairing HTTPS have separate trust settings.

For a public/system-trusted HTTPS certificate, no pairing CA setting is required. For a private CA, obtain and verify its certificate through an independent trusted channel, then put the following in the selected Hub profile's state directory as `pairing-transport.env` before pairing:

```sh
export HUB_PAIRING_SCHEME='https'
export HUB_PAIRING_CA_CERT_PATH='/absolute/path/to/independently-verified-ca.pem'
```

The native client accepts PEM bundles or DER certificates; use PEM for interoperability with `axhubctl`/curl. The certificate must cover the actual IP address or hostname entered in XT. Do not use `HUB_GRPC_TLS_SERVER_NAME` as an HTTPS hostname override or reuse a CA obtained over unauthenticated HTTP. Configuration is local to the selected profile, preserved across route-state rewrites and discovery probes, and removed by reset-pairing. Process environment overrides use the same names and take priority; ordinary Finder launches should use the profile file. Existing values in `hub.env`/`pairing.env` migrate into the dedicated file before those files are rewritten.

The embedded macOS Hub still binds the pairing/admin/health port to loopback HTTP. Native HTTPS support does not automatically expose that listener, enable SSH, provision certificates, or make legacy same-Wi-Fi invite links a secure direct-LAN path. For that Hub, establish the generated SSH forward for **both** gRPC and pairing ports, verify the SSH host key independently, keep it running, and select `127.0.0.1` with the forwarded ports in XT. Use a separate profile with pairing scheme unset (or `http`) for that path. A gRPC-only TCP tunnel does not carry pairing/control traffic; it needs a separate verified HTTPS control endpoint. Direct network pairing requires an explicitly configured HTTPS Hub and still obeys Hub approval, first-pair source restrictions, and invite policy.

Focused regression from the repository root (macOS, Node dependencies, Swift compiler, OpenSSL):

```bash
cd x-hub/grpc-server/hub_grpc_server
node --test src/xt_pairing_transport.test.js src/transport_security.test.js
```

The regression compiles the actual native transport, access-key and contract clients, and gRPC generation script source without requiring the Swift `Testing` module. It uses temporary HTTPS Hub state, real local sockets, independent test certificates, actual Hub pairing approval and heartbeat authorization, and a fixture-only gRPC model. It checks persisted trust, loopback HTTP compatibility, remote plaintext denial, malformed/untrusted/wrong-host certificates, redirect/downgrade refusal, missing or incompatible credential helpers, and reconnection after listener restart. This is not two-device GUI acceptance, real model inference, mTLS roaming qualification, or production release evidence. No installed apps or production Hub state are changed.

## Local Execution Safety

Active implementation context, not an expansion of the validated release slice:

- `/sandbox mode host` retains the existing host environment and shell session state. It is not OS-isolated; command results report `isolation: host_none`. The default remains host for compatibility.
- `/sandbox mode sandbox` uses the private per-project workspace, uploads, and outputs directories. It currently supports `read_file`, `write_file`, `list_dir`, `search`, and `run_command`. Other tools fail closed rather than silently using a host implementation. A model-supplied `sandbox=false` cannot downgrade this mode; the user must select host mode explicitly.
- Local sandbox commands run through macOS Seatbelt (`sandbox-exec`) with a deny-by-default profile. The profile allows system runtime reads and configured project roots, and denies network access by default. Additional readable roots do not silently switch sandbox file tools to the host. Missing or rejected sandbox support fails execution without a host fallback.
- The local runner uses an allowlisted environment instead of inheriting host tokens, credential-agent sockets, and startup configuration. The default executable search path contains only macOS system binary directories; Homebrew, language managers, and arbitrary user configuration are not automatically exposed. Explicit network opt-in is a broad network permission, not a destination-scoped Hub grant.
- One-shot capture multiplexes stdin, stdout, and stderr, limits combined captured output to 8 MiB by default, and bounds timeout/cancellation cleanup. Internal callers fail on output overflow unless they explicitly select truncation; sandbox and skill results label truncation. Cancellation terminates the original process group, escalating from TERM to KILL. Deliberately detached process groups are not covered by that lifecycle guarantee.
- Persistent host shell sessions preserve working directory and environment across successful commands. Timeout, cancellation, and output overflow discard the old shell before another command starts. Output is bounded and UTF-8 is decoded after byte-level capture.
- Managed background processes share the process-group capture engine without accumulating lifetime output in memory. Logs retain two segments of at most 1 MiB each; reads seek to the tail and are capped at 256 KiB. A rotation/truncation flag discloses limited retention. Stop waits for cancellation cleanup, and cancelled restart tasks cannot launch replacement generations.
- Managed processes use `zsh -f -c` and an allowlisted environment. The host `PATH` is retained, but shell startup files, ambient API keys, and credential-agent variables are not inherited; tools that relied on login-shell configuration need explicit executable/environment configuration. This remains host execution, not OS isolation or a credential broker. Explicit `env` values remain caller configuration, not secret-vault references.
- Persisted PIDs are treated as unowned after XT relaunch. Stop and same-ID restart fail with an ownership error rather than signalling or replacing a possibly unrelated process. Existing background services may still be running and need independent operator verification; PID alone is not recovery proof.
- `LocalSandboxProvider.executeWithMonitoring` now delivers incremental, byte-budgeted stdout/stderr text with separate UTF-8 fragment buffers. Its `@Sendable` callback executes synchronously on the capture worker (final fragments may be flushed by the caller), must return promptly, and must not directly mutate UI state. This API does not by itself add a new UI streaming surface.
- `ResourceUsage.measurementKind=estimated` identifies local CPU/memory estimates. The concurrent-execution limit is enforced; it is not a descendant-process quota, and configured memory/disk values are not OS-enforced quotas.

This is a local execution hardening layer, not a complete capability broker. The desktop app, interactive terminal, managed host processes, and host-mode skill execution are not made OS-isolated by this change. In-process file tools validate canonical path containment, but they are not descriptor-relative race-proof filesystem brokers. Binding Hub-signed action manifests, grants, actual execution, and unified receipts remains separate work. `sandbox-exec` is a deprecated macOS backend and needs replacement/qualification before broader platform or production-isolation claims.

Run the focused executable regression from the repository root:

```bash
bash x-terminal/scripts/ci/xt_execution_safety_regression.sh
```

It compiles the actual owning sources and shared test fixture without requiring the Swift `Testing` module. It checks large dual-stream output, stdin backpressure, output limits, cancellation, descendant cleanup, shell recovery, path escapes, and real OS file/network denial. It requires a host that permits creating a Seatbelt sandbox; nested sandbox restrictions are failures, not skipped isolation evidence. The same fixture is invoked by `ProcessCaptureTests` in `swift test` when the full test toolchain is available.

## Voice As A Paired Surface

Active implementation context:
X-Terminal voice is not just a TTS wrapper over a terminal session.
It is the paired high-trust interaction surface that turns Hub-governed state into something the operator can hear, respond to, and resume safely.

In the current design direction, that means:

- Hub-generated Supervisor briefs can be projected through X-Terminal voice instead of being recomposed as terminal-local summaries
- voice-driven authorization can stay attached to Hub grants, challenge lifecycle, and fail-closed behavior
- repeat, cancel, and mobile-confirmation flows belong to the same guided authorization path rather than being treated as generic chat commands
- post-action follow-up should return to the Hub brief path so spoken status and execution truth do not drift apart

Boundary reminder:

- X-Terminal can host the low-friction voice UX
- X-Terminal does not become the final grant authority
- trust, grant, and policy decisions still terminate in `x-hub/`

## A-Tier, S-Tier, And Heartbeat / Review

Active implementation context:
X-Terminal is also where per-project `A-Tier`, `S-Tier`, and `Heartbeat / Review` start to become visible as governed runtime behavior rather than one vague legacy single-governance slider.

In the current design direction, that means:

- project execution authority is being formalized as explicit `A-Tier` controls instead of collapsing everything into one terminal-local mode switch
- the highest `A-Tier` is still governed execution, not "remove Supervisor and hope for the best"
- Supervisor review can operate at different depths such as pulse, strategic, and rescue review instead of one generic check-in
- review output can be persisted as structured review notes and guidance injections rather than disappearing into chat-only commentary
- corrective guidance can wait for a safe point, require acknowledgement, or escalate into replan / stop behavior depending on risk and confidence
- Supervisor surfaces can span portfolio overview, focused project drill-down, and evidence-backed review context instead of one flat chat view

Boundary reminder:

- more execution authority does not make the project sovereign
- X-Terminal can host the review and correction surface
- Hub clamps, grants, TTL, kill-switch, and audit still remain authoritative

Compatibility note:
the repository still contains older compatibility surfaces such as `manual`, `guided`, and `trusted_openclaw_mode`.
Treat those as active implementation and migration layers, not as the full final governance contract.

## Main Surfaces

| Path | Role |
|---|---|
| `Sources/` | Swift source for UI, session runtime, Hub client, supervisor, and tools |
| `Tests/` | Terminal test targets |
| `scripts/` | Terminal-local gates, probes, fixtures, and support utilities |
| `work-orders/` | Scoped implementation packs and execution references |
| `skills/` | Active repo-local skills used during terminal development |

## Active Entry Points

Run locally:

```bash
bash x-terminal/tools/run_xterminal_from_source.command
```

Build locally:

```bash
cd x-terminal
swift build
```

Export the normalized XT doctor bundle from the latest saved unified doctor report:

```bash
bash x-terminal/tools/run_xterminal_from_source.command --xt-unified-doctor-export --project-root /path/to/workspace
```

Or use the thin repo-level wrapper:

```bash
bash scripts/run_xhub_doctor_from_source.command xt --workspace-root /path/to/workspace --out-json /tmp/xhub_doctor_output_xt.json
```

Or export both Hub and XT doctor outputs into one directory:

```bash
bash scripts/run_xhub_doctor_from_source.command all --workspace-root /path/to/workspace --out-dir /tmp/xhub_doctor_bundle
```

When XT has recent coder usage for the active project, the exported generic doctor bundle includes a structured `project_context_summary` under `session_runtime_readiness`, alongside the original raw `detail_lines`. This makes the exported bundle explain which recent project dialogue window, context depth, and coverage/boundary signals were actually assembled for the project AI.

When XT is carrying Hub-provided prompt-assembly metadata for the latest governed coding turn, the XT-native `session_runtime_readiness` section now also carries a structured `hubMemoryPromptProjection`, and the normalized generic bundle mirrors it as `hub_memory_prompt_projection`. Treat this as Hub-first explainability only: it keeps `projection_source / canonical_item_count / working_set_turn_count / runtime_truth_item_count / runtime_truth_source_kinds` machine-readable, but it does not let XT infer prompt contents locally or bypass constitution / export / policy gates.

When XT has remote Hub snapshot provenance to surface, the XT-native `session_runtime_readiness` section now also carries structured `projectRemoteSnapshotCacheProjection` and `supervisorRemoteSnapshotCacheProjection`, and the normalized generic bundle mirrors them as `project_remote_snapshot_cache_snapshot` and `supervisor_remote_snapshot_cache_snapshot`. Treat them as cache provenance only: they keep `source / freshness / cache_hit / scope / cached_at / age / ttl_remaining` machine-readable, but they do not claim XT cache became durable truth or that Hub-first routing was bypassed.

When XT has role-aware Project AI memory policy truth to project, the XT-native `session_runtime_readiness` section now also carries first-class `projectMemoryPolicyProjection` and `projectMemoryAssemblyResolutionProjection`, and the normalized generic bundle mirrors them as `project_memory_policy` and `project_memory_assembly_resolution`. Treat them as explainability surfaces only: they keep configured/recommended/effective project dialogue/context depth, A-tier memory ceiling, and the final selected/excluded assembly objects machine-readable, but they do not override Hub grant, runtime readiness, policy, TTL, or kill-switch boundaries.

When XT has heartbeat-governed review truth to project, the exported generic doctor bundle also includes a structured `heartbeat_governance_snapshot` under `session_runtime_readiness`. Read it as review explainability only: it keeps `latest_quality_band`, `open_anomaly_types`, the cadence triple, and `next_review_due` machine-readable, but it does not override normal chat memory, project memory routing, or policy truth.

When XT has observed a real remote provider-key routing decision for the requested model, the XT-native `model_route_readiness` section now also carries a structured `providerKeySelectionProjection`, and the normalized generic bundle mirrors it as `provider_key_selection_snapshot`. Treat it as remote key-routing explainability only: it keeps `requestedProvider / requestedModelId / selectedAccountKey / candidates` machine-readable so doctor/report/troubleshoot can replay selected-key, skipped-key, and retry-window truth without re-running scheduler logic locally.

When XT needs one stable route-context envelope instead of per-surface fallback parsing, the XT-native `model_route_readiness` section now also carries `providerKeyRouteContextProjection`, and the normalized generic bundle mirrors it as `provider_key_route_context_snapshot`. Treat it as route-context explainability only: it keeps `modelId / pool / decision / importContextLines / importIssues` machine-readable so doctor, export, settings, and troubleshoot can all read the same selected-key plus import-blocker truth without reverse-parsing raw `detail_lines`. XT troubleshoot should treat this route-context bundle as the primary provider-key input; older split troubleshoot arguments remain compatibility-only wrappers and must not grow new semantics. XT should also prefer Hub RPC-backed refresh/cache for this surface; any fallback read from `hub_provider_keys.json` is compatibility-only cold-start recovery, not the primary truth path.

When XT can compute the current project's effective skill capability truth, the XT-native `skills_compatibility_readiness` section now also carries a structured `skillDoctorTruthProjection`, and the normalized generic bundle mirrors it as `skill_doctor_truth_snapshot`. Treat this as doctor/readiness explainability only: it keeps the `effectiveProfileSnapshot`, `ready / grant_required / local_approval_required / blocked` skill counts, and representative blocked-or-pending skills machine-readable, but it does not itself grant execution authority or bypass Supervisor preflight.

The repo-level `scripts/ci/xhub_doctor_source_gate.sh` summary keeps `source_badge / status_line` for that project-context summary as well, and now also emits `heartbeat_governance_support` with `latest_quality_band / open_anomaly_types / review_pulse_effective_seconds / next_review_kind / next_review_due`, `provider_key_selection_support` with `requested_provider / requested_model_id / selected_account_key / next_retry_at_ms`, plus `durable_candidate_mirror_support` with `status / target / attempted / local_store_role`, so release evidence can reuse the XT explainability snapshot without dropping back to raw `detail_lines`.

When XT has role-aware Supervisor review-memory truth to project, the XT-native `session_runtime_readiness` section now also carries first-class `supervisorMemoryPolicyProjection` and `supervisorMemoryAssemblyResolutionProjection`, and the normalized generic bundle mirrors them as `supervisor_memory_policy` and `supervisor_memory_assembly_resolution`. Treat them as review explainability only: they keep configured/recommended/effective Recent Raw Context and Review Memory Depth, the S-tier review-memory ceiling, and the final selected/excluded assembly objects machine-readable, but they do not grant extra repo/browser/device authority and do not replace Hub policy or clamp surfaces.

When XT has supervisor durable-candidate mirror evidence, the XT-native `session_runtime_readiness` section now also carries a structured `durableCandidateMirrorProjection`, and the normalized generic bundle mirrors it as `durable_candidate_mirror_snapshot`. Treat this as handoff evidence only: it tells you whether XT stayed `local_only`, actually `mirrored_to_hub`, or hit `hub_mirror_failed`, but it does not claim durable promotion or read-source cutover.

When XT has local cache/fallback/edit-buffer provenance to surface, the XT-native `session_runtime_readiness` section now also carries a structured `localStoreWriteProjection`, and the normalized generic bundle mirrors it as `local_store_write_snapshot`. Treat this as XT-local provenance only: it tells you whether the current local state most recently came from `manual_edit_buffer_commit`, `after_turn_cache_refresh`, `derived_refresh`, and similar local write paths, but it does not claim XT local storage became the durable source of truth.

When XT has model-route diagnostics to project, the exported generic doctor bundle also includes a structured `memory_route_truth_snapshot` under `model_route_readiness`. Read `projection_source` and `completeness` first: they tell you whether you are looking at full upstream route truth or an explicit XT partial projection with `unknown` placeholders. The structured snapshot is the primary machine-readable surface; raw `detail_lines` remain only as migration-friendly context.

The XT-native source report envelope is frozen separately in `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`, so the XT app can treat `xt_unified_doctor_report.json` as a first-class contract instead of relying on the downstream generic doctor schema alone. `consumedContracts` should carry `xt.unified_doctor_report_contract.v1` for that source report.

Run the release gate:

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

`XT-G4 / Reliability` now requires three runtime smokes together: `--xt-route-smoke`, `--xt-grant-smoke`, and `--xt-supervisor-voice-smoke`. The voice smoke emits a machine-readable report at `.axcoder/reports/xt_supervisor_voice_smoke.runtime.json`, so release evidence can confirm the phone-like Supervisor path still covers wake, grant challenge, Hub brief playback, and talk-loop resume.

Run the stricter gate mode:

```bash
cd x-terminal
XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh
```

Run only the phone-like Supervisor voice smoke:

```bash
cd x-terminal
swift run XTerminal --xt-supervisor-voice-smoke --project-root "$(pwd)" --out-json .axcoder/reports/xt_supervisor_voice_smoke.runtime.json
```

## Operational Boundaries

- Do not use `archive/x-terminal-legacy/` for build, run, setup, or documentation entrypoints.
- Keep grant authority, pairing authority, and policy enforcement in `x-hub/`.
- Avoid reintroducing duplicate terminal surfaces outside `x-terminal/`.

## Read Next

- `README.md`
- `RELEASE.md`
- `docs/WORKING_INDEX.md`
- `x-terminal/Sources/README.md`
- `x-terminal/scripts/README.md`
- `docs/REPO_LAYOUT.md`
