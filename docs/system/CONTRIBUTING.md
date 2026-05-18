# Contributing

This system has strong internal boundaries. Contributions should preserve them.

## Before Changing Code

Identify which surface you are touching:

- XT product UI
- Node Hub authority
- Rust Hub candidate path
- Rust XT sidecar
- local Python runtime
- skills package
- docs only

Then identify whether the change affects:

- production authority
- shadow evidence
- policy/grant behavior
- secrets
- memory writes
- skill execution
- model route decisions
- pairing/trust

## Engineering Rules

- Prefer existing patterns.
- Keep authority changes explicit.
- Do not bypass fail-closed gates.
- Do not introduce secret leakage in logs or evidence.
- Preserve old client compatibility.
- Add tests proportional to risk.
- For Rust migration, keep default-off bridges default-off.
- For UI, do not move product UI into Rust diagnostics.

## Documentation Rules

Public docs should explain:

- what the capability does
- what owns authority
- what is implemented now
- what is shadow/candidate
- what is not supported
- how to troubleshoot it

Avoid public docs that only list "files the next AI should read." Keep those as internal handoff notes.

## Testing Expectations

High-risk changes should include:

- unit or integration tests
- smoke evidence
- fail-closed behavior
- no-secret checks
- compatibility checks
- readiness or doctor evidence where relevant

## Good Pull Request Shape

- Small authority scope.
- Clear contract impact.
- Tests named in the pull request.
- Rollback or fallback described.
- Docs updated if user behavior or authority changed.
