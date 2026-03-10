#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const DEFAULT_FREEZE_DOC = "docs/memory-new/xhub-memory-v3-m3-lineage-contract-freeze-v1.md";
const DEFAULT_CONTRACT_DOC = "docs/memory-new/xhub-memory-v3-m3-lineage-contract-tests-v1.md";
const DEFAULT_TEST_SOURCE = "x-hub/grpc-server/hub_grpc_server/src/memory_project_lineage.test.js";

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

function readText(filePath) {
  return String(fs.readFileSync(filePath, "utf8") || "");
}

function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, String(content || ""), "utf8");
}

function toUnique(list = []) {
  const seen = new Set();
  const out = [];
  for (const item of list) {
    const key = String(item || "").trim();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(key);
  }
  return out;
}

function findDuplicates(list = []) {
  const counts = new Map();
  for (const item of list) {
    const key = String(item || "").trim();
    if (!key) continue;
    counts.set(key, Number(counts.get(key) || 0) + 1);
  }
  return Array.from(counts.entries())
    .filter(([, count]) => count > 1)
    .map(([key]) => key);
}

function extractSection(markdown = "", headingMatcher) {
  const lines = String(markdown || "").split(/\r?\n/);
  let start = -1;
  for (let i = 0; i < lines.length; i += 1) {
    if (headingMatcher.test(lines[i])) {
      start = i + 1;
      break;
    }
  }
  if (start < 0) return "";

  let end = lines.length;
  for (let i = start; i < lines.length; i += 1) {
    if (/^##\s+/.test(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.slice(start, end).join("\n");
}

function extractFreezeDenyCodes(freezeMarkdown = "") {
  return toUnique(extractRawFreezeDenyCodes(freezeMarkdown));
}

function extractRawFreezeDenyCodes(freezeMarkdown = "") {
  const section =
    extractSection(freezeMarkdown, /^##\s+3\)/) ||
    extractSection(freezeMarkdown, /^##\s+.*deny_code/i);
  if (!section) return [];
  const matcher = /^\|\s*`([a-z0-9_]+)`\s*\|/gm;
  const out = [];
  let match = matcher.exec(section);
  while (match) {
    const code = String(match[1] || "").trim();
    if (code) out.push(code);
    match = matcher.exec(section);
  }
  return out;
}

function extractContractDenyGroups(contractMarkdown = "") {
  const text = String(contractMarkdown || "");
  const headingMatcher = /^###\s+(?:\d+\.\d+\s+)?`([a-z0-9_]+)`/gm;
  const entries = [];

  let match = headingMatcher.exec(text);
  while (match) {
    entries.push({
      deny_code: String(match[1] || "").trim(),
      start: headingMatcher.lastIndex,
    });
    match = headingMatcher.exec(text);
  }

  const groups = {};
  for (let i = 0; i < entries.length; i += 1) {
    const cur = entries[i];
    const next = entries[i + 1];
    const afterCur = text.slice(cur.start);
    const nextSectionMatch = /^##\s+/m.exec(afterCur);
    const sectionEnd = nextSectionMatch ? cur.start + nextSectionMatch.index : text.length;
    const blockEnd = Math.min(next ? next.start : text.length, sectionEnd);
    const body = text.slice(cur.start, blockEnd);
    const testIds = toUnique(Array.from(body.matchAll(/\bCT-[A-Z]{3}-[A-Z]\d{3}\b/g)).map((x) => x[0]));
    groups[cur.deny_code] = testIds;
  }

  return groups;
}

function extractRawContractDenyGroupCodes(contractMarkdown = "") {
  const text = String(contractMarkdown || "");
  return Array.from(text.matchAll(/^###\s+(?:\d+\.\d+\s+)?`([a-z0-9_]+)`/gm)).map((match) =>
    String(match[1] || "").trim()
  );
}

function extractCoveredDenyCodes(contractMarkdown = "") {
  const section =
    extractSection(contractMarkdown, /^##\s+7\)/) ||
    extractSection(contractMarkdown, /^##\s+.*当前实现映射/);
  if (!section) return [];
  const markerIndex = section.indexOf("已覆盖分组");
  const focus = markerIndex >= 0 ? section.slice(markerIndex) : section;
  const out = [];
  const matcher = /-\s+`([a-z0-9_]+)`/g;
  let match = matcher.exec(focus);
  while (match) {
    const code = String(match[1] || "").trim();
    if (code) out.push(code);
    match = matcher.exec(focus);
  }
  return toUnique(out);
}

function extractRawContractTestIds(contractMarkdown = "") {
  return Array.from(String(contractMarkdown || "").matchAll(/\bCT-[A-Z]{3}-[A-Z]\d{3}\b/g)).map((x) => x[0]);
}

function extractContractTestIds(contractMarkdown = "") {
  return toUnique(extractRawContractTestIds(contractMarkdown));
}

function extractSourceDenyCodeCoverage(sourceText = "") {
  const source = String(sourceText || "");
  const responseDenyCodes = [];
  const auditErrorCodes = [];

  const responseMatcher = /assert\.equal\([\s\S]{0,260}?deny_code[\s\S]{0,260}?['"`]([a-z0-9_]+)['"`]\s*\);/gm;
  let responseMatch = responseMatcher.exec(source);
  while (responseMatch) {
    responseDenyCodes.push(String(responseMatch[1] || "").trim());
    responseMatch = responseMatcher.exec(source);
  }

  const auditMatcher = /error_code\s*:\s*['"`]([a-z0-9_]+)['"`]/gm;
  let auditMatch = auditMatcher.exec(source);
  while (auditMatch) {
    auditErrorCodes.push(String(auditMatch[1] || "").trim());
    auditMatch = auditMatcher.exec(source);
  }

  return {
    response_deny_codes: toUnique(responseDenyCodes),
    audit_error_codes: toUnique(auditErrorCodes),
  };
}

function extractSourceCtIdCoverage(sourceText = "") {
  const lines = String(sourceText || "").split(/\r?\n/);
  const blocks = [];
  let active = null;

  for (let i = 0; i < lines.length; i += 1) {
    const line = String(lines[i] || "");
    const ids = Array.from(line.matchAll(/\bCT-[A-Z]{3}-[A-Z]\d{3}\b/g)).map((x) => x[0]);
    if (ids.length > 0) {
      if (active) blocks.push(active);
      active = {
        ct_id: String(ids[0] || "").trim(),
        lines: [line],
      };
      continue;
    }
    if (active) {
      active.lines.push(line);
    }
  }

  if (active) blocks.push(active);

  const out = {};
  for (const block of blocks) {
    const ctId = String(block?.ct_id || "").trim();
    if (!ctId) continue;
    const body = Array.isArray(block?.lines) ? block.lines.join("\n") : "";
    const perBlock = extractSourceDenyCodeCoverage(body);
    if (!Array.isArray(out[ctId])) out[ctId] = [];
    out[ctId].push(perBlock);
  }
  return out;
}

function extractRawSourceTestIds(sourceText = "") {
  return Array.from(String(sourceText || "").matchAll(/\bCT-[A-Z]{3}-[A-Z]\d{3}\b/g)).map((x) => x[0]);
}

function checkLineageContractCoverage({
  freezeMarkdown = "",
  contractMarkdown = "",
  testSource = "",
} = {}) {
  const freezeDenyCodeRaw = extractRawFreezeDenyCodes(freezeMarkdown);
  const freezeDenyCodes = extractFreezeDenyCodes(freezeMarkdown);
  const duplicateFreezeDenyCodes = findDuplicates(freezeDenyCodeRaw);
  const contractGroupCodeRaw = extractRawContractDenyGroupCodes(contractMarkdown);
  const contractDenyGroups = extractContractDenyGroups(contractMarkdown);
  const contractGroupCodes = Object.keys(contractDenyGroups);
  const duplicateContractDenyGroups = findDuplicates(contractGroupCodeRaw);
  const coveredFromSection = extractCoveredDenyCodes(contractMarkdown);
  const requiredDenyCodes = contractGroupCodes;
  const contractTestIdRaw = extractRawContractTestIds(contractMarkdown);
  const contractTestIds = extractContractTestIds(contractMarkdown);
  const duplicateContractTestIds = findDuplicates(contractTestIdRaw);
  const sourceTestIdRaw = extractRawSourceTestIds(testSource);
  const sourceTestIds = toUnique(sourceTestIdRaw);
  const duplicateSourceTestIds = findDuplicates(sourceTestIdRaw);
  const sourceCoverage = extractSourceDenyCodeCoverage(testSource);
  const sourceCtIdCoverage = extractSourceCtIdCoverage(testSource);
  const denyGroupTestIds = toUnique(
    Object.values(contractDenyGroups)
      .flat()
      .map((x) => String(x || "").trim())
      .filter(Boolean)
  );
  const denyGroupTestIdSet = new Set(denyGroupTestIds);
  const duplicateSourceDenyTestIds = duplicateSourceTestIds.filter((id) => denyGroupTestIdSet.has(id));

  const freezeSet = new Set(freezeDenyCodes);
  const groupSet = new Set(contractGroupCodes);
  const coveredSet = new Set(coveredFromSection);
  const sourceResponseSet = new Set(sourceCoverage.response_deny_codes);
  const sourceAuditSet = new Set(sourceCoverage.audit_error_codes);

  const errors = [];
  const warnings = [];

  if (freezeDenyCodes.length === 0) {
    errors.push("freeze dictionary deny_code extraction is empty");
  }
  if (contractGroupCodes.length === 0) {
    errors.push("contract deny_code group extraction is empty");
  }
  if (duplicateFreezeDenyCodes.length > 0) {
    errors.push(`duplicate freeze deny_code entry(s): ${duplicateFreezeDenyCodes.join(", ")}`);
  }
  if (duplicateContractDenyGroups.length > 0) {
    errors.push(`duplicate contract deny_code group heading(s): ${duplicateContractDenyGroups.join(", ")}`);
  }
  if (coveredFromSection.length === 0) {
    errors.push("contract section 7 covered deny_code extraction is empty");
  }
  if (requiredDenyCodes.length === 0) {
    errors.push("required deny_code extraction is empty");
  }
  if (contractTestIds.length === 0) {
    errors.push("contract test id extraction is empty");
  }
  if (sourceTestIds.length === 0) {
    errors.push("source test id extraction is empty");
  }
  if (duplicateContractTestIds.length > 0) {
    errors.push(`duplicate contract test id(s): ${duplicateContractTestIds.join(", ")}`);
  }
  if (duplicateSourceDenyTestIds.length > 0) {
    errors.push(`duplicate source deny test id block(s): ${duplicateSourceDenyTestIds.join(", ")}`);
  }

  for (const code of contractGroupCodes) {
    if (!freezeSet.has(code)) {
      errors.push(`contract deny_code group not present in freeze dictionary: ${code}`);
    }
  }
  for (const code of freezeDenyCodes) {
    if (!groupSet.has(code)) {
      errors.push(`freeze deny_code missing contract group section: ${code}`);
    }
  }
  for (const code of coveredFromSection) {
    if (!groupSet.has(code)) {
      errors.push(`section 7 covered deny_code missing contract group section: ${code}`);
    }
  }
  for (const code of contractGroupCodes) {
    if (!coveredSet.has(code)) {
      errors.push(`contract deny_code group missing from section 7 covered list: ${code}`);
    }
  }
  for (const code of sourceCoverage.response_deny_codes) {
    if (!groupSet.has(code)) {
      errors.push(`source response deny_code missing contract group section: ${code}`);
    }
  }
  for (const code of sourceCoverage.audit_error_codes) {
    if (!groupSet.has(code)) {
      errors.push(`source audit error_code missing contract group section: ${code}`);
    }
  }

  for (const code of requiredDenyCodes) {
    if (!freezeSet.has(code)) {
      errors.push(`required deny_code missing in freeze dictionary: ${code}`);
    }
    if (!groupSet.has(code)) {
      errors.push(`required deny_code missing contract group section: ${code}`);
      continue;
    }
    const ids = Array.isArray(contractDenyGroups[code]) ? contractDenyGroups[code] : [];
    if (ids.length === 0) {
      errors.push(`required deny_code has no contract test id mapping: ${code}`);
    }
    if (!sourceResponseSet.has(code)) {
      errors.push(`required deny_code not asserted in response deny_code path: ${code}`);
    }
    if (!sourceAuditSet.has(code)) {
      errors.push(`required deny_code not asserted in audit error_code path: ${code}`);
    }
  }

  for (const code of contractGroupCodes) {
    const ids = Array.isArray(contractDenyGroups[code]) ? contractDenyGroups[code] : [];
    for (const testId of ids) {
      if (!/-D\d{3}$/.test(testId)) {
        errors.push(`contract deny_code group contains non-deny test id: ${code} -> ${testId}`);
      }
      const blocks = Array.isArray(sourceCtIdCoverage[testId]) ? sourceCtIdCoverage[testId] : [];
      if (blocks.length === 0) {
        errors.push(`contract deny test id missing source block: ${testId}`);
        continue;
      }
      if (blocks.length > 1) {
        errors.push(`contract deny test id has duplicate source blocks: ${testId}`);
      }
      const block = blocks[0] || {};
      const responseCodes = Array.isArray(block?.response_deny_codes) ? block.response_deny_codes : [];
      const auditCodes = Array.isArray(block?.audit_error_codes) ? block.audit_error_codes : [];
      const hasExpectedResponse = Array.isArray(block?.response_deny_codes)
        ? block.response_deny_codes.includes(code)
        : false;
      const hasExpectedAudit = Array.isArray(block?.audit_error_codes)
        ? block.audit_error_codes.includes(code)
        : false;
      if (!hasExpectedResponse) {
        errors.push(`contract deny test id mapped to deny_code mismatch in response path: ${testId} -> ${code}`);
      }
      if (!hasExpectedAudit) {
        errors.push(`contract deny test id mapped to deny_code mismatch in audit path: ${testId} -> ${code}`);
      }
      if (responseCodes.length !== 1) {
        errors.push(
          `contract deny test id response deny_code assertions must be exactly 1: ${testId} -> ${responseCodes.join(", ")}`
        );
      }
      if (auditCodes.length !== 1) {
        errors.push(
          `contract deny test id audit error_code assertions must be exactly 1: ${testId} -> ${auditCodes.join(", ")}`
        );
      }
    }
  }

  for (const testId of contractTestIds) {
    const blocks = Array.isArray(sourceCtIdCoverage[testId]) ? sourceCtIdCoverage[testId] : [];
    if (blocks.length === 0) {
      errors.push(`contract test id missing source block: ${testId}`);
      continue;
    }
    if (blocks.length > 1 && denyGroupTestIdSet.has(testId)) {
      errors.push(`contract test id has duplicate source blocks: ${testId}`);
    }
  }
  for (const testId of sourceTestIds) {
    if (!contractTestIds.includes(testId)) {
      errors.push(`source test id missing from contract doc: ${testId}`);
    }
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    summary: {
      freeze_deny_code_total: freezeDenyCodes.length,
      contract_deny_group_total: contractGroupCodes.length,
      section7_covered_deny_code_total: coveredFromSection.length,
      required_deny_code_total: requiredDenyCodes.length,
      contract_test_id_total: contractTestIds.length,
      source_test_id_total: sourceTestIds.length,
      source_response_deny_code_total: sourceCoverage.response_deny_codes.length,
      source_audit_error_code_total: sourceCoverage.audit_error_codes.length,
      source_ct_id_block_total: Object.keys(sourceCtIdCoverage).length,
      duplicate_freeze_deny_code_total: duplicateFreezeDenyCodes.length,
      duplicate_contract_deny_group_total: duplicateContractDenyGroups.length,
      duplicate_contract_test_id_total: duplicateContractTestIds.length,
      duplicate_source_deny_test_id_total: duplicateSourceDenyTestIds.length,
      validation_passed: errors.length === 0,
    },
    freeze_deny_codes: freezeDenyCodes,
    contract_deny_groups: contractDenyGroups,
    section7_covered_deny_codes: coveredFromSection,
    required_deny_codes: requiredDenyCodes,
    contract_test_ids: contractTestIds,
    source_response_deny_codes: sourceCoverage.response_deny_codes,
    source_audit_error_codes: sourceCoverage.audit_error_codes,
    source_ct_id_coverage: sourceCtIdCoverage,
    duplicate_freeze_deny_codes: duplicateFreezeDenyCodes,
    duplicate_contract_deny_groups: duplicateContractDenyGroups,
    duplicate_contract_test_ids: duplicateContractTestIds,
    duplicate_source_deny_test_ids: duplicateSourceDenyTestIds,
  };
}

function runCli(argv = process.argv) {
  const args = parseArgs(argv);
  const freezeDocPath = path.resolve(args["freeze-doc"] || DEFAULT_FREEZE_DOC);
  const contractDocPath = path.resolve(args["contract-doc"] || DEFAULT_CONTRACT_DOC);
  const testSourcePath = path.resolve(args["test-source"] || DEFAULT_TEST_SOURCE);
  const outJsonPath = args["out-json"] ? path.resolve(args["out-json"]) : "";

  const report = checkLineageContractCoverage({
    freezeMarkdown: readText(freezeDocPath),
    contractMarkdown: readText(contractDocPath),
    testSource: readText(testSourcePath),
  });

  if (outJsonPath) {
    writeText(outJsonPath, `${JSON.stringify(report, null, 2)}\n`);
  }

  if (!report.ok) {
    throw new Error(`Gate-M3-0-CT coverage check failed: ${report.errors.join(" | ")}`);
  }

  for (const warning of report.warnings) {
    console.warn(`warn - ${warning}`);
  }

  console.log(
    `ok - Gate-M3-0-CT coverage passed (required_deny_codes=${report.required_deny_codes.length}, contract_test_ids=${report.contract_test_ids.length})`
  );
  return report;
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
  checkLineageContractCoverage,
  extractContractDenyGroups,
  extractContractTestIds,
  extractCoveredDenyCodes,
  extractFreezeDenyCodes,
  extractRawContractDenyGroupCodes,
  extractRawFreezeDenyCodes,
  extractRawSourceTestIds,
  extractSourceCtIdCoverage,
  extractSourceDenyCodeCoverage,
  runCli,
};
