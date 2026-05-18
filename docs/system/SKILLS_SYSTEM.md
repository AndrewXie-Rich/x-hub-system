# Skills System

XHub skills are governed packages, not loose prompt snippets.

A skill is useful only when the package body, manifest, compatibility metadata, trust chain, capability declaration, project grant, and runtime surface all agree that it can run.

## Skill Package

A skill package can include:

- `SKILL.md`
- `skill.json`
- manifest metadata
- capability declaration
- ABI compatibility metadata
- publisher and signing information
- runner or dispatch metadata
- tool and callback requirements

The package structure matters. A catalog entry without a valid package body is not enough.

## Hub Responsibilities

Hub is responsible for the package truth:

- discovery and import
- manifest normalization
- ABI compatibility
- signature validation
- trusted publisher validation
- official channel sync
- vetter gate
- lifecycle and doctor
- pin and version policy
- grant and capability derivation
- fail-closed behavior

This is why the official package body, catalog, manifest, signing chain, and tests must move together.

## XT Responsibilities

XT is responsible for the product and project surface:

- presenting available skills
- resolving project skill registry
- routing model skill calls only through resolved skills
- applying project governance
- enforcing runtime policy
- showing pending approvals
- showing skill activity and failures
- preserving user-understandable approval and denial flows

XT should not let a model invent arbitrary skill names outside the resolved registry.

## Preflight

Before a skill runs, the system should check:

- package is discoverable
- package body exists
- manifest is valid
- package is trusted
- package is compatible
- skill is installed and resolved
- project tier allows requested capability
- required grant exists
- local approval or lease is satisfied
- runtime surface is available
- secrets and callbacks are within policy

Preflight should produce machine-readable denial reasons and human-readable repair actions.

## Rust Skills Role

Rust currently fits best as a deterministic skill governance kernel:

- catalog/readiness read path
- durable pin/grant policy
- preflight
- audit
- retention
- revocation
- policy event trail
- doctor evidence

Rust intentionally should not execute third-party skill code yet.

This distinction is important:

- Rust can say whether a skill package appears ready under policy.
- Rust can say whether a project grant or pin would allow the skill.
- Rust can record policy evidence.
- Rust should not become the runner for untrusted third-party code until the sandbox and ABI contracts are complete.

## Execution Authority Comes Last

Before Rust skill execution authority, the system needs:

- unified capability contract
- hardened package trust chain
- runner sandbox contract
- stable skill ABI
- result contract
- callback contract
- secret boundary contract
- recovery and cancellation contract
- evidence ledger integration
- fail-closed tests across import, vetter, doctor, runtime, and XT approval paths

The safe order is governance first, execution last.

## Product Interpretation

For GitHub readers, the short version is:

XHub skills are installable, signed, capability-declared agent packages that pass governance before they can affect a project. Rust strengthens the policy and readiness layer first; execution authority remains deliberately gated.
