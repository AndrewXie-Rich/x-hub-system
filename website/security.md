# Security Model

<p class="lead">
X-Hub is designed around structural security advantages, not safety theater. The claim is not that risk disappears. The claim is that one prompt injection, one terminal compromise, one imported skill, or one exposed runtime should not automatically become full-system compromise.
</p>

<div class="preview-note">
  <strong>Public security position</strong>
  This page describes the security posture and design direction, not a complete public control catalog. Exact
  implementation details, edge-case handling, and still-evolving defenses are intentionally not all exposed here.
</div>

## The Core Security Position

X-Hub starts from a few structural assumptions:

- the terminal should not be the trust root
- high-risk actions should not proceed on ambiguous or incomplete authorization
- missing readiness should fail closed
- safety should be reinforced by policy, grants, audit, and runtime truth, not by prompts alone

## What This Design Is Trying To Improve

| Common risk pattern | X-Hub design direction |
| --- | --- |
| One client compromise becomes whole-system compromise | Trust, authorization, and higher-risk execution stay anchored in the Hub |
| Reading hostile content turns into exfiltration or destructive action | Policy, governed execution, and system-side controls provide more than prompt-only protection |
| Installed capabilities quietly expand privilege | Capabilities are treated as governed units rather than install-equals-trust shortcuts |
| Operators lose sight of what actually happened | Audit, runtime truth, and explicit system posture stay part of the product direction |

## Fail-Closed Over False Confidence

The public design stance is explicit: when the path is not trustworthy, the system should prefer blocking over pretending
everything is fine.

- no valid grant means no high-risk execution
- no readiness means no silent continuation
- ambiguous grant targeting should not be guessed
- broken pairing or stale trust state should block, not mask

## Why This Goes Beyond Prompt-Only Safety

Prompt wording can help shape behavior, but it is not a trust boundary.

X-Hub is built around layered controls:

- policy and authorization in the control plane
- runtime posture that stays visible to the operator
- memory and guidance that remain attached to the system of record
- memory maintenance authority that stays governed on the Hub side: the user chooses which AI executes memory jobs, while durable writes still terminate through `Writer + Gate`
- audit trails that help explain what happened
- a local-first operating path for teams that want tighter control over privacy and dependencies

This matters because behavior stays bounded by persistent system controls instead of whichever prompt or client surface happened to be active.

## Why User-Owned Posture Matters

If you run the Hub on user-owned hardware and keep the core path local, you reduce the number of outside systems that
need to be trusted for day-to-day execution.

That can improve control over:

- privacy posture
- secret handling
- provider dependency
- release timing and change control

It does not remove risk. Local compromise, hostile files, bugs, and operator mistakes can still exist. The point is not
magic safety. The point is a more defensible trust boundary.

## Cloud Versus User-Owned Control

| Typical cloud-agent default | X-Hub position |
| --- | --- |
| Vendor-hosted control plane | User-owned Hub host |
| Vendor holds more runtime truth by default | Memory truth, routing, and audit stay anchored to the Hub |
| Secret handling and policy are abstracted behind SaaS defaults | Grants, readiness, posture, and release timing remain user decisions |
| Local-only mode is weak or secondary | Local and paid models can sit under the same governed plane |

## What Security-Conscious Teams Gain

- reduced blast radius by design
- clearer runtime truth when something downgrades or blocks
- more credible user control over privacy, keys, and execution authority
- a safer path for external ingress and governed capabilities
- a stronger foundation than install-equals-trust ecosystems
