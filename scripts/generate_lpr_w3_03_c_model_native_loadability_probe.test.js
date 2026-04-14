#!/usr/bin/env node
/* eslint-disable no-console */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const {
  collectDiscoveredModelDirs,
  collectEnvDrivenScanRoots,
  collectModelDiscoveryInputs,
  defaultScanRoots,
  inferTaskHint,
  normalizeCatalogModelDir,
  normalizeTaskKindHint,
  readCatalogModelRefs,
  resolveKnownModelDiscoveryForPath,
  shouldSkipDiscoveryDir,
} = require("./generate_lpr_w3_03_c_model_native_loadability_probe.js");

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

function mkdirModel(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
  fs.writeFileSync(path.join(dirPath, "config.json"), "{}\n", "utf8");
  fs.writeFileSync(path.join(dirPath, "tokenizer.json"), "{}\n", "utf8");
  fs.writeFileSync(path.join(dirPath, "model.safetensors"), "", "utf8");
}

run("normalizeCatalogModelDir resolves both directory and file refs", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-model-dir-"));
  try {
    const modelDir = path.join(root, "hf-embed");
    mkdirModel(modelDir);
    const modelFile = path.join(modelDir, "model.safetensors");

    assert.equal(normalizeCatalogModelDir(modelDir), modelDir);
    assert.equal(normalizeCatalogModelDir(modelFile), modelDir);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("readCatalogModelRefs extracts model dirs from models list", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-model-catalog-"));
  try {
    const modelDir = path.join(root, "hf-embed");
    mkdirModel(modelDir);
    const catalogPath = path.join(root, "models_catalog.json");
    fs.writeFileSync(
      catalogPath,
      JSON.stringify({
        models: [
          {
            id: "embed-1",
            name: "HF Embed",
            modelPath: modelDir,
            taskKinds: ["embedding"],
            backend: "transformers",
            note: "catalog",
          },
        ],
      }),
      "utf8"
    );

    const refs = readCatalogModelRefs(catalogPath);
    assert.equal(refs.length, 1);
    assert.equal(refs[0].model_id, "embed-1");
    assert.equal(refs[0].model_dir, modelDir);
    assert.deepEqual(refs[0].task_kinds, ["embedding"]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("collectDiscoveredModelDirs merges scan-root and catalog discovery for the same model dir", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-discovery-"));
  try {
    const scanRoot = path.join(root, "scan-root");
    const modelDir = path.join(scanRoot, "hf-embed");
    mkdirModel(modelDir);
    const catalogPath = path.join(root, "models_catalog.json");
    fs.writeFileSync(
      catalogPath,
      JSON.stringify({
        models: [
          {
            id: "embed-1",
            name: "HF Embed",
            modelPath: path.join(modelDir, "model.safetensors"),
            taskKinds: ["embedding"],
            backend: "transformers",
            note: "catalog",
          },
        ],
      }),
      "utf8"
    );

    const discovered = collectDiscoveredModelDirs({
      scan_roots: [scanRoot],
      catalog_refs: readCatalogModelRefs(catalogPath),
    });

    assert.equal(discovered.length, 1);
    assert.equal(discovered[0].model_path, modelDir);
    assert.ok(discovered[0].discovery_sources.some((item) => item.startsWith("scan_root:")));
    assert.ok(discovered[0].discovery_sources.some((item) => item.startsWith("catalog:")));
    assert.equal(discovered[0].catalog_entry_refs.length, 1);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("normalizeTaskKindHint maps common aliases to canonical task kinds", () => {
  assert.equal(normalizeTaskKindHint("text_embedding"), "embedding");
  assert.equal(normalizeTaskKindHint("automatic_speech_recognition"), "speech_to_text");
  assert.equal(normalizeTaskKindHint("vision_understand"), "vision");
  assert.equal(normalizeTaskKindHint("text_generate"), "text_generate");
});

run("inferTaskHint prefers catalog taskKinds over ambiguous path names", () => {
  const inferred = inferTaskHint("/tmp/models/opaque-model-dir", {}, {
    catalog_entry_refs: [
      {
        task_kinds: ["embedding"],
        model_name: "Opaque Internal Model",
      },
    ],
  });

  assert.equal(inferred.task_hint, "embedding");
  assert.deepEqual(inferred.task_hint_sources, ["catalog_task_kind:embedding"]);
});

run("resolveKnownModelDiscoveryForPath matches explicit file refs back to catalog-backed model dirs", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-known-discovery-"));
  try {
    const scanRoot = path.join(root, "scan-root");
    const modelDir = path.join(scanRoot, "opaque-model-dir");
    mkdirModel(modelDir);
    const catalogPath = path.join(root, "models_catalog.json");
    fs.writeFileSync(
      catalogPath,
      JSON.stringify({
        models: [
          {
            id: "embed-opaque",
            name: "Opaque Internal Model",
            modelPath: path.join(modelDir, "model.safetensors"),
            taskKinds: ["embedding"],
            backend: "transformers",
          },
        ],
      }),
      "utf8"
    );

    const discoveryInputs = {
      scan_roots: [scanRoot],
      catalog_refs: readCatalogModelRefs(catalogPath),
    };
    const resolved = resolveKnownModelDiscoveryForPath(
      path.join(modelDir, "model.safetensors"),
      discoveryInputs
    );

    assert.equal(resolved.model_path, modelDir);
    assert.equal(resolved.catalog_entry_refs.length, 1);
    assert.deepEqual(resolved.catalog_entry_refs[0].task_kinds, ["embedding"]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("shouldSkipDiscoveryDir rejects obvious non-model heavy directories", () => {
  assert.equal(shouldSkipDiscoveryDir(".git"), true);
  assert.equal(shouldSkipDiscoveryDir("node_modules"), true);
  assert.equal(shouldSkipDiscoveryDir(".scratch-memory"), true);
  assert.equal(shouldSkipDiscoveryDir("MyApp.app"), true);
  assert.equal(shouldSkipDiscoveryDir("logs.logarchive"), true);
  assert.equal(shouldSkipDiscoveryDir("models"), false);
  assert.equal(shouldSkipDiscoveryDir("hf-embed"), false);
});

run("collectDiscoveredModelDirs skips blacklisted subdirectories during recursive search", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-discovery-skip-"));
  try {
    const scanRoot = path.join(root, "scan-root");
    const visibleModelDir = path.join(scanRoot, "models", "hf-embed");
    const hiddenGitModelDir = path.join(scanRoot, ".git", "objects", "fake-model");
    const nodeModulesModelDir = path.join(scanRoot, "node_modules", "fake-model");
    mkdirModel(visibleModelDir);
    mkdirModel(hiddenGitModelDir);
    mkdirModel(nodeModulesModelDir);

    const discovered = collectDiscoveredModelDirs({
      scan_roots: [scanRoot],
      catalog_refs: [],
    });

    assert.equal(discovered.length, 1);
    assert.equal(discovered[0].model_path, visibleModelDir);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("collectDiscoveredModelDirs follows symlinked model directories during recursive search", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "xhub-discovery-symlink-"));
  try {
    const scanRoot = path.join(root, "scan-root");
    const realModelsRoot = path.join(root, "real-models");
    const realModelDir = path.join(realModelsRoot, "hf-embed");
    const symlinkDir = path.join(scanRoot, "linked-models");
    fs.mkdirSync(scanRoot, { recursive: true });
    mkdirModel(realModelDir);
    fs.symlinkSync(realModelsRoot, symlinkDir);

    const discovered = collectDiscoveredModelDirs({
      scan_roots: [scanRoot],
      catalog_refs: [],
    });

    assert.equal(discovered.length, 1);
    assert.equal(discovered[0].model_path, path.join(symlinkDir, "hf-embed"));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

run("default scan roots include the common ~/models home directory", () => {
  const expectedRoot = path.join(os.homedir(), "models");
  assert.ok(defaultScanRoots.includes(expectedRoot));
  assert.ok(defaultScanRoots.includes(path.join(os.homedir(), "Library", "Caches", "huggingface", "hub")));
  assert.ok(defaultScanRoots.includes(path.join(os.homedir(), "Library", "Application Support", "LM Studio", "models")));

  const discoveryInputs = collectModelDiscoveryInputs();
  assert.ok(discoveryInputs.scan_roots.includes(expectedRoot));
});

run("collectModelDiscoveryInputs includes env-driven huggingface cache roots", () => {
  const envDrivenRoots = collectEnvDrivenScanRoots({
    HF_HOME: "/tmp/hf-home",
    HF_HUB_CACHE: "/tmp/hf-hub-cache",
    HUGGINGFACE_HUB_CACHE: "/tmp/hf-hub-cache-legacy",
    TRANSFORMERS_CACHE: "/tmp/transformers-cache",
    XDG_CACHE_HOME: "/tmp/xdg-cache",
  });

  assert.deepEqual(envDrivenRoots, [
    "/tmp/hf-home/hub",
    "/tmp/hf-hub-cache",
    "/tmp/hf-hub-cache-legacy",
    "/tmp/transformers-cache",
    "/tmp/xdg-cache/huggingface/hub",
  ]);

  const discoveryInputs = collectModelDiscoveryInputs({
    env: {
      HF_HOME: "/tmp/hf-home",
      HUGGINGFACE_HUB_CACHE: "/tmp/hf-hub-cache-legacy",
    },
  });

  assert.ok(discoveryInputs.scan_roots.includes("/tmp/hf-home/hub"));
  assert.ok(discoveryInputs.scan_roots.includes("/tmp/hf-hub-cache-legacy"));
});
