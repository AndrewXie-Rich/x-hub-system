# Local First

<p class="lead">
Sensitive code stays local. Heavy reasoning hits Claude or GPT. Both share the same Hub-governed memory and audit — and that's not because they're the same product, it's because they're behind the same Hub. Local-first here doesn't just mean "run a local model." It means the control plane stays yours.
</p>

<div class="preview-note">
  <strong>Local doesn't mean "all of it" or "none of it."</strong>
  Most real setups are mixed: local model for personal / sensitive context, paid model when the task needs more capability. X-Hub makes the mix coherent — one quota view, one fallback policy, one audit trail.
</div>

## One Governed Plane For Local And Paid Models

The same Hub can govern:

- local models
- paid model providers
- local multimodal runtimes
- per-project route and capability posture

This is important because too many systems treat local and paid paths as completely separate product worlds.

## What Full Local Mode Buys You

If you keep the Hub on user-owned hardware and run local models only:

- the core inference path can stay off third-party cloud infrastructure
- the control plane does not need to live inside a SaaS default
- remote-provider credentials can disappear from the core path
- prompt and context export can be materially reduced

This is not the same thing as "all threats are gone."
It is a stronger starting posture for privacy, authority, and operational independence.

## Local Provider Runtime Productization

The local-runtime direction has matured beyond a rough experimental bridge.
The productization path now includes:

- provider-pack inventory and truth surfaces
- compatibility policy before the operator loads or warms a runtime
- import guidance and recovery-oriented operator feedback
- quick bench and runtime-check surfaces
- local embeddings, speech-to-text, vision, and OCR under the same Hub posture

## Why Provider-Pack Truth Matters

One risk in multimodal local AI systems is fake readiness: the system says a provider exists, but the runtime, dependencies, or model pack are not actually coherent.

Provider-pack truth is aimed at making that visible:

- what provider pack is installed
- what is disabled
- what is incompatible
- what can be benchmarked now
- what should be blocked fail-closed

## Recommended Deployment Shape

For many individuals, teams, and studios, the clean model is to treat the Hub as a user-owned control plane that can stay online, not as a temporary process opened inside a project terminal.

Recommended hardware can start with:

- Mac mini: a good always-on Hub for personal use, small teams, lightweight local models, and remote pairing
- Mac Studio: a stronger Hub for heavier local models, multimodal runtimes, more parallel projects, and longer Supervisor runs
- your own MacBook: useful for development, demos, and solo trials, but not always the best long-running Hub location
- Linux box via `docker-compose up` (in flight, 90-day P0 — see [Status & Roadmap](/status-roadmap))

Recommended runtime shape:

- Hub runs on user-owned Apple silicon hardware or a Linux box
- local runtime is enabled only where it is actually ready
- paid providers are allowed selectively, not by default
- X-Terminal, remote entry points, and skills go through Hub authorization instead of becoming the final control plane
- runtime truth, model status, quota state, memory, and audit stay visible to the user

## When your IDE agent uses a local model, X-Hub still sits in front

This matters because the "local model" question isn't only about X-Hub's own runtime. By 2026, most major IDE agents accept local backends:

- Cursor can talk to a local Ollama endpoint
- Claude Code wraps a local MLX model with the right config
- Cline / Aider / Continue all support local providers

When they do, **X-Hub still sits between the agent and the action it tries to take**. The model running locally doesn't change the trust boundary — the Hub is still the place where memory writes, skill installs, destructive actions, and audit converge.

That gives you local-first control without pretending every remote path has disappeared forever.
