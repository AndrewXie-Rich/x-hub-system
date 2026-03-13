#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_IGNORED_DIRS = new Set([
  ".git",
  ".build",
  "node_modules",
  "dist",
  "DerivedData",
]);

const TEXT_EXTENSIONS = new Set([
  ".c",
  ".cc",
  ".cpp",
  ".css",
  ".en",
  ".h",
  ".hpp",
  ".html",
  ".java",
  ".js",
  ".json",
  ".m",
  ".md",
  ".mm",
  ".pbxproj",
  ".plist",
  ".proto",
  ".py",
  ".rb",
  ".rst",
  ".sh",
  ".sql",
  ".svg",
  ".swift",
  ".ts",
  ".tsx",
  ".txt",
  ".xml",
  ".yaml",
  ".yml",
]);

const FORBIDDEN_PATTERNS = [
  {
    ruleId: "uppercase_repo_path",
    regex: /\bX-terminal\//g,
    message: "repository paths must use lowercase x-terminal/",
  },
  {
    ruleId: "uppercase_product_path",
    regex: /\bX-Terminal\/(?:XTerminal\/)?(?:Sources|Tests|scripts|tools|work-orders|README\.md|Package\.swift|\.axcoder)\b/g,
    message: "source tree paths must use x-terminal/; reserve X-Terminal for product names only",
  },
  {
    ruleId: "uppercase_cd_command",
    regex: /(^|\s)cd\s+X-(?:T|t)erminal\b/gm,
    message: "shell examples must use cd x-terminal",
  },
  {
    ruleId: "uppercase_script_command",
    regex: /(^|\s)(?:bash|sh)\s+X-(?:T|t)erminal\//gm,
    message: "script paths must use lowercase x-terminal/",
  },
];

function isTextCandidate(filePath) {
  const ext = path.extname(filePath);
  return TEXT_EXTENSIONS.has(ext);
}

function walkFiles(rootDir, ignoredDirs = DEFAULT_IGNORED_DIRS) {
  const out = [];
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (ignoredDirs.has(entry.name)) {
          continue;
        }
        stack.push(fullPath);
        continue;
      }
      if (entry.isFile() && isTextCandidate(fullPath)) {
        out.push(fullPath);
      }
    }
  }
  return out.sort();
}

function lineAndColumn(text, index) {
  let line = 1;
  let lastLineStart = 0;
  for (let i = 0; i < index; i += 1) {
    if (text.charCodeAt(i) === 10) {
      line += 1;
      lastLineStart = i + 1;
    }
  }
  return { line, column: index - lastLineStart + 1 };
}

function snippetFor(text, index) {
  const start = text.lastIndexOf("\n", index);
  const end = text.indexOf("\n", index);
  return text.slice(start === -1 ? 0 : start + 1, end === -1 ? text.length : end).trim();
}

function checkFile(filePath) {
  const text = fs.readFileSync(filePath, "utf8");
  const violations = [];
  for (const pattern of FORBIDDEN_PATTERNS) {
    pattern.regex.lastIndex = 0;
    let match;
    while ((match = pattern.regex.exec(text)) !== null) {
      const index = match.index + (match[1] ? match[1].length : 0);
      const position = lineAndColumn(text, index);
      violations.push({
        filePath,
        ruleId: pattern.ruleId,
        message: pattern.message,
        line: position.line,
        column: position.column,
        snippet: snippetFor(text, index),
      });
    }
  }
  return violations;
}

function checkXTerminalPathCasing(options = {}) {
  const rootDir = path.resolve(options.rootDir || path.join(__dirname, ".."));
  const files = walkFiles(rootDir, options.ignoredDirs || DEFAULT_IGNORED_DIRS);
  const violations = files.flatMap(checkFile);
  return {
    ok: violations.length === 0,
    rootDir,
    violations,
  };
}

function formatViolation(violation, rootDir) {
  const rel = path.relative(rootDir, violation.filePath) || path.basename(violation.filePath);
  return `${rel}:${violation.line}:${violation.column} ${violation.message}\n  ${violation.snippet}`;
}

function main() {
  const result = checkXTerminalPathCasing();
  if (result.ok) {
    console.log("x-terminal path casing check passed");
    return;
  }
  console.error("x-terminal path casing check failed");
  for (const violation of result.violations) {
    console.error(formatViolation(violation, result.rootDir));
  }
  process.exitCode = 1;
}

if (require.main === module) {
  main();
}

module.exports = {
  checkXTerminalPathCasing,
};
