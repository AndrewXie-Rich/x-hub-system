#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

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

function readJson(fp) {
  return JSON.parse(fs.readFileSync(fp, "utf8"));
}

function mergeThresholds(base, override) {
  const out = { ...base };
  if (!override || typeof override !== "object") return out;
  for (const k of Object.keys(base)) {
    if (Object.prototype.hasOwnProperty.call(override, k)) {
      const n = num(override[k], base[k]);
      out[k] = n;
    }
  }
  return out;
}

function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function fail(msg, details = {}) {
  console.error(JSON.stringify({ ok: false, error: msg, ...details }, null, 2));
  process.exit(2);
}

function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(__dirname, "..");
  const baselinePath = path.resolve(
    args.baseline || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json")
  );
  const currentArg = String(args.current || "").trim();
  if (!currentArg) fail("missing --current report path");
  const currentPath = path.resolve(currentArg);
  const thresholdPath = args.thresholds ? path.resolve(String(args.thresholds)) : "";
  if (!fs.existsSync(currentPath)) fail("current report not found", { current: currentPath });
  if (!fs.existsSync(baselinePath)) fail("baseline report not found", { baseline: baselinePath });
  if (thresholdPath && !fs.existsSync(thresholdPath)) fail("thresholds file not found", { thresholds: thresholdPath });

  const baseline = readJson(baselinePath);
  const current = readJson(currentPath);

  const bGolden = baseline?.metrics?.golden || {};
  const cGolden = current?.metrics?.golden || {};
  const bAdv = baseline?.metrics?.adversarial || {};
  const cAdv = current?.metrics?.adversarial || {};

  const cliThresholds = {
    recall_drop_max: num(args["recall-drop-max"], 0.02),
    precision_drop_max: num(args["precision-drop-max"], 0.03),
    p95_latency_growth_max: num(args["p95-latency-growth-max"], 0.5), // +50%
    adversarial_match_drop_max: num(args["adversarial-match-drop-max"], 0.01),
  };
  const fileThresholds = thresholdPath ? readJson(thresholdPath) : {};
  const thresholds = mergeThresholds(cliThresholds, fileThresholds);

  const deltas = {
    recall: num(cGolden.recall_at_k_avg) - num(bGolden.recall_at_k_avg),
    precision: num(cGolden.precision_at_k_avg) - num(bGolden.precision_at_k_avg),
    p95_latency_ratio: (() => {
      const b = Math.max(0.0001, num(bGolden.latency_ms?.p95, 0.0001));
      return num(cGolden.latency_ms?.p95, 0) / b;
    })(),
    adversarial_match: num(cAdv.expected_match_rate) - num(bAdv.expected_match_rate),
  };

  const checks = [
    {
      key: "recall",
      pass: deltas.recall >= -thresholds.recall_drop_max,
      detail: `delta=${deltas.recall.toFixed(4)} (max drop=${thresholds.recall_drop_max})`,
    },
    {
      key: "precision",
      pass: deltas.precision >= -thresholds.precision_drop_max,
      detail: `delta=${deltas.precision.toFixed(4)} (max drop=${thresholds.precision_drop_max})`,
    },
    {
      key: "p95_latency",
      pass: deltas.p95_latency_ratio <= (1 + thresholds.p95_latency_growth_max),
      detail: `ratio=${deltas.p95_latency_ratio.toFixed(4)} (max ratio=${(1 + thresholds.p95_latency_growth_max).toFixed(4)})`,
    },
    {
      key: "adversarial_match",
      pass: deltas.adversarial_match >= -thresholds.adversarial_match_drop_max,
      detail: `delta=${deltas.adversarial_match.toFixed(4)} (max drop=${thresholds.adversarial_match_drop_max})`,
    },
  ];

  const ok = checks.every((c) => c.pass);
  const output = {
    ok,
    baseline: path.relative(repoRoot, baselinePath),
    current: path.relative(repoRoot, currentPath),
    thresholds_source: thresholdPath ? path.relative(repoRoot, thresholdPath) : "cli/defaults",
    thresholds,
    checks,
    metrics: {
      baseline: {
        golden: {
          precision_at_k_avg: num(bGolden.precision_at_k_avg),
          recall_at_k_avg: num(bGolden.recall_at_k_avg),
          p95_ms: num(bGolden.latency_ms?.p95),
        },
        adversarial: {
          expected_match_rate: num(bAdv.expected_match_rate),
        },
      },
      current: {
        golden: {
          precision_at_k_avg: num(cGolden.precision_at_k_avg),
          recall_at_k_avg: num(cGolden.recall_at_k_avg),
          p95_ms: num(cGolden.latency_ms?.p95),
        },
        adversarial: {
          expected_match_rate: num(cAdv.expected_match_rate),
        },
      },
    },
  };

  if (!ok) {
    console.error(JSON.stringify(output, null, 2));
    process.exit(2);
  }
  console.log(JSON.stringify(output, null, 2));
}

main();
