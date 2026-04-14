# X-Hub Whitepaper Preview

> Public note: X-Hub is still an early test release.
>
> Core runtime paths already work, but product completeness, onboarding, edge-case handling, and operational polish are still in progress.

This file is the current public landing page for the X-Hub whitepaper direction.

The long-form whitepaper may still move into a separate repository and later mount back into this codebase as a submodule under `docs/whitepaper/`. Until that is ready, this page explains the thesis, current status, and why the project is being opened early.

## One-Line Thesis

X-Hub separates **trust** from the terminal.

The Hub owns pairing, route control, grants, policy, memory truth, constitutional guardrails, audit, and kill-switches; terminals remain replaceable execution and interaction surfaces instead of becoming the trust anchor.

## Why This Direction Matters

Most AI products optimize for response generation first and governance later.

X-Hub starts from the opposite end:

- one control plane for local models and paid models
- one place for readiness, grants, and policy decisions
- one memory-backed system of record instead of scattered client-side state
- one audit surface for side effects, routing, and safety-critical execution
- one Supervisor-oriented orchestration path for work that is too large for a single chat loop

That still does not make terminals or skill runtimes the memory authority: the user still chooses which AI executes memory jobs in X-Hub, `Memory-Core` remains the governed rule layer, and durable writes still terminate through `Writer + Gate`.

The goal is not just to answer better. The goal is to make AI execution more governable, inspectable, and recoverable.

## Current Public Preview Status

What already exists in the repository and preview builds:

- X-Hub app build and run path on macOS
- X-Terminal build and packaged app path
- paired Hub <-> Terminal execution over local and remote routes
- Hub-governed local and paid model routing
- truthful configured-model vs actual-model visibility in X-Terminal
- early Supervisor, project orchestration, and governed runtime surfaces
- Hub-backed memory and X-Constitution foundations

For memory specifically, keep the public boundary precise: the user still chooses which AI executes memory jobs in X-Hub, `Memory-Core` remains the governed rule layer, and durable writes still terminate through `Writer + Gate`.

What is not finished yet:

- product UX is still uneven
- some workflows are still experimental or moving quickly
- not every feature shown in docs is productized
- protocol and runtime behavior may still change between preview revisions

So this should be read as a serious system in active construction, not as a finished commercial release.

## Why This Is Exciting Beyond The Narrow Preview Slice

The current validated public release claims are intentionally narrow, but the architecture direction is larger:

- Supervisor is being built toward multi-project delivery, module-aware decomposition, pools, lanes, dependency gates, and governed project progression.
- X-Constitution is meant to live as a Hub-backed behavioral genome rather than as disposable prompt text.
- high-risk action flows can be modeled as explicit evidence, challenge, confirmation, rollback, and audit instead of hidden side effects
- the same model naturally fits stronger enterprise, public-sector, and security-sensitive operating requirements
- voice is being approached as an operational control surface for progress, wake, guided authorization, and status conversations

This is where the project becomes more than "another AI terminal." The public package is still early, but the system thesis is already much bigger than the current polish level.

In X-Hub terms, that means the system is trying to write the right value boundaries into the operating DNA of the agent stack: not as moral decoration, but as pinned memory constraints plus policy, grants, audit, and fail-closed execution. The point is not to promise zero risk. The point is to turn real agent failure modes into governed, auditable, and blockable conditions: a malicious webpage should not be able to trick the agent into leaking secrets; a vague instruction should not be enough to delete important data; imported skills should not silently gain the power to steal keys or plant backdoors; and even when implementation flaws exist, the system should try to bound the blast radius instead of letting one bug become full compromise.

## Why Publish Before It Is Finished

Because the core thesis is already strong enough to benefit from outside scrutiny:

- the control-plane architecture is meaningfully different from terminal-only AI products
- the safety model benefits from review before the surface area hardens
- protocol, runtime, and packaging decisions are still pliable
- contributors can help shape the real system, not just polish the shell after the architecture is frozen

In short: the product is early, but the idea is real.

## Contribution Invitation

We welcome contributors who care about:

- trusted AI runtime architecture
- Hub-first security and governance
- Swift/macOS productization
- provider compatibility and routing reliability
- multi-project Supervisor orchestration
- voice, diagnostics, and operator UX
- tests, release discipline, and documentation quality

If that sounds like your lane, start with `README.md`, then `CONTRIBUTING.md`, and then the module READMEs under `x-hub/` and `x-terminal/`.

## Suggested Public Whitepaper Set

For the current GitHub-facing documentation pack, the recommended whitepaper set is:

- English long-form product whitepaper
- Chinese long-form product whitepaper
- Chinese summary whitepaper
- English "To Agent Users" transition note
- Chinese "To Agent Users" transition note

If you only publish one entry point inside this repository, use this page plus `README.md`. If you publish the broader document set, keep the full and summary papers aligned with the same public-preview message: real architecture, incomplete product surface, open invitation for contributors.

## Whitepaper Publication Plan

Current plan:

- keep this repository open source under MIT
- keep the long-form whitepaper lifecycle decoupled if needed
- mount the final whitepaper repo back into `docs/whitepaper/` as a submodule when it is ready

If whitepaper files are published from this repository, their license wording
must match the repository's current MIT licensing model.

The current GitHub-release whitepaper variants under `docs/whitepapers/` have
been updated to follow that repository-level wording.

Until then:

- use this page as the stable public whitepaper entry
- use `README.md` for product-facing scope and preview status
- use `docs/xhub-scenario-map-v1.md` for broader scenario framing
- use `X_MEMORY.md` and constitutional docs for the deeper operating model

## Read Next

- `README.md`
- `CONTRIBUTING.md`
- `docs/REPO_LAYOUT.md`
- `docs/xhub-scenario-map-v1.md`
- `docs/memory-new/xhub-constitution-l0-injection-v2.md`
- `docs/xhub-constitution-policy-engine-checklist-v1.md`
