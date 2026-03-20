# Governed Skills

<p class="lead">
X-Hub treats skills as governed capability units, not plugin roulette. The point is not only to expose more tools. The point is to make reusable execution paths reviewable, pin-able, auditable, retryable, and revocable.
</p>

## The Skill Boundary

Many agent stacks expose tools directly and let the model improvise everything else.

X-Hub moves one level up:

- skills can carry structured inputs and outputs
- execution mapping can be stabilized
- risk boundaries can be attached
- routing and review can happen before side effects

## The Dispatch Path

The intended runtime path is:

`skill intent -> governed dispatch -> tool execution`

That matters because it creates room for:

- policy checks
- grants
- deny codes
- audit references
- evidence references
- fail-closed rejection before execution

## Why This Is Stronger Than Loose Plugins

| Loose plugin model | Governed skill model |
| --- | --- |
| install often implies trust | trust can be separated from local enablement |
| tool usage dissolves into chat logs | skill activity can keep structured records |
| retry means "ask the model again" | retry can replay governed dispatch with the same guarded arguments |
| local client often becomes the final authority | the Hub can pin, audit, revoke, and route the package |

## Trust Chain Direction

The current direction includes:

- official skill catalog
- publisher trust roots
- package pinning
- compatibility and doctor surfaces on the terminal side
- governed import and promotion flow

That means the Hub can become the place where skill trust is held without turning the Hub into a place where arbitrary third-party code automatically becomes the trust anchor.

## Why This Matters For Long-Running Systems

If you want AI systems to operate across longer projects and higher-risk surfaces, skill quality has to be durable.

That is why governed skills matter:

- they are more reusable than one-off prompt plans
- they are more observable than raw tool calls
- they are easier to audit and recover
- they attach better to memory, review, and project continuity

The result is not just more capability.
It is a more governable execution substrate.
