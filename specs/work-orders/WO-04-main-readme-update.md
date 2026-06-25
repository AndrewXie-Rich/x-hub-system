# WO-04 — Update X-Hub main README to reference spinoffs

**Owner:** AI · **Effort:** 30 min · **Task ID:** #4 · **Dependencies:** ideally after U-A1 (so links resolve on main)

## Why this matters

The X-Hub-System main README was rewritten 945→74 lines earlier this month to fix a "manifesto problem". The terse version works, but it currently presents X-Hub as a self-contained product. The strategic pivot says X-Hub should also serve as the **reference implementation** of two extracted specs (mcp-trust-registry, agent-2fa). Without a small pointer in the main README, visitors who land on X-Hub won't discover the spinoffs, and visitors who find the spinoffs won't see X-Hub as the working reference.

This WO adds the minimum pointer text — 4–6 lines, integrated into the existing "Status" or new "Specs" section. Goal is discoverability, not promotion.

## Scope

**In scope:**
- Surgical edit to `README.md` and `README_zh.md`. Both files MUST be updated identically (modulo language).
- No restructuring, no new top-level sections beyond a single "Specs" anchor if needed.

**Out of scope:**
- Rewriting any other part of the README.
- Adding badges, logos, or marketing prose for the spinoffs.
- Updating `ENTERPRISE.md`, `FAMILY.md`, or any other doc.

## Deliverables

### English `README.md`

Add a new section between the existing "Architecture in 30 seconds" and "License and commercial" sections. Title: `## Specs (extracted)`. Body, verbatim:

```markdown
## Specs (extracted)

Two protocol specs have been extracted from X-Hub for independent community review. X-Hub-System is their reference implementation:

- [**mcp-trust-registry**](specs/mcp-trust-registry/) — federated attestation + capability tokens above MCP. Pre-RFC, v0.1 draft.
- [**agent-2fa**](specs/agent-2fa/) (planned) — Touch ID / dual-confirm for AI agent actions.
- [**hub-receipt**](specs/hub-receipt/) — shared signed-receipt primitive used by both specs above.
```

If `specs/agent-2fa/` doesn't yet exist when you make this edit, **omit that bullet** and leave a `<!-- placeholder for agent-2fa link, see WO-05 -->` HTML comment. Do not link to nonexistent paths.

Same for `specs/hub-receipt/` — only include the bullet if WO-03 has landed.

### Chinese `README_zh.md`

Mirror the same insertion. Section title: `## 抽出的协议规范 (Specs)`. Body:

```markdown
## 抽出的协议规范 (Specs)

以下两个协议规范从 X-Hub 抽出,作为独立协议交社区评审。X-Hub-System 是它们的引用实现:

- [**mcp-trust-registry**](specs/mcp-trust-registry/) — MCP 之上的联邦化签名 + 能力 token。Pre-RFC,v0.1 草案。
- [**agent-2fa**](specs/agent-2fa/)(计划中)— AI agent 操作的 Touch ID / 双重确认。
- [**hub-receipt**](specs/hub-receipt/) — 上述两规范共用的签名回执原语。
```

Same placeholder rules for missing dirs.

## Acceptance criteria

1. Both `README.md` and `README_zh.md` contain a "Specs" section at the right insertion point (between Architecture and License).
2. The total README line count grows by at most 10 lines per language. (Currently each is ~75 lines; afterwards each should be ~80–85.)
3. All linked paths resolve in the repo when the change is committed. No broken anchors.
4. No other content in either README is modified.
5. Section placement preserves the existing flow — visitor still reads Quick Start → Architecture → Specs → License → Status → Community.

## References (read first)

- `README.md` (current 74-line version)
- `README_zh.md` (current 74-line version)
- `specs/mcp-trust-registry/` directory listing (confirm it exists before linking)

## Anti-patterns

- Don't promote spinoffs ("revolutionary new approach to MCP security"). Neutral, factual phrasing only.
- Don't reintroduce manifesto language. Visit the archived 945-line README in `docs/legacy/` if you want to confirm what "manifesto" looks like and avoid it.
- Don't add a "Why two spinoffs" explainer. The READMEs of the spinoff specs themselves explain why each exists. Linking is enough.
- Don't break existing badges, links, or capability matrix references.

## Handoff notes

This WO is short, but timing matters: if you run it before U-A1 (commit + push), the linked paths on `main` won't exist for GitHub-rendered README readers. **Run after U-A1**, or commit the README edit in the same commit as the spec files.

If `specs/agent-2fa/` and `specs/hub-receipt/` directories are not yet created at run time, follow the placeholder-comment rule — don't link to nonexistent paths just because the strategy says they'll exist soon.
