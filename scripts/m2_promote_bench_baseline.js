#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const cp = require("node:child_process");

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

function fail(msg, details = {}) {
  console.error(JSON.stringify({ ok: false, error: msg, ...details }, null, 2));
  process.exit(2);
}

function sha256File(fp) {
  const h = crypto.createHash("sha256");
  h.update(fs.readFileSync(fp));
  return h.digest("hex");
}

function cpFile(src, dst) {
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
}

function runRegressionCheck({ repoRoot, baselinePath, fromJsonPath, thresholdsPath }) {
  const checker = path.join(repoRoot, "scripts/m2_check_bench_regression.js");
  const args = [checker, "--baseline", baselinePath, "--current", fromJsonPath];
  if (thresholdsPath) args.push("--thresholds", thresholdsPath);
  const out = cp.spawnSync("node", args, {
    cwd: repoRoot,
    encoding: "utf8",
  });
  return {
    ok: out.status === 0,
    status: Number(out.status || 0),
    stdout: String(out.stdout || ""),
    stderr: String(out.stderr || ""),
  };
}

function parseJsonSafe(raw) {
  const s = String(raw || "").trim();
  if (!s || !(s.startsWith("{") || s.startsWith("["))) return null;
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

function appendJsonl(fp, obj) {
  fs.mkdirSync(path.dirname(fp), { recursive: true });
  fs.appendFileSync(fp, `${JSON.stringify(obj)}\n`, "utf8");
}

function main() {
  const args = parseArgs(process.argv);
  const repoRoot = path.resolve(__dirname, "..");
  const approved = String(process.env.M2_BASELINE_UPDATE_APPROVED || "").trim() === "1";
  if (!approved) {
    fail("baseline promotion denied: set env M2_BASELINE_UPDATE_APPROVED=1");
  }

  const fromJsonArg = String(args["from-json"] || "").trim();
  const ticket = String(args.ticket || "").trim();
  const owner = String(args.owner || "").trim();
  const reason = String(args.reason || "").trim();
  if (!fromJsonArg) fail("missing --from-json");
  if (!ticket) fail("missing --ticket");
  if (!owner) fail("missing --owner");

  const fromJsonPath = path.resolve(fromJsonArg);
  if (!fs.existsSync(fromJsonPath)) fail("from-json not found", { from_json: fromJsonPath });

  const fromMdPath = args["from-md"] ? path.resolve(String(args["from-md"])) : fromJsonPath.replace(/\.json$/i, ".md");
  const baselinePath = path.resolve(
    args["baseline-json"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.json")
  );
  const baselineMdPath = path.resolve(
    args["baseline-md"] || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/report_baseline_week1.md")
  );
  const thresholdsPath = path.resolve(
    args.thresholds || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/regression_thresholds.json")
  );
  const logPath = path.resolve(
    args.log || path.join(repoRoot, "docs/memory-new/benchmarks/m2-w1/baseline_promotions.jsonl")
  );
  const allowRegression = String(args["allow-regression"] || "").trim() === "1";

  let checkResult = {
    ok: true,
    status: 0,
    stdout: "",
    stderr: "",
  };
  if (fs.existsSync(baselinePath)) {
    checkResult = runRegressionCheck({ repoRoot, baselinePath, fromJsonPath, thresholdsPath });
    if (!checkResult.ok && !allowRegression) {
      fail("regression check failed; use --allow-regression=1 to force promote", {
        baseline_json: baselinePath,
        from_json: fromJsonPath,
        checker_status: checkResult.status,
        checker_stderr: checkResult.stderr.slice(0, 4000),
      });
    }
  }

  const previousSha = fs.existsSync(baselinePath) ? sha256File(baselinePath) : "";
  cpFile(fromJsonPath, baselinePath);
  let promotedMd = false;
  if (fs.existsSync(fromMdPath)) {
    cpFile(fromMdPath, baselineMdPath);
    promotedMd = true;
  }
  const currentSha = sha256File(baselinePath);
  const promotedAtMs = Date.now();

  const record = {
    schema_version: "xhub.memory.baseline_promotion.v1",
    promoted_at_ms: promotedAtMs,
    ticket,
    owner,
    reason,
    allow_regression: allowRegression,
    baseline_json: path.relative(repoRoot, baselinePath),
    baseline_md: path.relative(repoRoot, baselineMdPath),
    source_json: path.relative(repoRoot, fromJsonPath),
    source_md: path.relative(repoRoot, fromMdPath),
    promoted_md: promotedMd,
    previous_sha256: previousSha,
    current_sha256: currentSha,
    checker: {
      ok: checkResult.ok,
      status: checkResult.status,
      thresholds: fs.existsSync(thresholdsPath) ? path.relative(repoRoot, thresholdsPath) : "",
      summary: (() => {
        const parsed = parseJsonSafe(checkResult.stdout) || parseJsonSafe(checkResult.stderr);
        if (!parsed || typeof parsed !== "object") return null;
        const checks = Array.isArray(parsed.checks)
          ? parsed.checks.map((c) => ({
            key: String(c?.key || ""),
            pass: !!c?.pass,
            detail: String(c?.detail || ""),
          }))
          : [];
        return {
          ok: !!parsed.ok,
          checks,
        };
      })(),
    },
  };
  appendJsonl(logPath, record);

  console.log(
    JSON.stringify(
      {
        ok: true,
        baseline_json: path.relative(repoRoot, baselinePath),
        baseline_md: path.relative(repoRoot, baselineMdPath),
        log: path.relative(repoRoot, logPath),
        promoted_md: promotedMd,
        ticket,
        owner,
        previous_sha256: previousSha,
        current_sha256: currentSha,
      },
      null,
      2
    )
  );
}

main();
