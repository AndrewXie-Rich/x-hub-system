# WO-R-06 — `redact_process_command` only catches a hard-coded flag list

**Owner:** AI · **Effort:** ~2 hours · **Severity:** P0 (security) · **Dependencies:** none

## Why this matters

`redact_process_command` (main.rs:~2394) walks the `ps` output's command line and redacts arguments that match an **exact set** of flags:

- `--access-key` / `--api-key` / `--token` / `--secret` / `--password` (space form)
- Tokens of the form `<key>=<value>` where `<key>` substring-matches one of the above

Anything else passes through verbatim. The output is served by `product_process_sanity_from_ps_output` at `/runtime/product-process-sanity`, an HTTP endpoint.

**Concrete leaks:**

| Process launched as | What `redact_process_command` does | What leaks |
|---|---|---|
| `app --client-secret hunter2` | No match for `--client-secret`; passes through | `hunter2` |
| `app --bearer <jwt>` | No match for `--bearer` | full JWT |
| `app postgres://user:pass@host` | Positional arg, no `=`; passes through | the URI |
| `app --aws-access-key-id AKIA…` | Doesn't match the exact `--access-key` form | the AKIA key |
| `app -k SECRET` | Short flag form not in the list | the secret |
| `app --refresh-token xyz` | Not in the list | the token |

Anyone who can reach the HTTP port can scrape secrets from running processes.

## Scope

**In scope:**
- `redact_process_command` (main.rs:~2394)
- The HTTP route registration for `/runtime/product-process-sanity`

**Out of scope:**
- Changing `ps` parsing — the parsing is correct; the redaction is the bug.
- Adding authentication to the endpoint — that's WO-R-12-adjacent (separate WO). This WO assumes the endpoint stays open and fixes the redaction.

## Deliverables

1. Replace exact-match flag list with **pattern-based detection**. Redact arguments that:
   - Follow a flag whose name matches `(?i).*(token|secret|password|key|auth|credential|bearer|cookie|session)`. Both `--name value` (space form) and `--name=value` should be covered.
   - Match a URI scheme with embedded credentials: `(?i)^[a-z][a-z0-9+.-]*://[^/]*:[^/@]*@`. Redact only the `userinfo` portion.
   - Match common token formats: AWS access keys (`AKIA[0-9A-Z]{16}`), JWTs (`eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*`), GitHub tokens (`(gh[ps]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]+)`), OpenAI / Anthropic-style keys (`(sk-[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9-]+)`), generic high-entropy base64 of ≥ 32 chars in suspect positions.
2. Replacement text: `<redacted:<reason>>` where `<reason>` is e.g. `flag_token`, `uri_userinfo`, `jwt_pattern`. Lets operators see WHY a redaction fired.
3. Add a test fixture file with one process line per pattern category. The tests assert each is redacted.
4. **Fail-closed mode:** when an argument is "suspicious-but-unclassified" (e.g., looks like high-entropy base64 longer than 32 chars and is the value position of a flag), redact it with reason `high_entropy_unknown`. False positives are preferable to leaks.

## Acceptance criteria

1. New tests for each of the 6 attack patterns in the table above.
2. New test: legitimate flags like `--port 8080` or `--config /etc/foo.toml` are NOT redacted.
3. New test: a JWT or AWS key appearing as a positional argument is redacted.
4. Existing tests of the redaction still pass (the existing flag list is a subset of the new behaviour).
5. `cargo test` clean.

## References (read first)

- `redact_process_command` (main.rs:~2394)
- The test files that exercise `product_process_sanity_*` — extend them
- Any existing regex helpers in `xhub-core` for credential detection (grep first; if one exists, reuse)

## Anti-patterns

- **Do NOT redact entire command lines on first match.** The label and other arguments are useful for the operator. Redact only the value, leave the flag/key intact.
- **Do NOT use `String::contains` for token detection.** Position matters: `--port 8080` should not be redacted because the flag doesn't match a secret-name pattern.
- **Do NOT add a config-file allowlist of "safe flags".** Allowlists for this purpose are unmaintainable. Use pattern-based detection.
- **Do NOT make the redaction reason a generic `<redacted>`.** Operators debugging false positives need to know which pattern fired.

## Handoff notes

This is the most visibly-broken finding in the batch from an external-surface perspective. The `/runtime/product-process-sanity` endpoint is the kind of thing that gets curl'd by automation, dashboards, and (during incident response) by anyone who can reach the host. Fix this before the endpoint sees real traffic.

Independent of WO-R-01..04 / WO-R-05; can ship as its own PR.
