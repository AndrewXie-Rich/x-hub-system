# Work Orders — Index

> **Read [`READ_FIRST.md`](READ_FIRST.md) and [`HANDOFF.md`](HANDOFF.md) before opening any work order.** READ_FIRST has the project context and decisions; HANDOFF has the current state snapshot (what's done, what's blocked, what's safe).

## Critical path to RFC submission

```
WO-01 ✓ + WO-02 ✓ + WO-03/05/06 ✓ → U-A1 ✓ → U-A2 ✓ → U-A3 (submit RFC)
```

All other work orders are post-submission or unrelated to the RFC critical path.

## Work order list

| ID | Title | Owner | Est. | Status | Depends on |
|---|---|---|---|---|---|
| **WO-01** | [Write valid example payloads for each schema](WO-01-schema-examples.md) | AI | 30 min | **✓ completed 2026-06-25** | — |
| **WO-02** | [CI script for schema validation](WO-02-schema-ci.md) | AI | 30 min | **✓ completed 2026-06-25** | — |
| **WO-03** | [Draft Hub Receipt unified spec](WO-03-hub-receipt-spec.md) | AI | 2–3 h | **✓ completed 2026-06-25** (parallel AI session) | — |
| **WO-04** | [Update X-Hub main README to reference spinoffs](WO-04-main-readme-update.md) | AI | 30 min | **deferred** (README mid-rewrite in tree) | tree settled |
| **WO-05** | [Draft agent-2fa protocol-v0.1.md](WO-05-agent-2fa-protocol.md) | AI | 1 day | **✓ completed 2026-06-25** (parallel AI session) | WO-03 done ✓ |
| **WO-06** | [agent-2fa README + demo + schemas](WO-06-agent-2fa-companions.md) | AI | half day | **✓ completed 2026-06-25** (parallel AI session) | WO-05 done ✓ |
| **U-A1** | Commit + push standalone spec artifacts | User | 5 min | **✓ completed 2026-06-25** | WO-01, WO-02, WO-03, WO-05, WO-06 complete |
| **U-A2** | Create placeholder repo `mcp-trust-registry` | User | 10 min | **✓ completed 2026-06-26** | U-A1 |
| **U-A3** | Submit RFC to MCP Discussions | User | 30 min | pending (API blocked by org OAuth policy; browser page opened, body copied) | U-A2 |
| **U-A4** | Outreach to MCP server maintainers | User | half day | pending | U-A3 |

User actions: see [`USER_ACTIONS.md`](USER_ACTIONS.md).

## Rust security & correctness work orders (independent track)

A separate batch of 13 work orders covers the X-Hub Rust kernel itself — security defects found in the uncommitted working-tree diff during the 2026-06-26 code review. These are NOT on the RFC critical path. See [`rust/WO-R-00-README.md`](rust/WO-R-00-README.md) for the index, severity ranking, and execution order.

Key entries:
- `WO-R-01..04` — memory user-reveal-grant subsystem (security; ship together in one PR)
- `WO-R-05` — model artifact-path traversal (security)
- `WO-R-06` — process-command secret redaction allowlist (security)
- `WO-R-07..11` — correctness / operator-experience (P1)
- `WO-R-12..13` — cleanup (P2)

## Task IDs

Work orders map 1:1 to tasks in TaskList:

| WO | Task ID |
|---|---|
| WO-01 | Task #1 |
| WO-02 | Task #2 |
| WO-03 | Task #3 |
| WO-04 | Task #4 |
| WO-05 | Task #5 |
| WO-06 | Task #6 |
| U-A1 | Task #7 |
| U-A2 | Task #8 |
| U-A3 | Task #9 |
| U-A4 | Task #10 |

Update task status when starting (`in_progress`) and only when fully done (`completed`). Partial work stays `in_progress`.

## Recommended execution order

**Phase 1 — RFC submission (current):**
1. ~~WO-01~~ ✓ completed 2026-06-25
2. ~~WO-02~~ ✓ completed 2026-06-25
3. ~~U-A1~~ ✓ completed 2026-06-25
4. ~~U-A2~~ ✓ completed 2026-06-26
5. **U-A3** — browser/manual submit remains. GitHub GraphQL API was blocked by the `modelcontextprotocol` org OAuth policy; use the open Discussion page and paste the copied body.

**Phase 2 — Companion specs (post-submission, parallel-safe):**

4. ~~WO-03~~ ✓ completed 2026-06-25 (by parallel AI session; see `HANDOFF.md` § "Collisions detected this session")
5. ~~WO-05~~ ✓ completed 2026-06-25 (by parallel AI session) — agent-2fa protocol at `specs/agent-2fa/protocol-v0.1.md`
6. ~~WO-06~~ ✓ completed 2026-06-25 (by parallel AI session) — agent-2fa README/demo/schemas under `specs/agent-2fa/`

**Phase 3 — Deferred / parallel:**

- **WO-04** (main README update) — defer until the active README rewrite in the working tree is committed. Resuming early would bundle two unrelated commits together. See `HANDOFF.md` for the specific state.
- **U-A4** (maintainer outreach) — run after U-A3; Phase 2 spec drafts are already complete and can be linked as supporting material.

## Cross-cutting principles

Whatever WO you take, these stay true:

- Read existing `specs/mcp-trust-registry/protocol-v0.1.md` if your output is a protocol spec — it's the canonical template for spec structure in this project.
- File paths in artifacts must resolve once committed. Don't link to paths that don't exist yet (or mark them as "(planned)" if you must).
- If a WO conflicts with `READ_FIRST.md`, the conflict itself is a blocker — surface it to the user, don't resolve it silently.
