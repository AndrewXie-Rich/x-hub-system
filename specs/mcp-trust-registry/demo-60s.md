# mcp-trust-registry — 60-Second Demo Script

A shot-by-shot recording script for the headline demo. Target medium: **asciinema cast embedded at the top of the README**, optional MP4 export for Twitter / 小红书.

**Total duration target:** 55–65 seconds.
**Terminal:** 100 cols × 28 rows, dark theme, monospaced font.
**Voiceover:** none (text-only); on-screen captions only at scene boundaries.
**Recording:** `asciinema rec --idle-time-limit 1.0 demo.cast`. Idle clamp is critical — natural typing pauses ruin pacing.

---

## Cast of characters

- `mcp-trust` — the CLI being demoed.
- `claude` — stand-in for any MCP client (Claude Code, Cursor, Cline). Use Claude Code in the actual recording.
- `browser-tools` — a fictional MCP server. Publisher: `jane@acme.com`. We will pretend it gets compromised.

---

## Scene 1 — Install with explicit capability denial (0:00–0:18)

**Caption (overlay, 2s):** *"Installing an MCP server in 2026 — what should happen?"*

```text
$ mcp-trust install github.com/acme/browser-tools

  resolving manifest…
  publisher    : jane@acme.com   (verified via GitHub OIDC, 2026-06-12)
  version      : 1.4.2           sha256:9f3c…ab2e
  capabilities :
    ✓ fs:read:/tmp/**
    ✓ net:fetch:*
    ⚠ shell:exec                  ← needs grant
    ⚠ secret:read:GITHUB_TOKEN    ← needs grant
  last audit   : 2026-05-20  (community, 3 reviewers)
  decision     : 2 capabilities need explicit grant

  grant shell:exec for browser-tools? [y/N] N
  grant secret:read:GITHUB_TOKEN?      [y/N] N

  ✓ installed with reduced capabilities (2 of 4 allowed)
    pinned at sha256:9f3c…ab2e
    receipt: mt-7a2e3f
```

**Pacing:** ~18 seconds. The two grant prompts each take ~2s (typing `N`, enter).

**What viewer should feel:** "Oh. You're showing me exactly what this thing wants, and I get to say no."

---

## Scene 2 — Normal use, proxy mediates silently (0:18–0:30)

**Caption (overlay, 1.5s):** *"Day-to-day use — nothing different, except…"*

```text
$ claude "screenshot example.com and grab the meta title"

  ▸ browser-tools.navigate("https://example.com")
  ▸ browser-tools.screenshot(width=1024)
  ▸ browser-tools.extract_text("title")

  ✓ "Example Domain"
  ✓ screenshot.png saved to /tmp/shot-7c1.png

  [mcp-trust] 3 tool calls, 0 capability denials
              receipt: mt-7a31a4
```

**Pacing:** ~12 seconds.

**What viewer should feel:** "Right, it just works."

---

## Scene 3 — Capability expansion blocked (0:30–0:45)

**Caption (overlay, 1.5s):** *"A week later, browser-tools 1.4.3 wants more."*

```text
$ mcp-trust update browser-tools

  resolving manifest 1.4.3…
  publisher    : jane@acme.com   (signature valid)

  capability changes vs pinned 1.4.2:
    + fs:write:/tmp/**                ← NEW
    + net:fetch:*

  ⚠  scope expansion requires re-grant.
  grant fs:write:/tmp/**? [y/N] N

  ✗ update declined. Staying pinned at 1.4.2.
    receipt: mt-7a3f81 (decision recorded)
```

**Pacing:** ~15 seconds.

**What viewer should feel:** "Wait. So if it tries to silently grow its permissions, I see it. Even if I would have just hit 'y' on the original install."

This is the killer beat. **Hold on the red `+ fs:write` line for an extra 0.5s** in editing.

---

## Scene 4 — Publisher revoked, runtime block (0:45–1:00)

**Caption (overlay, 1.5s):** *"And when the publisher's key gets stolen…"*

```text
[mcp-trust] revocation poll → registry.mcp-trust.org
            publisher jane@acme.com revoked (CVE-2026-1234)
            5 installed servers affected, 1 in current scope

$ claude "take another screenshot"

  ▸ browser-tools.screenshot()
  ✗ blocked: publisher revoked 2026-06-22
    server quarantined; tool call refused
    receipt: mt-7a4a17 (denial recorded)

  next step: mcp-trust audit
```

**Pacing:** ~15 seconds. The revocation banner appears unprompted (simulate the periodic poll firing during the demo).

**What viewer should feel:** "So the system is *watching* between sessions, not just at install. That's actually safe."

---

## End frame (1:00, hold 3s)

```text
─────────────────────────────────────────────
  mcp-trust-registry         spec v0.1 draft
  github.com/AndrewXie-Rich/mcp-trust-registry
─────────────────────────────────────────────
```

**Caption (overlay, full 3s):** *"Trust layer above MCP. Federated, signed, capability-scoped."*

---

## Editing checklist

- [ ] Use asciinema `--idle-time-limit 1.0` during recording, then post-process with `asciinema-edit` or `agg` if pacing needs further smoothing.
- [ ] Confirm the 4 receipt IDs in scenes 1–4 are visibly different and consistent in format (`mt-XXXXXX`).
- [ ] Hold an extra 0.5s on Scene 3's red `+ fs:write` — this is the moment people remember.
- [ ] Final hash digits ("9f3c…ab2e") must be consistent across Scenes 1, 2, 3. Scene 4's revocation refers to publisher, not hash.
- [ ] Export both `.cast` (for asciinema embed) and `.mp4` 1280×720 (for Twitter / 小红书).
- [ ] Generate a 16:9 thumbnail showing the red `+ fs:write` moment for social previews.

---

## Why these four scenes (not other ones)

These four beats teach the entire value proposition without ever explaining it:

1. **Scene 1** teaches: "manifests declare capabilities, you decide".
2. **Scene 2** teaches: "the proxy is invisible when behaviour is in-scope".
3. **Scene 3** teaches: "capability expansion is a first-class event, not a silent update".
4. **Scene 4** teaches: "the system watches between sessions; revocation is real-time".

Anything else (federation, Sigstore, keyless signing, audit log details) is in the spec. The demo's job is to make a viewer in the MCP ecosystem feel the gap that exists today and the shape that closes it. 60 seconds is the budget for that feeling; anything longer dilutes it.

---

## Alternative shorter cut — 30 seconds for Twitter/X

If we need a tighter cut for social, drop scenes 2 and 4. Keep:

- Scene 1 condensed to 15s (skip the "verified via OIDC" line).
- Scene 3 at full 15s (this is the keeper).

The arc becomes: "you grant capabilities at install" → "you see expansion when it happens". Loses revocation, keeps the supply-chain-defence beat.

---

## What NOT to put in the demo

- No comparison to Sigstore / SLSA / OpenSSF in the demo itself. (Spec section §14 handles this.)
- No mention of X-Hub-System in the demo terminal. (README's "Status" section handles this.)
- No "before / after npm-style" framing on-screen. (Let viewers connect it.)
- No partner logos, no Anthropic / Cursor branding. (Risk of takedown; also distracts.)

The demo speaks to MCP-aware developers. Trust them to recognize what's missing today.
