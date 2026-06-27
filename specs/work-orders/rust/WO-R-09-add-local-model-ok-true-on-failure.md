# WO-R-09 — `apply_local_model_registry_repair_value` returns `"ok": true` on failure

**Owner:** AI · **Effort:** ~1 hour · **Severity:** P1 (API contract) · **Dependencies:** consider with WO-R-05

## Why this matters

`apply_local_model_registry_repair_value` (model_bridge.rs:~1113) returns mixed success signaling:

- On `artifact_not_found`: `{"ok": true, "accepted": false, "status": "artifact_not_found"}`
- On `artifact_path_required`: `{"ok": true, "accepted": false, "status": "artifact_path_required"}`
- On `registry_write_failed`: `{"ok": false, "status": "registry_write_failed"}`

Clients that check `response.ok` as their primary success signal — the convention used elsewhere in the registry surface — treat the validation failures as successful operations with `accepted: false` happening to mean "we accepted your request but didn't act on it." Operators reading the response see `ok: true` and assume the model registered.

This is a contract bug, not a security bug. Real cost: silent partial failures in operator workflows; CI scripts that report green when they should report red.

## Scope

**In scope:**
- `apply_local_model_registry_repair_value` (model_bridge.rs:~1113)
- All return paths in that function (validation, accept, write failure, success)

**Out of scope:**
- The broader convention question (`ok` vs HTTP status code vs `accepted`). This WO standardizes within this one function. Cross-function consistency is a separate cleanup.

## Deliverables

1. Define the contract: **`ok: true` means "the requested action was applied and produced a usable result."** Anything else is `ok: false`.
2. Update all return paths:
   - Validation failures (`artifact_not_found`, `artifact_path_required`, `artifact_path_outside_runtime`): `{"ok": false, "status": "<reason>", "details": "..."}`
   - Successful registration: `{"ok": true, "status": "registered", "model_id": "...", "version": N}`
   - Already-registered (no-op): `{"ok": true, "status": "no_change", ...}` — operator sees green because nothing failed.
3. Backward compatibility: any caller that previously read `accepted` MAY continue to receive it as a secondary field, but `ok` MUST become the authoritative success signal.

## Acceptance criteria

1. New test: invalid `artifact_path` → response has `ok: false`.
2. New test: nonexistent path → response has `ok: false`.
3. New test: legitimate registration → response has `ok: true`.
4. New test: re-registering an already-present model → response has `ok: true, status: "no_change"`.
5. Existing tests updated if they relied on `ok: true, accepted: false`.

## References (read first)

- `apply_local_model_registry_repair_value` (model_bridge.rs:~1113)
- Any caller (CLI, HTTP route) that reads the response — find via grep and verify they check `ok` not `accepted`
- The `registry_write_failed` branch — its `ok: false` is the model to follow

## Anti-patterns

- **Do NOT add an `errors: [...]` array as the success indicator.** `ok: bool` is unambiguous; alternate signaling drifts.
- **Do NOT change the HTTP status code** as the primary signal. Many internal callers don't see status codes (they see only the body). Body must self-describe.
- **Do NOT keep `accepted: false` as the only signal of failure.** That's the bug being fixed.

## Handoff notes

Consider shipping with WO-R-05 since both touch `apply_local_model_registry_repair_value`. If they're combined, the resulting PR fixes both the path-traversal security gap and the success-signaling bug in one go. The reviewer sees a coherent "this function is now correct" diff.
