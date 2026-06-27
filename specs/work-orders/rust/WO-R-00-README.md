# Rust Work Orders — Index & Handoff

> **What this is.** A batch of work orders discovered during the 2026-06-26 review of the uncommitted Rust working-tree diff (28 modified files, 13 new untracked files, ~+40k / -24k lines net). The findings are independent of the RFC submission critical path — they target the X-Hub Rust kernel itself, NOT the spec spinoffs.
>
> **Read this entire file before opening any WO-R-NN.** It contains constraints that apply to every work order in this directory.

## CRITICAL: state of the code under review

The findings below were observed in the **working tree**, NOT in any pushed commit. As of the review:

```
origin/main HEAD : 7b867d7  docs: harden mcp trust pre-RFC materials
working tree     : 139 files modified, +40,020 / -24,375 lines
                   66 untracked files
```

The diff is uncommitted. Specifically:

- `rust/xhubd/crates/xhubd/src/memory_bridge.rs` grew from 4,231 lines (HEAD) → 12,693 lines (working tree).
- A memory note (`xhub_cleanup_targets.md`, 2026-06-24) claimed this file had been split into a `memory_bridge/` subdirectory with 13 files; that split is NOT present on `main` or in the working tree. Either it was reverted, or it was never committed.
- The current direction is **opposite** to that cleanup memo: the file is being expanded, not split.

### What every AI taking a WO-R-NN MUST do first

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system

# 1. Confirm the diff is still in the working tree, not committed away
git status -- rust/xhubd/crates/xhubd/src/memory_bridge.rs
git log --oneline origin/main -- rust/xhubd/crates/xhubd/src/memory_bridge.rs | head -3

# 2. Confirm the specific lines cited by your WO still exist
grep -n "<symbol-from-WO>" rust/xhubd/crates/xhubd/src/memory_bridge.rs

# 3. If the diff has been committed since this WO was authored — STOP.
#    The line numbers will be off; cross-reference by symbol, not line.
```

If the diff has been committed (the parallel AI session may have pushed it at any time), **re-derive the line numbers from the symbol names** before applying the fix. Symbols are stable; line numbers in a 12k-line file are not.

## The 13 work orders

### Critical path (P0): memory reveal-grant subsystem (one PR)

The first four work orders are **a single coupled defect**. They are listed separately because each is a distinct check, but **DO NOT ship a fix that addresses only some of them**. The threat model only holds if all four are fixed together. Read all four before starting any one.

| WO | File | Symbol | Issue |
|---|---|---|---|
| [WO-R-01](WO-R-01-memory-reveal-grant-read-bypass.md) | `memory_bridge.rs` | `get_memory_object_json`, `list_memory_objects_json` | Reads bypass the reveal-grant entirely |
| [WO-R-02](WO-R-02-memory-reveal-grant-ttl-base.md) | `memory_bridge.rs` | `memory_user_reveal_grant_issue`, `memory_user_reveal_now_ms` | Client-controlled `now_ms` defeats 15-min TTL clamp |
| [WO-R-03](WO-R-03-memory-reveal-grant-binding.md) | `memory_bridge.rs` | `memory_user_reveal_grant_active_for_mutation`, `memory_user_reveal_state_path` | Grant is global singleton, not bound to actor/memory_id |
| [WO-R-04](WO-R-04-memory-reveal-grant-fail-closed-defaults.md) | `memory_bridge.rs` | `memory_user_reveal_grant_deny_code` | Missing requester_role defaults to "supervisor" (fail-open) |

### Critical path (P0): standalone

| WO | File | Symbol | Issue |
|---|---|---|---|
| [WO-R-05](WO-R-05-model-artifact-path-traversal.md) | `model_bridge.rs` | `resolve_runtime_relative_path_for_repair`, `apply_local_model_registry_repair_value` | `artifact_path` accepts absolute paths and `..` — registry points outside `runtime_base_dir` |
| [WO-R-06](WO-R-06-redact-process-command-allowlist.md) | `main.rs` | `redact_process_command` | Only redacts a hard-coded flag list; secrets in other forms leak through `/runtime/product-process-sanity` |

### Medium severity (P1)

| WO | File | Symbol | Issue |
|---|---|---|---|
| [WO-R-07](WO-R-07-writeback-candidate-concurrency.md) | `memory_bridge.rs`, `xhub-db/lib.rs` | `transition_memory_object_candidate_json`, `update_memory_object_with_event` | Read-modify-write without version guard — concurrent approve/reject both win |
| [WO-R-08](WO-R-08-env-alias-silent-fallback.md) | `scheduler_bridge.rs` | `env_u32`, `env_u64` | First-set alias is parsed; if it fails parse, valid second alias is never tried |
| [WO-R-09](WO-R-09-add-local-model-ok-true-on-failure.md) | `model_bridge.rs` | `apply_local_model_registry_repair_value` | Returns `"ok": true` with `"accepted": false` on validation failure — clients checking `ok` miss it |
| [WO-R-10](WO-R-10-process-substring-false-positives.md) | `main.rs` | `product_process_label`, `is_target_xhubd_command` | Naive substring matching against `ps` output produces phantom xhubd detections |
| [WO-R-11](WO-R-11-registry-secret-substring-block.md) | `model_bridge.rs` | `read_local_model_registry_file`, `raw_contains_potential_secret_material` | Benign substrings (`gpt-sk-tuned`, "password reset") permanently block registry writes |

### Low severity (P2)

| WO | File | Symbol | Issue |
|---|---|---|---|
| [WO-R-12](WO-R-12-policy-path-disclosure.md) | `main.rs` | `model_concurrency_policy_http_json` | Unauthenticated endpoint discloses absolute home-directory path |
| [WO-R-13](WO-R-13-first-non-empty-vec-dedup.md) | `main.rs`, `model_bridge.rs` | `first_non_empty_vec` | Identical helper defined twice; CLI vs HTTP paths can diverge on a fix |

## Recommended execution order

1. **WO-R-01..04 together** (one PR). The reveal-grant subsystem is the intended authorization boundary for user-scoped memory. Until all four are fixed, the boundary is bypassed three different ways and the fourth fails open. Shipping a partial fix gives a false sense of security.
2. **WO-R-05** (one PR). Independent path-traversal risk. Highest single-finding severity.
3. **WO-R-06** (one PR). Process-command secret leak. Triggered by anything posted at `/runtime/product-process-sanity`.
4. **WO-R-07** when convenient. Concurrency window is narrow but real.
5. **WO-R-08..11** as a cleanup batch — small, low-risk patches that add up to operator-experience improvements.
6. **WO-R-12..13** when touching the surrounding files for other reasons. Not worth a dedicated PR.

## What's deliberately NOT in this batch

These were considered and EXCLUDED:

- **BM25 implementation** — checked, looked correct (avgdl div-by-zero guarded, IDF uses Lucene non-negative variant, tokenizer shared between corpus stats and scoring, query tokens deduped). If a later session finds a bug here, file a new WO-R-NN.
- **Migration 0009 `DROP TABLE IF EXISTS`** — destructive but the table is genuinely a derived index; `rebuild_memory_object_index` rebuilds lazily on empty count. Verified by tracing callers.
- **`memory_bridge.rs` 12,693-line size** — this is a structural problem (the file should be split per the `xhub_cleanup_targets.md` plan), but splitting it BEFORE landing the P0 security fixes risks rebase pain. **File a separate "split memory_bridge.rs" WO after WO-R-01..04 land.**
- **The 138-file general refactor** — out of scope for this batch. Each finding here is specific to a named function.

## Output format for each WO-R-NN

Each work order in this directory follows the structure used in the spinoff WOs (WO-NN-*.md):

- Header: Owner / Effort / Task ID (none — these don't go in the main TaskList) / Dependencies
- **Why this matters**: failure mode in concrete terms
- **Scope**: in / out
- **Deliverables**: file paths, function names, the exact change needed
- **Acceptance criteria**: numbered, testable
- **References (read first)**: pointers to the surrounding code
- **Anti-patterns**: traps the next implementer will fall into
- **Handoff notes**: what to coordinate with parallel sessions

## Coordination

The Rust kernel is being actively modified by a parallel AI session (the 138-file diff is its work). **Before opening any WO-R-NN:**

1. Check whether the parallel session has committed since this review (`git log --since="2026-06-26"`).
2. If it has, re-read the relevant function in the current tree; line numbers and surrounding code may have moved.
3. If you can't tell whose changes are whose, ask the user to clarify session ownership.

The parallel session is not aware of this review. The user is. Communication is the user's, not yours, to manage.

## Why these aren't in the main TaskList

The TaskList (#1–#10) tracks the **RFC submission critical path**: spec drafts, schemas, CI, commit/push, placeholder repo, RFC submission, maintainer outreach. The Rust kernel findings live in a separate track because:

- The RFC critical path completes in days; Rust security fixes take weeks.
- Mixing the two trackers would let either dominate the other's attention.
- A reviewer scanning the TaskList wants to see "is the RFC out?", not "what's the Rust kernel posture?".

When a WO-R-NN starts, you MAY add it to the TaskList as a temporary tracking entry — but remove it once done. The canonical state lives in this directory.

---

*Last updated: 2026-06-26 evening, after the Phase B Rust diff review.*
