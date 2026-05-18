# Capability Governance

Capability governance decides what an agent can ask for, what it can run now, why it is blocked, and how it can be safely unblocked.

This is one of XHub's core differences from a normal tool whitelist. XHub governs semantic capability first, then maps capability to skills, tools, runtime surfaces, project policy, and user approvals.

## Capability Chain

```text
skill or tool semantics
  -> capability family
  -> capability profile
  -> grant floor
  -> approval floor
  -> project capability bundle
  -> runtime surface clamp
  -> preflight
  -> runtime allow / deny
  -> doctor / governance / route truth
```

## Capability Families

Families are atomic capability meanings:

- repo.read
- repo.mutate
- repo.delivery
- web.live
- browser.observe
- browser.interact
- browser.secret_fill
- device.act
- memory.read
- memory.write
- skill.execute

Families should be stable contract terms, not UI labels.

## Capability Profiles

Profiles are user-facing and policy-facing bundles:

- observe_only
- coding_execute
- browser_research
- browser_operator
- browser_operator_with_secrets
- delivery
- device_governed
- supervisor_full

Profiles should be derived from capability declarations and project policy, not manually guessed per call.

## A-Tier And S-Tier

A-Tier defines the maximum autonomy of Project AI execution.

It should affect the project capability ceiling, but it should not replace runtime surface checks, grant checks, quota checks, or kill switches.

S-Tier defines how deeply Supervisor watches and intervenes.

It should not be merged into A-Tier. Autonomy and supervision are different axes.

## Runtime Surface

Runtime surface answers: can this machine and session run this capability now?

Examples:

- local tools available
- trusted automation ready
- browser runtime ready
- device runtime ready
- Hub bridge available
- skill runner available
- secret store available
- provider quota available

A capability may be allowed by policy but still blocked by runtime surface.

## Rust Authority Boundary

Capability is a good Rust governance target, but Rust should not independently redefine the capability system.

The safe route is:

1. Freeze the capability contract across Hub, XT, and Rust.
2. Add schema version and contract hash.
3. Generate or consume shared constants and validators.
4. Let Rust run shadow derivation and preflight evidence.
5. Promote Rust to preflight authority only after semantic diff is clean.
6. Promote Rust to lease authority before any long-term grant writer authority.

Today, JS Hub and Swift XT still carry much of the production capability truth. Rust should first be the deterministic policy/preflight/evidence kernel.

## Capability Lease

Capability Lease should become a first-class object.

A lease can define:

- project id
- run id
- request id
- skill or tool id
- capability family/profile
- target domain or resource
- secret class
- TTL
- single-use or reusable behavior
- revocation token
- approval evidence
- preflight evidence

This is more precise than broad permanent grants. It lets XT show exactly what is being allowed, while Hub/Rust can fail closed when the lease expires, drifts, or is revoked.

## Multi-Axis Readiness

Readiness should be explainable across multiple axes:

- structural readiness: manifest, schema, ABI, package body
- trust readiness: signature, publisher, channel, pin, vetter
- policy readiness: project tier, grants, approvals
- surface readiness: browser, device, repo, secret store, provider
- temporal readiness: quota, cooldown, reset time, lease TTL
- evidence readiness: doctor and audit references

This makes denial actionable instead of opaque.

## Governance Simulator

A governance simulator should answer:

- What becomes runnable if project moves from A2 to A3?
- What is still blocked if browser runtime becomes ready?
- What extra approval does this skill need?
- What lease would unblock the requested action?
- Why did a previous run pass while this one fails?

## Product Interpretation

For GitHub readers, the short version is:

XHub governs agents by semantic capability, not by raw tool access. It can explain what an agent is allowed to do, what is blocked right now, what evidence caused the decision, and what bounded approval would unblock the action.
