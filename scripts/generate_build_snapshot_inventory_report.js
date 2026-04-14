#!/usr/bin/env node
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const defaultBuildDir = path.join(repoRoot, "build");
const defaultOutputPath = path.join(defaultBuildDir, "reports", "build_snapshot_inventory.v1.json");

function isoNow() {
  return new Date().toISOString();
}

function parseArgs(argv) {
  const args = {
    root: repoRoot,
    buildDir: defaultBuildDir,
    outJson: defaultOutputPath,
    hubRetention: process.env.XHUB_BUILD_SNAPSHOT_RETENTION_COUNT,
    xtRetention: process.env.XTERMINAL_BUILD_SNAPSHOT_RETENTION_COUNT,
    hubSnapshotDir: "",
    xtSnapshotDir: "",
    generatedAt: "",
  };

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    switch (arg) {
      case "--root":
        args.root = path.resolve(next);
        index += 1;
        break;
      case "--build-dir":
        args.buildDir = next;
        index += 1;
        break;
      case "--out-json":
        args.outJson = next;
        index += 1;
        break;
      case "--hub-retention":
        args.hubRetention = next;
        index += 1;
        break;
      case "--xt-retention":
        args.xtRetention = next;
        index += 1;
        break;
      case "--hub-snapshot-dir":
        args.hubSnapshotDir = next;
        index += 1;
        break;
      case "--xt-snapshot-dir":
        args.xtSnapshotDir = next;
        index += 1;
        break;
      case "--generated-at":
        args.generatedAt = next;
        index += 1;
        break;
      case "--help":
        return { help: true };
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  return args;
}

function printHelp() {
  const lines = [
    "Usage:",
    "  node scripts/generate_build_snapshot_inventory_report.js [options]",
    "",
    "Options:",
    "  --root <path>",
    "  --build-dir <path>",
    "  --out-json <path>",
    "  --hub-retention <count>",
    "  --xt-retention <count>",
    "  --hub-snapshot-dir <path>",
    "  --xt-snapshot-dir <path>",
    "  --generated-at <iso8601>",
  ];
  console.log(lines.join("\n"));
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function normalizeNonNegativeInteger(value, fallback) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.trunc(value));
  }
  const trimmed = String(value ?? "").trim();
  if (/^-?\d+$/.test(trimmed)) {
    return Math.max(0, Number.parseInt(trimmed, 10));
  }
  return fallback;
}

function normalizePathRef(rootDir, absolutePath) {
  const resolved = path.resolve(absolutePath);
  const relative = path.relative(rootDir, resolved);
  if (relative === "") {
    return ".";
  }
  if (!relative.startsWith("..") && !path.isAbsolute(relative)) {
    return relative.split(path.sep).join("/");
  }
  return resolved.split(path.sep).join("/");
}

function resolveInputPath(rootDir, candidate, fallback) {
  const value = String(candidate || "").trim();
  if (!value) return fallback;
  return path.isAbsolute(value) ? path.resolve(value) : path.resolve(rootDir, value);
}

function computePathSizeBytes(targetPath) {
  const stat = fs.lstatSync(targetPath);
  if (!stat.isDirectory()) {
    return stat.size;
  }

  let total = 0;
  const entries = fs.readdirSync(targetPath, { withFileTypes: true });
  for (const entry of entries) {
    total += computePathSizeBytes(path.join(targetPath, entry.name));
  }
  return total;
}

function listHistoricalSnapshotDirs(parentDir, baseName) {
  if (!fs.existsSync(parentDir)) return [];
  return fs.readdirSync(parentDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.startsWith(`${baseName}-`))
    .map((entry) => path.join(parentDir, entry.name))
    .sort((left, right) => right.localeCompare(left));
}

function buildSnapshotEntry(rootDir, absolutePath) {
  const stat = fs.lstatSync(absolutePath);
  return {
    snapshot_ref: normalizePathRef(rootDir, absolutePath),
    snapshot_name: path.basename(absolutePath),
    size_bytes: computePathSizeBytes(absolutePath),
    mtime_ms: Number.isFinite(stat.mtimeMs) ? Math.trunc(stat.mtimeMs) : 0,
  };
}

function sumBytes(entries) {
  return entries.reduce((total, entry) => total + normalizeNonNegativeInteger(entry?.size_bytes, 0), 0);
}

function buildSurfaceInventory(options) {
  const {
    rootDir,
    snapshotDir,
    retentionKeepCount,
    surfaceID,
    retentionEnvVar,
  } = options;

  const parentDir = path.dirname(snapshotDir);
  const baseName = path.basename(snapshotDir);
  const currentExists = fs.existsSync(snapshotDir) && fs.lstatSync(snapshotDir).isDirectory();
  const currentSnapshot = currentExists
    ? buildSnapshotEntry(rootDir, snapshotDir)
    : {
        snapshot_ref: normalizePathRef(rootDir, snapshotDir),
        snapshot_name: path.basename(snapshotDir),
        size_bytes: 0,
        mtime_ms: 0,
      };
  const historicalSnapshots = listHistoricalSnapshotDirs(parentDir, baseName).map((entryPath) =>
    buildSnapshotEntry(rootDir, entryPath)
  );
  const keepHistory = historicalSnapshots.slice(0, retentionKeepCount);
  const pruneHistory = historicalSnapshots.slice(retentionKeepCount);

  let status = "no_snapshot_present";
  if (pruneHistory.length > 0) {
    status = "stale_history_present";
  } else if (currentExists || historicalSnapshots.length > 0) {
    status = "within_retention_budget";
  }

  return {
    surface_id: surfaceID,
    status,
    snapshot_root_ref: normalizePathRef(rootDir, snapshotDir),
    snapshot_root_exists: currentExists,
    snapshot_root_parent_ref: normalizePathRef(rootDir, parentDir),
    historical_snapshot_glob: `${baseName}-*`,
    retention_keep_count: retentionKeepCount,
    retention_env_var: retentionEnvVar,
    current_snapshot: currentSnapshot,
    historical_snapshot_count: historicalSnapshots.length,
    historical_snapshot_total_bytes: sumBytes(historicalSnapshots),
    historical_snapshots: historicalSnapshots,
    prune_preview: {
      current_snapshot_root_preserved: true,
      would_keep_history_count: keepHistory.length,
      would_keep_history_refs: keepHistory.map((entry) => entry.snapshot_ref),
      would_prune_history_count: pruneHistory.length,
      would_prune_history_refs: pruneHistory.map((entry) => entry.snapshot_ref),
      would_prune_total_bytes: sumBytes(pruneHistory),
    },
  };
}

function buildInventorySummary(surfaces) {
  const surfaceList = Object.values(surfaces);
  const staleSurfaces = surfaceList.filter((surface) => surface.prune_preview.would_prune_history_count > 0);
  const reclaimLeader = surfaceList.reduce((best, surface) => {
    if (!best) return surface;
    if (surface.prune_preview.would_prune_total_bytes > best.prune_preview.would_prune_total_bytes) {
      return surface;
    }
    return best;
  }, null);

  let status = "no_snapshot_present";
  if (staleSurfaces.length > 0) {
    status = "stale_history_present";
  } else if (surfaceList.some((surface) => surface.snapshot_root_exists || surface.historical_snapshot_count > 0)) {
    status = "within_retention_budget";
  }

  let verdictReason = "No build snapshot roots or timestamped history directories are present.";
  if (status === "stale_history_present") {
    verdictReason = "Timestamped historical build snapshots exceed the current retention budget and can be reclaimed without touching the live snapshot roots.";
  } else if (status === "within_retention_budget") {
    verdictReason = "Build snapshot roots exist, but timestamped historical siblings are already within the configured retention budget.";
  }

  return {
    status,
    verdict_reason: verdictReason,
    stale_history_surface_ids: staleSurfaces.map((surface) => surface.surface_id),
    largest_reclaim_candidate_surface_id: reclaimLeader ? reclaimLeader.surface_id : "",
  };
}

function buildBuildSnapshotInventoryReport(options = {}) {
  const rootDir = path.resolve(options.repoRoot || repoRoot);
  const buildDir = path.resolve(options.buildDir || defaultBuildDir);
  const hubRetentionKeepCount = normalizeNonNegativeInteger(options.hubRetentionKeepCount, 2);
  const xterminalRetentionKeepCount = normalizeNonNegativeInteger(options.xterminalRetentionKeepCount, 2);
  const hubSnapshotDir = resolveInputPath(
    rootDir,
    options.hubSnapshotDir,
    path.join(buildDir, ".xhub-build-src")
  );
  const xterminalSnapshotDir = resolveInputPath(
    rootDir,
    options.xterminalSnapshotDir,
    path.join(buildDir, ".xterminal-build-src")
  );

  const hubSurface = buildSurfaceInventory({
    rootDir,
    snapshotDir: hubSnapshotDir,
    retentionKeepCount: hubRetentionKeepCount,
    surfaceID: "hub",
    retentionEnvVar: "XHUB_BUILD_SNAPSHOT_RETENTION_COUNT",
  });
  const xterminalSurface = buildSurfaceInventory({
    rootDir,
    snapshotDir: xterminalSnapshotDir,
    retentionKeepCount: xterminalRetentionKeepCount,
    surfaceID: "xterminal",
    retentionEnvVar: "XTERMINAL_BUILD_SNAPSHOT_RETENTION_COUNT",
  });

  const surfaces = {
    hub: hubSurface,
    xterminal: xterminalSurface,
  };
  const summary = buildInventorySummary(surfaces);

  return {
    schema_version: "xhub.build_snapshot_inventory.v1",
    generated_at: options.generatedAt || isoNow(),
    generated_at_ms: Number(options.generatedAtMs || Date.now()),
    build_dir_ref: normalizePathRef(rootDir, buildDir),
    build_dir_exists: fs.existsSync(buildDir) && fs.lstatSync(buildDir).isDirectory(),
    summary,
    retention_policy: {
      hub_keep_count: hubRetentionKeepCount,
      xterminal_keep_count: xterminalRetentionKeepCount,
    },
    surfaces,
    totals: {
      current_snapshot_total_bytes:
        hubSurface.current_snapshot.size_bytes + xterminalSurface.current_snapshot.size_bytes,
      historical_snapshot_total_bytes:
        hubSurface.historical_snapshot_total_bytes + xterminalSurface.historical_snapshot_total_bytes,
      historical_snapshot_count:
        hubSurface.historical_snapshot_count + xterminalSurface.historical_snapshot_count,
      projected_prune_total_bytes:
        hubSurface.prune_preview.would_prune_total_bytes
        + xterminalSurface.prune_preview.would_prune_total_bytes,
      projected_prune_history_count:
        hubSurface.prune_preview.would_prune_history_count
        + xterminalSurface.prune_preview.would_prune_history_count,
    },
  };
}

function main(argv = process.argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }

  const rootDir = path.resolve(args.root || repoRoot);
  const buildDir = resolveInputPath(rootDir, args.buildDir, defaultBuildDir);
  const outJson = resolveInputPath(rootDir, args.outJson, defaultOutputPath);
  const report = buildBuildSnapshotInventoryReport({
    repoRoot: rootDir,
    buildDir,
    hubRetentionKeepCount: args.hubRetention,
    xterminalRetentionKeepCount: args.xtRetention,
    hubSnapshotDir: args.hubSnapshotDir,
    xterminalSnapshotDir: args.xtSnapshotDir,
    generatedAt: args.generatedAt || isoNow(),
  });
  writeJSON(outJson, report);
  console.log(`[build-snapshot-inventory] report=${outJson}`);
}

if (require.main === module) {
  try {
    main(process.argv);
  } catch (error) {
    console.error(`[build-snapshot-inventory] ${error.message}`);
    process.exit(1);
  }
}

module.exports = {
  buildBuildSnapshotInventoryReport,
  computePathSizeBytes,
  parseArgs,
};
