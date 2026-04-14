#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  buildSnapshotUrl,
  fetchConnectorIngressGateSnapshot,
} = require("./m3_fetch_connector_ingress_gate_snapshot.js");
const {
  decryptRemoteSecretsCiphertext,
  resolveLocalAdminToken,
} = require("./lib/xhub_local_admin_token.js");
const {
  runCli: resolveLocalAdminTokenCli,
} = require("./resolve_xhub_local_admin_token.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

async function runAsync(name, fn) {
  try {
    await fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function encryptRemoteSecretsCiphertext(plaintext, keyBytes) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", keyBytes, iv);
  const ciphertext = Buffer.concat([cipher.update(Buffer.from(String(plaintext), "utf8")), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1:${Buffer.concat([iv, ciphertext, tag]).toString("base64")}`;
}

run("buildSnapshotUrl encodes source and filter params", () => {
  const out = buildSnapshotUrl({
    base_url: "http://127.0.0.1:50052",
    route_path: "/admin/pairing/connector-ingress/gate-snapshot",
    source: "audit",
    device_id: "pairing-http",
    since_ms: "1000",
    until_ms: "2000",
    limit: "50",
  });
  assert.equal(out.source, "audit");
  const url = new URL(out.url);
  assert.equal(url.searchParams.get("source"), "audit");
  assert.equal(url.searchParams.get("device_id"), "pairing-http");
  assert.equal(url.searchParams.get("since_ms"), "1000");
  assert.equal(url.searchParams.get("until_ms"), "2000");
  assert.equal(url.searchParams.get("limit"), "50");
});

run("buildSnapshotUrl rejects invalid source", () => {
  assert.throws(
    () => buildSnapshotUrl({
      base_url: "http://127.0.0.1:50052",
      source: "broken",
    }),
    /invalid source/
  );
});

run("decryptRemoteSecretsCiphertext decrypts v1 ciphertext", () => {
  const key = crypto.randomBytes(32);
  const ciphertext = encryptRemoteSecretsCiphertext("axhub_admin_test", key);
  assert.equal(decryptRemoteSecretsCiphertext(ciphertext, key), "axhub_admin_test");
});

run("resolveLocalAdminToken auto-discovers encrypted local token files", () => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt-ready-token-home-"));
  const runtimeDir = path.join(homeDir, "Library", "Containers", "com.rel.flowhub", "Data", "XHub");
  const keyDir = path.join(homeDir, "RELFlowHub");
  fs.mkdirSync(runtimeDir, { recursive: true });
  fs.mkdirSync(keyDir, { recursive: true });

  const key = crypto.randomBytes(32);
  const token = "axhub_admin_discovered";
  fs.writeFileSync(path.join(keyDir, ".remote_model_secrets_v1.key"), key);
  fs.writeFileSync(
    path.join(runtimeDir, "hub_grpc_tokens.json"),
    JSON.stringify({
      schemaVersion: "hub_grpc_tokens.v1",
      updatedAtMs: 1730000000000,
      adminTokenCiphertext: encryptRemoteSecretsCiphertext(token, key),
    })
  );

  const out = resolveLocalAdminToken({ home_dir: homeDir }, {});
  assert.equal(out.admin_token, token);
  assert.equal(out.token_source, "encrypted_tokens_file");
});

run("resolveLocalAdminToken auto-discovers app-group token files", () => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt-ready-token-group-"));
  const groupDir = path.join(homeDir, "Library", "Group Containers", "group.rel.flowhub");
  fs.mkdirSync(groupDir, { recursive: true });

  const key = crypto.randomBytes(32);
  const token = "axhub_admin_group";
  fs.writeFileSync(path.join(groupDir, ".remote_model_secrets_v1.key"), key);
  fs.writeFileSync(
    path.join(groupDir, "hub_grpc_tokens.json"),
    JSON.stringify({
      schemaVersion: "hub_grpc_tokens.v1",
      updatedAtMs: 1730000000000,
      adminTokenCiphertext: encryptRemoteSecretsCiphertext(token, key),
    })
  );

  const out = resolveLocalAdminToken({ home_dir: homeDir }, {});
  assert.equal(out.admin_token, token);
  assert.equal(out.token_source, "encrypted_tokens_file");
});

run("resolveLocalAdminToken prefers plaintext fallback", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt-ready-token-plain-"));
  const tokensFile = path.join(tmpDir, "hub_grpc_tokens.json");
  fs.writeFileSync(
    tokensFile,
    JSON.stringify({
      schemaVersion: "hub_grpc_tokens.v1",
      updatedAtMs: 1730000000000,
      adminToken: "axhub_admin_plain",
    })
  );

  const out = resolveLocalAdminToken({ hub_tokens_file: tokensFile }, {});
  assert.equal(out.admin_token, "axhub_admin_plain");
  assert.equal(out.token_source, "plaintext_tokens_file");
});

run("resolve_xhub_local_admin_token CLI emits JSON payload", () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "xt-ready-token-cli-"));
  const tokensFile = path.join(tmpDir, "hub_grpc_tokens.json");
  const outJson = path.join(tmpDir, "resolution.json");
  fs.writeFileSync(
    tokensFile,
    JSON.stringify({
      schemaVersion: "hub_grpc_tokens.v1",
      updatedAtMs: 1730000000000,
      adminToken: "axhub_admin_cli",
    })
  );

  const chunks = [];
  const payload = resolveLocalAdminTokenCli(
    ["node", "resolve_xhub_local_admin_token.js", "--hub-tokens-file", tokensFile, "--out-json", outJson],
    {},
    {
      stdout: {
        write(chunk) {
          chunks.push(String(chunk));
        },
      },
    }
  );

  assert.equal(payload.ok, true);
  assert.equal(payload.admin_token, "axhub_admin_cli");
  const stdoutPayload = JSON.parse(chunks.join(""));
  assert.equal(stdoutPayload.admin_token, "axhub_admin_cli");
  const writtenPayload = JSON.parse(fs.readFileSync(outJson, "utf8"));
  assert.equal(writtenPayload.token_source, "plaintext_tokens_file");
});

async function main() {
await runAsync("fetchConnectorIngressGateSnapshot parses successful payload", async () => {
  const calls = [];
  const fakeFetch = async (url, init) => {
    calls.push({ url: String(url || ""), init });
    return {
      ok: true,
      status: 200,
      text: async () => JSON.stringify({
        ok: true,
        source_used: "audit",
        data_ready: true,
        audit_row_count: 3,
        scan_entry_count: 4,
        snapshot: {
          schema_version: "xhub.connector.non_message_ingress_gate.v1",
          metrics: {
            non_message_ingress_policy_coverage: 1,
            blocked_event_miss_rate: 0.005,
          },
        },
      }),
    };
  };

  const out = await fetchConnectorIngressGateSnapshot(
    {
      base_url: "http://127.0.0.1:50052",
      admin_token: "admin-token-1",
      source: "auto",
    },
    { fetch: fakeFetch }
  );
  assert.equal(calls.length, 1);
  assert.equal(calls[0].init?.headers?.authorization, "Bearer admin-token-1");
  assert.equal(out.source_used, "audit");
  assert.equal(out.data_ready, true);
  assert.equal(out.summary.non_message_ingress_policy_coverage, 1);
  assert.equal(out.summary.blocked_event_miss_rate, 0.005);
});

await runAsync("fetchConnectorIngressGateSnapshot fails closed on error payload", async () => {
  const fakeFetch = async () => ({
    ok: false,
    status: 403,
    text: async () => JSON.stringify({
      ok: false,
      error: { code: "permission_denied" },
    }),
  });
  await assert.rejects(
    async () => fetchConnectorIngressGateSnapshot(
      {
        base_url: "http://127.0.0.1:50052",
        admin_token: "admin-token-2",
      },
      { fetch: fakeFetch }
    ),
    /permission_denied/
  );
});

await runAsync("fetchConnectorIngressGateSnapshot requires admin token", async () => {
  await assert.rejects(
    async () => fetchConnectorIngressGateSnapshot(
      {
        base_url: "http://127.0.0.1:50052",
        admin_token: "",
      },
      { fetch: async () => ({ ok: true, status: 200, text: async () => "{}" }) }
    ),
    /missing admin_token/
  );
});
}

main().catch((err) => {
  console.error(err?.stack || String(err));
  process.exit(1);
});
