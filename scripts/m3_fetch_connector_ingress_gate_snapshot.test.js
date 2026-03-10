#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");

const {
  buildSnapshotUrl,
  fetchConnectorIngressGateSnapshot,
} = require("./m3_fetch_connector_ingress_gate_snapshot.js");

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
