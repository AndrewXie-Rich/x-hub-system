#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const {
  resolveLocalAdminToken,
  safeString,
} = require("./lib/xhub_local_admin_token.js");

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

function buildResolutionPayload(args = {}, env = process.env) {
  const explicitAdminToken = safeString(args["admin-token"] || env.HUB_ADMIN_TOKEN);
  const resolution = explicitAdminToken
    ? {
        admin_token: explicitAdminToken,
        token_source: "explicit_arg_or_env",
        tokens_file: "",
        key_file: "",
      }
    : resolveLocalAdminToken(
        {
          home_dir: args["home-dir"] || env.XHUB_SOURCE_RUN_HOME || "",
          hub_dir: args["hub-dir"] || env.REL_FLOW_HUB_BASE_DIR || env.XHUB_HUB_DIR || "",
          hub_tokens_file: args["hub-tokens-file"] || "",
          remote_secrets_key_file: args["remote-secrets-key-file"] || "",
        },
        env
      );

  return {
    schema_version: "xhub.local_admin_token_resolution.v1",
    resolved_at_ms: Date.now(),
    ok: safeString(resolution.admin_token).length > 0,
    admin_token: safeString(resolution.admin_token),
    token_source: safeString(resolution.token_source),
    tokens_file: safeString(resolution.tokens_file),
    key_file: safeString(resolution.key_file),
  };
}

function runCli(argv = process.argv, env = process.env, deps = {}) {
  const args = parseArgs(argv);
  const stdout = deps.stdout || process.stdout;
  const payload = buildResolutionPayload(args, env);
  const outJsonPath = safeString(args["out-json"]);
  const printToken = safeString(args["print-token"]).length > 0;
  const jsonText = `${JSON.stringify(payload, null, 2)}\n`;

  if (outJsonPath) {
    writeText(path.resolve(outJsonPath), jsonText);
  }

  if (printToken) {
    if (!payload.ok) {
      throw new Error(`local admin token resolution failed: ${payload.token_source || "unknown"}`);
    }
    stdout.write(`${payload.admin_token}\n`);
    return payload;
  }

  stdout.write(jsonText);
  if (!payload.ok) {
    throw new Error(`local admin token resolution failed: ${payload.token_source || "unknown"}`);
  }
  return payload;
}

if (require.main === module) {
  try {
    runCli(process.argv, process.env);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  buildResolutionPayload,
  parseArgs,
  runCli,
};
