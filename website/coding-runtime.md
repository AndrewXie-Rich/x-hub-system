# Coding Runtime

<p class="lead">
Cursor and Claude Code are great at minute 1. When AI has been running for 5 hours and you come back to half-done work, missing evidence, merge conflicts, and "I think I finished it?" — that's where they stop and X-Hub starts. This page is about the second half of that arc.
</p>

<div class="preview-note">
  <strong>Use the IDE agent for the IDE. Use X-Hub for what happens around it.</strong>
  X-Hub doesn't compete with Cursor / Cline / Aider on inline editing. It sits behind them and answers: where did the run get to, what evidence backs "done," and how do we resume from the wrong checkpoint.
</div>

## One Sentence

X-Hub-System is strongest when a complex project needs to keep moving steadily, not when a tiny task needs the fastest possible first output.

Its advantage shows up after minute 50, hour 5, or day 5, when the system still needs to answer:

- Where is the run now?
- Which steps were verified?
- What is blocked?
- What correction did Supervisor apply?
- Which grants, quota, models, and capabilities were used?
- If interrupted, where can it resume?
- Does final completion have evidence?

## Where It Is Strong

<div class="story-grid">
  <div class="story-card">
    <span>Continuity</span>
    <strong>Not one long chat context holding everything together</strong>
    <p>The direction is run, checkpoint, resume, retry, and recovery. Work can continue across devices and time windows without putting all state inside the active chat.</p>
  </div>
  <div class="story-card">
    <span>Governance</span>
    <strong>A-Tier, S-Tier, Heartbeat, and Review are separate</strong>
    <p>Execution ceiling, supervision depth, review cadence, and intervention behavior are not one vague automation slider. Work can become more autonomous without becoming less controlled.</p>
  </div>
  <div class="story-card">
    <span>Layered memory</span>
    <strong>Supervisor and Coder do not consume the same context</strong>
    <p>Supervisor sees broader context for direction and risk. Project AI / Coder sees focused context for the current step and verification. Strategy and execution do not pollute each other.</p>
  </div>
  <div class="story-card">
    <span>Recovery</span>
    <strong>Failure does not mean starting a new chat</strong>
    <p>Blocked state, evidence, review, guidance, ack, and run truth can return to the Hub. After interruption, the system can decide whether to continue, retry, repair route, rehydrate context, or wait for user judgment.</p>
  </div>
  <div class="story-card">
    <span>Audit boundary</span>
    <strong>Code execution stays under Hub governance</strong>
    <p>Repo edits, build/test, skill calls, model use, quota pressure, and high-risk actions go through grant, policy, audit, and kill-switch control paths. Every authorized action produces a signed <a href="https://github.com/AndrewXie-Rich/x-hub-system/blob/main/specs/hub-receipt/v0.1.md">Hub Receipt</a> — verifiable outside the IDE.</p>
  </div>
  <div class="story-card">
    <span>Evidence closure</span>
    <strong>Done is not a model sentence</strong>
    <p>Completion points to build, test, diff, logs, screenshots, doctor output, review notes, and signed receipts. Weak evidence means done candidate, not done. The receipt chain is what the auditor reads — not the chat history.</p>
  </div>
</div>

This is one of the differences between X-Hub Coding Runtime and a single-session coding assistant: continuity does not depend on an ever-growing prompt. It depends on the Hub-governed memory control plane. Supervisor, Project Coder, personal assistant, and remote channels can receive different memory packs; writeback starts as candidates; evidence, export, and audit remain traceable.

## What Is Still Being Productized

The public story should stay honest: the advantage is clear, but this is not the lowest-friction tool for every coding task.

| Area | Productization focus |
| --- | --- |
| Low-friction small tasks | Quick edits, small demos, and UI spikes need a lighter mode. Not every task should pay the cost of heavy governance |
| A4 execution surfaces | Browser, device, connector, extension, richer skill result contracts, and plan graphs are still being completed |
| Deeper verification chain | Build, test, e2e, evidence, done contracts, and release gates should become more connected than command exit codes |
| Guidance Ack loop | Supervisor guidance needs structured entry into the Coder loop, with ack, defer, and reject all traceable |
| Hub Run Scheduler | Run truth, wake, grants, audit, clamps, and recovery need to become a stronger first-class source of truth |

That means X-Hub-System should not be presented as the fastest quick-prototype tool. It should be understood as a **governed execution system for long-running software work**.

## What the Coder Loop does in practice

X-Hub's coding runtime has internal layers (the harness, the delivery loop, the checklist loop, the spec boundary) — but the user-facing shape is simpler:

- **For quick prototypes:** fast mode. Light checklist, light review. Don't pay the cost of full governance for a 10-minute spike.
- **For normal feature work:** default mode. Agentic delivery, checklist execution, light spec for high-risk edges. This is most of the work.
- **For long-running or high-risk projects:** full mode. Strong spec boundaries, deeper Supervisor review, A3/A4 execution under tight S2/S3 supervision.

The system picks defaults; you can override per-project.

## A-Tier / S-Tier Mapping For Coding

| Scenario | Recommended mode | A-Tier | S-Tier | Notes |
| --- | --- | --- | --- | --- |
| Fast prototype / small demo | Fast Prototype + light checklist execution | A1 / A2 | S1 | Move quickly inside project scope |
| Single feature / medium feature | Agentic Delivery + Checklist Loop + light Spec | A2 / A3 | S2 | Default working mode |
| Long-running larger project | Harness + Agentic Delivery + Checklist Loop + spec-first boundaries | A3 | S2 / S3 | X-Hub-System's strongest fit |
| High-risk automatic execution | Harness + Agentic Delivery + strong spec-first boundaries | A4 | S3 | Only when runtime readiness, grants, policy, and recovery are satisfied |
| New product from zero | Product Discovery -> Agentic Delivery -> spec-first boundaries | A1 -> A2 -> A3 | S2 / S3 | Shape requirements before execution |

The default coding mode should not be pure fast prototyping or an overly heavy multi-role process. It should be:

**Governed Agentic Delivery under A2/A3 + S2/S3.**

## What The Project Coder Loop Should Do

A mature Project Coder Loop needs at least:

1. Receive goal, scope, A/S tiers, and done contract.
2. Produce a step list instead of leaving the task as a vague wish.
3. Verify after each step.
4. Retry within a bounded budget.
5. Capture blocked reason instead of looping forever.
6. Write evidence and run truth at checkpoints.
7. Receive Supervisor guidance and ack, defer, or reject it.
8. Run pre-done review before closure.
9. Enter delivery closure only when evidence is sufficient.

That is the coding difference: not just "the model writes code," but "coding runs inside a sustainable, reviewable, recoverable operating structure."

## Where lighter mode is the right call

Not every task deserves the full governance path.

- small UI polish
- one-off scripts
- low-risk demos
- quick API spikes
- local temporary tools

These should use a lighter Fast Prototype Mode. They still stay inside project scope and baseline safety rules, but they should not require full spec, deep review, and long-cycle heartbeat.

Full governance is for coding work that crosses boundaries, is hard to roll back, has high risk, involves multiple people, or will run for a long time.

Continue with:
[X-Terminal](/x-terminal), [Governance](/governed-autonomy), and [Memory Control Plane](/memory).
