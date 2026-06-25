# USER_ACTIONS — Steps requiring the human user (not automatable)

These actions cannot be delegated to an AI session because they require GitHub credentials, public account presence, or human judgment on outreach. Each is short and listed in the order the critical path requires.

## U-A1 — Commit + push standalone spec artifacts to main

**Task ID:** #7 · **Estimated time:** 5 min · **Dependencies:** WO-01, WO-02, WO-03, WO-05, WO-06 complete

The RFC body (`specs/mcp-trust-registry/RFC-discussion-body.md`) references the spec via:

```
github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/mcp-trust-registry/protocol-v0.1.md
```

If the files aren't pushed to `main`, that URL 404s for every RFC reader. So this must happen before submission. Hub Receipt and agent-2fa are supporting standalone specs now, so include them in the same scoped commit rather than leaving the handoff docs ahead of the repo.

```bash
cd /Users/andrew.xie/Documents/AX/x-hub-system

git add specs/mcp-trust-registry/
git add specs/hub-receipt/
git add specs/agent-2fa/
git add specs/work-orders/
git add scripts/check_mcp_trust_schemas.sh         # if WO-02 complete
git add scripts/check_spinoff_schemas.sh
git add .github/workflows/mcp-trust-schemas.yml    # if WO-02 complete
git add .github/workflows/spinoff-schemas.yml

git status                                          # verify nothing unexpected staged

git commit -m "specs: standalone trust specs v0.1 drafts

Adds mcp-trust-registry, Hub Receipt, and agent-2fa v0.1 drafts,
schemas, examples, validation CI, work orders, and handoff docs.

Pre-submission to MCP community Discussions."

git push origin main
```

**Verify:** open `https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/mcp-trust-registry/protocol-v0.1.md` in a browser and confirm it renders.

## U-A2 — Create placeholder repo `mcp-trust-registry`

**Task ID:** #8 · **Estimated time:** 10 min · **Dependencies:** U-A1

The RFC and README mention `github.com/mcp-trust/mcp-trust-registry` and `github.com/AndrewXie-Rich/mcp-trust-registry` as placeholders. Pick one. Recommend the user-namespace version for v0.1; if the spec gains traction, transfer to a `mcp-trust` org later.

Steps:
1. Go to `github.com/new`.
2. Owner: `AndrewXie-Rich`. Repo name: `mcp-trust-registry`. Public. License: Apache 2.0 (matches spec recommendation). Initialize with README.
3. Replace the auto-generated README with the contents of `specs/mcp-trust-registry/README.md` from this repo. Update internal links so:
   - `[spec](spec/protocol-v0.1.md)` becomes `https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/mcp-trust-registry/protocol-v0.1.md`
   - All `specs/mcp-trust-registry/...` paths become full URLs to the x-hub-system tree.
   Or: add a short top-of-README note saying "canonical spec lives at <link to x-hub-system>; this repo is a placeholder until v0.1 stabilizes."
4. Add a `CONTRIBUTING.md` pointing reviewers to the X-Hub-System spec directory.
5. Commit, push.

**Verify:** the badges in the RFC body resolve. The reader of the RFC can click through to a public repo.

## U-A3 — Submit RFC to MCP specification Discussions

**Task ID:** #9 · **Estimated time:** 30 min · **Dependencies:** U-A1, U-A2

The RFC body is at `specs/mcp-trust-registry/RFC-discussion-body.md` (the file's own top says "Target venue: GitHub Discussion on modelcontextprotocol/specification").

Steps:

1. Go to `github.com/modelcontextprotocol/specification/discussions`.
2. Pick category: **"Ideas"** or **"Show and tell"**. Not "Q&A". Not "General". Not "Polls". The category sets reader expectation; "Ideas" is the most accurate.
3. Title: **`RFC: A trust layer above MCP — federated attestation + capability tokens`**. Exactly this string. Do not embellish ("Proposal:", "[Draft]", etc.) — clean is more credible.
4. Body: copy from `RFC-discussion-body.md` starting from the first `## TL;DR` (skip the front-matter blockquote that describes the file's purpose).
5. Before submitting, walk through every link in the body and confirm it resolves. Especially the `protocol-v0.1.md` link.
6. Submit.

**After submitting:**
- Tweet/X-post (if user wants to amplify) — keep it terse, link the discussion, mention "feedback wanted, especially on capability granularity and federation".
- Drop the link in the MCP Discord if you're a member.
- Do NOT @-mention Anthropic employees by name in either submission or amplification — politically toxic for an "outside-in" RFC.

**Watch for, in first 48 hours:**
- "How does this relate to the official MCP registry?" — answered in RFC body §3. Reply by pointing there.
- "Why federated?" — answered in RFC body §4. Same.
- "Will you implement this?" — answer: reference implementation exists inside X-Hub-System; standalone repo is at `github.com/AndrewXie-Rich/mcp-trust-registry`; v0.1 reference CLI ETA is in the RFC.
- Hostile takes about supply-chain risk being overblown — don't argue. Cite specific recent incidents if you've seen them; otherwise concede that severity is debated and the protocol is opt-in.

## U-A4 — Outreach to MCP server maintainers (pilot publishers)

**Task ID:** #10 · **Estimated time:** half day · **Dependencies:** U-A3 ideally already submitted (so you can link)

Target list (in order of estimated reach × estimated willingness):

1. **`browser-tools-mcp`** (and any browser-automation MCP servers) — high reach, security-relevant.
2. **`mcp-server-sqlite`** — Anthropic-published, low willingness (they may have their own attestation plans) but high signal.
3. **`mcp-server-git`** — Anthropic-published, same dynamic.
4. **`mcp-server-filesystem`** — same.
5. **`mcp-server-slack`** — common in enterprise, attestation makes obvious sense.
6. **`mcp-server-puppeteer`** — security-sensitive (runs Chromium).

For each, send a short email or open a GitHub issue:

```
Subject: pilot proposal — signed attestations for <server-name>

Hi <maintainer>,

I'm working on an RFC for a trust layer above MCP — federated, signed
attestations + capability tokens, with a local proxy that enforces capabilities
at runtime. Spec: <link>. RFC discussion: <link>.

The protocol works regardless of whether publishers sign, but it works better
when widely-used servers like <server-name> have signed manifests as a baseline.

Would you be open to being a pilot publisher? Cost is ~30 minutes once: generate
an ed25519 key, run `mcp-trust sign` on a release tarball, push the attestation
to the federated registry. No long-term commitment; if v0.1 turns out to be
the wrong shape, the keys are throwaway.

Happy to do the first run together (screen-share or async). Open to feedback
on the spec, especially the capability granularity for whatever <server-name>
needs.

Thanks,
Andrew
```

**Track responses** in a simple text file or GitHub project board. Even one "yes" from a non-Anthropic maintainer changes the RFC's social proof significantly.

If no response within a week: don't follow up more than once. Pivot to other maintainers.

## After U-A4: monitoring and iteration

You're now in the "RFC submitted, waiting for community response" phase. Stop adding new artifacts and:

- Monitor the discussion daily for the first week, every 3 days after.
- For each substantive comment, decide: update spec v0.1 inline (small typo / clarification), batch for v0.2 (substantive design change), or rebut in-thread (misunderstanding).
- Don't ship v0.2 in less than 2 weeks. Premature versioning erodes the v0.1 contract.

The next AI work orders (Rust skeletons, iOS app stubs) will be authored when v0.1 stabilizes — typically 4–6 weeks after submission.
