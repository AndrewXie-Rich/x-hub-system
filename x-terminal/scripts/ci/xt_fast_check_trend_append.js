#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const args = {
    summary: "",
    history: "",
    limit: 20
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--summary") {
      args.summary = argv[i + 1] || "";
      i += 1;
      continue;
    }
    if (token === "--history") {
      args.history = argv[i + 1] || "";
      i += 1;
      continue;
    }
    if (token === "--limit") {
      const raw = argv[i + 1] || "";
      const value = Number(raw);
      if (!Number.isInteger(value) || value <= 0) {
        fail(`--limit must be a positive integer, got ${raw || "(empty)"}`);
      }
      args.limit = value;
      i += 1;
      continue;
    }
    fail(`unknown argument: ${token}`);
  }

  return args;
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function toStepStatusMap(steps) {
  if (!steps || typeof steps !== "object") {
    return {};
  }

  const result = {};
  for (const [key, value] of Object.entries(steps)) {
    if (value && typeof value === "object") {
      result[key] = {
        status: typeof value.status === "string" ? value.status : "",
        note: typeof value.note === "string" ? value.note : ""
      };
    }
  }
  return result;
}

function normalizeHistoryPayload(raw) {
  if (!raw || typeof raw !== "object") {
    return [];
  }
  if (!Array.isArray(raw.entries)) {
    return [];
  }
  return raw.entries.filter((entry) => entry && typeof entry === "object");
}

function numberOr(value, fallback) {
  const parsed = Number(value);
  if (Number.isFinite(parsed)) {
    return parsed;
  }
  return fallback;
}

function normalizeStatus(raw) {
  const value = String(raw || "").trim().toLowerCase();
  if (value === "pass" || value === "fail" || value === "warn" || value === "skipped" || value === "pending") {
    return value;
  }
  return "unknown";
}

function isWarningRun(entry) {
  if (!entry || typeof entry !== "object" || !entry.steps || typeof entry.steps !== "object") {
    return false;
  }
  return Object.values(entry.steps).some((step) => normalizeStatus(step && step.status) === "warn");
}

function toTimestampMs(value) {
  const ts = Date.parse(String(value || ""));
  return Number.isFinite(ts) ? ts : 0;
}

function entryTimestampMs(entry) {
  const generated = toTimestampMs(entry.generated_at);
  if (generated > 0) {
    return generated;
  }
  const started = toTimestampMs(entry.started_at);
  if (started > 0) {
    return started;
  }
  return toTimestampMs(entry.appended_at);
}

function dedupeEntries(entries) {
  const seen = new Set();
  const deduped = [];

  for (const entry of entries) {
    const key = [
      String(entry.generated_at || ""),
      String(entry.started_at || ""),
      String(entry.summary_path || ""),
      String(entry.exit_code ?? "")
    ].join("|");
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    deduped.push(entry);
  }

  return deduped;
}

function buildOverview(entries) {
  const passCount = entries.filter((entry) => normalizeStatus(entry.overall_status) === "pass").length;
  const failCount = entries.filter((entry) => normalizeStatus(entry.overall_status) === "fail").length;
  const warnStepRuns = entries.filter(isWarningRun).length;
  const timestamps = entries
    .map((entry) => entryTimestampMs(entry))
    .filter((value) => value > 0)
    .sort((lhs, rhs) => lhs - rhs);

  const earliestTs = timestamps.length > 0 ? timestamps[0] : 0;
  const latestTs = timestamps.length > 0 ? timestamps[timestamps.length - 1] : 0;

  return {
    pass_count: passCount,
    fail_count: failCount,
    warn_step_runs: warnStepRuns,
    pass_rate: entries.length > 0 ? Number((passCount / entries.length).toFixed(4)) : 0,
    earliest_entry_at: earliestTs > 0 ? new Date(earliestTs).toISOString() : "",
    latest_entry_at: latestTs > 0 ? new Date(latestTs).toISOString() : ""
  };
}

function buildStepStatusCounts(entries) {
  const result = {};
  for (const entry of entries) {
    const steps = entry && typeof entry === "object" ? entry.steps : null;
    if (!steps || typeof steps !== "object") {
      continue;
    }
    for (const [stepName, stepState] of Object.entries(steps)) {
      if (!result[stepName]) {
        result[stepName] = {
          pass: 0,
          fail: 0,
          warn: 0,
          skipped: 0,
          pending: 0,
          unknown: 0
        };
      }
      const status = normalizeStatus(stepState && stepState.status);
      result[stepName][status] += 1;
    }
  }
  return result;
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.summary) {
    fail("missing required argument --summary <path>");
  }
  if (!args.history) {
    fail("missing required argument --history <path>");
  }

  const summaryPath = path.resolve(args.summary);
  const historyPath = path.resolve(args.history);

  if (!fs.existsSync(summaryPath)) {
    fail(`summary file not found: ${summaryPath}`);
  }

  const summary = loadJson(summaryPath);
  if (!summary || typeof summary !== "object") {
    fail(`invalid summary payload: ${summaryPath}`);
  }
  if (summary.schema_version !== "xt_fast_checks.v1") {
    fail(
      `unsupported summary schema_version=${summary.schema_version || "(empty)"} (expected xt_fast_checks.v1)`
    );
  }

  const nowIso = new Date().toISOString();
  const entry = {
    appended_at: nowIso,
    summary_path: summaryPath,
    summary_schema_version: typeof summary.schema_version === "string" ? summary.schema_version : "",
    generated_at: typeof summary.generated_at === "string" ? summary.generated_at : "",
    started_at: typeof summary.started_at === "string" ? summary.started_at : "",
    elapsed_sec: numberOr(summary.elapsed_sec, 0),
    exit_code: numberOr(summary.exit_code, 1),
    overall_status: typeof summary.overall_status === "string" ? summary.overall_status : "fail",
    config: summary.config && typeof summary.config === "object" ? summary.config : {},
    steps: toStepStatusMap(summary.steps)
  };

  let entries = [];
  if (fs.existsSync(historyPath)) {
    entries = normalizeHistoryPayload(loadJson(historyPath));
  }

  entries = dedupeEntries([...entries, entry]);
  entries.sort((lhs, rhs) => entryTimestampMs(lhs) - entryTimestampMs(rhs));
  if (entries.length > args.limit) {
    entries = entries.slice(entries.length - args.limit);
  }

  const overview = buildOverview(entries);
  const stepStatusCounts = buildStepStatusCounts(entries);
  const latestEntry = entries.length > 0 ? entries[entries.length - 1] : null;

  const historyPayload = {
    schema_version: "xt_fast_check_history.v1",
    generated_at: nowIso,
    source_summary_path: summaryPath,
    limit: args.limit,
    total_entries: entries.length,
    overview,
    latest_entry: latestEntry
      ? {
          generated_at: String(latestEntry.generated_at || ""),
          overall_status: String(latestEntry.overall_status || ""),
          exit_code: numberOr(latestEntry.exit_code, 1)
        }
      : null,
    step_status_counts: stepStatusCounts,
    entries
  };

  fs.mkdirSync(path.dirname(historyPath), { recursive: true });
  fs.writeFileSync(historyPath, `${JSON.stringify(historyPayload, null, 2)}\n`, "utf8");
  process.stdout.write(
    `[ok] fast-check history updated: entries=${historyPayload.total_entries}, limit=${args.limit}, history=${historyPath}\n`
  );
}

try {
  main();
} catch (error) {
  process.stderr.write(`[error] ${(error && error.message) || String(error)}\n`);
  process.exit(1);
}
