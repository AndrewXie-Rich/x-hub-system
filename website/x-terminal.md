# X-Terminal

<p class="lead">
If you're running 2+ AI-driven projects at once, X-Terminal is the workspace that keeps them from blurring together. It's not a chat window with extra tabs. It separates execution, supervision, and review — so an agent can keep moving on three projects while you actually understand what's happening on each.
</p>

<div class="preview-note">
  <strong>One paired surface, not the only one.</strong>
  X-Terminal is the deepest paired client today. The Web thin client (in flight, 90-day P0) is the alternative for Windows / Linux team members. See <a href="/architecture">Architecture</a> for the full surface map.
</div>

## The Four Roles

| Role | Responsible For | Not Responsible For |
| --- | --- | --- |
| User | Goals, boundaries, and key decisions | Watching every tool call |
| Project AI / Coder | Continuous execution, code changes, tests, blockers, evidence | Final authorization and durable memory truth |
| Supervisor | Global view, review, drift detection, correction, user reporting | Rewriting every coder step |
| Hub | Grants, policy, memory truth, quota, audit, runtime truth, kill switch | Handing trust to one terminal |

## Three Independent Dials

X-Terminal does not compress everything into one "automation level" slider. It separates execution, supervision, and review cadence.

### A-Tier: how far Project AI may go

| Tier | Meaning |
| --- | --- |
| A0 Observe | Reads project state and memory, gives advice, does not advance work automatically |
| A1 Plan | Creates plans and work orders, writes project memory, but does not modify repo or device state |
| A2 Repo Auto | Edits files inside the project root, runs build/test, produces patches and evidence |
| A3 Deliver Auto | Continues toward delivery, stage summaries, and completion reporting |
| A4 Agent | Uses broader governed execution surfaces such as browser, device, connector, and extension |

### S-Tier: how deeply Supervisor watches and corrects

| Tier | Meaning |
| --- | --- |
| S0 Silent Audit | Watches heartbeat and audit only |
| S1 Milestone Review | Reviews milestones, blockers, and pre-done moments |
| S2 Periodic Review | Runs periodic review on a set cadence |
| S3 Strategic Coach | Adds event-driven review and correction for drift or better paths |
| S4 Tight Supervision | High-frequency review, stronger confirmation, and fine-grained rescue |

### Heartbeat / Review: when to look and when to intervene

| Signal | Role |
| --- | --- |
| Project Execution Heartbeat | Whether work is active, blocked, risky, evidenced, or ready for next action |
| Supervisor Governance Heartbeat | Whether Supervisor should review, how deep, and whether correction is needed |
| Lane Vitality Signal | Whether the XT runtime path is stalled, routed incorrectly, or losing callbacks |
| User Digest Beat | Human-readable summary: what changed, why it matters, and what happens next |

Short memory version:

- A decides what the Coder may do.
- S decides how deeply Supervisor watches.
- Heartbeat / Review decides how often to inspect and what events trigger review.

## A4 Is Not Unsupervised Autopilot

A4 is better described as high-autonomy execution with side-channel governance.

Runtime shape:

1. Project Coder Loop keeps advancing the project.
2. Supervisor Governance Loop reviews on cadence or events.
3. Hub Run Scheduler maintains run truth, grants, audit, wake, clamp, and kill authority. Every authorized step produces a signed [Hub Receipt](https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md) — verifiable outside X-Hub.
4. High-risk actions still depend on capability, scope, TTL, policy, grants, and runtime readiness. Destructive actions trigger paired-device confirmation via [agent-2fa](https://github.com/AndrewXie-Rich/agent-2fa).

So A4 is not maximum permission. It is the highest governed autonomy tier.

## Safe-Point Guidance + Ack

Supervisor should not interrupt every coder step. The intended flow is:

1. Coder reaches a tool boundary, step boundary, or checkpoint.
2. Supervisor creates a structured Review Note.
3. The system turns it into Guidance Injection.
4. Guidance lands at a safe point unless high risk or kill switch requires immediate action.
5. Coder must ack, defer, or reject with a reason.

That keeps the system from drifting without turning review into a synchronous approval gate.

## What The User Should Experience

The user should not see lane ticks, raw grant noise, or internal runtime chatter. The user should see:

- which project made meaningful progress
- which project is blocked and why
- what correction Supervisor applied
- which actions need user decision or authorization
- what the system plans to do next

X-Terminal turns multi-project AI work from a chaotic chat stream into an execution workspace with state, roles, evidence, and shutdown authority.

Continue with:
[Coding Runtime](/coding-runtime), [Governance](/governed-autonomy), [Memory Control Plane](/memory), and [Use Cases](/scenarios).
