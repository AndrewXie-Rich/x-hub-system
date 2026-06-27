# WO-R-12 — `/model/concurrency-policy` discloses absolute filesystem paths

**Owner:** AI · **Effort:** ~30 minutes · **Severity:** P2 (information disclosure, low value to attacker) · **Dependencies:** none

## Why this matters

`model_concurrency_policy_http_json` (main.rs:~3389) returns a response that includes the absolute path of the policy file:

```json
{
  "policy_path": "/Users/<user>/Library/Application Support/AX/rust-hub/local/model_concurrency_policy.json",
  ...
}
```

The endpoint is unauthenticated (or, more precisely, has no scoping beyond the loopback/access-key check). Any client that can reach the HTTP port learns:

- The macOS username.
- The Application Support path layout.
- Confirmation that X-Hub is installed and where.

This is low-impact information disclosure but unnecessary: the path is internal state; clients have no reason to see it.

## Scope

**In scope:**
- `model_concurrency_policy_http_json` (main.rs:~3389)
- Any other `*_http_json` in main.rs that emits absolute paths (audit during this WO and document findings)

**Out of scope:**
- Re-architecting the HTTP authorization model.
- Hiding `runtime_base_dir` everywhere — that's a bigger initiative.

## Deliverables

1. Remove `policy_path` from the response of `model_concurrency_policy_http_json`. The policy *values* are useful; the path to the file is not.
2. If the path is needed for debugging, add a separate `model_concurrency_policy_http_json_debug` endpoint that requires an explicit debug grant. Default-off.
3. Sweep other `*_http_json` functions in main.rs for absolute paths in their response bodies. File follow-up WOs for each one found, OR fix them in this PR if obvious — comment in the PR description.

## Acceptance criteria

1. New test: GET `/model/concurrency-policy` does not include `policy_path` or any path-shaped string in the response.
2. New test: the policy values themselves are still present and correct.
3. Audit document attached to the PR: list of other endpoints scanned, anything else that leaks paths.

## References (read first)

- `model_concurrency_policy_http_json` (main.rs:~3389)
- Other `*_http_json` functions in main.rs (grep)

## Anti-patterns

- **Do NOT replace the absolute path with a redacted form like `<runtime_base_dir>/model_concurrency_policy.json`.** That still reveals the schema. Just omit.
- **Do NOT add an opt-in flag that re-enables the path.** Default-off-debug is fine; opt-in for non-debug clients is not.

## Handoff notes

P2 severity. Ship when convenient. If you're already touching main.rs for another WO, fold this in.

Independent of all other WO-Rs.
