import assert from 'node:assert/strict';
import test from 'node:test';

import {
  APPLIED_RUST_HUB_STATUS_AUTHORITY,
  LEGACY_RUST_HUB_STATUS_AUTHORITY,
  validateRustHubStatusAuthority,
} from './xt_file_ipc_live_heartbeat_soak.js';

test('accepts the production-applied Rust classic-status authority', () => {
  assert.deepEqual(validateRustHubStatusAuthority(APPLIED_RUST_HUB_STATUS_AUTHORITY), {
    ok: true,
    authority: APPLIED_RUST_HUB_STATUS_AUTHORITY,
    compatibility: 'current',
  });
});

test('accepts the legacy authority with an explicit compatibility designation', () => {
  assert.deepEqual(validateRustHubStatusAuthority(LEGACY_RUST_HUB_STATUS_AUTHORITY), {
    ok: true,
    authority: LEGACY_RUST_HUB_STATUS_AUTHORITY,
    compatibility: 'legacy_explicit_cutover_only',
  });
});

test('rejects unrelated Rust Hub authority values', () => {
  assert.deepEqual(validateRustHubStatusAuthority('rust_live_status_http'), {
    ok: false,
    authority: 'rust_live_status_http',
    compatibility: 'unsupported',
  });
});
