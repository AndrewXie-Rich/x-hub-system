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

## Project Governance And Supervisor Review

Active implementation context:
X-Terminal is also where per-project `Execution Tier`, `Supervisor Tier`, and `Heartbeat & Review` start to become visible as governed runtime behavior rather than one vague legacy single-governance slider.

In the current design direction, that means:

- project execution authority is being formalized as explicit tiers instead of collapsing everything into one terminal-local mode switch
- the highest execution tier is still governed execution, not "remove Supervisor and hope for the best"
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

The repo-level `scripts/ci/xhub_doctor_source_gate.sh` summary keeps `source_badge / status_line` for that project-context summary as well, and now also emits `durable_candidate_mirror_support` with `status / target / attempted / local_store_role`, so release evidence can reuse the XT explainability snapshot without dropping back to raw `detail_lines`.

When XT has supervisor durable-candidate mirror evidence, the XT-native `session_runtime_readiness` section now also carries a structured `durableCandidateMirrorProjection`, and the normalized generic bundle mirrors it as `durable_candidate_mirror_snapshot`. Treat this as handoff evidence only: it tells you whether XT stayed `local_only`, actually `mirrored_to_hub`, or hit `hub_mirror_failed`, but it does not claim durable promotion or read-source cutover.

When XT has model-route diagnostics to project, the exported generic doctor bundle also includes a structured `memory_route_truth_snapshot` under `model_route_readiness`. Read `projection_source` and `completeness` first: they tell you whether you are looking at full upstream route truth or an explicit XT partial projection with `unknown` placeholders. The structured snapshot is the primary machine-readable surface; raw `detail_lines` remain only as migration-friendly context.

The XT-native source report envelope is frozen separately in `docs/memory-new/schema/xt_unified_doctor_report_contract.v1.json`, so the XT app can treat `xt_unified_doctor_report.json` as a first-class contract instead of relying on the downstream generic doctor schema alone. `consumedContracts` should carry `xt.unified_doctor_report_contract.v1` for that source report.

Run the release gate:

```bash
bash x-terminal/scripts/ci/xt_release_gate.sh
```

Run the stricter gate mode:

```bash
cd x-terminal
XT_GATE_MODE=strict bash scripts/ci/xt_release_gate.sh
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
