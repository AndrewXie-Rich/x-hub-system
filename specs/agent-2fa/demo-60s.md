# agent-2fa — 60-Second Demo Script

A shot-by-shot recording script for the headline demo. Target medium: **asciinema cast embedded at the top of the README**, optional MP4 export for Twitter / 小红书.

**Total duration target:** 55–65 seconds.
**Terminal:** 100 cols × 28 rows, dark theme, monospaced font.
**Voiceover:** none (text-only); on-screen captions only at scene boundaries.
**Recording:** `asciinema rec --idle-time-limit 1.0 demo.cast`. Idle clamp is critical — natural typing pauses ruin pacing.

---

## Cast of characters

- `agent2fa` — the CLI being demoed.
- `agent-cli` — stand-in for any AI agent runtime.
- `alice-iphone`, `bob-laptop` — two paired Authorizer Devices belonging to two distinct humans.
- A fictional Postgres `prod_logs` table that the agent is asked to drop.

---

## Scene 1 — Pair a phone with the workstation (0:00–0:15)

**Caption (overlay, 2s):** *"Pair an Authorizer Device — Touch ID on a second device, not the workstation."*

```text
$ agent2fa pair

  generating ed25519 keypair for this device…
  device_id: workstation-andrew
  pubkey   : ed25519:k0a7…

  scan this QR with the Authorizer iOS app:
     [QR code rendered here]

  waiting for response…
  ✓ alice-iphone responded   (pubkey ed25519:m9b2…)
  ✓ touch ID confirmed on alice-iphone

  paired. trust record persisted at ~/.agent2fa/trust/
```

**Pacing:** ~15 seconds. The QR display is 3-4 seconds; the response is near-instant on LAN.

**What viewer should feel:** "Oh. The phone is the second factor, and pairing is a one-time mutual handshake — no account, no cloud."

---

## Scene 2 — Routine action runs silently (0:15–0:30)

**Caption (overlay, 1.5s):** *"Routine actions — policy says `notify`, no challenge fires."*

```text
$ agent2fa run -- agent-cli "deploy to staging"

  ▸ classifying action…
    rule matched: { command: "^deploy" }  →  risk: notify
  ▸ agent-cli: invoking deploy.sh staging

  ✓ deploy to staging completed in 47s

  [agent2fa] 1 action, 0 challenges raised
             receipt: a2fa-6b0c (logged)
```

**Pacing:** ~12 seconds.

---

## Scene 3 — High-risk action requires confirmation (0:30–0:45)

**Caption (overlay, 1.5s):** *"High-risk action — policy raises a Challenge to your phone."*

```text
$ agent2fa run -- agent-cli "drop the prod_logs table"

  ▸ classifying action…
    rule matched: { command: "^(DROP|TRUNCATE)\\s+" }  →  risk: confirm
  ▸ challenge chg-3a7f12bc dispatched to: alice-iphone

  [Authorizer iOS shows:
     "Allow `agent-cli` to: DROP TABLE prod_logs?"
     [ Deny ]                              [ Allow with Touch ID ]
   touch ID ✓ ]

  ▸ alice-iphone: touch_id ✓ allow  (chg-3a7f12bc)
  ▸ executing agent-cli…
  ✓ DROP TABLE prod_logs completed

  [agent2fa] 1 action, 1 challenge, 1 authorization
             receipt: a2fa-7c1e (Hub Receipt envelope, signed)
```

**Pacing:** ~15 seconds. The phone-side panel render is ~3s; the Touch ID tap is ~1.5s.

---

## Scene 4 — `dual_confirm` denies, action aborted (0:45–1:00)

**Caption (overlay, 1.5s):** *"Escalated to `dual_confirm`. Second authorizer denies."*

```text
$ agent2fa policy load strict.yaml
  ✓ policy loaded. default=dual_confirm.

$ agent2fa run -- agent-cli "drop the prod_logs table"

  ▸ classifying action… rule matched. risk: dual_confirm
  ▸ challenge chg-4e8d2a91 dispatched to: alice-iphone, bob-laptop

  ▸ alice-iphone: touch_id ✓ allow
  ▸ bob-laptop:   touch_id ✗ deny  (reason: "let's discuss first")

  ✗ quorum_not_reached  (1 of 2 allow)
  action aborted. receipt: a2fa-7c4f (denial recorded, signed)
```

**Pacing:** ~15 seconds. Bob's deny appears 2-3 seconds after Alice's allow.

---

## End frame (1:00, hold 3s)

```text
─────────────────────────────────────────────
  agent-2fa                  spec v0.1 draft
  github.com/AndrewXie-Rich/agent-2fa
─────────────────────────────────────────────
```

**Caption (overlay, full 3s):** *"Touch ID for AI agent actions. Per-action, signed, fail-closed."*

---

## Editing checklist

- [ ] Use asciinema `--idle-time-limit 1.0`; post-process with `agg` if pacing needs smoothing.
- [ ] Receipt IDs across scenes 2-4 must be visibly different (`a2fa-XXXX` format).
- [ ] Scene 3 phone-side panel MUST show verbatim action text (`DROP TABLE prod_logs`) — the "no phishing" beat. Composite a real iOS screenshot, not ASCII art.
- [ ] Hold Scene 3 Touch ID tap for extra 0.5s.
- [ ] Both `chg-3a7f12bc` (Scene 3) and `chg-4e8d2a91` (Scene 4) visible long enough to read.
- [ ] Export `.cast` (asciinema) + `.mp4` 1280×720 (social) + 16:9 thumbnail of Scene 3 phone prompt.

---

## Why these four scenes (not other ones)

These four beats teach the entire value proposition without ever explaining it:

1. **Scene 1** — pairing is mutual, one-time, no cloud account.
2. **Scene 2** — the gate is invisible when actions are routine; policy decides.
3. **Scene 3** — destructive actions raise a verbatim prompt on a second device, signed off via Touch ID.
4. **Scene 4** — `dual_confirm` is real; two humans on two devices; denial is signed evidence.

Anything else (modality enumeration, transport details, time-box semantics, threat model) is in the spec. 60 seconds is the budget for the feeling; longer dilutes it.

---

## Alternative shorter cut — 30 seconds for Twitter/X

Drop scenes 1 and 4. Keep:

- Scene 2 condensed to 10s (skip the receipt-id line).
- Scene 3 at full 15s.
- 5-second end caption: "Touch ID for AI agent actions. github.com/AndrewXie-Rich/agent-2fa"

The arc becomes: routine actions just run → destructive ones raise a verbatim Touch ID prompt, signed both ways. Loses pairing setup and dual-confirm denial; keeps the headline beat.

---

## What NOT to put in the demo

- No comparison to WebAuthn / FIDO2 / YubiKey on-screen. The protocol spec §14 handles this.
- No mention of X-Hub-System in the demo terminal. (README handles the pointer.)
- No vendor or IDE-brand logos. Risk of takedown; also distracts.
- No melodramatic capitalization on `DROP TABLE`. The action text speaks for itself.
- No fake credit card / "password leaked" framing. Stay with operational destruction; that's the actual threat model.
- No "before / after prompt injection epidemic" framing. Let viewers connect the relevance.
