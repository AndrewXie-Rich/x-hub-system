# HANDOFF — Current state snapshot

> **What this is.** A timestamped snapshot of where the X-Hub spinoff work stands. Read this AFTER `READ_FIRST.md`, BEFORE picking up any work order. If the state described here no longer matches the repo (commits have landed since), trust the repo, not this doc — but read on for the *plan* and *pitfalls*, which decay slower than file lists.
>
> **Snapshot date:** 2026-06-25, evening local time.
> **Branch:** `main`, up to date with `origin/main`.
> **Last commit:** `8b4aabe Refine website release scope and deployment guidance`.

---

## TL;DR for the next AI

1. **All standalone spec drafts are complete** — mcp-trust-registry, hub-receipt, agent-2fa, plus their schemas / examples / READMEs / demo scripts. Validated.
2. **All AI work orders except WO-04 are done.** WO-04 (main README pointer) is deferred until the in-tree README rewrite is committed.
3. **Working tree is messy** — a parallel Rust refactor (138 files, ~31k LOC) is uncommitted on `main`, plus prior-session uncommitted work (README rewrite, ENTERPRISE/FAMILY split). **Use scoped staging; never `git add .`**.
4. **User has 3 manual actions queued** (U-A1 commit, U-A2 placeholder repo, U-A3 submit RFC). Once these land, the RFC is out.

---

## Done this session (verified)

### mcp-trust-registry artifacts at `specs/mcp-trust-registry/`

| File | Status |
|---|---|
| `protocol-v0.1.md` | 530-line spec |
| `README.md` | 90-line standalone-repo README |
| `demo-60s.md` | 4-scene asciinema script |
| `RFC-discussion-body.md` | ~165 lines, ready to paste into MCP Discussions |
| `schemas/manifest.schema.json` | Draft 2020-12, valid |
| `schemas/attestation.schema.json` | Draft 2020-12, valid (oneOf signature/sigstore_bundle) |
| `schemas/pin.schema.json` | Draft 2020-12, valid |
| `schemas/policy.schema.json` | Draft 2020-12, valid |
| `schemas/recall.schema.json` | Draft 2020-12, valid |
| `schemas/receipt.schema.json` | Draft 2020-12, valid |
| `schemas/env-allowlist.json` | Data file (27 allow / 22 deny patterns) |
| `schemas/examples/*.example.json` | 6 example payloads, cross-consistent IDs/hashes |

### CI

| File | Status |
|---|---|
| `scripts/check_mcp_trust_schemas.sh` | Executable, 12/12 validations pass |
| `.github/workflows/mcp-trust-schemas.yml` | Path-filtered to `specs/mcp-trust-registry/**` only |
| `scripts/check_spinoff_schemas.sh` | Executable, 22/22 validations pass across mcp-trust-registry, hub-receipt, and agent-2fa |
| `.github/workflows/spinoff-schemas.yml` | Path-filtered to all three standalone spec directories |

### Process / handoff docs at `specs/work-orders/`

| File | Status |
|---|---|
| `READ_FIRST.md` | Decisions + style + red lines |
| `INDEX.md` | Work order catalog |
| `WO-01-schema-examples.md` | Done |
| `WO-02-schema-ci.md` | Done |
| `WO-03-hub-receipt-spec.md` | Done (by parallel AI session, see "Collisions" below) |
| `WO-04-main-readme-update.md` | Pending (deferred — see below) |
| `WO-05-agent-2fa-protocol.md` | Done (by parallel AI session) |
| `WO-06-agent-2fa-companions.md` | Done (by parallel AI session) |
| `USER_ACTIONS.md` | User-pending |
| `HANDOFF.md` | This file |

### Hub Receipt artifacts at `specs/hub-receipt/` (WO-03 deliverables)

| File | Status |
|---|---|
| `v0.1.md` | 141-line spec, satisfies all WO-03 acceptance criteria |
| `schema/receipt-envelope.schema.json` | Draft 2020-12, valid (singular `schema/` directory — see "Naming inconsistency" below) |
| `schema/examples/envelope.example.json` | Validates against the schema |

### agent-2fa artifacts at `specs/agent-2fa/` (WO-05 + WO-06 deliverables)

| File | Status |
|---|---|
| `protocol-v0.1.md` | 421-line spec, 21 sections mirroring mcp-trust-registry structure, references hub-receipt for envelope |
| `README.md` | 100 lines, "Touch ID for AI agent actions" tagline, badges, install + how-it-works narrative |
| `demo-60s.md` | 177 lines, asciinema-style recording script |
| `schemas/{authorization,challenge,policy,receipt-claims}.schema.json` | 4 schemas, all Draft 2020-12 valid |
| `schemas/examples/{authorization,challenge,policy,receipt-claims}.example.json` | 4 examples, all validate, cross-consistent (`chg-3a7f12bc`, `alice-iphone`, `agent-cli-1` thread through) |

### Cross-project memo at `docs/cross-project/`

| File | Status |
|---|---|
| `LESSONS_FOR_RELFLOWHUB_FROM_XHUB.md` | Portable artifact for sibling project copy |

### Validation re-run commands

```bash
./scripts/check_mcp_trust_schemas.sh
# Expected: 12 passed, 0 failed, 0 warnings

./scripts/check_spinoff_schemas.sh
# Expected: 22 passed, 0 failed
```

---

## Critical situation: parallel work in tree

`git status` at snapshot time shows:

- **138 files modified** (Rust kernel, gRPC server, Swift Hub UI, X-Terminal, Python runtime, docs) — this is a different AI's in-progress refactor, not yet committed
- **README.md / README_zh.md modified** — 945→74 line rewrite from 2026-06-24 that was never committed
- **40+ untracked files**, including:
  - Mine: `specs/mcp-trust-registry/`, `specs/hub-receipt/`, `specs/agent-2fa/`, `specs/work-orders/`, `docs/cross-project/`, `scripts/check_mcp_trust_schemas.sh`, `scripts/check_spinoff_schemas.sh`, `.github/workflows/mcp-trust-schemas.yml`, `.github/workflows/spinoff-schemas.yml`
  - Prior sessions: `ENTERPRISE.md`, `FAMILY.md`, `docs/legacy/README_full_v1.md`, etc.
  - Other AI: `scripts/ci/rust_memory_hybrid_quality_gate.sh` and Swift refactor splits

### Rules for any AI working in this state

1. **NEVER `git add .`** — bundles everyone's work into one commit. Use scoped paths:
   ```
   git add specs/mcp-trust-registry/ specs/hub-receipt/ specs/agent-2fa/ \
           scripts/check_mcp_trust_schemas.sh scripts/check_spinoff_schemas.sh \
           .github/workflows/mcp-trust-schemas.yml .github/workflows/spinoff-schemas.yml \
           specs/work-orders/ docs/cross-project/
   ```
2. **Do NOT touch any of the 138 modified files** unless explicitly assigned. Specifically:
   - `README.md` / `README_zh.md` (the active rewrite belongs to a prior session)
   - Anything under `rust/`, `x-hub/`, `x-terminal/`, `docs/memory-new/`
   - `scripts/ci/README.md` (modified by other AI)
3. **New spec work stays in scoped spec directories**: `specs/hub-receipt/`, `specs/agent-2fa/`, etc. Do not touch unrelated root, Rust, Swift, or XT files while handling spec work.
4. **Re-check `git status` before starting** any WO. If the tree has been committed since this snapshot, your situation may differ. Adjust accordingly.

---

## Outstanding work, in execution order

### Phase 1: RFC submission (user-driven, AI already done)

| Step | Owner | File / Action | Blocking |
|---|---|---|---|
| **U-A1** | User | scoped commit + push (see `USER_ACTIONS.md#u-a1`) | next steps |
| **U-A2** | User | create placeholder repo `github.com/AndrewXie-Rich/mcp-trust-registry` | U-A3 |
| **U-A3** | User | submit RFC to `modelcontextprotocol/specification` Discussions | community feedback |

### Phase 2: Companion specs (AI work, safe to do anytime)

These are all in **scoped spec directories** with **zero conflict** with the in-tree refactor. They are now complete.

| Step | Owner | Path | Status | Depends |
|---|---|---|---|---|
| **WO-03** | AI | `specs/hub-receipt/` | **Done 2026-06-25** (parallel session) | — |
| **WO-05** | AI | `specs/agent-2fa/protocol-v0.1.md` | **Done 2026-06-25** (parallel session) | WO-03 done ✓ |
| **WO-06** | AI | `specs/agent-2fa/` (README + demo + schemas) | **Done 2026-06-25** (parallel session) | WO-05 done ✓ |

**Phase 2 is fully complete.** No active AI work orders remain other than WO-04 (deferred — see Phase 3).

### Phase 3: Deferred work

| Step | Why deferred |
|---|---|
| **WO-04** (main README update) | `README.md` is mid-rewrite; my edit would bundle into someone else's commit. Resume **only after** the README rewrite has been committed by whoever did it (likely the user as part of U-A1, or in a separate prior-work commit). |
| **U-A4** (maintainer outreach) | Best done after U-A3 lands, so outreach emails can reference the submitted RFC. |

### Phase 4: After RFC submission (out of immediate scope)

Not part of this handoff, but listed so the next AI knows the horizon:

- Rust reference implementations: `mcp-trust-cli`, `mcp-trust-proxy` (skeleton + minimum demo backend)
- iOS / macOS implementations for agent-2fa
- Seed attestations for top 20 MCP servers
- Continuous v0.1 → v0.2 iteration from community feedback

---

## Collisions detected this session

When picking up WO-03 / WO-05 / WO-06 around 16:00–17:00 local, I discovered the deliverables already existed in tree, created by a parallel AI session between 14:13 and 15:55. Specifically:

- **WO-03 (hub-receipt)** — `specs/hub-receipt/v0.1.md` + schema + example created 14:13–14:15. Substantive 141-line spec, schema/example valid.
- **WO-05 (agent-2fa protocol)** — `specs/agent-2fa/protocol-v0.1.md` created 14:28. 421-line spec, 21 sections mirroring mcp-trust-registry layout, references hub-receipt envelope correctly.
- **WO-06 (agent-2fa companions)** — README, demo-60s, 4 schemas, 4 examples all created 15:53–15:55, then lightly polished to remove product-specific runtime names. Cross-field consistency holds.

My write attempts for WO-03 and WO-05 hit "file has not been read yet" errors, which is the harness's existence check. Resolution:

- Existing work satisfies acceptance criteria in each case. Kept as-is.
- My duplicate `specs/hub-receipt/schemas/` (plural) directory from the WO-03 attempt was removed; canonical location is `specs/hub-receipt/schema/` (singular).
- No content was overwritten.
- Tasks #3, #5, #6 marked completed.

**Lesson for any incoming AI:** before starting a work order whose deliverable path is "new", **list the whole spec tree**, not just the WO's named output. Parallel sessions may have completed adjacent work too:

```bash
find specs/ -type f -newer specs/work-orders/HANDOFF.md
```

If the existing work satisfies acceptance criteria, accept it and move on. Do not rewrite for marginal improvements.

## Naming inconsistency between spec dirs

| Spec | Schema directory |
|---|---|
| `specs/mcp-trust-registry/` | `schemas/` (plural) |
| `specs/hub-receipt/` | `schema/` (singular) |

Both are valid. mcp-trust-registry has 6 schemas so plural is natural; hub-receipt has 1 schema so singular is natural. **Do not "harmonize" by renaming** — that would invalidate the schema `$id` URLs and break any external references already taken. agent-2fa (WO-06) MAY pick either; recommend matching mcp-trust-registry (plural) since it will likely accumulate more schemas.

## CI coverage status

`scripts/check_mcp_trust_schemas.sh` remains the narrow mcp-trust-registry gate and still reports 12/12. `scripts/check_spinoff_schemas.sh` is the broader standalone-spec gate and validates:

- 6 mcp-trust-registry schemas + 6 examples
- 1 hub-receipt schema + 1 example
- 4 agent-2fa schemas + 4 examples

Current result: **22 passed, 0 failed**. `.github/workflows/spinoff-schemas.yml` runs this broader gate on changes to any standalone spec directory.

---

Read in this order:

1. **`READ_FIRST.md`** — project context, style bar, decisions already made
2. **This file (`HANDOFF.md`)** — what's done, what's blocked, what's safe
3. **`INDEX.md`** — work order catalog with task IDs
4. **The specific `WO-NN-*.md`** you're picking up

Then:

5. Run `git status` — verify the tree state. If it diverges materially from the "Critical situation" above (e.g., commits have landed), update your mental model. If you're unsure, ask the user.
6. Run `./scripts/check_mcp_trust_schemas.sh` and `./scripts/check_spinoff_schemas.sh` — expected results are 12/12 and 22/22 respectively. If either fails, something regressed; investigate before continuing.

### Recommended next pickup

If the user wants linear progress: **U-A1 → U-A2 → U-A3** is next. The AI-created spec artifacts are ready for a scoped commit and RFC submission.

If the user wants more AI work before submission: the only clean remaining item is WO-04, but it must wait until the active root README rewrite is committed. Do not resume WO-04 while `README.md` / `README_zh.md` are dirty from another session.

---

## Strategic context (read these in memory, don't re-derive)

The "why" of all this work lives in memory:

| Memory file | What it says |
|---|---|
| `xhub_strategic_pivot_2026.md` | Why X-Hub repositioned to enterprise governance plane in 2026-06 |
| `xhub_2026_06_competitive_landscape.md` | Why 2 spinoffs (mcp-trust + agent-2fa) and the priority reorder |
| `xhub_system_overview.md` | Active trees / production authority / refactor list |
| `relflowhub_sibling_project.md` | Sibling project, natural 2nd implementation of these specs |

If the strategic frame has shifted (e.g., user has decided to fold a spinoff back into X-Hub, or to abandon RFC submission), check these for an updated rationale — but they're project memory, so they should be updated as decisions change, not stale.

---

## Open invariants to maintain

Things that should remain true across any AI's work:

- **Decisions in READ_FIRST §"Decisions already made"** stay frozen unless the user explicitly says otherwise. ed25519 / SHA-256 / Apache 2.0 implementations / CC BY 4.0 spec / canonical JSON rules — none of these get relitigated.
- **Validation must keep passing.** The mcp-trust CI script must stay 12/12. New spec schemas must pass AJV against their examples until they are folded into CI.
- **Cross-field consistency in examples.** Manifest hash, artifact hash, publisher key, server name thread through manifest → attestation → pin → receipt → recall. New examples in WO-03/05/06 should follow the same discipline.
- **No new top-level docs at repo root.** All new work goes under `specs/` or `docs/`. The repo root is already cleaner after the README rewrite; don't dilute it.

---

## Failure modes the next AI should watch for

- **`git add .` shipping unintended work.** Already covered above; worth repeating.
- **Modifying `README.md` before the existing rewrite is committed.** This is WO-04's specific failure mode.
- **Inlining Hub Receipt format inside WO-05** because WO-03 hasn't shipped. The two specs share a primitive; duplicating it bifurcates the design and creates a real merge conflict later.
- **Promoting X-Hub inside spinoff artifacts.** spec READMEs / demo scripts must read as independent projects. X-Hub is the reference implementation, not the brand.
- **Adding "Anthropic" / "Cursor" / "Claude Code" branding to demos.** Out of scope and politically risky; spec is for the MCP ecosystem at large.
- **Drift from the canonical hash/key/signature placeholders.** All examples use cross-consistent values. If a new example invents fresh placeholders, the narrative breaks for readers tracing artifacts across specs.

---

*If you, as an incoming AI, find this document inconsistent with the repo's actual state, surface the inconsistency to the user before starting any work. Stale handoff docs are worse than no handoff docs — they look authoritative while pointing at the past.*
