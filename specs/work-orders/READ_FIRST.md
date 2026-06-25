# READ_FIRST — Context for any AI working on X-Hub spinoff work orders

You have been assigned a work order from `specs/work-orders/WO-NN-*.md`. Read this file first so you don't re-derive context or contradict prior decisions. Then read your specific work order. Then start.

## What is X-Hub-System

A self-hosted AI agent governance plane on macOS. MIT-licensed, public tech preview at `github.com/AndrewXie-Rich/x-hub-system`. The repo contains a Hub daemon (Rust kernel + Node gRPC), legacy X-Terminal tree, and governance primitives (trust root, grants, audit, fail-closed boundaries).

**Strategic context** lives in two memory files (read them if you need motivation):
- `~/.claude/projects/-Users-andrew-xie-Documents-AX/memory/xhub_strategic_pivot_2026.md`
- `~/.claude/projects/-Users-andrew-xie-Documents-AX/memory/xhub_2026_06_competitive_landscape.md`

**TL;DR:** Project pivoted 2026-06-24 from personal Agent terminal → enterprise governance plane. To break the "1 star" recognition problem, two **spinoff specs** were extracted from X-Hub's internal design:

1. **mcp-trust-registry** — federated attestation + capability tokens above MCP. Currently lives at `specs/mcp-trust-registry/`. **All artifacts shipped: spec, README, demo script, JSON schemas, RFC submission draft.**
2. **agent-2fa** — Touch ID / 2FA for AI agent actions. Currently planned at `specs/agent-2fa/`. **Spec not yet drafted.**

Both spinoffs share one primitive: **Hub Receipt** (signed JSON-LD execution receipt). Currently hand-waved; needs its own spec.

## File layout

```
x-hub-system/
├── specs/
│   ├── mcp-trust-registry/
│   │   ├── protocol-v0.1.md         # 530-line spec ← read this if your WO touches mcp-trust
│   │   ├── README.md                # ~90-line standalone-repo README
│   │   ├── demo-60s.md              # 4-scene asciinema script
│   │   ├── RFC-discussion-body.md   # ~165-line RFC for MCP community
│   │   └── schemas/                 # 6 JSON Schemas + env-allowlist.json
│   ├── agent-2fa/                   # to be created
│   ├── hub-receipt/                 # to be created
│   └── work-orders/                 # THIS DIRECTORY
└── ...
```

## Style / quality bar

- **Terse. No manifesto.** The X-Hub README was rewritten 945 → 74 lines specifically because the long version felt like positioning theater. Match that bar.
- **No emojis in any artifact.** User has never asked for them.
- **No code comments unless the why is non-obvious.** Identifiers should self-document.
- **Use RFC 2119 keywords** (MUST / SHOULD / MAY) in protocol specs. Plain English elsewhere.
- **English for spec / README artifacts** (international community); Chinese only when the user explicitly asks for a translated version.
- **Imitate, don't invent.** If you're writing a new spec, copy the structure of `mcp-trust-registry/protocol-v0.1.md` rather than designing your own outline.

## Decisions already made (do NOT relitigate)

| Decision | Value | Rationale |
|---|---|---|
| Spec license | CC BY 4.0 | Standard for open protocols |
| Implementation license | Apache 2.0 | Patent clause friendlier than MIT for enterprise contributors |
| Signing primitive | ed25519, optional Sigstore keyless | Low barrier + keyless option for orgs |
| Hash | SHA-256 | Universally available; SHA-3 / BLAKE3 not justified for v0.1 |
| Canonical JSON | sorted keys, no whitespace, UTF-8 NFC | Same as RFC 8785 JCS in spirit |
| Encoding for keys | `ed25519:` + lowercase base32, no padding, 52 chars | 32-byte ed25519 pubkey → 52 base32 chars |
| Encoding for signatures | `ed25519:` + standard base64 with padding | 64-byte ed25519 sig → 88 base64 chars |
| Hash format in fields | `sha256:<hex>` with prefix | Multihash-style, room for SHA-3 in v0.2 |

Any deviation from these requires a comment explaining why this artifact diverges.

## Things to NOT do

- **Do not invent new design** in places where the existing spec already chose. Read the spec first.
- **Do not modify MCP protocol** in any artifact. mcp-trust-registry lives *above* MCP; agent-2fa is *orthogonal* to MCP. Touching MCP itself is out of scope and politically fatal to the RFC.
- **Do not promote X-Hub** in spinoff artifacts. Spinoffs must read as independent projects with X-Hub as the reference implementation, not as X-Hub marketing.
- **Do not write planning / decision documents** unless explicitly asked. Output is artifacts (spec, schema, README, demo script), not meta-discussion.
- **Do not run `git push` or create commits** unless the work order explicitly says "user action". Most work orders end with files on disk; commits are the user's call.
- **Do not start work on multiple work orders simultaneously** unless told to. One WO per session keeps responsibility clean.

## How to update task status

Each WO maps to a task ID (in TaskList). When you start, set the task to `in_progress`. When done — and only when *all acceptance criteria pass* — set to `completed`. If you encounter a blocker, leave it `in_progress` and create a new task describing the blocker; do not `completed` partial work.

## When in doubt

Ask the user. The user is the project's sole maintainer; they're available and prefer a 30-second clarification over a 30-minute wrong direction. Specifically: ask if you're tempted to invent a new design choice that doesn't match the existing spec, or if you're unsure whether output should be English or Chinese.
