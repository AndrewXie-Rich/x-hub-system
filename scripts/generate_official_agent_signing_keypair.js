#!/usr/bin/env node
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function safeString(value) {
  return String(value == null ? "" : value).trim();
}

function usage() {
  return [
    "Usage:",
    "  node scripts/generate_official_agent_signing_keypair.js \\",
    "    --private-key-out /secure/path/xhub_official_ed25519.pem \\",
    "    --trust-out official-agent-skills/publisher/trusted_publishers.json",
    "",
    "Flags:",
    "  --publisher-id <id>       default: xhub.official",
    "  --private-key-out <path>  required",
    "  --trust-out <path>        required",
    "  --force                   overwrite existing files",
  ].join("\n");
}

function fromBase64Url(text) {
  const raw = String(text || "").replace(/-/g, "+").replace(/_/g, "/");
  const padded = raw.padEnd(Math.ceil(raw.length / 4) * 4, "=");
  return Buffer.from(padded, "base64");
}

function ensureParentDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeFileChecked(filePath, contents, force) {
  if (!force && fs.existsSync(filePath)) {
    throw new Error(`refusing to overwrite existing file: ${filePath}`);
  }
  ensureParentDir(filePath);
  fs.writeFileSync(filePath, contents, "utf8");
}

function main(argv) {
  const args = Array.isArray(argv) ? [...argv] : process.argv.slice(2);
  let publisherId = "xhub.official";
  let privateKeyOut = "";
  let trustOut = "";
  let force = false;

  for (let index = 0; index < args.length; index += 1) {
    const flag = String(args[index] || "");
    if (flag === "--publisher-id") {
      publisherId = safeString(args[index + 1] || "");
      index += 1;
      continue;
    }
    if (flag === "--private-key-out") {
      privateKeyOut = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--trust-out") {
      trustOut = path.resolve(String(args[index + 1] || ""));
      index += 1;
      continue;
    }
    if (flag === "--force") {
      force = true;
      continue;
    }
    throw new Error(`unknown flag: ${flag}\n\n${usage()}`);
  }

  if (!publisherId || !privateKeyOut || !trustOut) {
    throw new Error(`missing required flags\n\n${usage()}`);
  }

  const pair = crypto.generateKeyPairSync("ed25519");
  const publicJwk = pair.publicKey.export({ format: "jwk" });
  const rawPublic = fromBase64Url(String(publicJwk.x || ""));
  const publicKey = `base64:${rawPublic.toString("base64")}`;
  const privateKeyPem = pair.privateKey.export({ format: "pem", type: "pkcs8" }).toString("utf8");
  const trustSnapshot = {
    schema_version: "xhub.trusted_publishers.v1",
    updated_at_ms: Date.now(),
    publishers: [
      {
        publisher_id: publisherId,
        public_key_ed25519: publicKey,
        enabled: true,
      },
    ],
  };

  writeFileChecked(privateKeyOut, privateKeyPem, force);
  writeFileChecked(trustOut, `${JSON.stringify(trustSnapshot, null, 2)}\n`, force);

  process.stdout.write(`${JSON.stringify({
    publisher_id: publisherId,
    private_key_out: privateKeyOut,
    trust_out: trustOut,
    public_key_ed25519: publicKey,
  }, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${String(error && error.stack ? error.stack : error)}\n`);
    process.exitCode = 1;
  }
}
