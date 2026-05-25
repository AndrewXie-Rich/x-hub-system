# Local First

<p class="lead">
X-Hub is designed so the trusted control plane, permissions posture, key material, privacy decisions, and release timing can stay under user control. Local-first here does not just mean "run a local model." It means the control plane stays yours.
</p>

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

Recommended runtime shape:

- Hub runs on user-owned Apple silicon hardware
- local runtime is enabled only where it is actually ready
- paid providers are allowed selectively, not by default
- X-Terminal, remote entry points, and skills go through Hub authorization instead of becoming the final control plane
- runtime truth, model status, quota state, memory, and audit stay visible to the user

That gives you local-first control without pretending every remote path has disappeared forever.
