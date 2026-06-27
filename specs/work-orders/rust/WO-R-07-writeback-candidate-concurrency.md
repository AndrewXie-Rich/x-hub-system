# WO-R-07 — Writeback candidate transition: read-modify-write without version guard

**Owner:** AI · **Effort:** ~3 hours · **Severity:** P1 (correctness, narrow race window) · **Dependencies:** none

## Why this matters

`transition_memory_object_candidate_json` (memory_bridge.rs:~5327) implements an approve / reject / promote flow for memory writeback candidates. The current sequence is:

1. SELECT the candidate row.
2. Check in code that `existing.status == "candidate"`.
3. Validate the requested transition.
4. ... ~200 lines later ...
5. Call `update_memory_object_with_event` (memory_bridge.rs:~5538).
6. That helper issues an UPDATE keyed on `WHERE memory_id = ?` (xhub-db/lib.rs:~1754) with **no version or expected-status guard**.

Two concurrent requests — one approving and one rejecting the same candidate — both read `status == "candidate"`, both pass the in-code validation, both UPDATE. Last-writer-wins. Two history events are emitted with the same `before_version`. The candidate state machine is then in a state where the audit trail says two different operators decided two different outcomes at the same `before_version`, with no way to tell which actually took effect.

This is a textbook lost-update bug. The window is narrow (~200 lines of synchronous work between SELECT and UPDATE), but the diff under review extends both sides of this window — the gap will only grow.

## Scope

**In scope:**
- `transition_memory_object_candidate_json` (memory_bridge.rs:~5327)
- `update_memory_object_with_event` (memory_bridge.rs:~5538)
- The underlying SQL UPDATE in `xhub-db/lib.rs:~1754`

**Out of scope:**
- Moving the storage to a different concurrency primitive (advisory locks, etc.).
- Rewriting the candidate state machine.

## Deliverables

1. Make the UPDATE in `xhub-db/lib.rs:~1754` **version-guarded**:
   ```sql
   UPDATE rust_hub_memory_objects
      SET status = ?, version = version + 1, ...
    WHERE memory_id = ?
      AND version = ?         -- expected version from the prior SELECT
   ```
2. Return the number of rows affected (`changes()` in sqlite). If zero, the row was modified between SELECT and UPDATE; the caller MUST retry from the SELECT or report a structured conflict error.
3. `transition_memory_object_candidate_json` MUST capture `existing.version` (or equivalent), pass it to `update_memory_object_with_event`, and propagate the conflict outcome to the HTTP/CLI caller.
4. Conflict response shape: `{"ok": false, "status": "conflict", "current_version": <N>, "expected_version": <M>}`. Caller can retry.
5. The audit log MUST record conflict outcomes — they are diagnostically useful.

## Acceptance criteria

1. New test (sequential): two transitions issued back-to-back against the same memory_id, second uses the version observed before the first transition committed → second returns conflict.
2. New test (concurrent, with a small synthetic delay): two threads / tasks call transition simultaneously → exactly one succeeds, the other returns conflict.
3. New test: a single transition still succeeds and increments `version`.
4. Existing transition tests pass once they are updated to pass `version`.
5. Conflict appears in the audit log with a distinct outcome code.

## References (read first)

- `transition_memory_object_candidate_json` (memory_bridge.rs:~5327)
- `update_memory_object_with_event` (memory_bridge.rs:~5538)
- The SQL UPDATE in `xhub-db/lib.rs:~1754`
- The `version` column on `rust_hub_memory_objects` — confirm it exists and is incremented

## Anti-patterns

- **Do NOT serialize all transitions through a global mutex.** That works but is slow at any scale beyond one user.
- **Do NOT retry inside the helper.** Retry policy belongs at the caller; the helper just reports conflict.
- **Do NOT silently accept conflicts as "user changed their mind."** Conflicts here mean two operations raced; the correct response is to retry or surface.
- **Do NOT only fix `update_memory_object_with_event` callers in `transition_*`.** If other callers exist, they may need the same treatment — grep for all callers and document any that intentionally don't pass `version`.

## Handoff notes

Independent of the WO-R-01..04 reveal-grant batch. Can ship in its own PR.

This is the kind of bug that surfaces in production only when two operators happen to act on the same candidate within the ~200ms gap. Easy to miss in dev. Add the conflict-outcome metric to observability so it's visible when it does happen.
