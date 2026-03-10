# Split Audit Decoder Guide (AI-XT-2)

This guide describes how to consume split audit events from X-Terminal safely.

## Preferred API

Use:

- `SplitAuditPayloadDecoder.decodeResult(event)`
- `SupervisorOrchestrator.latestDecodedSplitAuditResult()`

It returns:

- `Result<SplitAuditDecodedPayload, SplitAuditPayloadDecodeError>`

This gives explicit failure reasons and is recommended for integration and incident triage.

## Backward-Compatible API

If your code path still expects optional decoding:

- `SplitAuditPayloadDecoder.decode(event) -> SplitAuditDecodedPayload?`

This remains supported and internally delegates to `decodeResult`.

## Error Handling Contract

`SplitAuditPayloadDecodeError` values:

- `schemaMismatch(expected, actual)`
  - action: treat payload as incompatible contract version.
- `versionMismatch(expected, actual)`
  - action: treat payload as incompatible contract version.
- `eventTypeMismatch(expected, actual)`
  - action: treat payload as malformed/inconsistent event record.
- `missingField(key)`
  - action: treat payload as incomplete producer output.
- `invalidFieldValue(key, value)`
  - action: treat payload as malformed producer output.

## Recommended Consumer Flow

1. Read event from `splitAuditTrail`.
2. Call `latestDecodedSplitAuditResult()` (or `decodeResult(event)` for explicit event input).
3. On `.success(payload)`, continue typed flow handling.
4. On `.failure(error)`, emit structured telemetry with:
   - `event_type`
   - `split_plan_id`
   - `decode_error`
5. Keep fail-closed behavior for automation paths when decode fails.

## `splitOverridden` Extended Fields

For `supervisor.split.overridden`, consume these typed fields from
`SplitOverriddenAuditPayload`:

- `overrideCount`, `overrideLaneIDs`
- `blockingIssueCount`, `blockingIssueCodes`
- `highRiskHardToSoftConfirmedCount`, `highRiskHardToSoftConfirmedLaneIDs`
- `isReplay`

Recommended policy for AI-XT-2:

- If `blockingIssueCount > 0`, treat override application as blocked and surface
  `blockingIssueCodes`.
- If `highRiskHardToSoftConfirmedCount > 0`, treat the corresponding lanes as
  explicitly user-confirmed hard->soft overrides.
- Use `isReplay` to distinguish user-triggered override events from replay
  verification events.

## Fixture Pair For Regression

- valid sample: `split_audit_payload_events.sample.json`
- negative sample: `split_audit_payload_events.invalid.sample.json`

Use both in integration tests to prevent decoder contract drift.
