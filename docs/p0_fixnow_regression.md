# P0 Fix Now Regression (One-Click Recovery)

This checklist validates the P0 closure goals:

- Fix Now executes action, then re-checks health.
- Fix Now returns explicit `result_code` + `status`.
- gRPC restart loop uses backoff/rate-limit to avoid spam.

Use helper script:

```bash
scripts/p0_fixnow_regression.sh
```

Hub diagnostics result codes are also written to:

```text
~/Library/Containers/com.rel.flowhub/Data/RELFlowHub/hub_debug.log
```

Filter recent codes:

```bash
scripts/p0_fixnow_regression.sh tail-fix-codes
```

---

## Case 1: gRPC Port Conflict

Inject:

```bash
scripts/p0_fixnow_regression.sh inject-port 50052
```

Expected:

1. Hub Settings shows gRPC port-in-use issue.
2. Click **Fix Now** once.
3. Fix Now returns one of:
   - `FIX_GRPC_PORT_SWITCH_OK`
   - `FIX_GRPC_RESTART_OK`

Cleanup:

```bash
scripts/p0_fixnow_regression.sh clear-port
```

---

## Case 2: Runtime Lock Busy

Inject:

```bash
scripts/p0_fixnow_regression.sh inject-runtime-lock
```

Expected:

1. Runtime shows lock-busy symptom.
2. Click **Fix Now** once.
3. Fix Now returns one of:
   - `FIX_RT_LOCK_CLEAR_RESTART_OK`
   - `FIX_RT_LOCK_FORCE_CLEAR_RESTART_OK`

Cleanup:

```bash
scripts/p0_fixnow_regression.sh clear-runtime-lock
```

---

## Case 3: TLS PEM Corruption

Inject:

```bash
scripts/p0_fixnow_regression.sh inject-tls-pem
```

Expected:

1. Set gRPC TLS mode to `tls` (or `mtls`) to trigger TLS path.
2. gRPC start fails due to broken cert.
3. Click **Fix Now** once.
4. Fix Now returns:
   - `FIX_GRPC_TLS_DOWNGRADE_RESTART_OK` (preferred auto-heal path), or
   - `FIX_GRPC_RESTART_OK` (if already insecure or restart path recovers)

Cleanup:

```bash
scripts/p0_fixnow_regression.sh clear-tls-pem
```

