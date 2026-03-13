#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  checkXTerminalPathCasing,
} = require("./check_xterminal_path_casing.js");

function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "xt-path-casing-"));
}

function write(filePath, text) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(text || ""), "utf8");
}

function run() {
  const repoRoot = path.resolve(__dirname, "..");
  const baseline = checkXTerminalPathCasing({ rootDir: repoRoot });
  assert.equal(
    baseline.ok,
    true,
    `repo baseline should pass, got violations: ${baseline.violations.map((item) => item.filePath).join(", ")}`
  );

  const tmpDir = makeTmpDir();
  write(
    path.join(tmpDir, "docs", "good.md"),
    [
      "Use X-Terminal as the product name.",
      "Run from source with `cd x-terminal`.",
      "The app bundle is `build/X-Terminal.app`.",
      "User data may live under `~/Library/Application Support/X-Terminal/skills`.",
    ].join("\n")
  );
  let result = checkXTerminalPathCasing({ rootDir: tmpDir });
  assert.equal(result.ok, true, "good fixture should pass");

  write(
    path.join(tmpDir, "docs", "bad.md"),
    [
      `\`${["X-Terminal", "XTerminal", "Sources/Project/XMemoryPipeline.swift"].join("/")}\``,
      ["cd", "X-terminal"].join(" "),
      ["bash", ["X-Terminal", "scripts/ci/xt_release_gate.sh"].join("/")].join(" "),
    ].join("\n")
  );
  result = checkXTerminalPathCasing({ rootDir: tmpDir });
  assert.equal(result.ok, false, "bad fixture should fail");
  assert.ok(
    result.violations.some((item) => item.ruleId === "uppercase_product_path"),
    "old product path should be reported"
  );
  assert.ok(
    result.violations.some((item) => item.ruleId === "uppercase_cd_command"),
    "uppercase cd command should be reported"
  );
  assert.ok(
    result.violations.some((item) => item.ruleId === "uppercase_script_command"),
    "uppercase script command should be reported"
  );

  fs.rmSync(tmpDir, { recursive: true, force: true });
  console.log("check_xterminal_path_casing.test.js ok");
}

run();
