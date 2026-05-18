# Models and Quota

XHub treats local models, paid models, free accounts, OAuth accounts, and API-key providers as one governed AI resource portfolio.

The user should not have to manually decide which account, model, runtime, quota window, and fallback path is safe for every request. Hub should assemble that truth and explain the route.

## Local Models

Local models are not just downloaded files. A local model is ready only when:

- the artifact exists
- the format is supported
- the provider runtime is ready
- the model can be loaded on the current device
- memory and GPU pressure are acceptable
- capability tags match the task
- runtime status is fresh enough

Supported provider directions include:

- MLX
- MLX VLM
- Transformers
- llama.cpp
- other provider packs as the runtime evolves

Local models are the preferred path for privacy, low latency, offline work, and low-cost background tasks when capability is sufficient.

## Remote Models

Remote models are provider routes, not downloaded weights.

A remote model entry usually includes:

- provider
- model id
- base URL
- wire API
- account or credential reference
- endpoint health
- grant and policy constraints
- quota and cooldown state
- fallback eligibility

Hub governs remote model access through provider keys, OAuth imports, device policy, allowlists, budgets, quota windows, cooldowns, and route decisions.

## Unified Inventory

XT should see one model truth:

- local-only ready
- remote-only ready
- both ready
- local fallback available
- remote gated by policy
- remote gated by quota
- runtime stale
- provider partial readiness
- account unhealthy or cooling down

This lets the UI show "what can run now" instead of making the user mentally join local model state, provider account state, quota state, and policy state.

## Account Pools

Provider accounts form pools. A pool can contain:

- API-key accounts
- OAuth accounts
- free accounts
- paid accounts
- account-specific model allowlists
- account-specific quota windows
- per-account health and cooldown state

Routing should avoid blocked, stale, disabled, limited, cooling, or exhausted accounts. It should also avoid burning scarce paid quota when a local or free account route is good enough.

## Quota Windows

Hub should preserve separate upstream usage windows when available and expose them without breaking older flattened quota clients.

For ChatGPT-style accounts this can include:

- 5-hour usage amount and used percent
- 7-day usage amount and used percent
- basis-point precision for progress bars
- reset time per window
- limited flag per window
- last refresh time
- error and cooldown state

This is important because one account can look available in a flattened quota view while still being risky in the near 5-hour window, or safe in the short window but close to a 7-day cap.

Legacy flattened quota should remain available as fallback for older clients and providers that do not expose separate windows.

## Rust Route Position

Provider/model route is the second authority cutover candidate after scheduler.

The safe order is:

1. Rust reads inventory and provider state.
2. Rust produces candidate provider/model decisions.
3. Node keeps production route authority.
4. Shadow compare records mismatch evidence.
5. Candidate audit verifies same-account and same-model behavior.
6. Rust emits selected-model authority dry-run plans.
7. Only after readiness and rollback are proven should Rust own selected-model authority for a narrow path.

Rust should not silently change paid model selection, provider account selection, OAuth account selection, or free-account rotation.

## Route Scoring

A mature route decision should score candidates using:

- readiness
- capability fit
- local privacy preference
- latency
- cost
- 5-hour quota score
- 7-day quota score
- provider health
- account cooldown
- project policy
- user grant
- failure history
- fallback quality

The output should include both the selected route and the reason other routes were skipped.

## Account Portfolio Optimizer

The long-term direction is an Account Portfolio Optimizer:

- prefer local models for private or simple work
- use high-reasoning paid models for hard planning and review
- rotate free accounts conservatively
- avoid accounts near 5-hour or 7-day exhaustion
- keep paid accounts available for tasks that truly need them
- respect per-user and per-project budgets
- explain route choice, fallback, and deny reasons

This turns model routing from static selection into governed resource allocation.

## Product Interpretation

For GitHub readers, the short version is:

XHub gives the agent a governed AI resource portfolio: local models, remote models, account pools, quota windows, route evidence, and fallback decisions are assembled into one explainable model layer.
