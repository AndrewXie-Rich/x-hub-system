# WO-R-13 — Deduplicate `first_non_empty_vec` (and friends)

**Owner:** AI · **Effort:** ~30 minutes · **Severity:** P2 (maintenance hazard) · **Dependencies:** none

## Why this matters

`first_non_empty_vec` is defined identically in:

- `rust/xhubd/crates/xhubd/src/main.rs:~4231`
- `rust/xhubd/crates/xhubd/src/model_bridge.rs:~3756`

The related `first_non_empty` (scalar version) has near-duplicate copies across:

- `crates/xhub-core/`
- `crates/xhub-provider/`
- `crates/xhub-runtime/`
- `crates/xhubd/src/main.rs`
- `crates/xhubd/src/model_bridge.rs`

This is not a runtime bug today. It is a future-tense maintenance hazard:

- Suppose someone fixes a corner case in `first_non_empty_vec` (e.g., treating `Vec<String>` of only empty strings as empty).
- The fix lands in ONE of the two definitions.
- The two paths — CLI (model_bridge) and HTTP (main) — silently diverge in their flag-resolution semantics for the same operation.
- Operators see different behaviour from `model-bridge add-local-model` versus a POST to the equivalent HTTP endpoint.

The bug doesn't exist yet. It will the moment someone fixes one of the copies and not the other.

## Scope

**In scope:**
- Both `first_non_empty_vec` copies.
- The related scalar `first_non_empty` if you have time; otherwise file a follow-up.

**Out of scope:**
- Sweeping all utility duplication across the codebase. That's a bigger initiative.

## Deliverables

1. Move `first_non_empty_vec` to a shared location. Either:
   - **Preferred:** `xhub-core` (or whichever shared crate already exists for utilities). Both `main.rs` and `model_bridge.rs` already depend on `xhub-core`.
   - **Acceptable:** A new `helpers.rs` module inside `crates/xhubd/src/` re-exported from main.rs and model_bridge.rs.
2. Delete the duplicates. Update both call sites to use the shared definition.
3. Add a single set of unit tests for the shared function. Delete duplicate tests if any.
4. If `first_non_empty` (scalar) shows up in 3+ places too, do the same. If it's in 2 places, leave it for a follow-up WO.

## Acceptance criteria

1. `rg "fn first_non_empty_vec"` returns exactly one definition.
2. Both `main.rs` and `model_bridge.rs` call the shared definition.
3. `cargo test` clean across all crates.
4. The tests previously covering the duplicates are consolidated and still pass.

## References (read first)

- `first_non_empty_vec` in main.rs:~4231 and model_bridge.rs:~3756 — confirm they're identical
- The shared utility module pattern in `crates/xhub-core/src/`

## Anti-patterns

- **Do NOT add a feature flag for the shared vs local version.** No path back.
- **Do NOT introduce a new crate just for this one function.** Use the existing shared crate.
- **Do NOT change the function's signature in the move.** Behaviour must be byte-identical; this is a refactor.

## Handoff notes

Cosmetic but easy. Good first task for an AI that needs to get oriented in this codebase before tackling something heavier.

Independent of all other WO-Rs. Ship when convenient.
