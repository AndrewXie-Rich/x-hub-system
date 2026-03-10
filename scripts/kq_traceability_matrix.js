#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_SCHEMA_VERSION = "xhub.memory.traceability_matrix.v1";

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

function boolArg(value, fallback = false) {
  if (value == null || value === "") return !!fallback;
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  return !!fallback;
}

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function extractBacktickTokens(text) {
  if (!text) return [];
  const tokens = [];
  const matcher = /`([^`]+)`/g;
  let match = matcher.exec(text);
  while (match) {
    const token = String(match[1] || "").trim();
    if (token) tokens.push(token);
    match = matcher.exec(text);
  }
  return tokens;
}

function parseRequirements(requirementsMarkdown = "") {
  const lines = String(requirementsMarkdown || "").split(/\r?\n/);
  const requirements = [];
  const duplicateIds = [];
  const seen = new Set();

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const match = line.match(/^###\s+(RQ-\d{3})\s+(.+)$/);
    if (!match) continue;
    const id = String(match[1] || "").trim();
    const title = String(match[2] || "").trim();
    if (seen.has(id)) {
      duplicateIds.push(id);
      continue;
    }
    seen.add(id);
    requirements.push({
      requirement_id: id,
      title,
      line: i + 1,
    });
  }

  return {
    requirements,
    duplicate_ids: Array.from(new Set(duplicateIds)),
  };
}

function parseTasks(tasksMarkdown = "") {
  const lines = String(tasksMarkdown || "").split(/\r?\n/);
  const tasks = [];
  const duplicateIds = [];
  const seen = new Set();
  let currentTask = null;

  const flushCurrent = () => {
    if (!currentTask) return;
    currentTask.requirement_ids = Array.from(new Set(currentTask.requirement_ids));
    currentTask.property_ids = Array.from(new Set(currentTask.property_ids));
    tasks.push(currentTask);
    currentTask = null;
  };

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const taskMatch = line.match(/^-\s*\[[ xX]\]\s+`([^`]+)`\s*(.*)$/);
    if (taskMatch) {
      flushCurrent();
      const taskId = String(taskMatch[1] || "").trim();
      const title = String(taskMatch[2] || "").trim();
      if (seen.has(taskId)) {
        duplicateIds.push(taskId);
      }
      seen.add(taskId);
      currentTask = {
        task_id: taskId,
        title,
        line: i + 1,
        requirement_ids: [],
        property_ids: [],
      };
      continue;
    }

    if (!currentTask) continue;

    const requirementLine = line.match(/^\s*-\s*requirement_ids\s*:\s*(.+)$/i);
    if (requirementLine) {
      const raw = String(requirementLine[1] || "");
      const fromTicks = extractBacktickTokens(raw);
      const fallback = Array.from(raw.matchAll(/RQ-\d{3}/g)).map((m) => m[0]);
      const parsed = fromTicks.length > 0 ? fromTicks : fallback;
      currentTask.requirement_ids.push(...parsed);
      continue;
    }

    const propertyLine = line.match(/^\s*-\s*property_ids\s*:\s*(.+)$/i);
    if (propertyLine) {
      const raw = String(propertyLine[1] || "");
      const fromTicks = extractBacktickTokens(raw);
      const fallback = Array.from(raw.matchAll(/CP-[A-Za-z]+-\d{3}/g)).map((m) => m[0]);
      const parsed = fromTicks.length > 0 ? fromTicks : fallback;
      currentTask.property_ids.push(...parsed);
      continue;
    }
  }

  flushCurrent();

  return {
    tasks,
    duplicate_ids: Array.from(new Set(duplicateIds)),
  };
}

function buildTraceabilityMatrix({
  specId,
  requirementsMarkdown,
  tasksMarkdown,
  schemaVersion = DEFAULT_SCHEMA_VERSION,
  sourceRequirementsPath = "",
  sourceTasksPath = "",
}) {
  const req = parseRequirements(requirementsMarkdown);
  const task = parseTasks(tasksMarkdown);

  const requirementById = new Map();
  for (const item of req.requirements) {
    requirementById.set(item.requirement_id, item);
  }

  const requirementToTasks = new Map();
  for (const item of req.requirements) {
    requirementToTasks.set(item.requirement_id, []);
  }

  const unknownRequirementReferences = [];
  const orphanTasks = [];

  for (const taskItem of task.tasks) {
    if (!Array.isArray(taskItem.requirement_ids) || taskItem.requirement_ids.length === 0) {
      orphanTasks.push(taskItem.task_id);
      continue;
    }

    let hasValidReference = false;
    for (const reqId of taskItem.requirement_ids) {
      if (!requirementById.has(reqId)) {
        unknownRequirementReferences.push({
          task_id: taskItem.task_id,
          requirement_id: reqId,
        });
        continue;
      }
      hasValidReference = true;
      const mapped = requirementToTasks.get(reqId);
      mapped.push(taskItem.task_id);
    }

    if (!hasValidReference) {
      orphanTasks.push(taskItem.task_id);
    }
  }

  const requirements = req.requirements.map((item) => {
    const mappedTasks = Array.from(new Set(requirementToTasks.get(item.requirement_id) || [])).sort();
    return {
      ...item,
      mapped_task_ids: mappedTasks,
    };
  });

  const orphanRequirements = requirements
    .filter((item) => item.mapped_task_ids.length === 0)
    .map((item) => item.requirement_id)
    .sort();

  const duplicateRequirementIds = Array.from(new Set(req.duplicate_ids)).sort();
  const duplicateTaskIds = Array.from(new Set(task.duplicate_ids)).sort();
  const normalizedOrphanTasks = Array.from(new Set(orphanTasks)).sort();
  const normalizedUnknownRefs = unknownRequirementReferences
    .map((entry) => ({
      task_id: entry.task_id,
      requirement_id: entry.requirement_id,
    }))
    .sort((a, b) => {
      if (a.task_id !== b.task_id) return a.task_id.localeCompare(b.task_id);
      return a.requirement_id.localeCompare(b.requirement_id);
    });

  const errors = [];
  if (duplicateRequirementIds.length > 0) {
    errors.push(`duplicate requirement ids: ${duplicateRequirementIds.join(", ")}`);
  }
  if (duplicateTaskIds.length > 0) {
    errors.push(`duplicate task ids: ${duplicateTaskIds.join(", ")}`);
  }
  if (orphanRequirements.length > 0) {
    errors.push(`orphan requirements: ${orphanRequirements.join(", ")}`);
  }
  if (normalizedOrphanTasks.length > 0) {
    errors.push(`orphan tasks: ${normalizedOrphanTasks.join(", ")}`);
  }
  if (normalizedUnknownRefs.length > 0) {
    const pretty = normalizedUnknownRefs.map((x) => `${x.task_id}->${x.requirement_id}`).join(", ");
    errors.push(`unknown requirement references: ${pretty}`);
  }

  const matrix = {
    schema_version: schemaVersion,
    spec_id: String(specId || "").trim(),
    sources: {
      requirements: String(sourceRequirementsPath || ""),
      tasks: String(sourceTasksPath || ""),
    },
    summary: {
      requirement_total: requirements.length,
      task_total: task.tasks.length,
      mapped_requirement_total: requirements.filter((item) => item.mapped_task_ids.length > 0).length,
      orphan_requirements_count: orphanRequirements.length,
      orphan_tasks_count: normalizedOrphanTasks.length,
      unknown_requirement_references_count: normalizedUnknownRefs.length,
      duplicate_requirement_ids_count: duplicateRequirementIds.length,
      duplicate_task_ids_count: duplicateTaskIds.length,
      validation_passed: errors.length === 0,
    },
    validation_errors: errors,
    duplicates: {
      requirement_ids: duplicateRequirementIds,
      task_ids: duplicateTaskIds,
    },
    orphans: {
      requirement_ids: orphanRequirements,
      task_ids: normalizedOrphanTasks,
    },
    unknown_requirement_references: normalizedUnknownRefs,
    requirements,
    tasks: task.tasks,
  };

  return matrix;
}

function ensureMatrixUpToDate({ outputPath, nextContent }) {
  if (!fs.existsSync(outputPath)) {
    throw new Error(`matrix file not found: ${outputPath}`);
  }
  const existing = readText(outputPath);
  if (existing !== nextContent) {
    throw new Error(`matrix file is stale: ${outputPath}. Run without --check to regenerate.`);
  }
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const specDir = path.resolve(args["spec-dir"] || path.join(process.cwd(), ".kiro/specs/xhub-memory-quality-v1"));
  const requirementsPath = path.resolve(args.requirements || path.join(specDir, "requirements.md"));
  const tasksPath = path.resolve(args.tasks || path.join(specDir, "tasks.md"));
  const outputPath = path.resolve(args["out-json"] || path.join(specDir, "traceability_matrix_v1.json"));
  const checkMode = boolArg(args.check, false);

  const requirementsMarkdown = readText(requirementsPath);
  const tasksMarkdown = readText(tasksPath);

  const matrix = buildTraceabilityMatrix({
    specId: path.basename(specDir),
    requirementsMarkdown,
    tasksMarkdown,
    sourceRequirementsPath: path.relative(process.cwd(), requirementsPath),
    sourceTasksPath: path.relative(process.cwd(), tasksPath),
  });

  const serialized = `${JSON.stringify(matrix, null, 2)}\n`;

  if (checkMode) {
    ensureMatrixUpToDate({ outputPath, nextContent: serialized });
    if (!matrix.summary.validation_passed) {
      throw new Error(`traceability validation failed: ${matrix.validation_errors.join(" | ")}`);
    }
    console.log(`ok - traceability matrix is valid and up to date (${path.relative(process.cwd(), outputPath)})`);
    return matrix;
  }

  writeText(outputPath, serialized);
  if (!matrix.summary.validation_passed) {
    throw new Error(`traceability validation failed: ${matrix.validation_errors.join(" | ")}`);
  }

  console.log(`ok - wrote traceability matrix: ${path.relative(process.cwd(), outputPath)}`);
  return matrix;
}

if (require.main === module) {
  try {
    runCli(process.argv);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = {
  buildTraceabilityMatrix,
  parseRequirements,
  parseTasks,
  runCli,
};
