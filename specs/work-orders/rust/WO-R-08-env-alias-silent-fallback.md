# WO-R-08 — `env_u32` / `env_u64` first-alias parse failure silently falls back

**Owner:** AI · **Effort:** ~30 minutes · **Severity:** P1 (operator experience) · **Dependencies:** none

## Why this matters

`env_u32` and `env_u64` in `scheduler_bridge.rs:~121` are structured as:

```rust
keys.iter()
    .find_map(|key| env::var(key).ok())
    .and_then(|value| value.trim().parse::<u32>().ok())
    .unwrap_or(fallback)
    .clamp(min_value, max_value)
```

If the operator sets `HUB_PAID_AI_GLOBAL_CONCURRENCY=abc` (typo) **and** `XHUB_PAID_MODEL_GLOBAL_CONCURRENCY=8` (the working alias):

1. `find_map` picks the first present alias → `"abc"`.
2. `parse::<u32>()` fails.
3. `unwrap_or(fallback)` discards the parse error **and** the second alias.
4. Operator sees default `fallback`, with no warning that their intent was misconfigured.

Same shape for negative values like `-1`. The clamp doesn't help because we never reach a parsed value.

This is a quiet operator footgun: the system "works" but ignores the operator's configuration.

## Scope

**In scope:**
- `env_u32` (scheduler_bridge.rs:~121)
- `env_u64` (scheduler_bridge.rs:~128)
- Loggers / stderr writers that already exist in this module (use whatever convention is already in place)

**Out of scope:**
- Changing the env var alias lists.
- Restructuring `effective_scheduler_config`.

## Deliverables

1. Change the iteration: instead of `find_map(|key| env::var(key).ok())` followed by parse, iterate all aliases and try each:
   ```rust
   for key in keys {
       let Some(raw) = env::var(key).ok() else { continue; };
       match raw.trim().parse::<u32>() {
           Ok(v) => return v.clamp(min, max),
           Err(e) => {
               eprintln!("warning: env var {} = {:?} failed to parse as u32: {}; trying next alias or fallback", key, raw, e);
               continue;
           }
       }
   }
   fallback
   ```
2. When all aliases fail to parse, emit one warning summarizing the values seen and the fallback chosen.
3. Apply the same fix to `env_u64`.
4. If the project already has a structured logging helper, use that instead of `eprintln!`.

## Acceptance criteria

1. New test: env_u32 with first alias = "abc", second alias = "8" returns 8 (not fallback).
2. New test: env_u32 with first alias = "-1", second alias = "8" returns 8.
3. New test: env_u32 with no aliases set returns fallback (existing behaviour).
4. New test: env_u32 with first alias = "abc", second alias = "xyz" returns fallback **and emits a warning** containing both raw values.
5. Same four tests for env_u64.

## References (read first)

- `env_u32` / `env_u64` (scheduler_bridge.rs:~121)
- `effective_scheduler_config` (~17) — the caller passing alias lists
- Existing log/warn helpers in the crate; reuse rather than introduce a new pattern

## Anti-patterns

- **Do NOT panic on parse failure.** Some operators will tolerate the "fall through to next alias" behaviour and removing the alias is a separate concern.
- **Do NOT silently parse signed values as u32.** `-1` should fail and warn, not coerce.
- **Do NOT log the raw value in production.** If the env var holds a secret-ish value (unlikely for concurrency limits but possible elsewhere), truncate or hash. For this WO the concurrency values are not sensitive — log them as-is.

## Handoff notes

Smallest WO in the batch. Can ship as a standalone PR.

After this lands, file a follow-up to audit other env-var parsers in the codebase (`grep "env::var" rust/`) for the same pattern. There may be 5+ instances.
