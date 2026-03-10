#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_BASE_URL = "http://127.0.0.1:50052";
const DEFAULT_ROUTE_PATH = "/admin/pairing/connector-ingress/gate-snapshot";
const VALID_SOURCES = new Set(["auto", "audit", "scan"]);

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const cur = String(argv[i] || "");
    if (!cur.startsWith("--")) continue;
    const key = cur.slice(2);
    const nxt = argv[i + 1];
    if (nxt && !String(nxt).startsWith("--")) {
      out[key] = String(nxt);
      i += 1;
    } else {
      out[key] = "1";
    }
  }
  return out;
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function toIntLike(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.floor(n);
}

function safeNumber(value, fallback = 0) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return n;
}

function buildSnapshotUrl(opts = {}) {
  const baseUrl = String(opts.base_url || DEFAULT_BASE_URL).trim();
  if (!baseUrl) throw new Error("missing base_url");
  const routePath = String(opts.route_path || DEFAULT_ROUTE_PATH).trim() || DEFAULT_ROUTE_PATH;
  const source = String(opts.source || "auto").trim().toLowerCase() || "auto";
  if (!VALID_SOURCES.has(source)) {
    throw new Error(`invalid source: ${source} (expected auto|audit|scan)`);
  }

  const url = new URL(routePath, baseUrl);
  url.searchParams.set("source", source);

  const maybeAttach = (key, value, intLike = false) => {
    const raw = String(value || "").trim();
    if (!raw) return;
    if (intLike) {
      const n = toIntLike(raw, -1);
      if (n < 0) return;
      url.searchParams.set(key, String(n));
      return;
    }
    url.searchParams.set(key, raw);
  };

  maybeAttach("since_ms", opts.since_ms, true);
  maybeAttach("until_ms", opts.until_ms, true);
  maybeAttach("device_id", opts.device_id);
  maybeAttach("user_id", opts.user_id);
  maybeAttach("project_id", opts.project_id);
  maybeAttach("request_id", opts.request_id);
  maybeAttach("limit", opts.limit, true);

  return {
    url: url.toString(),
    source,
    base_url: baseUrl,
    route_path: routePath,
  };
}

async function fetchConnectorIngressGateSnapshot(opts = {}, deps = {}) {
  const fetchFn = deps.fetch || globalThis.fetch;
  if (typeof fetchFn !== "function") {
    throw new Error("fetch is unavailable in current runtime");
  }

  const adminToken = String(opts.admin_token || "").trim();
  if (!adminToken) throw new Error("missing admin_token");

  const requestMeta = buildSnapshotUrl(opts);
  const response = await fetchFn(requestMeta.url, {
    method: "GET",
    headers: {
      authorization: `Bearer ${adminToken}`,
    },
  });

  const text = await response.text();
  let payload = {};
  try {
    payload = JSON.parse(String(text || "{}"));
  } catch {
    payload = {};
  }

  if (!response.ok || payload.ok !== true) {
    const code = String(payload?.error?.code || payload?.code || `http_${Number(response.status || 0)}`).trim();
    throw new Error(`connector ingress gate snapshot fetch failed: ${code}`);
  }

  const snapshot = payload.snapshot && typeof payload.snapshot === "object" ? payload.snapshot : {};
  const metrics = snapshot.metrics && typeof snapshot.metrics === "object" ? snapshot.metrics : {};

  return {
    schema_version: "xt_ready_connector_ingress_gate_fetch.v1",
    fetched_at_ms: Date.now(),
    request: requestMeta,
    source_used: String(payload.source_used || "").trim(),
    data_ready: payload.data_ready === true,
    audit_row_count: Math.max(0, toIntLike(payload.audit_row_count, 0)),
    scan_entry_count: Math.max(0, toIntLike(payload.scan_entry_count, 0)),
    snapshot,
    snapshot_audit: payload.snapshot_audit && typeof payload.snapshot_audit === "object" ? payload.snapshot_audit : {},
    snapshot_scan: payload.snapshot_scan && typeof payload.snapshot_scan === "object" ? payload.snapshot_scan : {},
    summary: {
      non_message_ingress_policy_coverage: safeNumber(metrics.non_message_ingress_policy_coverage, 0),
      blocked_event_miss_rate: safeNumber(metrics.blocked_event_miss_rate, 0),
    },
  };
}

async function runCli(argv = process.argv, env = process.env) {
  const args = parseArgs(argv);
  const outPath = String(args["out-json"] || "").trim();
  if (!outPath) throw new Error("missing --out-json");

  const payload = await fetchConnectorIngressGateSnapshot({
    base_url: args["base-url"] || DEFAULT_BASE_URL,
    route_path: args["route-path"] || DEFAULT_ROUTE_PATH,
    admin_token: args["admin-token"] || env.HUB_ADMIN_TOKEN || "",
    source: args.source || "auto",
    since_ms: args["since-ms"] || "",
    until_ms: args["until-ms"] || "",
    device_id: args["device-id"] || "",
    user_id: args["user-id"] || "",
    project_id: args["project-id"] || "",
    request_id: args["request-id"] || "",
    limit: args.limit || "",
  });

  writeText(path.resolve(outPath), `${JSON.stringify(payload, null, 2)}\n`);
  console.log(
    `ok - connector ingress gate snapshot fetched (source=${payload.source_used || payload.request.source}, blocked_event_miss_rate=${payload.summary.blocked_event_miss_rate}, out=${outPath})`
  );
  return payload;
}

if (require.main === module) {
  runCli(process.argv, process.env).catch((err) => {
    console.error(`error: ${err.message}`);
    process.exit(1);
  });
}

module.exports = {
  buildSnapshotUrl,
  fetchConnectorIngressGateSnapshot,
  parseArgs,
  runCli,
};
