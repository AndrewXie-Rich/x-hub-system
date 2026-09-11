import { getClientAuthStatus, loadClients } from './clients.js';
import { delegatedKeyPolicyError, hasAccessKeyManagementScope } from './access_key_delegation.js';

function text(value) {
  return String(value ?? '').trim();
}

function limitOf(client, key) {
  return Math.max(0, Math.floor(Number(client?.approved_trust_profile?.budget_policy?.[key] ?? client?.[key] ?? 0)));
}

export function reserveDelegatedGenerationBudget({ db, runtimeBaseDir, auth, prompt, maxTokens }) {
  const accessKeyId = text(auth?.access_key_id);
  if (!accessKeyId) return { ok: true, delegated: false };
  let clients;
  try {
    clients = loadClients(runtimeBaseDir, 500);
  } catch {
    return { ok: false, code: 'delegation_budget_unavailable' };
  }
  const current = clients.find((item) => text(item?.access_key_id) === accessKeyId);
  if (!current) return { ok: false, code: 'delegation_parent_unavailable' };
  if (!getClientAuthStatus(current).usable) return { ok: false, code: 'delegation_parent_unavailable' };
  const parentId = text(current.managed_by_access_key_id) || accessKeyId;
  const children = clients.filter((item) => text(item?.managed_by_access_key_id) === parentId);
  if (!current.managed_by_access_key_id && children.length === 0 && !hasAccessKeyManagementScope(current)) return { ok: true, delegated: false };
  const parent = clients.find((item) => text(item?.access_key_id) === parentId);
  if (!parent || !getClientAuthStatus(parent).usable) return { ok: false, code: 'delegation_parent_unavailable' };
  if (current.managed_by_access_key_id) {
    const policyError = delegatedKeyPolicyError(parent, current);
    if (policyError) return { ok: false, code: policyError };
  }
  const groupLimit = limitOf(parent, 'daily_token_limit');
  const keyLimit = current.managed_by_access_key_id ? limitOf(current, 'daily_token_limit') : groupLimit;
  const singleLimit = Math.min(
    limitOf(parent, 'single_request_token_limit'),
    current.managed_by_access_key_id ? limitOf(current, 'single_request_token_limit') : Number.MAX_SAFE_INTEGER
  );
  const requested = Buffer.byteLength(String(prompt ?? ''), 'utf8') + maxTokens + 64;
  if (!Number.isSafeInteger(maxTokens) || maxTokens <= 0 || !Number.isSafeInteger(requested)
    || !Number.isSafeInteger(groupLimit) || !Number.isSafeInteger(keyLimit) || !Number.isSafeInteger(singleLimit)
    || groupLimit <= 0 || keyLimit <= 0 || singleLimit <= 0 || requested > singleLimit) {
    return { ok: false, code: 'delegation_quota_exceeded' };
  }
  const day = new Date().toISOString().slice(0, 10);
  const keyScope = `delegation-key:${accessKeyId}`;
  const groupScope = `delegation:${parentId}`;
  const baselineScopes = [...new Set([parent, ...children].map((item) => `device:${text(item.device_id)}`))];
  try {
    return db.tryReserveDelegatedQuotaDaily({
      day,
      group_scope: groupScope,
      group_cap: groupLimit,
      key_scope: keyScope,
      key_cap: keyLimit,
      amount: requested,
      baseline_scopes: baselineScopes,
      key_baseline_scope: `device:${text(current.device_id)}`,
    });
  } catch {
    return { ok: false, code: 'delegation_budget_unavailable' };
  }
}
