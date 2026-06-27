# WO-R-04 — Memory reveal-grant: missing fields default to most-privileged

**Owner:** AI · **Effort:** ~1 hour · **Severity:** P0 (security) · **Dependencies:** ship with WO-R-01, WO-R-02, WO-R-03

## Why this matters

`memory_user_reveal_grant_deny_code` defaults `requester_role` to `"supervisor"` (memory_bridge.rs:~4618) and `use_mode` to `"assistant_user_memory_inspector"` (~4630) when the request body omits those fields. The deny branches then check for **explicit** coder / project roles and project use-modes to reject. A request that **omits** both fields hits none of the deny branches and is issued a user-memory reveal grant.

This violates the fail-closed principle the project advertises. Absence of credentials should be treated as the **least**-privileged actor, not the most-privileged. The defaults invert the security posture.

## Scope

**In scope:**
- `memory_user_reveal_grant_deny_code` (memory_bridge.rs:~4616)
- Any callers that pass a partial body (typically HTTP / CLI entry points)

**Out of scope:**
- Adding new role types — keep the existing taxonomy, just fix the defaults.
- Renaming `supervisor` / `assistant_user_memory_inspector` — too invasive for this WO.

## Deliverables

1. When `requester_role` is missing or empty in the request body, the deny check MUST treat it as **deny**, not "supervisor". One of:
   - Return `deny_code = "requester_role_missing"`.
   - Reject the request at parsing time with a 400-level structured error.
   Prefer the first — it gives a usable error code without changing the API surface.
2. Same treatment for missing `use_mode`: deny with `deny_code = "use_mode_missing"`.
3. The `supervisor` role retains its current privilege when it IS explicitly stated. This WO does NOT downgrade the supervisor role; it stops treating "no role at all" as supervisor.
4. Update all existing internal callers that previously relied on the implicit "supervisor" default to pass the role explicitly. If you find any caller that cannot supply the role, that's a separate bug — file a follow-up WO.

## Acceptance criteria

1. New test: POST `/memory/user-reveal/issue` with body `{}` returns `deny_code = "requester_role_missing"` (or 400-level error).
2. New test: POST with `{"requester_role": "supervisor", "use_mode": "assistant_user_memory_inspector"}` and explicit fields works unchanged.
3. New test: POST with `{"requester_role": "coder"}` returns the existing coder-deny code.
4. Existing tests that posted bodies with the implicit-supervisor pattern are updated to be explicit, OR documented as the test that catches future regressions.

## References (read first)

- `memory_user_reveal_grant_deny_code` (~4616) — the function with the bad defaults
- Existing deny codes returned elsewhere in the file for naming consistency
- Internal callers (`grep "memory_user_reveal_grant_deny_code" rust/`) — find them, fix them

## Anti-patterns

- **Do NOT silently downgrade missing-role to `"coder"`** or any other named role. That makes the failure mode "wrong role assumed" instead of "no role". Explicit deny is clearer.
- **Do NOT keep `unwrap_or("supervisor")` and "fix" it by also adding a separate check.** The bug is the default; fix the default.
- **Do NOT add a config flag like `allow_role_default` that re-enables the bug.** No flag, no escape hatch — defaults are deny.

## Handoff notes

This is the smallest of WO-R-01..04 but the most embarrassing if missed: a single `unwrap_or("supervisor")` makes the rest of the reveal-grant subsystem moot.

Ship with WO-R-01 / WO-R-02 / WO-R-03 in one PR.
