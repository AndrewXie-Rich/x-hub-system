# WO-R-05 — Model artifact path traversal in local-model registry repair

**Owner:** AI · **Effort:** ~2 hours · **Severity:** P0 (security) · **Dependencies:** none

## Why this matters

`apply_local_model_registry_repair_value` accepts an `artifact_path` from the request body, passes it through `resolve_runtime_relative_path_for_repair` (which only `join()`s relative paths against `runtime_base_dir` — it does NOT canonicalize or block `..`), checks only `path.exists()`, then writes the verbatim path into `models_catalog.json` and `models_state.json` as the registered model's `modelPath`.

**Concrete attack:** POST `/model/repair-apply` with:
```json
{
  "action": "add_local_model:text_generate",
  "confirm": true,
  "confirmation_token": "confirm:add_local_model:text_generate",
  "artifact_path": "/etc"
}
```

`confirmation_token` is the fully-predictable string `confirm:<action>` derived from the request — it is NOT a secret. `/etc` exists. The local model registry now contains an entry whose `modelPath` is `/etc`. The next time the runtime tries to load this "model", behaviour depends on the downstream loader: best case a load failure; worst case the loader does something useful with `/etc`'s contents (e.g., embeds them, attempts to mmap them).

The same shape works with `..` traversal: `artifact_path: "../../../some/sibling/directory"`.

## Scope

**In scope:**
- `apply_local_model_registry_repair_value` (model_bridge.rs:~1113)
- `resolve_runtime_relative_path_for_repair` (model_bridge.rs:~1198)
- The `confirmation_token` generation and check
- Path validation: absolute paths, `..` segments, symlinks

**Out of scope:**
- Renaming the action or restructuring the request shape — too invasive.
- Rewriting the model registry storage — independent concern.

## Deliverables

1. **Reject absolute `artifact_path` values.** Only relative paths are accepted. If absolute, return `artifact_path_must_be_relative`.
2. **Canonicalize before checking `.exists()`.** Use `std::fs::canonicalize` on `runtime_base_dir.join(artifact_path)`. After canonicalization, verify the result is still a descendant of `runtime_base_dir` via `path.starts_with(&runtime_base_dir)`. Otherwise return `artifact_path_outside_runtime`.
3. **Reject `..` segments at parse time** (defense in depth), even though canonicalization would catch escape attempts.
4. **Make `confirmation_token` a real secret.** Options:
   - Generate a per-request token from server-side random + action + nonce, return it in a `prepare` response, require it in the `apply` request.
   - At minimum, derive it from action + a server-side secret + a timestamp window. The current `confirm:<action>` pattern provides no replay protection at all.
   The preferred approach is the prepare/apply pattern; if that's too invasive for this WO, at minimum make the token unguessable.
5. Reject symlinks pointing outside `runtime_base_dir` — `canonicalize` resolves symlinks, so the `starts_with` check from step 2 handles this.

## Acceptance criteria

1. New test: POST with `artifact_path: "/etc"` returns `artifact_path_must_be_relative` (or `artifact_path_outside_runtime` if you choose to canonicalize first).
2. New test: POST with `artifact_path: "../foo"` is rejected.
3. New test: POST with `artifact_path: "models/legitimate.bin"` (relative, under runtime_base_dir) succeeds.
4. New test: POST with a stale or wrong confirmation_token is rejected.
5. New test: symlink inside `runtime_base_dir` pointing outside is rejected.

## References (read first)

- `apply_local_model_registry_repair_value` (model_bridge.rs:~1113)
- `resolve_runtime_relative_path_for_repair` (model_bridge.rs:~1198) — the current "validation"
- Existing `confirmation_token` callers for the token-generation pattern (if one exists already)
- `runtime_base_dir` source in `HubConfig`

## Anti-patterns

- **Do NOT add a `safe_paths` allowlist config option.** Allowlists for paths get out of date the moment the runtime layout shifts. Use canonicalize + descendant check.
- **Do NOT validate by string prefix.** `runtime_base_dir.to_str().unwrap()` prefix-matching is bypassable with `..` or symlinks. Canonicalize both sides, then `Path::starts_with`.
- **Do NOT skip the canonicalize step "because exists() already checked."** `exists()` does not validate path containment.
- **Do NOT keep `confirmation_token = "confirm:<action>"`** even if the rest of this WO ships. The predictable token is itself the bug.

## Handoff notes

This is independent of WO-R-01..04. Can ship as its own PR.

The `confirmation_token` fix may have callers outside the repair-apply path that also use the same predictable pattern — grep for `confirmation_token` across `model_bridge.rs` and `memory_bridge.rs`. If found, file follow-up WOs; do NOT fix them all under this WO.
