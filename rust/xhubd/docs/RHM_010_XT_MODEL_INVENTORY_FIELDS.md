# RHM-010 XT Model Inventory Field Contract

Status: implemented for XT fixture/presentation parity on 2026-05-05.

XT consumes only the secret-free `xhub.model_inventory.v1` fields listed here.
It must not read provider token files, auth files, API keys, refresh tokens, or
provider passwords while projecting this inventory.

## Top Level

- `schema_version`
- `updated_at_ms`
- `remote_models`
- `local_models`

## Remote Rows

- `model_id`
- `provider`
- `provider_host`
- `family_key`
- `pool_id`
- `availability_state`
- `available_account_count`
- `total_account_count`
- `blocking_reason_code`
- `next_retry_at_ms`

XT maps a remote row to a visible `HubModel` only as loaded when
`availability_state=ready`, `available_account_count>0`, and
`blocking_reason_code` is empty. Quota/cooldown and scope/permission blockers
stay visible as unavailable truth states.

## Local Rows

- `model_id`
- `display_name`
- `family_key`
- `artifact_path`
- `format`
- `artifact_size_bytes`
- `checksum`
- `quantization`
- `runtime_provider`
- `availability_state`
- `blocking_reason_code`
- `capabilities`
- `memory_risk`
- `duplicate_artifact_of`
- `runtime_preflight.runtime_provider`
- `runtime_preflight.availability_state`
- `runtime_preflight.blocking_reason_code`
- `runtime_preflight.supported_format`
- `runtime_preflight.side_effect_free`
- `runtime_preflight.runtime_updated_at_ms`
- `runtime_preflight.capability_tags`
- `runtime_preflight.runtime_missing_requirements`

XT maps a local row to loaded only when both row and runtime preflight are
ready. Runtime missing/stale and capability mismatch blockers stay visible as
unavailable truth states.

## Fixtures

XT fixture coverage lives in:

- `x-hub-system/x-terminal/Tests/Fixtures/RustModelInventory/remote_quota_blocked.json`
- `x-hub-system/x-terminal/Tests/Fixtures/RustModelInventory/remote_missing_scope.json`
- `x-hub-system/x-terminal/Tests/Fixtures/RustModelInventory/local_runtime_missing.json`
- `x-hub-system/x-terminal/Tests/Fixtures/RustModelInventory/local_capability_mismatch.json`

Validation:

```bash
swift test --filter 'XTModelInventoryTruthPresentationTests|XTVisibleHubModelInventoryTests|XTRustModelInventoryProjectionTests'
```
