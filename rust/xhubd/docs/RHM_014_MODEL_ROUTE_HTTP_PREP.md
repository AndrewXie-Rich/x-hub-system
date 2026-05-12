# RHM-014 Model Route HTTP Prep

Status: implemented 2026-05-06

## Goal

Expose Rust model route decisions through a warm-daemon HTTP surface so Node/XT
can later run default-off route authority prep without invoking a cold CLI for
each decision.

This is a read-only prep surface. It does not change Node `HubAI.Generate`,
provider-key routing, local runtime dispatch, XT model selection, or production
authority.

## Endpoint

```text
GET  /model/route
POST /model/route
```

Supported request fields:

- `runtime_base_dir` / `runtimeBaseDir`
- `now_ms` / `nowMs`
- `task_type` / `taskType` / `task`
- `model_id` / `modelId`
- `preferred_model_id` / `preferredModelId`
- `required_capability` / `requiredCapability`
- `required_capabilities` / `requiredCapabilities`
- `capabilities`
- `privacy_mode` / `privacyMode`
- `cost_preference` / `costPreference`

Responses use the existing `xhub.model_route_decision.v1` schema from
`xhubd model route`.

## Validation

Command:

```bash
bash "tools/model_route_http_smoke.command" --timeout-ms 30000
```

The smoke starts an isolated Rust daemon and proves:

- remote route can select a ready provider model
- local-only route can select a ready local model
- provider secret material is not serialized
- the smoke only observes route decisions and does not change production
  authority

Observed result:

- remote selected route kind: `remote`
- remote selected model id: `gpt-5.5`
- local selected route kind: `local`
- local selected model id: `local.summary`
- authority changed: `false`
