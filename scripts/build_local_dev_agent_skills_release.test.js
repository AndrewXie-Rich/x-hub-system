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

function writeFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, "utf8");
}

run("local dev agent skill release stages source and signs under a local publisher", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "local-dev-agent-skills-"));
  try {
    const sourceRoot = path.join(root, "canonical-source");
    const stagingRoot = path.join(root, "staged-source");
    const outputRoot = path.join(stagingRoot, "dist");
    const privateKeyPath = path.join(root, "keys", "xhub_local_dev.pem");
    const trustPath = path.join(stagingRoot, "publisher", "trusted_publishers.json");
    const envPath = path.join(root, "use_local_dev.env.sh");
    const metaPath = path.join(root, "release.json");
    const scriptPath = path.join(__dirname, "build_local_dev_agent_skills_release.js");

    writeFile(path.join(sourceRoot, "find-skills", "SKILL.md"), `---
name: find-skills
version: 1.0.0
description: Discover governed skills.
---

# Find Skills
`);
    writeFile(path.join(sourceRoot, "find-skills", "skill.json"), JSON.stringify({
      schema_version: "xhub.skill_manifest.v1",
      skill_id: "find-skills",
      name: "Find Skills",
      version: "1.0.0",
      description: "Discover governed skills.",
      entrypoint: {
        runtime: "text",
        command: "cat",
        args: ["SKILL.md"],
      },
      capabilities_required: ["skills.search"],
      publisher: {
        publisher_id: "xhub.official",
      },
      install_hint: "Install via baseline.",
    }, null, 2));

    const result = childProcess.spawnSync(process.execPath, [
      scriptPath,
      "--publisher-id", "xhub.local.dev.test",
      "--source-root", sourceRoot,
      "--staging-root", stagingRoot,
      "--output-root", outputRoot,
      "--private-key-out", privateKeyPath,
      "--trust-out", trustPath,
      "--env-out", envPath,
      "--meta-out", metaPath,
    ], {
      cwd: path.join(__dirname, ".."),
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr || result.stdout);

    const meta = JSON.parse(result.stdout);
    assert.equal(meta.publisher_id, "xhub.local.dev.test");
    assert.equal(meta.staging_source_root, stagingRoot);
    assert.equal(meta.dist_root, outputRoot);
    assert.equal(fs.existsSync(privateKeyPath), true);
    assert.equal(fs.existsSync(trustPath), true);
    assert.equal(fs.existsSync(envPath), true);
    assert.equal(fs.existsSync(metaPath), true);

    const stagedManifest = JSON.parse(fs.readFileSync(path.join(stagingRoot, "find-skills", "skill.json"), "utf8"));
    assert.equal(String(stagedManifest.publisher?.publisher_id || ""), "xhub.local.dev.test");

    const trust = JSON.parse(fs.readFileSync(trustPath, "utf8"));
    assert.equal(String(trust.publishers?.[0]?.publisher_id || ""), "xhub.local.dev.test");

    const index = JSON.parse(fs.readFileSync(path.join(outputRoot, "index.json"), "utf8"));
    assert.equal(String(index.publisher_id || ""), "xhub.local.dev.test");
    assert.equal(String(index.skills?.[0]?.publisher_id || ""), "xhub.local.dev.test");

    const manifestPath = path.join(outputRoot, String(index.skills[0].manifest_path || ""));
    const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    assert.equal(String(manifest.publisher?.publisher_id || ""), "xhub.local.dev.test");
    assert.equal(fs.readFileSync(envPath, "utf8").includes("XHUB_OFFICIAL_AGENT_SKILLS_DIR"), true);
    assert.equal(fs.readFileSync(envPath, "utf8").includes("XHUB_OFFICIAL_AGENT_SKILLS_DIST_DIR"), true);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
