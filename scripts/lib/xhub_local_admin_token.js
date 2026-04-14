#!/usr/bin/env node
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const DEFAULT_HUB_BUNDLE_ID = "com.rel.flowhub";
const DEFAULT_APP_GROUP_IDS = ["group.rel.flowhub", "group.com.relentless.flowhub"];
const RUNTIME_DIRECTORY_ALIASES = ["XHub", "RELFlowHub"];
const HUB_TOKENS_FILE_NAME = "hub_grpc_tokens.json";
const REMOTE_SECRETS_KEY_FILE_NAME = ".remote_model_secrets_v1.key";
const REMOTE_SECRETS_VERSION_PREFIX = "v1:";
const AES_GCM_ALG = "aes-256-gcm";

function safeString(value) {
  return String(value || "").trim();
}

function uniqueStrings(values = []) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = safeString(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function realHomeDirectory(env = process.env) {
  const override = safeString(env.XHUB_SOURCE_RUN_HOME);
  return override || os.homedir();
}

function runtimeDirectoryCandidates(baseDir) {
  return RUNTIME_DIRECTORY_ALIASES.map((name) => path.join(baseDir, name));
}

function localHubDirectoryCandidates(opts = {}, env = process.env) {
  const homeDir = safeString(opts.home_dir) || realHomeDirectory(env);
  const groupContainersBase = path.join(homeDir, "Library", "Group Containers");
  const containerBase = path.join(homeDir, "Library", "Containers", DEFAULT_HUB_BUNDLE_ID, "Data");

  return uniqueStrings([
    opts.hub_dir,
    env.REL_FLOW_HUB_BASE_DIR,
    env.XHUB_HUB_DIR,
    ...DEFAULT_APP_GROUP_IDS.map((groupId) => path.join(groupContainersBase, groupId)),
    ...runtimeDirectoryCandidates(containerBase),
    ...runtimeDirectoryCandidates("/private/tmp"),
    ...runtimeDirectoryCandidates("/tmp"),
    ...runtimeDirectoryCandidates(homeDir),
  ]);
}

function hubTokensFileCandidates(opts = {}, env = process.env) {
  const explicit = uniqueStrings([
    opts.hub_tokens_file,
    env.XHUB_HUB_GRPC_TOKENS_FILE,
  ]);
  const discovered = localHubDirectoryCandidates(opts, env).map((dir) => path.join(dir, HUB_TOKENS_FILE_NAME));
  return uniqueStrings([...explicit, ...discovered]);
}

function remoteSecretsKeyFileCandidates(opts = {}, env = process.env) {
  const explicit = uniqueStrings([
    opts.remote_secrets_key_file,
    env.XHUB_REMOTE_SECRETS_KEY_FILE,
  ]);
  const discovered = localHubDirectoryCandidates(opts, env).map((dir) => path.join(dir, REMOTE_SECRETS_KEY_FILE_NAME));
  return uniqueStrings([...explicit, ...discovered]);
}

function firstExistingFile(candidates = []) {
  for (const filePath of candidates) {
    try {
      const stat = fs.statSync(filePath);
      if (stat.isFile()) return filePath;
    } catch {
      continue;
    }
  }
  return "";
}

function decryptRemoteSecretsCiphertext(ciphertext, keyBytes) {
  const raw = safeString(ciphertext);
  if (!raw) return "";

  const payload = raw.startsWith(REMOTE_SECRETS_VERSION_PREFIX)
    ? raw.slice(REMOTE_SECRETS_VERSION_PREFIX.length)
    : raw;
  const blob = Buffer.from(payload, "base64");
  if (!Buffer.isBuffer(blob) || blob.length < 29) return "";

  const key = Buffer.isBuffer(keyBytes) ? keyBytes : Buffer.from(keyBytes || "");
  if (key.length !== 32) return "";

  const iv = blob.subarray(0, 12);
  const tag = blob.subarray(blob.length - 16);
  const ciphertextBytes = blob.subarray(12, blob.length - 16);

  try {
    const decipher = crypto.createDecipheriv(AES_GCM_ALG, key, iv);
    decipher.setAuthTag(tag);
    const plain = Buffer.concat([decipher.update(ciphertextBytes), decipher.final()]);
    return safeString(plain.toString("utf8"));
  } catch {
    return "";
  }
}

function resolveLocalAdminToken(opts = {}, env = process.env) {
  const tokensFile = firstExistingFile(hubTokensFileCandidates(opts, env));
  if (!tokensFile) {
    return {
      admin_token: "",
      token_source: "missing_tokens_file",
      tokens_file: "",
      key_file: "",
    };
  }

  let parsed = {};
  try {
    parsed = JSON.parse(fs.readFileSync(tokensFile, "utf8"));
  } catch {
    return {
      admin_token: "",
      token_source: "invalid_tokens_file",
      tokens_file: tokensFile,
      key_file: "",
    };
  }

  const plainToken = safeString(parsed?.adminToken);
  if (plainToken) {
    return {
      admin_token: plainToken,
      token_source: "plaintext_tokens_file",
      tokens_file: tokensFile,
      key_file: "",
    };
  }

  const ciphertext = safeString(parsed?.adminTokenCiphertext);
  if (!ciphertext) {
    return {
      admin_token: "",
      token_source: "missing_admin_token",
      tokens_file: tokensFile,
      key_file: "",
    };
  }

  const keyFile = firstExistingFile(remoteSecretsKeyFileCandidates(opts, env));
  if (!keyFile) {
    return {
      admin_token: "",
      token_source: "missing_remote_secrets_key",
      tokens_file: tokensFile,
      key_file: "",
    };
  }

  let keyBytes = Buffer.alloc(0);
  try {
    keyBytes = fs.readFileSync(keyFile);
  } catch {
    return {
      admin_token: "",
      token_source: "unreadable_remote_secrets_key",
      tokens_file: tokensFile,
      key_file: keyFile,
    };
  }

  if (keyBytes.length !== 32) {
    return {
      admin_token: "",
      token_source: "invalid_remote_secrets_key",
      tokens_file: tokensFile,
      key_file: keyFile,
    };
  }

  const decryptedToken = decryptRemoteSecretsCiphertext(ciphertext, keyBytes);
  if (!decryptedToken) {
    return {
      admin_token: "",
      token_source: "decrypt_failed",
      tokens_file: tokensFile,
      key_file: keyFile,
    };
  }

  return {
    admin_token: decryptedToken,
    token_source: "encrypted_tokens_file",
    tokens_file: tokensFile,
    key_file: keyFile,
  };
}

module.exports = {
  AES_GCM_ALG,
  DEFAULT_APP_GROUP_IDS,
  DEFAULT_HUB_BUNDLE_ID,
  HUB_TOKENS_FILE_NAME,
  REMOTE_SECRETS_KEY_FILE_NAME,
  REMOTE_SECRETS_VERSION_PREFIX,
  decryptRemoteSecretsCiphertext,
  firstExistingFile,
  hubTokensFileCandidates,
  localHubDirectoryCandidates,
  realHomeDirectory,
  remoteSecretsKeyFileCandidates,
  resolveLocalAdminToken,
  safeString,
  uniqueStrings,
};
