#!/usr/bin/env node
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const cp = require("node:child_process");

const {
  reportsDir,
  repoRoot,
  writeJSON,
} = require("./lpr_w3_03_require_real_bundle_lib.js");

const outputPath = path.join(reportsDir, "lpr_w3_03_c_model_native_loadability_probe.v1.json");
const artifactRoot = path.join(reportsDir, "lpr_w3_03_require_real", "model_native_loadability_probe");

const lmStudioCPython = "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/cpython3.11-mac-arm64@10/bin/python3";
const lmStudioTransformersSitePackages = "/Users/andrew.xie/Documents/AX/Opensource/LM Studio.app/Contents/Resources/app/.webpack/bin/extensions/backends/vendor/_amphibian/app-mlx-generate-mac14-arm64@19/lib/python3.11/site-packages";
const xcodePython = "/Applications/Xcode.app/Contents/Developer/usr/bin/python3";
const homeDir = os.homedir();
const defaultScanRoots = [
  path.join(homeDir, ".lmstudio", "models"),
  path.join(homeDir, ".cache", "huggingface", "hub"),
  path.join(homeDir, "Library", "Caches", "huggingface", "hub"),
  path.join(homeDir, "models"),
  path.join(homeDir, "Documents", "AX", "Local Model"),
  path.join(homeDir, "RELFlowHub", "models"),
  path.join(homeDir, "Library", "Containers", "com.rel.flowhub", "Data", "RELFlowHub", "models"),
  path.join(homeDir, "Library", "Application Support", "LM Studio", "models"),
];
const defaultCatalogPaths = [
  path.join(homeDir, "RELFlowHub", "models_catalog.json"),
  path.join(homeDir, "RELFlowHub", "models_state.json"),
  path.join(homeDir, "Library", "Containers", "com.rel.flowhub", "Data", "RELFlowHub", "models_catalog.json"),
  path.join(homeDir, "Library", "Containers", "com.rel.flowhub", "Data", "RELFlowHub", "models_state.json"),
];
const discoverySkipDirNames = new Set([
  ".git",
  ".svn",
  ".hg",
  "node_modules",
  "__pycache__",
  ".build",
  "build",
  "dist",
  "DerivedData",
  ".axcoder",
  ".sandbox_home",
  ".sandbox_tmp",
]);

function isoNow() {
  return new Date().toISOString();
}

function pathExists(targetPath) {
  try {
    return fs.existsSync(targetPath);
  } catch {
    return false;
  }
}

function relPath(targetPath) {
  return path.relative(repoRoot, targetPath).split(path.sep).join("/");
}

function safeMkdir(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

function safeReadJSON(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function safeReadDir(dirPath) {
  try {
    return fs.readdirSync(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }
}

function pathIsDirectory(targetPath) {
  try {
    return fs.statSync(targetPath).isDirectory();
  } catch {
    return false;
  }
}

function realPathOrSelf(targetPath) {
  try {
    return fs.realpathSync.native(targetPath);
  } catch {
    try {
      return fs.realpathSync(targetPath);
    } catch {
      return path.resolve(targetPath);
    }
  }
}

function shouldSkipDiscoveryDir(dirName) {
  const name = normalizeString(dirName);
  if (!name) return true;
  const lower = name.toLowerCase();
  if (discoverySkipDirNames.has(name) || discoverySkipDirNames.has(lower)) return true;
  if (name.startsWith(".")) return true;
  if (lower.startsWith(".scratch")) return true;
  if (lower.startsWith(".ax")) return true;
  if (lower.endsWith(".app")) return true;
  if (lower.endsWith(".logarchive")) return true;
  if (lower === "archive" || lower === "tmp" || lower === "temp") return true;
  return false;
}

function trimOutput(text, maxChars = 8000) {
  const normalized = String(text || "").trim();
  if (!normalized) return "";
  if (normalized.length <= maxChars) return normalized;
  return `${normalized.slice(0, maxChars)}\n...[truncated]`;
}

function shellJoin(parts) {
  return parts
    .map((part) => {
      const text = String(part);
      if (/^[A-Za-z0-9_./:@=,+-]+$/.test(text)) return text;
      return `'${text.replace(/'/g, `'\\''`)}'`;
    })
    .join(" ");
}

function runCommand(command, args, options = {}) {
  const startedAt = Date.now();
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd || repoRoot,
    env: options.env || process.env,
    input: options.input || undefined,
    encoding: "utf8",
    timeout: Number.isFinite(options.timeoutMs) ? options.timeoutMs : 120000,
    maxBuffer: 32 * 1024 * 1024,
  });
  const finishedAt = Date.now();
  return {
    command: shellJoin([command, ...args]),
    cwd: relPath(options.cwd || repoRoot),
    started_at_utc: new Date(startedAt).toISOString(),
    finished_at_utc: new Date(finishedAt).toISOString(),
    duration_ms: Math.max(0, finishedAt - startedAt),
    exit_code: typeof result.status === "number" ? result.status : -1,
    signal: result.signal || "",
    ok: result.status === 0,
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    timed_out: !!(result.error && result.error.code === "ETIMEDOUT"),
    error: result.error ? String(result.error.message || result.error) : "",
  };
}

function persistArtifacts(dirPath, prefix, runResult) {
  safeMkdir(dirPath);
  fs.writeFileSync(path.join(dirPath, `${prefix}.stdout.log`), String(runResult.stdout || ""), "utf8");
  fs.writeFileSync(path.join(dirPath, `${prefix}.stderr.log`), String(runResult.stderr || ""), "utf8");
  writeJSON(path.join(dirPath, `${prefix}.meta.json`), {
    command: runResult.command,
    cwd: runResult.cwd,
    started_at_utc: runResult.started_at_utc,
    finished_at_utc: runResult.finished_at_utc,
    duration_ms: runResult.duration_ms,
    exit_code: runResult.exit_code,
    signal: runResult.signal,
    ok: runResult.ok,
    timed_out: runResult.timed_out,
    error: runResult.error,
  });
}

function tryParseJSON(text) {
  const raw = String(text || "").trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function sha8(text) {
  return crypto.createHash("sha256").update(String(text || "")).digest("hex").slice(0, 8);
}

function normalizeString(value) {
  return String(value || "").trim();
}

function dedupeStrings(values = []) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = normalizeString(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function normalizeTaskKindHint(value) {
  const text = normalizeString(value).toLowerCase();
  if (!text) return "unknown";
  if (/(^|[_:\-\s])(embed|embedding|text_embedding|rerank|bge|gte|e5)([_:\-\s]|$)/.test(text)) {
    return "embedding";
  }
  if (/(speech_to_text|automatic_speech_recognition|asr|transcrib|whisper|audio)/.test(text)) {
    return "speech_to_text";
  }
  if (/(vision_understand|vision|vl|ocr|image)/.test(text)) {
    return "vision";
  }
  if (/(text_generate|generate|chat|instruct|completion)/.test(text)) {
    return "text_generate";
  }
  return "unknown";
}

function directoryLooksLikeModel(dirPath) {
  if (!pathExists(dirPath) || !pathIsDirectory(dirPath)) return false;
  const names = new Set(safeReadDir(dirPath).map((entry) => entry.name));
  if (!names.has("config.json")) return false;
  for (const name of names) {
    if (name.endsWith(".safetensors") || name.endsWith(".bin") || name === "tokenizer.json") {
      return true;
    }
  }
  return false;
}

function discoverModelDirs(root, maxDepth = 5) {
  const discovered = [];
  const visited = new Set();

  function walk(currentPath, depth) {
    if (depth > maxDepth || !pathExists(currentPath) || !pathIsDirectory(currentPath)) return;
    const visitKey = realPathOrSelf(currentPath);
    if (visited.has(visitKey)) return;
    visited.add(visitKey);
    if (directoryLooksLikeModel(currentPath)) {
      discovered.push(currentPath);
      return;
    }
    for (const entry of safeReadDir(currentPath)) {
      const childPath = path.join(currentPath, entry.name);
      const isDirectoryEntry =
        entry.isDirectory() || (entry.isSymbolicLink() && pathIsDirectory(childPath));
      if (!isDirectoryEntry) continue;
      if (shouldSkipDiscoveryDir(entry.name)) continue;
      walk(childPath, depth + 1);
    }
  }

  walk(root, 0);
  return discovered;
}

function normalizeCatalogModelDir(modelPath) {
  const raw = normalizeString(modelPath);
  if (!raw) return "";
  const resolved = path.resolve(raw);
  try {
    const stat = fs.statSync(resolved);
    if (stat.isDirectory()) return resolved;
    if (stat.isFile()) return path.dirname(resolved);
  } catch {
    return "";
  }
  return "";
}

function readCatalogModelRefs(catalogPath) {
  const resolved = path.resolve(catalogPath);
  const payload = safeReadJSON(resolved);
  const models = payload && Array.isArray(payload.models) ? payload.models : [];
  return models
    .map((entry) => {
      const row = entry && typeof entry === "object" ? entry : {};
      const modelPath = normalizeString(row.modelPath);
      const modelDir = normalizeCatalogModelDir(modelPath);
      return {
        catalog_path: resolved,
        model_id: normalizeString(row.id),
        model_name: normalizeString(row.name),
        backend: normalizeString(row.backend),
        task_kinds: Array.isArray(row.taskKinds)
          ? row.taskKinds.map((item) => normalizeString(item)).filter(Boolean)
          : [],
        note: normalizeString(row.note),
        model_path: modelPath,
        model_dir: modelDir,
      };
    })
    .filter((row) => !!row.model_dir);
}

function collectEnvDrivenScanRoots(env = process.env) {
  const candidates = [];
  const push = (value, suffix = "") => {
    const base = normalizeString(value);
    if (!base) return;
    candidates.push(path.resolve(suffix ? path.join(base, suffix) : base));
  };

  push(env.HF_HOME, "hub");
  push(env.HF_HUB_CACHE);
  push(env.HUGGINGFACE_HUB_CACHE);
  push(env.TRANSFORMERS_CACHE);
  push(env.XDG_CACHE_HOME, path.join("huggingface", "hub"));

  return dedupeStrings(candidates);
}

function collectModelDiscoveryInputs(options = {}) {
  const env = options && typeof options.env === "object" && options.env !== null
    ? options.env
    : process.env;
  const scanRoots = dedupeStrings([
    ...defaultScanRoots,
    ...collectEnvDrivenScanRoots(env),
  ]);
  const catalogPaths = dedupeStrings(defaultCatalogPaths).filter((item) => pathExists(item));
  const catalogRefs = catalogPaths.flatMap((catalogPath) => readCatalogModelRefs(catalogPath));
  return {
    scan_roots: scanRoots,
    catalog_paths: catalogPaths,
    catalog_refs: catalogRefs,
  };
}

function collectDiscoveredModelDirs(discoveryInputs) {
  const scanRoots = Array.isArray(discoveryInputs?.scan_roots) ? discoveryInputs.scan_roots : [];
  const catalogRefs = Array.isArray(discoveryInputs?.catalog_refs) ? discoveryInputs.catalog_refs : [];
  const byDir = new Map();

  const upsert = (modelDir, input = {}) => {
    const resolved = normalizeCatalogModelDir(modelDir);
    if (!resolved) return;
    const current = byDir.get(resolved) || {
      model_path: resolved,
      discovery_sources: [],
      catalog_entry_refs: [],
      source_root: "",
    };
    current.discovery_sources = dedupeStrings([
      ...current.discovery_sources,
      ...(Array.isArray(input.discovery_sources) ? input.discovery_sources : []),
    ]);
    current.catalog_entry_refs = [
      ...current.catalog_entry_refs,
      ...(Array.isArray(input.catalog_entry_refs) ? input.catalog_entry_refs : []),
    ];
    current.source_root = current.source_root || normalizeString(input.source_root);
    byDir.set(resolved, current);
  };

  for (const root of scanRoots) {
    if (!pathExists(root)) continue;
    for (const modelDir of discoverModelDirs(root)) {
      upsert(modelDir, {
        source_root: root,
        discovery_sources: [`scan_root:${root}`],
      });
    }
  }

  for (const ref of catalogRefs) {
    upsert(ref.model_dir, {
      source_root: normalizeString(ref.model_path),
      discovery_sources: [`catalog:${ref.catalog_path}`],
      catalog_entry_refs: [ref],
    });
  }

  return Array.from(byDir.values()).sort((a, b) =>
    String(a.model_path || "").localeCompare(String(b.model_path || ""))
  );
}

function emptyDiscoveredMeta(modelPath = "") {
  const normalizedModelPath = normalizeCatalogModelDir(modelPath) || normalizeString(modelPath);
  return {
    model_path: normalizedModelPath,
    discovery_sources: [],
    catalog_entry_refs: [],
    source_root: "",
  };
}

function resolveKnownModelDiscoveryForPath(modelPath, discoveryInputs = null) {
  const normalizedModelPath = normalizeCatalogModelDir(modelPath);
  if (!normalizedModelPath) {
    return emptyDiscoveredMeta(modelPath);
  }
  const discoveredModelDirs = collectDiscoveredModelDirs(discoveryInputs || collectModelDiscoveryInputs());
  return (
    discoveredModelDirs.find((item) => item.model_path === normalizedModelPath) ||
    emptyDiscoveredMeta(normalizedModelPath)
  );
}

function modelNameHint(modelPath) {
  return path.basename(modelPath);
}

function inferTaskHint(modelPath, config, discoveredMeta = {}) {
  const catalogEntryRefs = Array.isArray(discoveredMeta.catalog_entry_refs)
    ? discoveredMeta.catalog_entry_refs
    : [];
  const catalogTaskKinds = dedupeStrings(
    catalogEntryRefs.flatMap((entry) => Array.isArray(entry.task_kinds) ? entry.task_kinds : [])
  );
  for (const taskKind of catalogTaskKinds) {
    const normalizedTaskKind = normalizeTaskKindHint(taskKind);
    if (normalizedTaskKind !== "unknown" && normalizedTaskKind !== "text_generate") {
      return {
        task_hint: normalizedTaskKind,
        task_hint_sources: [`catalog_task_kind:${taskKind}`],
      };
    }
  }

  const candidateSignals = [
    {
      label: `path_name:${path.basename(modelPath)}`,
      text: path.basename(modelPath),
    },
    {
      label: `config_model_type:${String(config && config.model_type || "")}`,
      text: String(config && config.model_type || ""),
    },
    ...(Array.isArray(config && config.architectures) ? config.architectures : []).map((item) => ({
      label: `config_architecture:${item}`,
      text: item,
    })),
    ...catalogEntryRefs.flatMap((entry) => ([
      {
        label: `catalog_model_id:${normalizeString(entry.model_id)}`,
        text: normalizeString(entry.model_id),
      },
      {
        label: `catalog_model_name:${normalizeString(entry.model_name)}`,
        text: normalizeString(entry.model_name),
      },
      {
        label: `catalog_backend:${normalizeString(entry.backend)}`,
        text: normalizeString(entry.backend),
      },
      {
        label: `catalog_note:${normalizeString(entry.note)}`,
        text: normalizeString(entry.note),
      },
    ])),
  ];

  for (const signal of candidateSignals) {
    const normalizedTaskKind = normalizeTaskKindHint(signal.text);
    if (normalizedTaskKind !== "unknown" && normalizedTaskKind !== "text_generate") {
      return {
        task_hint: normalizedTaskKind,
        task_hint_sources: [signal.label],
      };
    }
  }

  for (const taskKind of catalogTaskKinds) {
    const normalizedTaskKind = normalizeTaskKindHint(taskKind);
    if (normalizedTaskKind !== "unknown") {
      return {
        task_hint: normalizedTaskKind,
        task_hint_sources: [`catalog_task_kind:${taskKind}`],
      };
    }
  }

  return {
    task_hint: "unknown",
    task_hint_sources: [],
  };
}

function listTopLevelFiles(modelPath) {
  const out = [];
  for (const entry of safeReadDir(modelPath)) {
    if (!entry.isFile()) continue;
    out.push(entry.name);
  }
  return out.sort();
}

function buildStaticMarkers(modelPath, discoveredMeta = {}) {
  const configPath = path.join(modelPath, "config.json");
  const indexPath = path.join(modelPath, "model.safetensors.index.json");
  const config = safeReadJSON(configPath) || {};
  const index = safeReadJSON(indexPath) || {};
  const quantizationConfig = config.quantization_config || null;
  const weightMap = index.weight_map || {};
  const weightKeys = Object.keys(weightMap);
  const hasScaleWeights = weightKeys.some((key) => key.includes(".scales"));
  const hasBiasWeights = weightKeys.some((key) => key.includes(".biases"));
  const hasQuantMethod = !!(
    quantizationConfig &&
    typeof quantizationConfig === "object" &&
    Object.prototype.hasOwnProperty.call(quantizationConfig, "quant_method")
  );
  const topLevelFiles = listTopLevelFiles(modelPath);
  const sentenceTransformersMarkers = dedupeStrings([
    topLevelFiles.includes("modules.json") ? "top_level:modules.json" : "",
    topLevelFiles.includes("config_sentence_transformers.json")
      ? "top_level:config_sentence_transformers.json"
      : "",
    topLevelFiles.includes("sentence_bert_config.json") ? "top_level:sentence_bert_config.json" : "",
    normalizeString(modelPath).toLowerCase().includes("sentence-transformers") ? "path:sentence-transformers" : "",
  ]);
  const inferredTaskHint = inferTaskHint(modelPath, config, discoveredMeta);
  const taskHint = sentenceTransformersMarkers.length > 0 && inferredTaskHint.task_hint === "unknown"
    ? {
      task_hint: "embedding",
      task_hint_sources: sentenceTransformersMarkers.map((marker) => `sentence_transformers_layout:${marker}`),
    }
    : inferredTaskHint;
  const reasons = [];
  if (quantizationConfig && !hasQuantMethod) {
    reasons.push("quantization_config_missing_quant_method");
  }
  if (hasScaleWeights) reasons.push("weight_map_contains_scales_sidecars");
  if (hasBiasWeights) reasons.push("weight_map_contains_biases_sidecars");
  if (topLevelFiles.includes("model.safetensors") && topLevelFiles.includes("model.safetensors.index.json")) {
    reasons.push("single_safetensors_file_plus_index_present");
  }
  return {
    config_summary: {
      architectures: Array.isArray(config.architectures) ? config.architectures : [],
      model_type: String(config.model_type || ""),
      torch_dtype: String(config.torch_dtype || ""),
      max_position_embeddings: Number(config.max_position_embeddings || 0),
      hidden_size: Number(config.hidden_size || 0),
      quantization_config: quantizationConfig,
    },
    file_markers: {
      top_level_files: topLevelFiles,
      has_config_json: topLevelFiles.includes("config.json"),
      has_tokenizer_json: topLevelFiles.includes("tokenizer.json"),
      has_model_safetensors: topLevelFiles.includes("model.safetensors"),
      has_model_safetensors_index: topLevelFiles.includes("model.safetensors.index.json"),
      has_sentence_transformers_modules_json: topLevelFiles.includes("modules.json"),
      has_sentence_transformers_config: topLevelFiles.includes("config_sentence_transformers.json"),
      has_sentence_bert_config: topLevelFiles.includes("sentence_bert_config.json"),
      weight_map_entry_count: weightKeys.length,
      weight_map_has_scales_sidecars: hasScaleWeights,
      weight_map_has_biases_sidecars: hasBiasWeights,
    },
    format_assessment: {
      task_hint: taskHint.task_hint,
      task_hint_sources: taskHint.task_hint_sources,
      sentence_transformers_layout_markers: sentenceTransformersMarkers,
      quantization_config_has_quant_method: hasQuantMethod,
      suspected_non_native_quantized_layout: reasons.length > 0,
      reasons,
    },
  };
}

function runtimeCandidates() {
  return [
    {
      runtime_id: "lmstudio_cpython311_combo_transformers",
      label: "LM Studio cpython3.11 + app-mlx-generate site-packages",
      command: lmStudioCPython,
      env: {
        PYTHONPATH: lmStudioTransformersSitePackages,
      },
    },
    {
      runtime_id: "xcode_python3",
      label: "Xcode python3",
      command: xcodePython,
      env: {},
    },
  ].filter((row) => pathExists(row.command));
}

function probeRuntimeReadiness(candidate) {
  const script = [
    "import importlib, json, sys",
    "mods = {}",
    "for name in ('torch','transformers','tokenizers','PIL'):",
    "    try:",
    "        mod = importlib.import_module(name)",
    "        mods[name] = {'ok': True, 'version': str(getattr(mod, '__version__', 'ok'))}",
    "    except Exception as exc:",
    "        mods[name] = {'ok': False, 'error': f'{type(exc).__name__}:{exc}'}",
    "print(json.dumps({'python_executable': sys.executable, 'modules': mods}, ensure_ascii=False))",
  ].join("\n");
  const env = {
    ...process.env,
    ...candidate.env,
  };
  const runResult = runCommand(candidate.command, ["-c", script], {
    env,
    timeoutMs: 30000,
  });
  const parsed = tryParseJSON(runResult.stdout);
  return {
    candidate,
    command_result: {
      command: runResult.command,
      exit_code: runResult.exit_code,
      ok: runResult.ok,
      stderr_excerpt: trimOutput(runResult.stderr, 2000),
      error: runResult.error,
    },
    parsed,
    ready: !!(
      parsed &&
      parsed.modules &&
      parsed.modules.torch &&
      parsed.modules.torch.ok &&
      parsed.modules.transformers &&
      parsed.modules.transformers.ok &&
      parsed.modules.tokenizers &&
      parsed.modules.tokenizers.ok &&
      parsed.modules.PIL &&
      parsed.modules.PIL.ok
    ),
  };
}

function chooseReadyRuntime() {
  const probes = runtimeCandidates().map(probeRuntimeReadiness);
  const best = probes.find((probe) => probe.ready) || null;
  return {
    probes,
    best,
  };
}

function slugForModel(modelPath) {
  const base = path.basename(modelPath).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return `${base || "model"}-${sha8(modelPath)}`;
}

function runNativeLoadabilityProbe(runtimeProbe, modelPath, artifactDir) {
  const env = {
    ...process.env,
    TRANSFORMERS_OFFLINE: "1",
    HF_HUB_OFFLINE: "1",
    PYTHONUNBUFFERED: "1",
    ...runtimeProbe.candidate.env,
  };
  const script = [
    "import json, sys, traceback",
    "model_path = sys.argv[1]",
    "out = {}",
    "try:",
    "    from transformers import AutoConfig, AutoTokenizer, AutoModel, AutoModelForCausalLM",
    "    out['imports'] = {'ok': True}",
    "except Exception as exc:",
    "    out['imports'] = {'ok': False, 'error_type': type(exc).__name__, 'error': str(exc)}",
    "    print(json.dumps(out, ensure_ascii=False))",
    "    raise SystemExit(0)",
    "def attempt(label, fn):",
    "    try:",
    "        value = fn()",
    "        detail = {'ok': True}",
    "        if label == 'auto_config':",
    "            cfg = value",
    "            quant_cfg = getattr(cfg, 'quantization_config', None)",
    "            detail.update({",
    "                'model_type': str(getattr(cfg, 'model_type', '') or ''),",
    "                'architectures': list(getattr(cfg, 'architectures', []) or []),",
    "                'quantization_config_type': type(quant_cfg).__name__ if quant_cfg is not None else '',",
    "                'quantization_config_has_quant_method': bool(hasattr(quant_cfg, 'quant_method')) if quant_cfg is not None else False,",
    "            })",
    "        elif label == 'auto_tokenizer':",
    "            tok = value",
    "            detail.update({",
    "                'tokenizer_class': tok.__class__.__name__,",
    "                'vocab_size': int(getattr(tok, 'vocab_size', 0) or 0),",
    "            })",
    "        else:",
    "            model = value",
    "            cfg = getattr(model, 'config', None)",
    "            detail.update({",
    "                'model_class': model.__class__.__name__,",
    "                'model_type': str(getattr(cfg, 'model_type', '') or ''),",
    "            })",
    "        out[label] = detail",
    "    except Exception as exc:",
    "        out[label] = {'ok': False, 'error_type': type(exc).__name__, 'error': str(exc), 'traceback': traceback.format_exc(limit=3)}",
    "attempt('auto_config', lambda: AutoConfig.from_pretrained(model_path, local_files_only=True, trust_remote_code=False))",
    "attempt('auto_tokenizer', lambda: AutoTokenizer.from_pretrained(model_path, local_files_only=True, trust_remote_code=False))",
    "attempt('auto_model', lambda: AutoModel.from_pretrained(model_path, local_files_only=True, trust_remote_code=False))",
    "attempt('auto_model_for_causal_lm', lambda: AutoModelForCausalLM.from_pretrained(model_path, local_files_only=True, trust_remote_code=False))",
    "print(json.dumps(out, ensure_ascii=False))",
  ].join("\n");
  const runResult = runCommand(runtimeProbe.candidate.command, ["-c", script, modelPath], {
    env,
    timeoutMs: 240000,
  });
  persistArtifacts(artifactDir, "native_loadability", runResult);
  return {
    run_result: {
      command: runResult.command,
      exit_code: runResult.exit_code,
      ok: runResult.ok,
      stderr_excerpt: trimOutput(runResult.stderr, 2000),
      error: runResult.error,
    },
    parsed: tryParseJSON(runResult.stdout),
  };
}

function classifyLoadability(staticMarkers, loadProbe) {
  const parsed = loadProbe && loadProbe.parsed ? loadProbe.parsed : {};
  const autoConfigOk = !!(parsed.auto_config && parsed.auto_config.ok);
  const autoTokenizerOk = !!(parsed.auto_tokenizer && parsed.auto_tokenizer.ok);
  const autoModelOk = !!(parsed.auto_model && parsed.auto_model.ok);
  const autoCausalLmOk = !!(parsed.auto_model_for_causal_lm && parsed.auto_model_for_causal_lm.ok);
  const reasons = [];
  if (!autoConfigOk) reasons.push(`auto_config_failed:${parsed.auto_config ? parsed.auto_config.error || "unknown" : "missing"}`);
  if (!autoTokenizerOk) reasons.push(`auto_tokenizer_failed:${parsed.auto_tokenizer ? parsed.auto_tokenizer.error || "unknown" : "missing"}`);
  if (!autoModelOk) reasons.push(`auto_model_failed:${parsed.auto_model ? parsed.auto_model.error || "unknown" : "missing"}`);
  if (!autoCausalLmOk) reasons.push(`auto_model_for_causal_lm_failed:${parsed.auto_model_for_causal_lm ? parsed.auto_model_for_causal_lm.error || "unknown" : "missing"}`);
  reasons.push(...(staticMarkers.format_assessment.reasons || []));

  let blockerReason = "";
  const autoModelError = String(parsed.auto_model && parsed.auto_model.error || "");
  const autoCausalLmError = String(parsed.auto_model_for_causal_lm && parsed.auto_model_for_causal_lm.error || "");
  if (autoModelError.includes("quant_method") || autoCausalLmError.includes("quant_method")) {
    blockerReason = "unsupported_quantization_config";
  } else if (!autoModelOk && !autoCausalLmOk) {
    blockerReason = "transformers_native_model_load_failed";
  }

  let verdict = "not_native_loadable";
  if (autoModelOk || autoCausalLmOk) {
    verdict = "native_loadable";
  } else if (autoConfigOk || autoTokenizerOk) {
    verdict = "partially_loadable_metadata_only";
  }

  return {
    verdict,
    blocker_reason: blockerReason,
    reasons,
    auto_config_ok: autoConfigOk,
    auto_tokenizer_ok: autoTokenizerOk,
    auto_model_ok: autoModelOk,
    auto_model_for_causal_lm_ok: autoCausalLmOk,
  };
}

function summarize(runtimeSelection, candidates) {
  const nativeCandidates = candidates.filter((row) => row.task_hint === "embedding" && row.loadability.verdict === "native_loadable");
  const blockedCandidates = candidates.filter((row) => row.task_hint === "embedding" && row.loadability.blocker_reason === "unsupported_quantization_config");
  let primaryBlocker = "";
  let nextStep = "";
  if (!runtimeSelection.best) {
    primaryBlocker = "no_ready_transformers_runtime_candidate";
    nextStep = "restore_combo_runtime_or_helper_bridge_before_rerunning_sample1";
  } else if (candidates.length === 0) {
    primaryBlocker = "no_local_embedding_model_dir_found";
    nextStep = "source_one_real_local_embedding_model_dir_then_rerun_sample1";
  } else if (nativeCandidates.length === 0 && blockedCandidates.length > 0) {
    primaryBlocker = "current_embedding_dirs_not_torch_transformers_native_loadable(unsupported_quantization_config)";
    nextStep = "source_one_native_torch_transformers_loadable_real_embedding_model_dir_or_restore_lmstudio_helper_daemon_then_rerun_sample1";
  } else if (nativeCandidates.length === 0) {
    primaryBlocker = "current_embedding_dirs_not_torch_transformers_native_loadable";
    nextStep = "inspect_other_local_model_dirs_or_restore_lmstudio_helper_daemon_then_rerun_sample1";
  } else {
    primaryBlocker = "";
    nextStep = "use_best_native_loadable_embedding_dir_for_lpr_rr_01";
  }
  return {
    discovered_embedding_candidates: candidates.length,
    native_loadable_embedding_candidates: nativeCandidates.length,
    partially_loadable_embedding_candidates: candidates.filter((row) => row.loadability.verdict === "partially_loadable_metadata_only").length,
    best_native_candidate_model_path: nativeCandidates[0] ? nativeCandidates[0].model_path : "",
    primary_blocker: primaryBlocker,
    recommended_next_step: nextStep,
  };
}

function main() {
  safeMkdir(artifactRoot);
  const generatedAt = isoNow();
  const runtimeSelection = chooseReadyRuntime();
  const discoveryInputs = collectModelDiscoveryInputs();
  const discoveredModelDirs = collectDiscoveredModelDirs(discoveryInputs);
  const uniqueModelDirs = discoveredModelDirs.map((item) => item.model_path);
  const discoveredByPath = new Map(
    discoveredModelDirs.map((item) => [item.model_path, item])
  );

  const embeddingCandidates = [];
  for (const modelPath of uniqueModelDirs) {
    const discoveredMeta = discoveredByPath.get(modelPath) || {
      discovery_sources: [],
      catalog_entry_refs: [],
      source_root: "",
    };
    const staticMarkers = buildStaticMarkers(modelPath, discoveredMeta);
    if (staticMarkers.format_assessment.task_hint !== "embedding") continue;
    const modelSlug = slugForModel(modelPath);
    const artifactDir = path.join(artifactRoot, modelSlug);
    safeMkdir(artifactDir);

    const loadProbe = runtimeSelection.best
      ? runNativeLoadabilityProbe(runtimeSelection.best, modelPath, artifactDir)
      : {
          run_result: {
            command: "",
            exit_code: -1,
            ok: false,
            stderr_excerpt: "",
            error: "no_ready_transformers_runtime_candidate",
          },
          parsed: null,
        };
    const loadability = classifyLoadability(staticMarkers, loadProbe);
    embeddingCandidates.push({
      model_name_hint: modelNameHint(modelPath),
      model_path: modelPath,
      model_path_hash8: sha8(modelPath),
      source_root: discoveredMeta.source_root || "",
      discovery_sources: Array.isArray(discoveredMeta.discovery_sources)
        ? discoveredMeta.discovery_sources
        : [],
      catalog_entry_refs: Array.isArray(discoveredMeta.catalog_entry_refs)
        ? discoveredMeta.catalog_entry_refs
        : [],
      task_hint: staticMarkers.format_assessment.task_hint,
      static_markers: staticMarkers,
      runtime_probe: loadProbe.parsed || {
        imports: { ok: false, error: loadProbe.run_result.error || "probe_not_executed" },
      },
      loadability,
      artifact_refs: {
        native_loadability_meta: relPath(path.join(artifactDir, "native_loadability.meta.json")),
        native_loadability_stdout: relPath(path.join(artifactDir, "native_loadability.stdout.log")),
        native_loadability_stderr: relPath(path.join(artifactDir, "native_loadability.stderr.log")),
      },
    });
  }

  const summary = summarize(runtimeSelection, embeddingCandidates);
  const report = {
    schema_version: "xhub.lpr_w3_03_model_native_loadability_probe.v1",
    generated_at: generatedAt,
    scope: "Discover local embedding model dirs and test whether sample1 can use a torch/transformers-native model directory on a ready runtime.",
    fail_closed: true,
    scan_roots: discoveryInputs.scan_roots.map((root) => ({
      path: root,
      present: pathExists(root),
    })),
    catalog_sources: {
      catalog_paths: discoveryInputs.catalog_paths,
      catalog_model_ref_total: discoveryInputs.catalog_refs.length,
      catalog_model_refs: discoveryInputs.catalog_refs,
    },
    runtime_resolution: {
      selected_runtime_id: runtimeSelection.best ? runtimeSelection.best.candidate.runtime_id : "",
      selected_runtime_label: runtimeSelection.best ? runtimeSelection.best.candidate.label : "",
      selected_runtime_command: runtimeSelection.best ? runtimeSelection.best.candidate.command : "",
      runtime_probes: runtimeSelection.probes.map((probe) => ({
        runtime_id: probe.candidate.runtime_id,
        label: probe.candidate.label,
        ready: probe.ready,
        python_executable: probe.parsed ? probe.parsed.python_executable || "" : "",
        modules: probe.parsed ? probe.parsed.modules || {} : {},
        command_result: probe.command_result,
      })),
    },
    discovered_model_dirs_total: uniqueModelDirs.length,
    discovered_model_dirs: discoveredModelDirs,
    embedding_candidates: embeddingCandidates,
    summary,
    next_actions: [
      "优先使用 `native_loadable` 的 embedding 模型目录来执行 `lpr_rr_01`。",
      "若 `embedding_candidates` 全部不是 `native_loadable`，当前主线应转为：补一条 torch/transformers 原生可加载的真实 embedding 模型目录，或恢复 LM Studio helper bridge 路径。",
      "若仍是 `unsupported_quantization_config`，说明当前目录更像 LM Studio / MLX 风格量化产物，不应把它误判为 sample1 可用目录。",
    ],
  };

  writeJSON(outputPath, report);
  process.stdout.write(`${outputPath}\n`);
}

if (require.main === module) {
  main();
}

module.exports = {
  buildStaticMarkers,
  chooseReadyRuntime,
  classifyLoadability,
  collectDiscoveredModelDirs,
  collectEnvDrivenScanRoots,
  collectModelDiscoveryInputs,
  defaultCatalogPaths,
  defaultScanRoots,
  directoryLooksLikeModel,
  emptyDiscoveredMeta,
  inferTaskHint,
  normalizeCatalogModelDir,
  normalizeTaskKindHint,
  pathExists,
  readCatalogModelRefs,
  resolveKnownModelDiscoveryForPath,
  runNativeLoadabilityProbe,
  shouldSkipDiscoveryDir,
  slugForModel,
};
