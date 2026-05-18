import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  loadProviderKeyStore,
  saveProviderKeyStore,
  invalidateProviderKeyCache,
  listProviderKeys,
  addProviderKey,
  removeProviderKey,
  updateProviderKey,
  setProviderRoutingStrategy,
  getProviderRoutingStrategy,
  selectProviderKey,
  importAuthDir,
  importProxyConfig,
  listProviderKeyImportSourceStatuses,
  providerKeyStoreSummary,
} from './provider_key_store.js';

function run(name, fn) {
  try {
    const maybePromise = fn();
    if (maybePromise && typeof maybePromise.then === 'function') {
      return maybePromise.then(() => {
        process.stdout.write(`ok - ${name}\n`);
      }).catch((error) => {
        process.stderr.write(`not ok - ${name}\n`);
        throw error;
      });
    }
    process.stdout.write(`ok - ${name}\n`);
    return Promise.resolve();
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n`);
    throw error;
  }
}

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'xhub-provider-keys-'));
}

await run('loadProviderKeyStore returns empty store when no file exists', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.schema_version, 'hub_provider_keys.v1');
  assert.deepEqual(store.providers, {});
  assert.equal(store.routing_strategy, 'fill-first');
});

await run('addProviderKey adds an api_key account', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = addProviderKey(dir, {
    provider: 'openai',
    email: 'test@example.com',
    api_key: 'sk-test1234567890',
    auth_type: 'api_key',
  });
  assert.equal(result.ok, true);
  assert.ok(result.account_key);
  assert.ok(result.account_key.startsWith('openai:'));
});

await run('addProviderKey rejects duplicate api_key', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-dup-key',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  const result = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-dup-key',
    auth_type: 'api_key',
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, 'duplicate_api_key');
});

await run('addProviderKey rejects invalid provider', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = addProviderKey(dir, {
    provider: 'nonexistent_provider',
    api_key: 'sk-test',
    auth_type: 'api_key',
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, 'invalid_account');
});

await run('listProviderKeys returns redacted keys', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'claude',
    api_key: 'sk-ant-api03-longkey1234567890',
    auth_type: 'api_key',
  });
  invalidateProviderKeyCache();
  const keys = listProviderKeys(dir, 'claude');
  assert.equal(keys.length, 1);
  assert.equal(keys[0].provider, 'claude');
  assert.ok(keys[0].api_key.includes('...'));
  assert.ok(!keys[0].api_key.includes('longkey1234567890'));
});

await run('listProviderKeys filters by provider', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-openai-1', auth_type: 'api_key' });
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'claude', api_key: 'sk-claude-1', auth_type: 'api_key' });
  invalidateProviderKeyCache();
  const openaiKeys = listProviderKeys(dir, 'openai');
  assert.equal(openaiKeys.length, 1);
  assert.equal(openaiKeys[0].provider, 'openai');
});

await run('removeProviderKey removes an account', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'gemini',
    api_key: 'AIza-test-key-1234567890',
    auth_type: 'api_key',
  });
  assert.equal(addResult.ok, true);
  invalidateProviderKeyCache();
  const removeResult = removeProviderKey(dir, addResult.account_key);
  assert.equal(removeResult.ok, true);
  invalidateProviderKeyCache();
  const keys = listProviderKeys(dir, 'gemini');
  assert.equal(keys.length, 0);
});

await run('removeProviderKey returns error for missing account_key', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = removeProviderKey(dir, '');
  assert.equal(result.ok, false);
  assert.equal(result.error, 'missing_account_key');
});

await run('updateProviderKey updates fields', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const addResult = addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-update-test',
    auth_type: 'api_key',
    notes: 'original',
  });
  assert.equal(addResult.ok, true);
  invalidateProviderKeyCache();
  const updateResult = updateProviderKey(dir, addResult.account_key, {
    notes: 'updated',
    enabled: false,
  });
  assert.equal(updateResult.ok, true);
  invalidateProviderKeyCache();
  const keys = listProviderKeys(dir, 'openai');
  assert.equal(keys.length, 1);
  assert.equal(keys[0].notes, 'updated');
  assert.equal(keys[0].enabled, false);
});

await run('updateProviderKey returns error for missing account', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = updateProviderKey(dir, 'nonexistent:key', { notes: 'test' });
  assert.equal(result.ok, false);
  assert.equal(result.error, 'account_not_found');
});

await run('setProviderRoutingStrategy sets and gets strategy', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-strat-test', auth_type: 'api_key' });
  invalidateProviderKeyCache();
  const setResult = setProviderRoutingStrategy(dir, 'openai', 'round-robin');
  assert.equal(setResult.ok, true);
  const strategy = getProviderRoutingStrategy(dir, 'openai');
  assert.equal(strategy, 'round-robin');
});

await run('setProviderRoutingStrategy rejects invalid strategy', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = setProviderRoutingStrategy(dir, 'openai', 'invalid-strategy');
  assert.equal(result.ok, false);
  assert.equal(result.error, 'invalid_strategy');
});

await run('selectProviderKey returns first enabled account with fill-first', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-sel-1', auth_type: 'api_key', priority: 1 });
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-sel-2', auth_type: 'api_key', priority: 5 });
  invalidateProviderKeyCache();
  const selected = selectProviderKey(dir, 'openai');
  assert.ok(selected);
  assert.equal(selected.api_key, 'sk-sel-1');
});

await run('selectProviderKey returns null for unknown provider', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const selected = selectProviderKey(dir, 'nonexistent');
  assert.equal(selected, null);
});

await run('selectProviderKey returns null when all accounts disabled', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'claude', api_key: 'sk-disabled', auth_type: 'api_key', enabled: false });
  invalidateProviderKeyCache();
  const selected = selectProviderKey(dir, 'claude');
  assert.equal(selected, null);
});

await run('importAuthDir imports JSON auth files', () => {
  const dir = makeTempDir();
  const authDir = makeTempDir();
  invalidateProviderKeyCache();

  const codexAuth = {
    access_token: 'codex-token-1234567890',
    refresh_token: 'codex-refresh-123',
    email: 'user@codex.test',
    type: 'codex',
    expired: '2026-12-31T00:00:00Z',
  };
  fs.writeFileSync(path.join(authDir, 'codex_user1.json'), JSON.stringify(codexAuth, null, 2));

  const result = importAuthDir(dir, authDir);
  assert.equal(result.ok, true);
  assert.ok(result.imported >= 1);
  assert.equal(result.errors.length, 0);
});

await run('importAuthDir handles nested data envelope', () => {
  const dir = makeTempDir();
  const authDir = makeTempDir();
  invalidateProviderKeyCache();

  const wrappedAuth = {
    data: {
      access_token: 'wrapped-token-1234567890',
      type: 'claude',
      email: 'wrapped@test.com',
    },
  };
  fs.writeFileSync(path.join(authDir, 'claude_wrapped.json'), JSON.stringify(wrappedAuth, null, 2));

  const result = importAuthDir(dir, authDir);
  assert.equal(result.ok, true);
  assert.ok(result.imported >= 1);
});

await run('importAuthDir supports Codex CLI auth files with nested tokens', () => {
  const dir = makeTempDir();
  const authDir = makeTempDir();
  invalidateProviderKeyCache();

  const jwtPayload = Buffer.from(JSON.stringify({
    email: 'codex-user@test.com',
    chatgpt_account_id: 'acct-codex-cli-1',
    exp: 2000000000,
  })).toString('base64url');
  const idToken = `header.${jwtPayload}.sig`;

  fs.writeFileSync(path.join(authDir, 'auth17.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      id_token: idToken,
      access_token: 'codex-cli-access-token',
      refresh_token: 'codex-cli-refresh-token',
      account_id: 'acct-codex-cli-1',
    },
  }, null, 2));

  const result = importAuthDir(dir, authDir);
  assert.equal(result.ok, true);
  assert.equal(result.imported, 1);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.codex.accounts.length, 1);
  assert.equal(store.providers.codex.accounts[0].email, 'codex-user@test.com');
  assert.equal(store.providers.codex.accounts[0].auth_type, 'oauth');
  assert.equal(store.providers.codex.accounts[0].account_id, 'acct-codex-cli-1');
  assert.equal(store.providers.codex.accounts[0].source_type, 'auth_file');
  assert.ok(String(store.providers.codex.accounts[0].source_ref || '').endsWith('auth17.json'));
  assert.equal(store.providers.codex.accounts[0].oauth_source_key, 'chatgpt');
  assert.equal(store.providers.codex.accounts[0].auth_index, 0);
});

await run('importAuthDir preserves Gemini oauth refresh metadata from nested token payloads', () => {
  const dir = makeTempDir();
  const authDir = makeTempDir();
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(authDir, 'gemini-user@example.com-all.json'), JSON.stringify({
    type: 'gemini',
    email: 'gemini-user@example.com',
    project_id: 'all',
    token: {
      access_token: 'gemini-access-token',
      refresh_token: 'gemini-refresh-token',
      client_id: 'gemini-client-id',
      client_secret: 'gemini-client-secret',
      token_uri: 'https://oauth2.googleapis.com/token',
      scopes: [
        'https://www.googleapis.com/auth/cloud-platform',
        'https://www.googleapis.com/auth/userinfo.email',
      ],
      universe_domain: 'googleapis.com',
    },
  }, null, 2));

  const result = importAuthDir(dir, authDir);
  assert.equal(result.ok, true);
  assert.equal(result.imported, 1);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.gemini.accounts.length, 1);
  assert.deepEqual(store.providers.gemini.accounts[0].oauth_refresh_config, {
    client_id: 'gemini-client-id',
    client_secret: 'gemini-client-secret',
    token_uri: 'https://oauth2.googleapis.com/token',
    scopes: [
      'https://www.googleapis.com/auth/cloud-platform',
      'https://www.googleapis.com/auth/userinfo.email',
    ],
    universe_domain: 'googleapis.com',
  });
});

await run('importAuthDir reimports the same auth file path without duplicating the account', () => {
  const dir = makeTempDir();
  const authDir = makeTempDir();
  const filePath = path.join(authDir, 'codex_primary.json');
  invalidateProviderKeyCache();

  fs.writeFileSync(filePath, JSON.stringify({
    access_token: 'codex-token-v1',
    refresh_token: 'codex-refresh-v1',
    email: 'primary@codex.test',
    type: 'codex',
  }, null, 2));

  const first = importAuthDir(dir, authDir);
  assert.equal(first.ok, true);
  assert.equal(first.imported, 1);

  invalidateProviderKeyCache();
  fs.writeFileSync(filePath, JSON.stringify({
    access_token: 'codex-token-v2',
    refresh_token: 'codex-refresh-v2',
    email: 'rotated@codex.test',
    type: 'codex',
    priority: 7,
  }, null, 2));

  const second = importAuthDir(dir, authDir);
  assert.equal(second.ok, true);
  assert.equal(second.imported, 1);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  const accounts = store.providers.codex.accounts;
  assert.equal(accounts.length, 1);
  assert.equal(accounts[0].api_key, 'codex-token-v2');
  assert.equal(accounts[0].email, 'rotated@codex.test');
  assert.equal(accounts[0].priority, 7);
});

await run('importAuthDir syncs owned accounts and removes deleted auth files', () => {
  const dir = makeTempDir();
  const authDir = path.join(dir, 'auth');
  fs.mkdirSync(authDir, { recursive: true });
  invalidateProviderKeyCache();

  const firstAuthPath = path.join(authDir, 'auth17.json');
  const secondAuthPath = path.join(authDir, 'auth19.json');
  fs.writeFileSync(firstAuthPath, JSON.stringify({
    provider: 'openai',
    access_token: 'sk-auth-owned-a',
    account_id: 'acct-owned-a',
  }, null, 2));
  fs.writeFileSync(secondAuthPath, JSON.stringify({
    provider: 'openai',
    access_token: 'sk-auth-owned-b',
    account_id: 'acct-owned-b',
  }, null, 2));

  const first = importAuthDir(dir, authDir);
  assert.equal(first.ok, true);
  assert.equal(first.imported, 2);

  let raw = JSON.parse(fs.readFileSync(path.join(dir, 'hub_provider_keys.json'), 'utf8'));
  const sourceKey = `auth_dir:${authDir}`;
  assert.ok(Array.isArray(raw.import_sources));
  assert.ok(raw.import_sources.includes(sourceKey));
  assert.equal(raw.providers.openai.accounts.length, 2);
  assert.ok(raw.providers.openai.accounts.every((account) => Array.isArray(account.source_owners) && account.source_owners.includes(sourceKey)));

  fs.unlinkSync(secondAuthPath);
  const second = importAuthDir(dir, authDir);
  assert.equal(second.ok, true);
  assert.equal(second.imported, 1);

  raw = JSON.parse(fs.readFileSync(path.join(dir, 'hub_provider_keys.json'), 'utf8'));
  assert.equal(raw.providers.openai.accounts.length, 1);
  assert.equal(raw.providers.openai.accounts[0].account_id, 'acct-owned-a');
  assert.deepEqual(raw.providers.openai.accounts[0].source_owners, [sourceKey]);
  assert.equal(raw.import_source_statuses[sourceKey].state, 'ready');
  assert.equal(raw.import_source_statuses[sourceKey].owned_account_count, 1);
  assert.equal(raw.import_source_statuses[sourceKey].last_imported_count, 1);
  assert.equal(raw.import_source_statuses[sourceKey].last_error_count, 0);
  assert.deepEqual(raw.import_source_statuses[sourceKey].last_errors, []);
});

await run('importAuthDir scans auth-disabled sibling and preserves disabled state fail-closed', () => {
  const dir = makeTempDir();
  const authRoot = path.join(dir, 'auth');
  const disabledRoot = path.join(dir, 'auth-disabled');
  fs.mkdirSync(authRoot, { recursive: true });
  fs.mkdirSync(disabledRoot, { recursive: true });
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(disabledRoot, 'claude_disabled.json'), JSON.stringify({
    access_token: 'sk-ant-disabled-token',
    type: 'claude',
    email: 'disabled@claude.test',
  }, null, 2));

  const result = importAuthDir(dir, authRoot);
  assert.equal(result.ok, true);
  assert.equal(result.imported, 1);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  const account = store.providers.claude.accounts[0];
  assert.equal(account.enabled, false);
  assert.ok(account.account_key.startsWith('claude:'));
});

await run('importAuthDir keeps same basename files in separate directories as separate accounts', () => {
  const dir = makeTempDir();
  const authRoot = makeTempDir();
  const aDir = path.join(authRoot, 'a');
  const bDir = path.join(authRoot, 'b');
  fs.mkdirSync(aDir, { recursive: true });
  fs.mkdirSync(bDir, { recursive: true });
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(aDir, 'claude.json'), JSON.stringify({
    type: 'claude',
    access_token: 'claude-token-a',
    email: 'a@test.com',
  }, null, 2));
  fs.writeFileSync(path.join(bDir, 'claude.json'), JSON.stringify({
    type: 'claude',
    access_token: 'claude-token-b',
    email: 'b@test.com',
  }, null, 2));

  const result = importAuthDir(dir, authRoot);
  assert.equal(result.ok, true);
  assert.equal(result.imported, 2);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.claude.accounts.length, 2);
});

await run('importAuthDir returns error for missing directory', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = importAuthDir(dir, '/nonexistent/path');
  assert.equal(result.ok, false);
});

await run('importProxyConfig imports YAML config', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const yamlContent = `
openai-compatibility:
  - name: deepseek
    base-url: "https://api.deepseek.com"
    api-key-entries:
      - api-key: "sk-deepseek-test123456"
    models:
      - name: deepseek-chat

claude-api-key:
  - name: claude-main
    api-key: "sk-ant-claude-test123456"
    base-url: "https://api.anthropic.com"

gemini-api-key:
  - name: gemini-pro
    api-key: "AIza-gemini-test123456"
`;
  const configPath = path.join(dir, 'config.yaml');
  fs.writeFileSync(configPath, yamlContent);

  const result = importProxyConfig(dir, configPath);
  assert.equal(result.ok, true);
  assert.ok(result.imported >= 2, `expected >= 2 imports, got ${result.imported}`);
});

await run('importProxyConfig keeps multiple keys from the same provider in one pool', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const configPath = path.join(dir, 'multi-openai.yaml');
  fs.writeFileSync(configPath, `
openai-compatibility:
  - name: primary
    base-url: "https://api.example.com"
    api-key-entries:
      - api-key: "sk-openai-a"
      - api-key: "sk-openai-b"
`, 'utf8');

  const result = importProxyConfig(dir, configPath);
  assert.equal(result.ok, true);
  assert.equal(result.imported, 2);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.openai.accounts.length, 2);
  const poolIDs = new Set(store.providers.openai.accounts.map((account) => account.pool_id));
  assert.equal(poolIDs.size, 1);
  assert.equal(store.providers.openai.accounts[0].provider_host, 'api.example.com');
});

await run('addProviderKey keeps same host and wire in the same pool', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-pool-a',
    auth_type: 'api_key',
    base_url: 'https://api.example.com/v1',
    wire_api: 'chat_completions',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-pool-b',
    auth_type: 'api_key',
    base_url: 'https://api.example.com/v1',
    wire_api: 'chat_completions',
  });

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  const accounts = store.providers.openai.accounts;
  assert.equal(accounts.length, 2);
  assert.equal(accounts[0].pool_id, accounts[1].pool_id);
  assert.equal(accounts[0].provider_host, 'api.example.com');
  assert.equal(accounts[0].wire_api, 'chat_completions');
});

await run('addProviderKey splits pools when wire_api differs', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-wire-a',
    auth_type: 'api_key',
    base_url: 'https://api.example.com/v1',
    wire_api: 'chat_completions',
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-wire-b',
    auth_type: 'api_key',
    base_url: 'https://api.example.com/v1',
    wire_api: 'responses',
  });

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  const accounts = store.providers.openai.accounts;
  assert.equal(accounts.length, 2);
  assert.notEqual(accounts[0].pool_id, accounts[1].pool_id);
});

await run('addProviderKey splits pools when custom header boundary differs', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-hdr-a',
    auth_type: 'api_key',
    base_url: 'https://api.example.com/v1',
    custom_headers: { 'X-Tenant': 'alpha' },
  });
  invalidateProviderKeyCache();
  addProviderKey(dir, {
    provider: 'openai',
    api_key: 'sk-hdr-b',
    auth_type: 'api_key',
    base_url: 'https://api.example.com/v1',
    custom_headers: { 'X-Tenant': 'beta' },
  });

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  const accounts = store.providers.openai.accounts;
  assert.equal(accounts.length, 2);
  assert.notEqual(accounts[0].pool_id, accounts[1].pool_id);
});

await run('importProxyConfig reimports the same YAML config idempotently', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();

  const configPath = path.join(dir, 'deepseek.yaml');
  fs.writeFileSync(configPath, `
openai-compatibility:
  - name: first
    base-url: "https://api.example.com"
    api-key-entries:
      - api-key: "sk-one"
      - api-key: "sk-two"
`, 'utf8');

  const first = importProxyConfig(dir, configPath);
  assert.equal(first.ok, true);
  assert.equal(first.imported, 2);

  const second = importProxyConfig(dir, configPath);
  assert.equal(second.ok, true);
  assert.equal(second.imported, 2);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.openai.accounts.length, 2);
});

await run('importProxyConfig syncs owned proxy config accounts and removes deleted entries', () => {
  const dir = makeTempDir();
  const configPath = path.join(dir, 'deepseek-owned.yaml');
  invalidateProviderKeyCache();

  fs.writeFileSync(configPath, `
openai-compatibility:
  - name: first
    base-url: "https://api.example.com"
    api-key-entries:
      - api-key: "sk-owned-one"
      - api-key: "sk-owned-two"
`, 'utf8');

  const first = importProxyConfig(dir, configPath);
  assert.equal(first.ok, true);
  assert.equal(first.imported, 2);

  let raw = JSON.parse(fs.readFileSync(path.join(dir, 'hub_provider_keys.json'), 'utf8'));
  const sourceKey = `config_path:${configPath}`;
  assert.ok(Array.isArray(raw.import_sources));
  assert.ok(raw.import_sources.includes(sourceKey));
  assert.equal(raw.providers.openai.accounts.length, 2);
  assert.ok(raw.providers.openai.accounts.every((account) => Array.isArray(account.source_owners) && account.source_owners.includes(sourceKey)));

  fs.writeFileSync(configPath, `
openai-compatibility:
  - name: first
    base-url: "https://api.example.com"
    api-key-entries:
      - api-key: "sk-owned-one"
`, 'utf8');

  const second = importProxyConfig(dir, configPath);
  assert.equal(second.ok, true);
  assert.equal(second.imported, 1);

  raw = JSON.parse(fs.readFileSync(path.join(dir, 'hub_provider_keys.json'), 'utf8'));
  assert.equal(raw.providers.openai.accounts.length, 1);
  assert.equal(raw.providers.openai.accounts[0].api_key, 'sk-owned-one');
  assert.deepEqual(raw.providers.openai.accounts[0].source_owners, [sourceKey]);
});

await run('importProxyConfig treats Codex CLI TOML without explicit auth binding as a no-op', () => {
  const dir = makeTempDir();
  const codexDir = makeTempDir();
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(codexDir, 'config149.toml'), `
model = "gpt-5.4"
model_reasoning_effort = "xhigh"

[projects."/tmp/example"]
trust_level = "trusted"
`, 'utf8');

  const first = importProxyConfig(dir, path.join(codexDir, 'config149.toml'));
  assert.equal(first.ok, true);
  assert.equal(first.imported, 0);
  assert.deepEqual(first.errors, []);
});

await run('importProxyConfig imports sibling Codex auth files when TOML omits auth_file', () => {
  const dir = makeTempDir();
  const codexDir = makeTempDir();
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(codexDir, 'config149.toml'), `
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
`, 'utf8');

  const payloadA = Buffer.from(JSON.stringify({
    email: 'first@test.com',
    chatgpt_account_id: 'acct-first',
  })).toString('base64url');
  const payloadB = Buffer.from(JSON.stringify({
    email: 'second@test.com',
    chatgpt_account_id: 'acct-second',
  })).toString('base64url');

  fs.writeFileSync(path.join(codexDir, 'auth17.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      id_token: `h.${payloadA}.s`,
      access_token: 'first-access-token',
      refresh_token: 'first-refresh-token',
      account_id: 'acct-first',
    },
  }, null, 2));
  fs.writeFileSync(path.join(codexDir, 'auth19.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      id_token: `h.${payloadB}.s`,
      access_token: 'second-access-token',
      refresh_token: 'second-refresh-token',
      account_id: 'acct-second',
    },
  }, null, 2));

  const result = importProxyConfig(dir, path.join(codexDir, 'config149.toml'));
  assert.equal(result.ok, true);
  assert.equal(result.imported, 2);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.codex.accounts.length, 2);
  assert.deepEqual(
    store.providers.codex.accounts.map((account) => account.account_id).sort(),
    ['acct-first', 'acct-second']
  );
  assert.ok(store.providers.codex.accounts.every((account) => account.provider_host === 'api.openai.com'));
  assert.ok(store.providers.codex.accounts.every((account) => account.wire_api === 'chat_completions'));
  assert.equal(new Set(store.providers.codex.accounts.map((account) => account.pool_id)).size, 1);
});

await run('importProxyConfig overlays explicit Codex CLI provider metadata onto imported auth files', () => {
  const dir = makeTempDir();
  const codexDir = makeTempDir();
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(codexDir, 'config149.toml'), `
model = "gpt-5.4"
model_provider = "gateway"

[model_providers.gateway]
base_url = "https://gateway.example.com/openai/v1"
requires_openai_auth = true
wire_api = "responses"
`, 'utf8');

  const payloadA = Buffer.from(JSON.stringify({
    email: 'first@test.com',
    chatgpt_account_id: 'acct-first',
  })).toString('base64url');
  const payloadB = Buffer.from(JSON.stringify({
    email: 'second@test.com',
    chatgpt_account_id: 'acct-second',
  })).toString('base64url');

  fs.writeFileSync(path.join(codexDir, 'auth17.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      id_token: `h.${payloadA}.s`,
      access_token: 'first-access-token',
      refresh_token: 'first-refresh-token',
      account_id: 'acct-first',
    },
  }, null, 2));
  fs.writeFileSync(path.join(codexDir, 'auth19.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      id_token: `h.${payloadB}.s`,
      access_token: 'second-access-token',
      refresh_token: 'second-refresh-token',
      account_id: 'acct-second',
    },
  }, null, 2));

  const result = importProxyConfig(dir, path.join(codexDir, 'config149.toml'));
  assert.equal(result.ok, true);
  assert.equal(result.imported, 2);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  const accounts = store.providers.codex.accounts;
  assert.equal(accounts.length, 2);
  assert.ok(accounts.every((account) => account.base_url === 'https://gateway.example.com/openai/v1'));
  assert.ok(accounts.every((account) => account.provider_host === 'gateway.example.com'));
  assert.ok(accounts.every((account) => account.wire_api === 'responses'));
  assert.equal(new Set(accounts.map((account) => account.pool_id)).size, 1);
});

await run('importProxyConfig imports Codex CLI TOML with an explicit auth_file binding', () => {
  const dir = makeTempDir();
  const codexDir = makeTempDir();
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(codexDir, 'config149.toml'), `
model = "gpt-5.4"
auth_file = "auth17.json"
`, 'utf8');

  const payload = Buffer.from(JSON.stringify({
    email: 'first@test.com',
    chatgpt_account_id: 'acct-first',
  })).toString('base64url');
  fs.writeFileSync(path.join(codexDir, 'auth17.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      id_token: `h.${payload}.s`,
      access_token: 'first-access-token',
      refresh_token: 'first-refresh-token',
      account_id: 'acct-first',
    },
  }, null, 2));

  const result = importProxyConfig(dir, path.join(codexDir, 'config149.toml'));
  assert.equal(result.ok, true);
  assert.equal(result.imported, 1);

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.codex.accounts.length, 1);
  const statuses = listProviderKeyImportSourceStatuses(dir);
  assert.equal(statuses.length, 1);
  assert.equal(statuses[0].state, 'ready');
  assert.equal(statuses[0].owned_account_count, 1);
});

await run('importProxyConfig persists sync_failed import source status without pruning owned accounts', () => {
  const dir = makeTempDir();
  const codexDir = makeTempDir();
  const configPath = path.join(codexDir, 'config149.toml');
  invalidateProviderKeyCache();

  fs.writeFileSync(path.join(codexDir, 'auth17.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: {
      access_token: 'sync-failed-access-token',
      refresh_token: 'sync-failed-refresh-token',
      account_id: 'acct-sync-failed',
    },
  }, null, 2));
  fs.writeFileSync(configPath, `
model = "gpt-5.4"
auth_file = "auth17.json"
`, 'utf8');

  const first = importProxyConfig(dir, configPath);
  assert.equal(first.ok, true);
  assert.equal(first.imported, 1);

  fs.writeFileSync(configPath, `
title = "unsupported"
`, 'utf8');

  const second = importProxyConfig(dir, configPath);
  assert.equal(second.ok, false);
  assert.ok(second.errors.includes('unsupported_toml_config'));

  invalidateProviderKeyCache();
  const store = loadProviderKeyStore(dir, 0);
  assert.equal(store.providers.codex.accounts.length, 1);

  const sourceKey = `config_path:${configPath}`;
  const raw = JSON.parse(fs.readFileSync(path.join(dir, 'hub_provider_keys.json'), 'utf8'));
  assert.equal(raw.import_source_statuses[sourceKey].state, 'sync_failed');
  assert.equal(raw.import_source_statuses[sourceKey].owned_account_count, 1);
  assert.equal(raw.import_source_statuses[sourceKey].last_error_count, 1);
  assert.deepEqual(raw.import_source_statuses[sourceKey].last_errors, ['unsupported_toml_config']);
});

await run('importProxyConfig returns error for missing file', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = importProxyConfig(dir, '/nonexistent/config.yaml');
  assert.equal(result.ok, false);
});

await run('providerKeyStoreSummary returns provider counts', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-sum-1', auth_type: 'api_key' });
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-sum-2', auth_type: 'api_key' });
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'claude', api_key: 'sk-sum-3', auth_type: 'api_key', enabled: false });
  invalidateProviderKeyCache();

  const summary = providerKeyStoreSummary(dir);
  assert.ok(summary.providers.length >= 2);
  const openai = summary.providers.find(p => p.provider === 'openai');
  assert.ok(openai);
  assert.equal(openai.total_accounts, 2);
  assert.equal(openai.enabled_accounts, 2);

  const claude = summary.providers.find(p => p.provider === 'claude');
  assert.ok(claude);
  assert.equal(claude.total_accounts, 1);
  assert.equal(claude.enabled_accounts, 0);
});

await run('save and load round-trip preserves data', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  addProviderKey(dir, { provider: 'openai', api_key: 'sk-rt-1', auth_type: 'api_key', tier: 'pro' });
  invalidateProviderKeyCache();

  const store = loadProviderKeyStore(dir, 0);
  assert.ok(store.providers.openai);
  assert.equal(store.providers.openai.accounts.length, 1);
  assert.equal(store.providers.openai.accounts[0].tier, 'pro');
});

await run('oauth account requires access_token or refresh_token', () => {
  const dir = makeTempDir();
  invalidateProviderKeyCache();
  const result = addProviderKey(dir, {
    provider: 'openai',
    auth_type: 'oauth',
    refresh_token: 'rt-oauth-test-1234567890',
  });
  assert.equal(result.ok, true);
});

await run('copilot type detected from filename', () => {
  const dir = makeTempDir();
  const authDir = makeTempDir();
  invalidateProviderKeyCache();

  const copilotAuth = {
    access_token: 'ghu_copilot-token-1234567890',
    type: 'github-copilot',
    email: 'user@github.com',
  };
  fs.writeFileSync(path.join(authDir, 'copilot_user.json'), JSON.stringify(copilotAuth, null, 2));

  const result = importAuthDir(dir, authDir);
  assert.equal(result.ok, true);
  assert.ok(result.imported >= 1);
  invalidateProviderKeyCache();
  const keys = listProviderKeys(dir, 'copilot');
  assert.ok(keys.length >= 1);
});

process.stdout.write('\nAll provider_key_store tests passed.\n');
