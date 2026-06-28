# For families

<p class="lead">
Your kid uses ChatGPT to do homework. Your teenager uses Claude for projects. AI is already in your home. The question isn't whether it should be — it's what happens the first time it tries to do something nobody told you about.
</p>

<div class="preview-note">
  <strong>Family mode is the same MIT-licensed Hub teams use.</strong> No separate product. No subscription. Parent runs the Hub (admin); kids' clients run as governed users.
</div>

## Three things you've probably already imagined

<div class="story-grid">
  <div class="story-card story-card--risk">
    <span>The cleanup</span>
    <strong>Kid asks AI to "clean up the Downloads folder."</strong>
    <p>AI helpfully runs <code>rm -rf ~/Downloads/</code>. In there: school papers, vacation photo backups, the half-finished birthday-card design you saved last week. No undo.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>The email</span>
    <strong>Kid asks AI to "email Mrs. Chen about the field trip."</strong>
    <p>AI picks the wrong Mrs. Chen from contacts and sends a message to your boss's wife. Or worse — drafts something embarrassing and sends before you see it.</p>
  </div>
  <div class="story-card story-card--risk">
    <span>The subscription</span>
    <strong>Kid asks AI to "get me access to that game pass."</strong>
    <p>AI walks through a sign-up flow with your saved card, recurring billing turned on. You find out a month later when the statement comes.</p>
  </div>
</div>

These aren't hypothetical. By 2026 every major AI tool can act on tools, browsers, files, and accounts. The "are you sure?" prompt inside the chat window is the wrong place to confirm.

## How X-Hub puts the decision back in your hands

<img class="diagram-frame" src="/family_approval_flow.svg" alt="Family approval flow: kid's device → AI plans action → X-Hub policy gate → parent's phone tap → action runs or denies, signed receipt either way" />

The flow is the same whether the action is a delete, an email, a payment, or a download:

1. **Kid's device** asks the AI for something.
2. **AI plans an action**. (It doesn't know what's important to your family.)
3. **Hub policy gate** classifies the action by your rules. Notify-tier (auto). Confirm-tier (one approver). Dual-confirm tier (two approvers for the really destructive stuff).
4. **Parent's phone** gets a push: "Allow DELETE ~/Downloads/?" Touch ID confirms.
5. **Action runs or denies** — and a signed receipt is recorded either way. You can read why something was blocked later, without having to watch every chat in real time.

## What's actually on your phone

The push looks like this (mock-up, not a final UI):

```
X-Hub · Now
─────────────────────────────────────
ALLOW THIS ACTION?

Device: Mia's iPad (paired 2026-03-04)
Tool:   Claude
Action: DELETE ~/Downloads/ (recursive)
Risk:   dual_confirm  (matches "rm|delete")

[ Deny ]               [ Touch ID to Allow ]
```

You see exactly what's being requested, on which device, by which AI tool. No surprise charges. No "the AI just did it."

## Setup, day one

You don't need to be a developer. The setup is:

1. **Install X-Hub on your Mac.** Drag the app to Applications. Launch it. Pair your phone (QR code).
2. **Pick a policy template.** Three come built in: `personal`, `team`, `strict`. `strict` is the right default for kids — dual_confirm on anything irreversible, confirm on most things, notify on a small allowlist.
3. **Hand the kid an iPad / their laptop / whatever device they use.** From the device's AI app, scan the QR code X-Hub shows. Done — that device is a paired client.

After that, every AI request from the kid's device routes through the Hub. You don't have to install anything special on the AI tool itself. The Hub sits between them.

## What X-Hub does NOT do

This is a parental control layer, not surveillance. Honesty about what's outside scope:

| Scope | Not in scope |
|---|---|
| Approve destructive actions before they happen | Read every chat in real time (you can if you want — but it's not on by default) |
| Set spending limits across providers | Pre-filter what kids can ask the AI |
| Verify what the AI actually did, after the fact | Track location, install spyware, override what the kid is doing on the device generally |
| Govern AI-initiated actions on shared resources | Govern the kid's *own* files on their *own* device unless the AI touches them |

The principle: kids get freedom inside their device. The Hub only steps in when AI tries to act on the family's shared world — accounts, money, files outside the kid's user space, outgoing messages.

## Why per-action confirmation matters more for kids

Adults read AI output before approving it. Kids skim. Kids trust. Kids don't yet have the instinct for "wait, that's weird." The window between "AI suggests something" and "kid clicks yes" is shorter for kids than for you.

X-Hub puts a separate-device tap in that window. Same primitive your bank uses when a charge looks unusual: the action waits for a confirmation on a device the kid isn't holding.

## Older kids and teenagers

For older kids who are already responsible AI users, you can give them their own `operator` role: they can use AI tools normally, they get their own audit log, and only specific high-risk actions (large payments, destructive deletes, outgoing emails to unknown addresses) need your tap. As they show good judgment, you relax the policy.

For younger kids, default to `strict` and tighten what they can do unattended.

The same Hub serves both. You just adjust who has what role.

## What a week looks like

After a week of running, X-Hub gives you a digest you can actually read in 30 seconds:

```
This week, AI ran 247 actions for your family.
  - 218 ran silently (file edits, code generation, normal chat)
  - 27 you approved via your phone
  - 2 you denied
  - 0 ran without authorization

Notable:
  - Mia tried to download a Roblox plugin — blocked (unknown publisher)
  - Eli used Claude for 4 hours of homework — within budget
  - Jamie's AI suggested a $24/mo subscription — you denied
```

That's the entire "did anything bad happen" question, answered.

## FAQ

**Does X-Hub work with Claude / ChatGPT / Gemini?**
Yes. X-Hub sits between the AI client and the actions it tries to take. It doesn't replace your AI provider; it governs what their output can touch.

**Does my kid see that I'm in the loop?**
Yes. When an action needs approval, the kid sees "waiting for parent approval" on their device. This is intentional — you're teaching them what's high-risk, not spying on them.

**What if I'm not home and they need a quick approval?**
The push comes through wherever your phone has signal. Approve from anywhere. Or pre-authorize specific patterns ahead of time ("Mia can download from the school's domain without asking") — these are signed bypass entries with time limits.

**Can I see what AI my kid is using?**
Yes — every action logs which AI tool initiated it and which model actually ran. You can see "Claude was used 47 times this week, GPT 12 times" without having to read chats.

**Is this surveillance?**
No. The Hub records *attempted actions*, not chats. If your kid asks Claude for advice on a sensitive personal topic and Claude just answers, that conversation doesn't show up here. Only when AI tries to *do* something — touch files, send messages, charge accounts — does the Hub get involved.

**My kid is a developer — won't they just go around the Hub?**
Possible, but harder than it sounds. The Hub is the trust root for paired devices. Going around it means re-pairing the device, which prompts you. And every AI tool that uses a normal model API or MCP server gets routed through the Hub by default once the device is paired.

## Where to start

1. Read [Get Started](/get-started) — the install path.
2. See the [Trust Model](/security) — the security claims, written plainly.
3. Check [Status & Roadmap](/status-roadmap) — what's working today vs. what's coming.

Or jump straight to: [github.com/AndrewXie-Rich/x-hub-system](https://github.com/AndrewXie-Rich/x-hub-system).

Continue with:
[Use Cases](/scenarios), [Why this matters now](/why-now), [For my team](/team).
