#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    throw err;
  }
}

function makeTmpDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "xhub-doctor-wrapper-"));
}

function writeExecutable(filePath, lines) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${lines.join("\n")}\n`, { mode: 0o755 });
}

function readLogLines(logPath) {
  if (!fs.existsSync(logPath)) {
    return [];
  }
  return fs
    .readFileSync(logPath, "utf8")
    .trim()
    .split("\n")
    .filter(Boolean);
}

function makeHelper(helperPath, logPath, exitCode = 0) {
  writeExecutable(helperPath, [
    "#!/bin/bash",
    "set -euo pipefail",
    `printf '%s|%s\\n' "$0" "$*" >> "${logPath}"`,
    `exit ${exitCode}`,
  ]);
}

const repoRoot = path.resolve(__dirname, "..");
const wrapperPath = path.join(
  repoRoot,
  "scripts",
  "run_xhub_doctor_from_source.command"
);

run("dispatches hub doctor through the Hub helper", () => {
  const tmpDir = makeTmpDir();
  const logPath = path.join(tmpDir, "calls.log");
  const hubHelper = path.join(tmpDir, "hub_helper.command");
  const xtHelper = path.join(tmpDir, "xt_helper.command");
  makeHelper(hubHelper, logPath);
  makeHelper(xtHelper, logPath);

  const result = spawnSync(
    "bash",
    [wrapperPath, "hub", "--out-json", "/tmp/xhub_doctor_output_hub.json"],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_HUB_SOURCE_HELPER: hubHelper,
        XHUB_XT_SOURCE_HELPER: xtHelper,
      },
    }
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(readLogLines(logPath), [
    `${hubHelper}|doctor --out-json /tmp/xhub_doctor_output_hub.json`,
  ]);
});

run("dispatches xt export through the XT helper", () => {
  const tmpDir = makeTmpDir();
  const logPath = path.join(tmpDir, "calls.log");
  const hubHelper = path.join(tmpDir, "hub_helper.command");
  const xtHelper = path.join(tmpDir, "xt_helper.command");
  makeHelper(hubHelper, logPath);
  makeHelper(xtHelper, logPath);

  const result = spawnSync(
    "bash",
    [
      wrapperPath,
      "--surface",
      "xt",
      "--workspace-root",
      "/tmp/xt_workspace",
      "--out-json",
      "/tmp/xhub_doctor_output_xt.json",
    ],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_HUB_SOURCE_HELPER: hubHelper,
        XHUB_XT_SOURCE_HELPER: xtHelper,
      },
    }
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.deepEqual(readLogLines(logPath), [
    `${xtHelper}|--xt-unified-doctor-export --project-root /tmp/xt_workspace --out-json /tmp/xhub_doctor_output_xt.json`,
  ]);
});

run("rejects xt-only flags on the hub surface", () => {
  const tmpDir = makeTmpDir();
  const logPath = path.join(tmpDir, "calls.log");
  const hubHelper = path.join(tmpDir, "hub_helper.command");
  const xtHelper = path.join(tmpDir, "xt_helper.command");
  makeHelper(hubHelper, logPath);
  makeHelper(xtHelper, logPath);

  const result = spawnSync(
    "bash",
    [wrapperPath, "hub", "--project-root", "/tmp/xt_workspace"],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_HUB_SOURCE_HELPER: hubHelper,
        XHUB_XT_SOURCE_HELPER: xtHelper,
      },
    }
  );

  assert.equal(result.status, 2);
  assert.match(
    result.stderr,
    /--workspace-root is only supported for the 'xt' or 'all' surfaces/
  );
  assert.deepEqual(readLogLines(logPath), []);
});

run("dispatches both surfaces in all mode with a shared output directory", () => {
  const tmpDir = makeTmpDir();
  const logPath = path.join(tmpDir, "calls.log");
  const outDir = path.join(tmpDir, "bundle");
  const hubHelper = path.join(tmpDir, "hub_helper.command");
  const xtHelper = path.join(tmpDir, "xt_helper.command");
  makeHelper(hubHelper, logPath);
  makeHelper(xtHelper, logPath);

  const result = spawnSync(
    "bash",
    [
      wrapperPath,
      "all",
      "--workspace-root",
      "/tmp/xt_workspace",
      "--out-dir",
      outDir,
    ],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_HUB_SOURCE_HELPER: hubHelper,
        XHUB_XT_SOURCE_HELPER: xtHelper,
      },
    }
  );

  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.match(result.stdout, /final_exit_code=0/);
  assert.deepEqual(readLogLines(logPath), [
    `${hubHelper}|doctor --out-json ${path.join(outDir, "xhub_doctor_output_hub.json")}`,
    `${xtHelper}|--xt-unified-doctor-export --project-root /tmp/xt_workspace --out-json ${path.join(outDir, "xhub_doctor_output_xt.json")}`,
  ]);
});

run("returns a blocked exit code when one surface reports blocked in all mode", () => {
  const tmpDir = makeTmpDir();
  const logPath = path.join(tmpDir, "calls.log");
  const hubHelper = path.join(tmpDir, "hub_helper.command");
  const xtHelper = path.join(tmpDir, "xt_helper.command");
  makeHelper(hubHelper, logPath, 1);
  makeHelper(xtHelper, logPath, 0);

  const result = spawnSync("bash", [wrapperPath, "all"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      XHUB_HUB_SOURCE_HELPER: hubHelper,
      XHUB_XT_SOURCE_HELPER: xtHelper,
    },
  });

  assert.equal(result.status, 1, result.stderr || result.stdout);
  assert.match(result.stdout, /surface=hub raw_exit_code=1 normalized_exit_code=1/);
  assert.match(result.stdout, /surface=xt raw_exit_code=0 normalized_exit_code=0/);
  assert.deepEqual(readLogLines(logPath), [
    `${hubHelper}|doctor`,
    `${xtHelper}|--xt-unified-doctor-export`,
  ]);
});

run("rejects out-json when all mode is selected", () => {
  const tmpDir = makeTmpDir();
  const logPath = path.join(tmpDir, "calls.log");
  const hubHelper = path.join(tmpDir, "hub_helper.command");
  const xtHelper = path.join(tmpDir, "xt_helper.command");
  makeHelper(hubHelper, logPath);
  makeHelper(xtHelper, logPath);

  const result = spawnSync(
    "bash",
    [wrapperPath, "all", "--out-json", "/tmp/xhub_doctor_output.json"],
    {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_HUB_SOURCE_HELPER: hubHelper,
        XHUB_XT_SOURCE_HELPER: xtHelper,
      },
    }
  );

  assert.equal(result.status, 2);
  assert.match(
    result.stderr,
    /--out-json is only supported for a single surface; use --out-dir with 'all'/
  );
  assert.deepEqual(readLogLines(logPath), []);
});
