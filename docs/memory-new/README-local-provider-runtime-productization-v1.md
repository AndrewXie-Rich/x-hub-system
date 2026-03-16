# X-Hub Local Provider Runtime Productization README

Last updated: `2026-03-15`

Scope:
- `LPR-W3-05` Provider-aware Warmup / Unload / Instance Lifecycle
- `LPR-W3-08` Task-aware Local Model Routing / Use-For Binding
- `LPR-W3-07` Runtime Monitor / Useful Telemetry
- `LPR-W3-06` Task-aware Bench v2 / Capability Summary
- `LPR-W4-01..09` LM Studio-aligned provider-pack, load-config, model-library, runtime-console, `mlx_vlm`, `llama.cpp` productization

This document is the operator-facing README for the next local-model productization phase of X-Hub.
Its purpose is simple: turn the current "local runtime can execute some non-MLX tasks" state into a complete Hub product path where users can import a local model, bind it to a real task, warm it up when needed, monitor it while it runs, and bench it with results they can actually interpret.

## Why This Work Exists

X-Hub already has a meaningful local-provider foundation, but the product loop is not closed yet.

What is already true:
- MLX text generation path exists and remains the legacy compatibility baseline.
- Local Provider Runtime already supports non-MLX task execution for `embedding`, `speech_to_text`, and `vision_understand` preview paths.
- Per-device load profile and context-length controls were added in `LPR-W3-04-A/B/C`, so runtime identity is no longer only `model_id`; it can now resolve by effective load profile and device.

What is not finished yet:
- `LPR-W3-05 / W3-06 / W3-07 / W3-08` are now delivered under `LPR-G5`, but `LPR-G6` still needs require-real smoke with actual local model directories.
- `process_local` providers intentionally remain on-demand; only `runtime_process` providers can truthfully expose Hub `Warmup / Unload`.
- resident lifecycle, bench, and monitor now share one control plane, but they still need a real-machine validation pass for memory pressure and eviction behavior.

The product target is not "support more loaders."
The product target is "make local models governable and useful through one Hub control plane."

## External Reference Baseline

This line should explicitly reference both `lmstudio-js` and `opencode`, but only as pattern sources.
X-Hub should not replace its resident runtime architecture with either project wholesale.

What to borrow from LM Studio:
- typed separation between disk model info and loaded instance info, as seen in [ModelInfoBase.ts](/Users/andrew.xie/Documents/AX/Opensource/lmstudio-js-main/packages/lms-shared-types/src/ModelInfoBase.ts)
- first-class load config, especially `contextLength`, device targeting, progress, and TTL semantics, as seen in [ModelNamespace.ts](/Users/andrew.xie/Documents/AX/Opensource/lmstudio-js-main/packages/lms-client/src/modelShared/ModelNamespace.ts), [baseModelBackendInterface.ts](/Users/andrew.xie/Documents/AX/Opensource/lmstudio-js-main/packages/lms-external-backend-interfaces/src/baseModelBackendInterface.ts), [LLMLoadModelConfig.ts](/Users/andrew.xie/Documents/AX/Opensource/lmstudio-js-main/packages/lms-shared-types/src/llm/LLMLoadModelConfig.ts), and [EmbeddingLoadModelConfig.ts](/Users/andrew.xie/Documents/AX/Opensource/lmstudio-js-main/packages/lms-shared-types/src/embedding/EmbeddingLoadModelConfig.ts)
- domain-specific model metadata where the model and the loaded instance each expose effective context fields, as seen in [EmbeddingModelInfo.ts](/Users/andrew.xie/Documents/AX/Opensource/lmstudio-js-main/packages/lms-shared-types/src/embedding/EmbeddingModelInfo.ts)

What to borrow from OpenCode:
- provider-agnostic `providerID + modelID` identity and capability-first model metadata, as seen in [provider.ts](/Users/andrew.xie/Documents/AX/Opensource/opencode/opencode/packages/opencode/src/provider/provider.ts) and [types.gen.ts](/Users/andrew.xie/Documents/AX/Opensource/opencode/opencode/packages/sdk/js/src/gen/types.gen.ts)
- explicit `capabilities`, `modalities`, and `limit.context / limit.output` shape for model picker, routing, and UI filtering, as seen in [models.ts](/Users/andrew.xie/Documents/AX/Opensource/opencode/opencode/packages/opencode/src/provider/models.ts)
- transform-time fail-closed behavior for unsupported modalities instead of silent best effort, as seen in [transform.ts](/Users/andrew.xie/Documents/AX/Opensource/opencode/opencode/packages/opencode/src/provider/transform.ts)

What X-Hub should not borrow:
- do not replace the current resident daemon + provider registry with LM Studio's full backend/client contract
- do not import OpenCode's cloud-provider auth/cost assumptions into local-runtime UX
- do not collapse multimodal local models back into a generic text-only picker

What the 2026-03-15 local LM Studio install confirmed:
- it really ships as `daemon + workers + engine extensions`, not one monolithic runtime
- the current local install exposes dedicated workers for LLM, embedding, ASR, and image generation
- the current local install already carries separate engine manifests for `mlx-llm` and `llama.cpp`
- the MLX engine release data explicitly tracks `mlx-vlm`, which is the strongest signal that X-Hub should stop treating multimodal MLX as "just another text-only MLX edge case"
- the CLI already treats `context-length / gpu / parallel / ttl / identifier` as explicit load parameters, which matches the direction X-Hub has already started with `load_profile_hash / effective_context_length`

Direct X-Hub mapping:
- model catalog should expose stable provider-aware identity, capability/modality fields, and context limits
- paired terminal devices should own load-profile overrides such as `context_length`, later extensible to GPU/offload parameters
- runtime loaded instances should remain keyed by `provider + model_id + device_id + load_profile_hash`
- warmup, bench, and monitor should all read the same loaded-instance truth instead of inventing separate state

## What We Should Stop Rebuilding Ourselves

The next local-model phase should explicitly avoid repeating product problems LM Studio already solved reasonably well.

Stop rebuilding:
- a manual backend picker as the normal user path
- one-off context-length widgets that are detached from runtime instance identity
- hidden runtime state where `loaded`, `warm`, and `currently usable` mean different things in different screens
- model-library cards that show only format/backend but not actual task capability
- a bench page that knows nothing about the currently loaded instance and runtime pressure

Start reusing the same product shape:
- capability-first model library
- typed load config
- loaded-instance inventory as a first-class surface
- provider pack / engine manifest inventory
- one runtime operations console for warmup / unload / evict / diagnostics
- bench + monitor fused into one explainable capability view

## Current Reality On 2026-03-15

If the question is "can Hub already load non-MLX models," the answer is:
- yes for the supported local task kinds and product path
- with the remaining caveat that require-real smoke is still pending

If the question is "can Hub UI already use Bench to evaluate these models," the answer is:
- yes
- Bench v2 is delivered, but it still needs require-real fixture runs on actual user model directories

In practical terms:
- runtime-side Transformers execution exists for the currently supported local task kinds
- per-device effective context and load-profile resolution exists
- Hub now has the common lifecycle, routing, monitor, and bench layers needed for normal operators
- the remaining gap is proof on real local model directories rather than missing product surfaces

## What Already Landed

The following groundwork is already delivered and is the direct prerequisite for this README's scope:

### `LPR-W3-04-A` Load Profile Schema / Manifest Surface

Delivered outcome:
- local model manifests can describe load profile choices and context-length intent
- schema and parsing path are frozen enough for UI and runtime to share the same identity model

### `LPR-W3-04-B` Hub / Device Settings Integration

Delivered outcome:
- Hub and paired terminal surfaces can carry per-device load-profile settings
- context length is no longer a hidden implementation detail

### `LPR-W3-04-C` Runtime Instance Identity / Cache Isolation

Delivered outcome:
- runtime resolves `effectiveLoadProfile`, `effectiveContextLength`, `effectiveContextSource`, `loadProfileHash`, and `instanceKey`
- scheduler tracks per-instance identity instead of silently mutating one shared instance
- Transformers embedding and ASR caches now key on `instance_key`
- node-side local task calls now pass `device_id`

Why this matters:
- `LPR-W3-05-A` only makes sense after instance identity is explicit
- warmup/unload/bench/monitor all depend on stable instance identity

## Next Tranche After W3

The W3 chain gave X-Hub the minimum complete local-model loop:
- provider-aware lifecycle
- task-aware routing
- runtime monitor
- task-aware bench

That is enough to stop being MLX-only in practice.
It is not yet enough to become the best local-model product surface.

The next tranche is therefore fixed as:

1. `LPR-W3-03` require-real closure
2. `LPR-W4-01` managed provider pack / engine manifest
3. `LPR-W4-02` managed runtime bundle / dependency isolation
4. `LPR-W4-03` typed load config + loaded instance contract
5. `LPR-W4-04` Add Model / library UX simplification
6. `LPR-W4-05` loaded models / runtime operations console
7. `LPR-W4-06` bench + monitor fusion
8. `LPR-W4-07` `mlx_vlm` provider pack
9. `LPR-W4-08` `llama.cpp` / GGUF provider pack
10. `LPR-W4-09` product exit / migration / require-real closure

Why this order is correct:
- provider packs come before new backends because otherwise `mlx_vlm` and `llama.cpp` will become one-off integrations
- typed load config comes before UI because otherwise the UI will hard-code behavior again
- runtime operations console comes before bench fusion because the user must first see loaded-instance truth
- `mlx_vlm` comes before `llama.cpp` because the current user-critical target is real local MLX vision success, not broad format count

## Recommended Execution Order

The next chain should be executed in this exact order:

1. `LPR-W3-05` Provider-aware Warmup / Unload / Instance Lifecycle
2. `LPR-W3-08` Task-aware Local Model Routing / Use-For Binding
3. `LPR-W3-07` Runtime Monitor / Useful Telemetry
4. `LPR-W3-06` Task-aware Bench v2 / Capability Summary

Why this order is correct:
- warmup comes first because the system needs an explicit lifecycle before UI, monitor, or bench can speak truthfully about loaded instances
- routing comes next because users need a first-class way to say what each model is for
- monitor comes before bench because bench failures and fallback results are only useful when runtime truth is visible
- bench comes last because it depends on lifecycle, routing, and telemetry to produce explainable output instead of isolated numbers

## Workstream Summary

| Workstream | Status | Immediate Value | Depends On | Blocks |
|---|---|---|---|---|
| `LPR-W3-05` | `delivered` | gives Hub a real lifecycle control plane | `LPR-W3-04-C` | require-real smoke |
| `LPR-W3-08` | `delivered` | lets users bind models to real tasks | `LPR-W3-05` | require-real smoke |
| `LPR-W3-07` | `delivered` | gives operators usable runtime truth | `LPR-W3-05`, `LPR-W3-08` | require-real smoke |
| `LPR-W3-06` | `delivered` | turns bench into task-aware capability summary | `LPR-W3-05`, `LPR-W3-07`, `LPR-W3-08` | require-real fixture runs |

## Detailed Execution Plan

The breakdown below preserves the original execution granularity.
The authoritative current status is the summary table above plus the lane board and evidence files.

### `LPR-W3-05` Provider-aware Warmup / Unload / Instance Lifecycle

Goal:
- upgrade Hub model actions from legacy MLX-only command semantics to provider-aware `Warmup / Unload / Evict`

Done means:
- non-MLX local models are not blocked in Hub just because they are not MLX
- runtime can express loaded instances as first-class objects
- providers that cannot truly unload must say so explicitly

### `LPR-W3-05-A` Local Runtime Warmup / Unload Contract

Status:
- `planned`
- this is the next implementation start point

Why this comes first:
- Warmup/UI/Routing/Bench/Monitor all depend on a shared lifecycle contract
- without this step, later UI work would either lie or keep special-casing MLX forever

Paths:
- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/python-runtime/python_service/providers/base.py`
- `x-hub/python-runtime/python_service/providers/mlx_provider.py`
- `x-hub/python-runtime/python_service/providers/transformers_provider.py`
- `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`

Definition of done:
- Local Provider Runtime supports `warmup_local_model`
- Local Provider Runtime supports `unload_local_model`
- Local Provider Runtime supports `evict_local_instance`
- warmup returns at least `provider / model_id / task_kinds / instance_key / device_backend / cold_start_ms`
- unsupported provider or unsupported task fails closed with machine-readable reason
- legacy MLX `model_command` remains compatible, but it is no longer the only recommended control path

Execution steps:
1. add lifecycle contract methods to `providers/base.py` with fail-closed defaults
2. implement Transformers warmup path for task kinds that already have real runtime support
3. implement Transformers unload and evict semantics around cached instances
4. report `unsupported` or `preview_only` explicitly for tasks that do not yet have resident lifecycle support
5. keep MLX legacy path compatible without pretending MLX already supports the full new lifecycle contract
6. extend local runtime command handling so Node can call lifecycle operations directly
7. extend runtime IPC parsing to preserve lifecycle results and loaded-instance inventory
8. add targeted compat tests and machine-readable evidence

Expected evidence:
- `build/reports/lpr_w3_05_a_warmup_contract_evidence.v1.json`

### `LPR-W3-05-B` Hub UI Warmup / Unload Generalization

Status:
- `planned`

Goal:
- remove the Hub-side assumption that only legacy MLX models can participate in explicit load actions

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/AIRuntimeStatus.swift`

Definition of done:
- `Load` is generalized to `Warmup` for provider-aware models
- `Unload` is only shown when the provider truthfully supports instance lifecycle
- failure strings no longer hard-code legacy MLX wording
- UI distinguishes `warmable`, `ephemeral_on_demand`, and `mlx_legacy`

Execution steps:
1. remove MLX-only action gating from model action resolution
2. add capability-driven action labels and disabled-state reasons
3. render lifecycle state returned by runtime instead of inferring from provider name
4. preserve clear fallback messaging for legacy MLX-only paths
5. add UI tests or state-shape tests where the codebase already has schema coverage

Expected evidence:
- `build/reports/lpr_w3_05_b_hub_warmup_ui_evidence.v1.json`

### `LPR-W3-05-C` Loaded Instance Inventory / Idle Eviction Semantics

Status:
- `planned`

Goal:
- make loaded instances visible and auditable so unload, monitor, bench, and future idle eviction all have the same truth source

Paths:
- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/python-runtime/python_service/providers/transformers_provider.py`
- `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`

Definition of done:
- provider status exposes `loaded_instances[]`
- each instance carries `instance_key / model_id / task_kinds / load_profile_hash / effective_context_length / loaded_at / last_used_at`
- `resident` and `ephemeral` are clearly distinguishable
- idle eviction is machine-readable and never silent

Execution steps:
1. add loaded-instance metadata to provider caches
2. surface instance inventory in runtime status output
3. preserve stable identity fields between provider, runtime, and IPC layers
4. define explicit eviction reason codes
5. verify that status output matches scheduler truth

Expected evidence:
- `build/reports/lpr_w3_05_c_loaded_instance_inventory_evidence.v1.json`

### `LPR-W3-08` Task-aware Local Model Routing / Use-For Binding

Goal:
- let users bind imported models to real tasks instead of relying on environment variables, implicit favorites, or hidden fallback rules

Done means:
- the system can explain why a specific model was chosen for a specific task on a specific device

### `LPR-W3-08-A` Task Routing Settings Schema v2

Status:
- `planned`

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/`
- `x-hub/grpc-server/hub_grpc_server/src/mlx_runtime_ipc.js`
- `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`

Definition of done:
- routing store supports `task_kind -> model_id`
- routing store can optionally support `device_id + task_kind -> model_id`
- existing `routing_settings.json` remains readable
- source trace distinguishes `hub_default / device_override / request_override / auto_selected`

Execution steps:
1. freeze schema and backward-compat read path
2. define route-source precedence model
3. add shared read/write helpers where Hub and runtime both need them
4. verify schema migration does not break old installs

Expected evidence:
- `build/reports/lpr_w3_08_a_task_routing_schema_evidence.v1.json`

### `LPR-W3-08-B` Hub `Use For...` Binding UI

Status:
- `planned`

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- `x-terminal/Sources/Hub/HubModels.swift`

Definition of done:
- model cards support `Use For...`
- at minimum, users can bind `Generate / Embedding / ASR / Vision / OCR`
- paired terminal view can show device-level override
- UI shows routing source clearly

Execution steps:
1. add per-task binding actions to the model surface
2. add view-state model for hub default and device override
3. render source trace in a user-readable way
4. prevent invalid task bindings for unsupported model capabilities

Expected evidence:
- `build/reports/lpr_w3_08_b_use_for_binding_ui_evidence.v1.json`

### `LPR-W3-08-C` Node / Runtime Local Task Resolution

Status:
- `planned`

Paths:
- `x-hub/grpc-server/hub_grpc_server/src/services.js`
- `x-hub/grpc-server/hub_grpc_server/src/local_embeddings.js`
- `x-hub/grpc-server/hub_grpc_server/src/local_audio.js`
- `x-hub/grpc-server/hub_grpc_server/src/local_vision.js`

Definition of done:
- local embedding, ASR, vision, and OCR all resolve through routing store
- priority order is `request_override > device_override > hub_default > auto_selected`
- route miss returns explainable deny
- audit captures route source and resolved model id

Execution steps:
1. add shared routing resolver at Node entry points
2. replace scattered env-based selection logic
3. emit route source in request audit trail
4. verify deny behavior stays fail-closed

Expected evidence:
- `build/reports/lpr_w3_08_c_task_resolution_evidence.v1.json`

### `LPR-W3-07` Runtime Monitor / Useful Telemetry

Goal:
- expose the runtime facts users actually need to judge readiness, diagnose slowness, and understand fallback behavior

Done means:
- Hub can tell the user not just that a model exists, but what it is doing, what is loaded, what is queued, and why a path is slow or degraded

### `LPR-W3-07-A` Runtime Monitor Snapshot v1

Status:
- `planned`

Paths:
- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/python-runtime/python_service/local_provider_scheduler.py`
- `x-hub/grpc-server/hub_grpc_server/src/local_runtime_ipc.js`

Definition of done:
- snapshot contains `providers / active_tasks / loaded_instances / queue / last_errors / fallback_counters`
- structure remains compatible with old `ai_runtime_status.json`
- active task can link to `request_id / model_id / instance_key`
- missing memory or queue data is rendered as explicit `unknown` or `0`, never fake green

Execution steps:
1. freeze snapshot structure
2. merge scheduler and provider truth into one runtime view
3. include active-task identity and queue metadata
4. include fallback state and last error in machine-readable form
5. verify old status readers do not crash

Expected evidence:
- `build/reports/lpr_w3_07_a_runtime_monitor_snapshot_evidence.v1.json`

### `LPR-W3-07-B` Hub Runtime Monitor View

Status:
- `planned`

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- `x-terminal/Sources/UI/`

Definition of done:
- Hub UI shows active tasks, loaded instances, queue wait, memory, fallback mode, and last error
- key fields can be copied
- view does not assume there are exactly two providers
- warm/cold and readiness still show even when there are no active tasks

Execution steps:
1. add runtime monitor state model in Hub store
2. build a provider-agnostic runtime status view
3. surface copyable diagnostic fields
4. ensure empty-state behavior still communicates readiness truth

Expected evidence:
- `build/reports/lpr_w3_07_b_runtime_monitor_ui_evidence.v1.json`

### `LPR-W3-07-C` Operator / Diagnostics Export

Status:
- `planned`

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubDiagnosticsBundleExporter.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/HubStore.swift`
- `docs/memory-new/`

Definition of done:
- diagnostics bundle exports runtime monitor snapshot
- operator summary can copy key runtime facts
- redact rules cover request payload and input path
- diagnostics can explain `why_slow / why_failed / why_cpu_fallback`

Execution steps:
1. add monitor snapshot to diagnostics bundle
2. add summary extraction for operator-friendly review
3. apply redact rules before export
4. verify exported evidence stays machine-readable

Expected evidence:
- `build/reports/lpr_w3_07_c_monitor_export_evidence.v1.json`

### `LPR-W3-06` Task-aware Bench v2 / Capability Summary

Goal:
- turn Bench from old MLX text-speed output into a cross-task capability summary that helps users choose the right local model

Done means:
- users can bench a model for the task they actually care about
- bench output is explainable, not just raw timing noise

### `LPR-W3-06-A` Bench Schema v2 / Storage Migration

Status:
- `planned`

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHubCore/ModelBench.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/ModelStore.swift`

Definition of done:
- bench results are keyed by `model_id + task_kind + load_profile_hash + fixture_profile`
- schema contains `latency / throughput / peak_memory / fallback_mode / verdict / notes`
- old bench files remain readable
- legacy records are labeled `legacy_text_bench`

Execution steps:
1. freeze schema v2
2. add legacy read compatibility
3. define task-aware summary fields and verdicts
4. ensure new storage keys align with load-profile identity

Expected evidence:
- `build/reports/lpr_w3_06_a_bench_schema_v2_evidence.v1.json`

### `LPR-W3-06-B` Runtime Bench Adapters

Status:
- `planned`

Paths:
- `x-hub/python-runtime/python_service/relflowhub_local_runtime.py`
- `x-hub/python-runtime/python_service/providers/mlx_provider.py`
- `x-hub/python-runtime/python_service/providers/transformers_provider.py`
- `x-hub/grpc-server/hub_grpc_server/src/`

Definition of done:
- text bench still supports real MLX execution
- embedding, ASR, vision, and OCR bench return at least `cold_start / single_run_latency / batch_or_fixture_profile`
- fallback bench is explicitly marked `fallback_only`
- bench execution does not pollute normal request-path audit or quota semantics

Execution steps:
1. define a unified bench command path in local runtime
2. implement provider-specific bench adapters by task kind
3. preserve MLX real-run bench behavior
4. label fallback and unsupported states explicitly
5. isolate bench accounting from normal request accounting

Expected evidence:
- `build/reports/lpr_w3_06_b_runtime_bench_adapters_evidence.v1.json`

### `LPR-W3-06-C` Hub Quick Bench UX / Recommendation Summary

Status:
- `planned`

Paths:
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/MainPanelView.swift`
- `x-hub/macos/RELFlowHub/Sources/RELFlowHub/SettingsSheetView.swift`

Definition of done:
- model card shows latest bench summary
- clicking Bench can choose task and fixture profile
- UI shows verdicts like `Fast / Balanced / Heavy / Preview only / CPU fallback`
- failures show reason code, not only generic red text

Execution steps:
1. add task-aware bench invocation UI
2. add summary renderer for verdict and notes
3. display last bench result on model surface
4. render structured failure reasons

Expected evidence:
- `build/reports/lpr_w3_06_c_hub_quick_bench_ux_evidence.v1.json`

### `LPR-W3-06-D` Require-Real Bench Fixtures / Release Gate

Status:
- `planned`

Paths:
- `docs/memory-new/`
- `scripts/`

Definition of done:
- bench v2 has at least one real fixture path for supported task kinds
- evidence generation and validation scripts can run
- release gate can distinguish synthetic-only and real-sample coverage

Execution steps:
1. define minimum real fixtures for each supported task kind
2. wire bench evidence generation
3. add validation script and release hinting
4. keep fixture availability failures explicit

Expected evidence:
- `build/reports/lpr_w3_06_d_require_real_bench_evidence.v1.json`

## Whole-Chain Product Definition Of Done

This work is complete only when the full user path is true:

1. a user can import a local model and the manifest truthfully describes what it can do
2. the user can set load profile and context length, including per-device override when needed
3. the user can bind that model to a real task with `Use For...`
4. the user can warm the model up when the provider supports resident lifecycle
5. the user can see whether the model is warm, busy, queued, in fallback, or failed
6. the user can run Bench for the task they care about and get an interpretable verdict
7. diagnostics export can explain why a path was slow, failed, or fell back to CPU

If any one of those is missing, the product loop is still incomplete.

For the next tranche, add three more conditions:

8. the operator can see which provider pack and which runtime bundle each loaded instance is using
9. the user does not need to manually choose backend/provider in the normal Add Model flow
10. at least one real MLX vision model and one real GGUF model can complete `add -> load -> route -> bench -> monitor`

## Known Gaps And Guardrails

Known gaps:
- legacy `relflowhub_mlx_runtime.py` file-IPC text generation path is still not fully aligned with load-profile-aware lifecycle semantics
- not every provider/task combination should pretend to support resident warmup
- vision and OCR may remain `preview_only` or `unsupported` on some providers until runtime support is real

Guardrails:
- unsupported paths must fail closed
- providers that are only on-demand must be labeled `ephemeral_on_demand`
- no status view should fake green when queue, memory, fallback, or error data is unknown
- bench results must preserve task kind and load-profile identity, or they will mislead users
- provider-pack absence, runtime-bundle absence, and model-format mismatch must be different failure reasons
- visual MLX support should land as a dedicated provider path, not as a hidden Transformers fallback
- GGUF support should land as a dedicated provider path, not as "try importing into Transformers and hope"

## Immediate Next Action

The next implementation entry point is:

- `LPR-W3-03` require-real closure, then `LPR-W4-01` Managed Provider Pack / Engine Manifest

Reason:
- W3 is already functionally closed enough for real use, but not yet release-credible without require-real
- once require-real is in place, provider-pack inventory becomes the single highest-leverage next step
- that step prevents `mlx_vlm`, `llama.cpp`, and future local runtimes from repeating the current ad-hoc dependency pattern
