# WO-R-01 — Memory reveal-grant: GET endpoints bypass authorization

**Owner:** AI · **Effort:** ~half day (with WO-R-02..04) · **Severity:** P0 (security) · **Dependencies:** none, but coordinate with WO-R-02, WO-R-03, WO-R-04 in same PR

## Why this matters

The `memory_user_reveal_grant_*` subsystem is the intended authorization gate for **user-scoped memory mutations**. The mutation path correctly consults `memory_user_reveal_grant_active_for_mutation`. But the **read** path performs **zero** authorization beyond a coarse "sensitivity == secret" text redaction.

Concretely: any HTTP caller that clears the loopback / access-key check can `GET /memory/objects/<id>` or `GET /memory/objects` and receive the **full text** of every user-scoped memory object, including ones flagged `private` or `internal`, as long as their `sensitivity` field is not literally `"secret"`. The reveal-grant gate is bypassable simply by reading instead of mutating.

This is the highest-severity item in the review batch and breaks the model's stated trust boundary on user-scoped memory.

## Scope

**In scope:**
- `get_memory_object_json` (memory_bridge.rs:4361, working tree)
- `list_memory_objects_json` (memory_bridge.rs:4398)
- `memory_object_to_json` (memory_bridge.rs:~7914) — the renderer used by both
- HTTP route registration that exposes these (`crates/xhubd/src/main.rs`, look for `/memory/objects` paths)

**Out of scope:**
- Refactoring `memory_object_to_json` to support multiple visibility tiers — that is a follow-on
- Migrating the storage schema — read-path enforcement is a code change, not a schema change

## Deliverables

1. Before returning a memory object body, the read path MUST consult a `memory_object_read_allowed_for_caller(...)` helper that takes:
   - The object's `scope` (user / project / shared / etc.)
   - The object's `visibility` and `sensitivity`
   - The caller identity (the same actor identity the mutation gate uses)
   - The active reveal-grant state, if any
2. For `scope == "user"`: read is allowed only if (a) caller is the actor who owns the memory, OR (b) an active reveal-grant matches the caller AND the target object (see WO-R-03 for binding).
3. For other scopes: preserve current behaviour. This WO does NOT widen access; it only closes the read bypass on `user` scope.
4. `list_memory_objects_json` MUST filter the returned set: objects the caller is not allowed to read MUST be omitted. Do NOT return them with redacted text (that leaks existence and timestamps).
5. The denial path MUST emit a structured audit record matching the existing convention (`actor_id`, action `"memory_object_read"`, decision `"deny"`, reason code).

## Acceptance criteria

1. New test: caller without reveal-grant requesting `GET /memory/objects/<user-scope-id>` returns 403 / structured deny — NOT the object text.
2. New test: caller with reveal-grant for a DIFFERENT memory_id requesting `GET /memory/objects/<other-user-scope-id>` returns 403 (depends on WO-R-03 landing in the same PR).
3. New test: caller listing memory objects sees user-scope objects they own, but not user-scope objects they don't.
4. Existing tests on project-scope and shared-scope memory still pass.
5. Audit log produces one deny entry per refused read, with `evidence_ref` pointing at the policy / grant context that decided the deny.

## References (read first)

- `memory_user_reveal_grant_active_for_mutation` (memory_bridge.rs:~4806) — the mutation path's check; the read path should call an analog
- `memory_object_to_json` (memory_bridge.rs:~7914) — current renderer, only redacts `sensitivity == "secret"`
- Existing read-path entry points and their HTTP route registrations in main.rs

## Anti-patterns

- **Do NOT just redact `text` for unauthorized reads.** Metadata (timestamps, summary, hashes) is also sensitive. Refuse the request entirely.
- **Do NOT add a `?reveal=true` query parameter that loosens enforcement.** That recreates the same bypass at a different URL.
- **Do NOT widen the mutation gate to also cover reads.** Reads have different semantics (idempotent, lower friction) — they need their own grant type if granular control is needed later, but v0.1 can be "read = same actor OR active reveal-grant matching both actor and memory_id."

## Handoff notes

This WO ships in the same PR as WO-R-02, WO-R-03, WO-R-04. The four together close the reveal-grant subsystem. Partial fix gives false sense of security: an attacker reading the WO-R-01 patch would simply pivot to WO-R-02 or WO-R-03 to forge a long-lived grant.

If you can only finish WO-R-01 in one session, **mark the PR as `Draft` and explicitly note in the description that WO-R-02..04 are required before merge**.
