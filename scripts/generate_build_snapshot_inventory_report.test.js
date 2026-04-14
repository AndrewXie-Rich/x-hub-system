#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const {
  buildBuildSnapshotInventoryReport,
} = require("./generate_build_snapshot_inventory_report.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function writeSizedFile(filePath, sizeBytes) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, "x".repeat(sizeBytes), "utf8");
}

run("build snapshot inventory computes stale-history prune preview per surface", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-build-snapshot-report."));
  const buildDir = path.join(root, "build");

  try {
    writeSizedFile(path.join(buildDir, ".xhub-build-src", "current.bin"), 5);
    writeSizedFile(path.join(buildDir, ".xhub-build-src-20260318-0739", "a.bin"), 10);
    writeSizedFile(path.join(buildDir, ".xhub-build-src-20260318-0730", "b.bin"), 20);
    writeSizedFile(path.join(buildDir, ".xhub-build-src-20260318-0702", "c.bin"), 30);
    writeSizedFile(path.join(buildDir, ".xterminal-build-src", "current.bin"), 7);
    writeSizedFile(path.join(buildDir, ".xterminal-build-src-20260318-0702", "d.bin"), 11);

    const report = buildBuildSnapshotInventoryReport({
      repoRoot: root,
      buildDir,
      hubRetentionKeepCount: 2,
      xterminalRetentionKeepCount: 0,
      generatedAt: "2026-03-24T00:00:00Z",
      generatedAtMs: 1742745600000,
    });

    assert.equal(report.summary.status, "stale_history_present");
    assert.deepEqual(report.summary.stale_history_surface_ids, ["hub", "xterminal"]);
    assert.equal(report.surfaces.hub.current_snapshot.size_bytes, 5);
    assert.equal(report.surfaces.hub.historical_snapshot_count, 3);
    assert.deepEqual(report.surfaces.hub.prune_preview.would_keep_history_refs, [
      "build/.xhub-build-src-20260318-0739",
      "build/.xhub-build-src-20260318-0730",
    ]);
    assert.deepEqual(report.surfaces.hub.prune_preview.would_prune_history_refs, [
      "build/.xhub-build-src-20260318-0702",
    ]);
    assert.equal(report.surfaces.hub.prune_preview.would_prune_total_bytes, 30);
    assert.equal(report.surfaces.xterminal.prune_preview.would_prune_history_count, 1);
    assert.deepEqual(report.surfaces.xterminal.prune_preview.would_prune_history_refs, [
      "build/.xterminal-build-src-20260318-0702",
    ]);
    assert.equal(report.surfaces.xterminal.prune_preview.would_prune_total_bytes, 11);
    assert.equal(report.totals.current_snapshot_total_bytes, 12);
    assert.equal(report.totals.historical_snapshot_total_bytes, 71);
    assert.equal(report.totals.projected_prune_total_bytes, 41);
    assert.equal(report.totals.projected_prune_history_count, 2);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("build snapshot inventory CLI writes machine-readable report", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-build-snapshot-cli."));
  const buildDir = path.join(root, "build");
  const outJson = path.join(root, "build/reports/custom_build_snapshot_inventory.v1.json");

  try {
    writeSizedFile(path.join(buildDir, ".xhub-build-src", "current.bin"), 9);
    writeSizedFile(path.join(buildDir, ".xhub-build-src-20260318-0751", "a.bin"), 13);

    const result = spawnSync(
      process.execPath,
      [
        path.join(__dirname, "generate_build_snapshot_inventory_report.js"),
        "--root", root,
        "--build-dir", buildDir,
        "--out-json", outJson,
        "--hub-retention", "1",
        "--xt-retention", "1",
      ],
      {
        cwd: root,
        encoding: "utf8",
        env: {
          ...process.env,
          TZ: "Asia/Shanghai",
        },
      }
    );

    assert.equal(result.status, 0, result.stderr || result.stdout);
    const report = JSON.parse(fs.readFileSync(outJson, "utf8"));
    assert.equal(report.schema_version, "xhub.build_snapshot_inventory.v1");
    assert.equal(report.retention_policy.hub_keep_count, 1);
    assert.equal(report.surfaces.hub.historical_snapshot_count, 1);
    assert.equal(report.surfaces.hub.prune_preview.would_prune_history_count, 0);
    assert.equal(report.surfaces.xterminal.status, "no_snapshot_present");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
