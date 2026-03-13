#!/usr/bin/env node
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

run("local dev baseline smoke resolves all default Agent baseline skills", () => {
  const repoRoot = path.resolve(__dirname, "..");
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "local-dev-agent-baseline-smoke-"));
  try {
    const releaseScript = path.join(repoRoot, "scripts", "build_local_dev_agent_skills_release.js");
    const smokeScript = path.join(repoRoot, "scripts", "smoke_local_dev_agent_skills_baseline.js");
    const sourceRoot = path.join(repoRoot, "official-agent-skills");
    const stagingRoot = path.join(tempRoot, "staged-source");
    const outputRoot = path.join(stagingRoot, "dist");
    const privateKeyPath = path.join(tempRoot, "keys", "xhub_local_dev_test.pem");
    const trustPath = path.join(stagingRoot, "publisher", "trusted_publishers.json");
    const envPath = path.join(tempRoot, "use_local_dev.env.sh");
    const metaPath = path.join(tempRoot, "release.json");
    const runtimeBaseDir = path.join(tempRoot, "runtime");
    const smokeOutPath = path.join(tempRoot, "smoke.json");
    const optionalSmokeOutPath = path.join(tempRoot, "optional-smoke.json");

    const release = childProcess.spawnSync(process.execPath, [
      releaseScript,
      "--publisher-id", "xhub.local.dev.test",
      "--source-root", sourceRoot,
      "--staging-root", stagingRoot,
      "--output-root", outputRoot,
      "--private-key-out", privateKeyPath,
      "--trust-out", trustPath,
      "--env-out", envPath,
      "--meta-out", metaPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
    });
    assert.equal(release.status, 0, release.stderr || release.stdout);

    const distIndex = JSON.parse(fs.readFileSync(path.join(outputRoot, "index.json"), "utf8"));
    const distSkillIDs = Array.isArray(distIndex.skills)
      ? distIndex.skills.map((row) => row.skill_id)
      : [];
    assert.equal(distSkillIDs.includes("agent-backup"), true);
    assert.equal(distSkillIDs.includes("code-review"), true);
    assert.equal(distSkillIDs.includes("skill-creator"), true);
    assert.equal(distSkillIDs.includes("skill-vetter"), true);
    assert.equal(distSkillIDs.includes("tavily-websearch"), true);

    const smoke = childProcess.spawnSync(process.execPath, [
      smokeScript,
      "--scope", "project",
      "--project-id", "project-smoke",
      "--user-id", "user-smoke",
      "--runtime-base-dir", runtimeBaseDir,
      "--json-out", smokeOutPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_OFFICIAL_AGENT_SKILLS_DIR: stagingRoot,
        XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: outputRoot,
      },
    });
    assert.equal(smoke.status, 0, smoke.stderr || smoke.stdout);

    const payload = JSON.parse(fs.readFileSync(smokeOutPath, "utf8"));
    assert.equal(payload.ok, true);
    assert.equal(payload.publisher_id, "xhub.local.dev.test");
    assert.deepEqual(payload.missing, []);
    assert.equal(Array.isArray(payload.blocked), true);
    assert.equal(payload.blocked.length, 0);

    const resolvedIds = payload.resolved.map((row) => row.skill_id).sort();
    assert.deepEqual(
      resolvedIds,
      ["agent-browser", "find-skills", "self-improving-agent", "summarize"]
    );

    const deniedGate = payload.gates.find((row) => !row.allowed);
    assert.equal(deniedGate, undefined);

    const optionalSmoke = childProcess.spawnSync(process.execPath, [
      smokeScript,
      "--scope", "project",
      "--project-id", "project-optional-smoke",
      "--user-id", "user-optional-smoke",
      "--runtime-base-dir", path.join(tempRoot, "runtime-optional"),
      "--skills", "agent-backup,code-review,skill-creator,skill-vetter,tavily-websearch",
      "--json-out", optionalSmokeOutPath,
    ], {
      cwd: repoRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        XHUB_OFFICIAL_AGENT_SKILLS_DIR: stagingRoot,
        XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR: outputRoot,
      },
    });
    assert.equal(optionalSmoke.status, 0, optionalSmoke.stderr || optionalSmoke.stdout);

    const optionalPayload = JSON.parse(fs.readFileSync(optionalSmokeOutPath, "utf8"));
    assert.equal(optionalPayload.ok, true);
    assert.deepEqual(optionalPayload.missing, []);
    assert.equal(Array.isArray(optionalPayload.blocked), true);
    assert.equal(optionalPayload.blocked.length, 0);
    assert.deepEqual(
      optionalPayload.resolved.map((row) => row.skill_id).sort(),
      ["agent-backup", "code-review", "skill-creator", "skill-vetter", "tavily-websearch"]
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
