# WO-R-03 — Memory reveal-grant: grant is global singleton, not actor/object bound

**Owner:** AI · **Effort:** ~half day · **Severity:** P0 (security) · **Dependencies:** ship with WO-R-01, WO-R-02, WO-R-04

## Why this matters

The reveal-grant state lives in a single file (`memory_user_reveal_state_path`) with one active `grant_id`. The mutation gate validates only that `requested_grant_id == current_grant_id` — it never:

- Checks the **actor** that initiated the mutation.
- Checks the **target memory_id** the mutation touches.

The `grant_id` is generated as `user_reveal_{now}_{counter}` with `counter` starting at 1. If `now` is client-controllable (see WO-R-02), an attacker can predict or reuse a grant_id. Even with WO-R-02 fixed, the grant_id is structured enough that an actor in the same machine can read it.

**Concrete attack:** Actor A issues a grant for memory `m1` (intending to delete it). Actor B observes the grant_id (filesystem, audit log, or simply guessing the structure) and uses it to mutate memory `m2` — a completely different memory belonging to A. The mutation gate accepts because `grant_id` matches the singleton.

## Scope

**In scope:**
- `memory_user_reveal_grant_active_for_mutation` (memory_bridge.rs:~4806)
- `memory_user_reveal_state_path` and the on-disk grant store (~4655)
- `memory_user_reveal_grant_issue` (~4456) — must record actor and target binding

**Out of scope:**
- Migrating to multi-grant storage (more than one active grant at a time). v0.1 can stay single-active-grant per actor.
- Cryptographic signing of grants. Filesystem permissions on the state file are sufficient for v0.1.

## Deliverables

1. The grant record MUST include `actor_id` (the actor that issued the grant) and `target_memory_id` (the memory the grant applies to). Both are required fields on issuance.
2. `memory_user_reveal_grant_active_for_mutation` MUST verify:
   - `requested_grant_id == current_grant_id` (existing check)
   - **AND** `current_grant.actor_id == mutation_actor_id`
   - **AND** `current_grant.target_memory_id == mutation_target_memory_id`
   - **AND** server-time-based expiry check (from WO-R-02)
3. Grant_id generation MUST use a cryptographically-random component: 16+ bytes from `rand::random()` or equivalent, base64-encoded, in addition to or replacing the predictable `{now}_{counter}` pattern. Format: `user_reveal_<random-base64>`.
4. Reusing a `grant_id` after expiry MUST emit an audit event with reason `grant_id_reused_after_expiry`.

## Acceptance criteria

1. New test: actor B with a valid grant_id issued for `m1` attempting to mutate `m2` is rejected.
2. New test: actor B attempting to mutate `m1` (the correct target) but with actor A's grant_id is rejected on `actor_id` mismatch.
3. New test: grant_id format matches `^user_reveal_[A-Za-z0-9+/]{20,}$` (rough sanity for the random component).
4. New test: replayed grant_id after expiry produces the audit event.
5. Existing tests of the mutation gate still pass when the legitimate actor uses their own grant on the correct target.

## References (read first)

- `memory_user_reveal_grant_active_for_mutation` (~4806) — current single-check logic
- The grant-state JSON schema implicit in `memory_user_reveal_state_path` writes — extend it
- Existing audit record conventions: actor_id is a string, action / decision / evidence_ref fields

## Anti-patterns

- **Do NOT store actor_id as a free-form string from the request body.** Pull it from the same authenticated context the mutation gate already uses.
- **Do NOT bind to memory_id alone without actor.** That lets actor B mutate actor A's memory using the same grant if the actor binding is missing.
- **Do NOT use `counter` as the entropy source.** Counters are predictable. The random component is the security primitive.
- **Do NOT keep the predictable `{now}_{counter}` format "for human readability".** Operators who need readability can prefix with a short label; the entropy is non-negotiable.

## Handoff notes

This is the most invasive of the WO-R-01..04 set because it changes the grant-state format on disk. Migration of an existing v0.1 grant-state file: treat any pre-existing grant as expired on first read after the upgrade. Document this in the PR.

Ship with WO-R-01 / WO-R-02 / WO-R-04 in one PR.
