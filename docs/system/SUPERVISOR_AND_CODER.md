# Supervisor and Coder

Project Coder executes. Supervisor governs. Hub controls authority. The user sets goals and makes key decisions.

This is not two parallel chatbots. It is a two-layer agent runtime: one layer moves the project forward, and one layer keeps the work aligned, bounded, and recoverable.

## Project Coder

Project Coder is the focused execution agent.

It should:

- understand current project context
- plan the next local step
- call tools and skills through governed routes
- edit files
- run checks
- capture blockers
- verify results
- write structured progress
- continue until done, blocked, cancelled, or policy stops it

It should not:

- expand permissions by itself
- bypass Supervisor
- ignore runtime policy
- invent unavailable skills
- claim completion without evidence
- silently continue after repeated failure

Coder is optimized for local progress.

## Supervisor

Supervisor is the governance and orchestration layer.

It should:

- watch project direction
- assess risk and progress
- decide intervention depth
- review heartbeat quality
- inject guidance at safe points
- summarize for users
- trigger recovery or repair
- coordinate multi-lane work when needed
- escalate approval, capability, or policy gaps

Supervisor should not become a second always-on coder that fights Project Coder. It should intervene when the evidence says intervention is useful.

## Collaboration Loop

```text
User gives goal
  -> Coder executes project steps
  -> tools / skills / checks produce evidence
  -> runtime records progress, blockers, route truth, and policy truth
  -> Supervisor reviews signals
  -> Supervisor allows, suggests, replans, pauses, or escalates
  -> Coder continues under updated constraints
```

The loop should be event-driven, not constant micromanagement.

## Intervention Depth

Strong coder / low risk:

- lighter Supervisor intervention
- fewer safe-point interruptions
- heartbeat monitoring only
- event-driven review
- larger work chunks

Weak coder / high risk:

- more review
- smaller work orders
- stronger guidance acknowledgement
- more frequent safe points
- stricter done verification
- earlier escalation to user approval

This keeps the system from slowing down trivial work while still protecting high-risk changes.

## Runtime And Scheduler Relationship

Supervisor decides whether work should proceed.

Scheduler decides whether work owns capacity.

Coder executes only after both the governance path and runtime capacity path allow it. This separation matters because a project can be allowed by policy but queued by capacity, or blocked by policy while capacity is available.

Rust scheduler authority should strengthen this layer first: claim, lease, heartbeat, release, cancel, timeout, and recovery are deterministic and testable.

## XT Rust Sidecar Boundary

XT Rust sidecar should focus on hot runtime paths:

- event subscription
- snapshot assembly
- checkpoint recovery
- low-latency local reads
- background bridge health

It should not replace Swift UI, approval UX, project cockpit, or Supervisor presentation.

Swift XT remains the product shell. Rust sidecar provides faster and more reliable backend plumbing where determinism matters.

## Coding Method

The best fit is:

> Harness foundation + Agentic workflow + Ralph-style execution loop + SDD at high-risk boundaries + Vibe mode for small exploration.

Do not turn every small task into heavy governance. Do not turn high-risk runtime work into casual exploration.

## Product Interpretation

For GitHub readers, the short version is:

XHub separates doing from governing. Project Coder pushes the task forward; Supervisor watches direction, risk, evidence, and recovery; Hub enforces authority boundaries underneath both.
