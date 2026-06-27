# WO-R-02 — Memory reveal-grant: client-controlled `now_ms` defeats TTL ceiling

**Owner:** AI · **Effort:** ~1 hour · **Severity:** P0 (security) · **Dependencies:** none, but ship with WO-R-01, WO-R-03, WO-R-04

## Why this matters

The reveal-grant issuer reads `now_ms` from the request body. It then computes `expires_at_ms = now.saturating_add(ttl_ms)` where `ttl_ms` is clamped to ≤ 15 minutes. The **TTL delta is clamped**; the **base** is not. The mutation gate later checks `now_server >= expires_at_ms` using server time.

An attacker posts `{"now_ms": 99999999999999, "ttl_ms": 900000}`. The clamp accepts `ttl_ms` (it's 15 minutes). `expires_at_ms` becomes `99999999999999 + 900000` — many years in the future. The mutation gate's server-time check never satisfies `now_server >= expires_at_ms`. The grant is **effectively permanent**, defeating the intended 15-minute ceiling.

## Scope

**In scope:**
- `memory_user_reveal_grant_issue` (memory_bridge.rs:~4456)
- `memory_user_reveal_now_ms` (memory_bridge.rs:~4451)
- `memory_user_reveal_grant_active_for_mutation` (memory_bridge.rs:~4806, the verifier)

**Out of scope:**
- All other places `now_ms` is read from client bodies — those are separate WOs if they affect security decisions.

## Deliverables

1. **Stop reading `now_ms` from the request body** in the reveal-grant issuance path. Use `now_ms_i64()` (server clock) as the authoritative base.
2. If the request includes a `now_ms` field, IGNORE it. Do NOT error — preserve API shape — but the value MUST NOT influence `expires_at_ms`.
3. The TTL clamp stays as-is (≤ 15 minutes).
4. Add an audit log entry when a request body carried a `now_ms` value that differed from server time by more than 60 seconds. This is a useful signal of attempted abuse without breaking benign clock skew.

## Acceptance criteria

1. New test: POST `/memory/user-reveal/issue` with `{"now_ms": <very-large>}` produces a grant whose `expires_at_ms` is within `(server_now + 15min)` and `(server_now + 15min + skew_tolerance)`.
2. New test: POST `/memory/user-reveal/issue` with no `now_ms` field works unchanged.
3. New test: the audit log records the `now_ms` discrepancy (>60s) when the client sent one.
4. Mutation gate test from WO-R-01 still passes: a grant issued at server_now expires correctly after 15 minutes by server-time check.

## References (read first)

- `memory_user_reveal_grant_issue` and surrounding helpers (memory_bridge.rs:~4456)
- `memory_user_reveal_grant_active_for_mutation` (~4806) and its `now=now_ms_i64()` (~5078) — the verifier already uses server time, so this is consistent
- `now_ms_i64()` is the established server-time accessor; reuse it

## Anti-patterns

- **Do NOT add a "max clock skew" check that conditionally accepts client `now_ms`.** That's a foot-gun configured wrong. The base time has exactly one source: the server.
- **Do NOT remove `now_ms` from the request body's schema.** Other code paths or future clients may include it harmlessly; just don't use it for security decisions.
- **Do NOT enforce a maximum `expires_at_ms` after computation.** Two checks is worse than one correct check — the correct fix is to use server time as the base.

## Handoff notes

Ship with WO-R-01 / WO-R-03 / WO-R-04 in one PR. This change alone closes one bypass; the reveal-grant subsystem stays broken until all four land.
