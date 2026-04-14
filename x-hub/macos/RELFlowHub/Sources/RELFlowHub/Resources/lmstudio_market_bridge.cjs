const fs = require("fs");
const http = require("http");
const https = require("https");
const os = require("os");
const path = require("path");

const HUGGING_FACE_BASE_URL = "https://huggingface.co";
const HUGGING_FACE_FALLBACK_BASE_URLS = ["https://hf-mirror.com"];
const DEFAULT_BRANCH = "main";
const DEFAULT_DISCOVER_QUERIES = ["vision", "coder", "embedding", "voice", "qwen", "llama", "glm"];
const CATEGORY_QUERY_EXPANSIONS = {
  chat: ["chat", "instruct", "assistant", "qwen", "llama", "glm"],
  vision: ["vision", "vl", "llava", "glm-4.6v", "qwen2-vl", "qwen3-vl", "florence", "ocr", "image"],
  ocr: ["ocr", "document", "trocr", "donut", "florence"],
  coding: ["coder", "coding", "code", "qwen-coder", "deepseek-coder"],
  embedding: ["embedding", "embed", "bge", "gte", "qwen-embedding"],
  voice: ["tts", "voice", "text-to-speech", "kokoro", "melo", "parler", "bark", "speecht5", "f5-tts", "cosyvoice"],
  speech: ["speech", "audio", "asr", "whisper"],
};
const CATEGORY_QUERY_ALIASES = {
  assistant: "chat",
  chat: "chat",
  general: "chat",
  instruct: "chat",
  llm: "chat",
  text: "chat",
  asr: "speech",
  audio: "speech",
  speech: "speech",
  tts: "voice",
  "text-to-speech": "voice",
  "speech-synthesis": "voice",
  speechsynthesis: "voice",
  transcribe: "speech",
  transcription: "speech",
  voice: "voice",
  kokoro: "voice",
  melo: "voice",
  parler: "voice",
  "parler-tts": "voice",
  bark: "voice",
  speecht5: "voice",
  "f5-tts": "voice",
  f5tts: "voice",
  cosyvoice: "voice",
  chattts: "voice",
  whisper: "speech",
  code: "coding",
  coder: "coding",
  coding: "coding",
  dev: "coding",
  programming: "coding",
  document: "ocr",
  doc: "ocr",
  ocr: "ocr",
  pdf: "ocr",
  scan: "ocr",
  embed: "embedding",
  embedding: "embedding",
  embeddings: "embedding",
  rerank: "embedding",
  retrieval: "embedding",
  vector: "embedding",
  image: "vision",
  images: "vision",
  multimodal: "vision",
  photo: "vision",
  vision: "vision",
  vl: "vision",
  vlm: "vision",
};
const CATEGORY_TAG_FILTERS = {
  chat: new Set(["Text"]),
  vision: new Set(["Vision", "OCR"]),
  ocr: new Set(["OCR"]),
  coding: new Set(["Coding"]),
  embedding: new Set(["Embedding"]),
  voice: new Set(["Voice"]),
  speech: new Set(["Speech"]),
};
const CURATED_RECOMMENDATION_BUCKETS_BASE = [
  { tag: "Text", weight: 6 },
  { tag: "Coding", weight: 4 },
  { tag: "Embedding", weight: 4 },
];
const CURATED_RECOMMENDATION_BUCKETS_HELPER = [
  { tag: "Vision", weight: 4 },
  { tag: "Voice", weight: 3 },
  { tag: "OCR", weight: 2 },
];
const REPO_EXCLUDE_TAGS = new Set(["gguf", "onnx", "diffusers"]);
const JSON_TIMEOUT_MS = 8000;
const DOWNLOAD_TIMEOUT_MS = 10 * 60 * 1000;
const MAX_REDIRECTS = 8;
const DISCOVER_OVERSCAN = 3;
const MARKET_METADATA_FILE = ".xhub-market-source.json";
const HUGGING_FACE_BASE_PREFERENCE_FILE = "huggingface_base_preference.json";
const REQUEST_RETRY_DELAYS_MS = [500];
const DEFAULT_HELPER_BINARY_NAMES = ["lms", "llmster", "lmstudio"];

function writeJSON(value, stream = process.stdout) {
  stream.write(`${JSON.stringify(value)}\n`);
}

function realHomeDirectory() {
  return String(process.env.XHUB_REAL_HOME || process.env.HOME || os.homedir() || "").trim() || os.homedir();
}

function normalizedBaseURL(value) {
  return String(value || "").trim().replace(/\/+$/, "");
}

function configuredHuggingFaceBaseURL() {
  const configured = String(
    process.env.XHUB_HF_BASE_URL
      || process.env.HF_ENDPOINT
      || process.env.HUGGINGFACE_HUB_ENDPOINT
      || "",
  ).trim();
  return normalizedBaseURL(configured);
}

function huggingFaceBasePreferencePath() {
  return path.join(hubDirectory(), HUGGING_FACE_BASE_PREFERENCE_FILE);
}

function storedHuggingFaceBaseURL() {
  try {
    const raw = fs.readFileSync(huggingFaceBasePreferencePath(), "utf8");
    const payload = JSON.parse(raw);
    return normalizedBaseURL(payload && payload.preferredBaseURL);
  } catch {
    return "";
  }
}

function persistStoredHuggingFaceBaseURL(baseURL) {
  const normalized = normalizedBaseURL(baseURL);
  const preferencePath = huggingFaceBasePreferencePath();
  if (!normalized) {
    try {
      fs.unlinkSync(preferencePath);
    } catch {}
    return "";
  }
  try {
    ensureDirectory(path.dirname(preferencePath));
    fs.writeFileSync(
      preferencePath,
      JSON.stringify(
        {
          preferredBaseURL: normalized,
          updatedAt: Date.now(),
        },
        null,
        2,
      ),
    );
  } catch {}
  return normalized;
}

function resolvedHuggingFaceBaseURLs({
  preferredBaseURL = "",
  configuredBaseURL = "",
  storedBaseURL = "",
} = {}) {
  const candidates = [
    normalizedBaseURL(preferredBaseURL),
    normalizedBaseURL(configuredBaseURL),
    normalizedBaseURL(storedBaseURL),
    normalizedBaseURL(HUGGING_FACE_BASE_URL),
    ...HUGGING_FACE_FALLBACK_BASE_URLS.map(normalizedBaseURL),
  ].filter(Boolean);

  const ordered = [];
  for (const candidate of candidates) {
    if (!ordered.includes(candidate)) {
      ordered.push(candidate);
    }
  }
  return ordered;
}

function huggingFaceBaseURLs(preferredBaseURL = "") {
  return resolvedHuggingFaceBaseURLs({
    preferredBaseURL,
    configuredBaseURL: configuredHuggingFaceBaseURL(),
    storedBaseURL: storedHuggingFaceBaseURL(),
  });
}

function huggingFaceHostLabel(urlString = huggingFaceBaseURLs()[0] || HUGGING_FACE_BASE_URL) {
  try {
    const parsed = new URL(urlString);
    return parsed.host || "huggingface.co";
  } catch {
    return "huggingface.co";
  }
}

function hubDirectory() {
  return String(process.env.XHUB_HUB_DIR || "").trim() || path.join(realHomeDirectory(), "RELFlowHub");
}

function marketDirectory() {
  const configured = String(process.env.XHUB_MARKET_DIR || "").trim();
  if (configured) {
    return configured;
  }
  return path.join(hubDirectory(), "models", "_market");
}

function readHFToken() {
  const envCandidates = [
    process.env.HF_TOKEN,
    process.env.HUGGING_FACE_HUB_TOKEN,
    process.env.XHUB_HF_TOKEN,
  ];
  for (const candidate of envCandidates) {
    const token = String(candidate || "").trim();
    if (token) {
      return token;
    }
  }

  const fileCandidates = [
    path.join(realHomeDirectory(), ".cache", "huggingface", "token"),
    path.join(realHomeDirectory(), ".huggingface", "token"),
  ];
  for (const candidate of fileCandidates) {
    try {
      const token = fs.readFileSync(candidate, "utf8").trim();
      if (token) {
        return token;
      }
    } catch {}
  }
  return "";
}

function requestHeaders({ acceptsJSON = false } = {}) {
  const headers = {
    "User-Agent": "X-Hub/1.0 (local-model-market)",
  };
  if (acceptsJSON) {
    headers.Accept = "application/json";
  }
  const token = readHFToken();
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  return headers;
}

function normalizeCapabilityToken(value) {
  return String(value || "").trim().toLowerCase();
}

function resolvedDiscoverCategory(value) {
  const normalized = normalizeCapabilityToken(value);
  if (!normalized) {
    return "";
  }
  if (CATEGORY_QUERY_EXPANSIONS[normalized]) {
    return normalized;
  }
  return CATEGORY_QUERY_ALIASES[normalized] || "";
}

function uniqueSearchTerms(terms) {
  const seen = new Set();
  const ordered = [];
  for (const raw of Array.isArray(terms) ? terms : []) {
    const trimmed = String(raw || "").trim();
    if (!trimmed) {
      continue;
    }
    const key = trimmed.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    ordered.push(trimmed);
  }
  return ordered;
}

function expandedSearchTermsFor(searchTerm, category) {
  const trimmedSearchTerm = String(searchTerm || "").trim();
  if (trimmedSearchTerm) {
    const resolvedQueryCategory = resolvedDiscoverCategory(trimmedSearchTerm);
    if (resolvedQueryCategory && CATEGORY_QUERY_EXPANSIONS[resolvedQueryCategory]) {
      return uniqueSearchTerms([trimmedSearchTerm, ...CATEGORY_QUERY_EXPANSIONS[resolvedQueryCategory]]);
    }
    return [trimmedSearchTerm];
  }
  const resolvedCategory = resolvedDiscoverCategory(category);
  if (resolvedCategory && CATEGORY_QUERY_EXPANSIONS[resolvedCategory]) {
    return CATEGORY_QUERY_EXPANSIONS[resolvedCategory];
  }
  return DEFAULT_DISCOVER_QUERIES;
}

function categoryTagFilterFor(searchTerm, category) {
  const resolvedCategory = resolvedDiscoverCategory(category);
  if (resolvedCategory && CATEGORY_TAG_FILTERS[resolvedCategory]) {
    return CATEGORY_TAG_FILTERS[resolvedCategory];
  }
  const resolvedQuery = resolvedDiscoverCategory(searchTerm);
  if (resolvedQuery && CATEGORY_TAG_FILTERS[resolvedQuery]) {
    return CATEGORY_TAG_FILTERS[resolvedQuery];
  }
  const normalized = normalizeCapabilityToken(searchTerm);
  return CATEGORY_TAG_FILTERS[normalized] || null;
}

function helperBinaryCandidatePaths() {
  const candidates = [];
  const home = realHomeDirectory();
  if (home) {
    candidates.push(path.join(home, ".lmstudio", "bin", "lms"));
    candidates.push(path.join(home, ".lmstudio", "bin", "llmster"));
  }
  const pathValue = String(process.env.PATH || "").trim();
  if (pathValue) {
    for (const directory of pathValue.split(":").map(entry => entry.trim()).filter(Boolean)) {
      for (const helperName of DEFAULT_HELPER_BINARY_NAMES) {
        candidates.push(path.join(directory, helperName));
      }
    }
  }

  const seen = new Set();
  return candidates.filter(candidate => {
    const normalized = path.resolve(candidate);
    if (seen.has(normalized)) {
      return false;
    }
    seen.add(normalized);
    return true;
  });
}

function helperBridgeInstalled() {
  return helperBinaryCandidatePaths().some(candidate => {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  });
}

function rowHasCapabilityTag(row, tag) {
  return Array.isArray(row && row.capabilityTags)
    && row.capabilityTags.some(candidate => String(candidate || "").toLowerCase() === String(tag || "").toLowerCase());
}

function recommendationHaystack(row) {
  return [
    row && row.modelKey,
    row && row.title,
    row && row.summary,
    Array.isArray(row && row.capabilityTags) ? row.capabilityTags.join(" ") : "",
    row && row.formatHint,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function currentRecommendationBuckets(rows) {
  const buckets = [...CURATED_RECOMMENDATION_BUCKETS_BASE];
  if (helperBridgeInstalled()) {
    buckets.push(...CURATED_RECOMMENDATION_BUCKETS_HELPER);
  }
  return buckets.filter(bucket => rows.some(row => rowHasCapabilityTag(row, bucket.tag)));
}

function recommendationTargets(buckets, limit) {
  if (!Array.isArray(buckets) || buckets.length === 0 || limit <= 0) {
    return {};
  }
  if (limit <= buckets.length) {
    return Object.fromEntries(buckets.slice(0, limit).map(bucket => [bucket.tag, 1]));
  }

  const totalWeight = Math.max(1, buckets.reduce((sum, bucket) => sum + Math.max(1, Number(bucket.weight) || 0), 0));
  const targets = Object.fromEntries(buckets.map(bucket => [bucket.tag, 1]));
  let allocated = buckets.length;

  for (const bucket of buckets) {
    const proportional = Math.round(limit * (Math.max(1, Number(bucket.weight) || 0) / totalWeight));
    const desired = Math.max(1, proportional);
    targets[bucket.tag] = desired;
    allocated += desired - 1;
  }

  while (allocated > limit) {
    const candidate = [...buckets]
      .sort((lhs, rhs) => {
        const lhsTarget = Number(targets[lhs.tag] || 0);
        const rhsTarget = Number(targets[rhs.tag] || 0);
        if (lhsTarget !== rhsTarget) {
          return rhsTarget - lhsTarget;
        }
        return (Number(rhs.weight) || 0) - (Number(lhs.weight) || 0);
      })
      .find(bucket => Number(targets[bucket.tag] || 0) > 1);
    if (!candidate) {
      break;
    }
    targets[candidate.tag] -= 1;
    allocated -= 1;
  }

  while (allocated < limit) {
    const candidate = [...buckets]
      .sort((lhs, rhs) => {
        const lhsWeight = Number(lhs.weight) || 0;
        const rhsWeight = Number(rhs.weight) || 0;
        if (lhsWeight !== rhsWeight) {
          return rhsWeight - lhsWeight;
        }
        return (Number(targets[lhs.tag] || 0) || 0) - (Number(targets[rhs.tag] || 0) || 0);
      })[0];
    if (!candidate) {
      break;
    }
    targets[candidate.tag] = Number(targets[candidate.tag] || 0) + 1;
    allocated += 1;
  }

  return targets;
}

function primaryFocusTagFor(category) {
  switch (normalizeCapabilityToken(category)) {
    case "chat":
      return "Text";
    case "coding":
      return "Coding";
    case "embedding":
      return "Embedding";
    case "voice":
      return "Voice";
    case "vision":
      return "Vision";
    case "ocr":
      return "OCR";
    case "speech":
      return "Speech";
    default:
      return "";
  }
}

function fitScoreFor(estimation) {
  const normalized = normalizeCapabilityToken(String(estimation || "").replace(/_/g, ""));
  switch (normalized) {
    case "fullgpuoffload":
      return 240;
    case "partialgpuoffload":
      return 190;
    case "fitwithoutgpu":
      return 150;
    case "willnotfit":
      return 40;
    default:
      return 110;
  }
}

function formatScoreFor(row, focusTag) {
  const formatHint = normalizeCapabilityToken(row && row.formatHint);
  if (formatHint === "mlx") {
    if (["text", "coding", "embedding"].includes(normalizeCapabilityToken(focusTag))) {
      return 42;
    }
    if (["vision", "ocr"].includes(normalizeCapabilityToken(focusTag))) {
      return 12;
    }
    return 18;
  }
  if (formatHint === "transformers") {
    if (["vision", "ocr"].includes(normalizeCapabilityToken(focusTag))) {
      return 34;
    }
    if (["speech", "voice"].includes(normalizeCapabilityToken(focusTag))) {
      return 26;
    }
    return 18;
  }
  return 0;
}

function familyScoreFor(row, focusTag) {
  const haystack = recommendationHaystack(row);
  const genericSignals = [
    ["qwen", 18],
    ["llama", 16],
    ["gemma", 15],
    ["phi", 14],
    ["mistral", 14],
    ["deepseek", 14],
    ["glm", 12],
    ["bge", 14],
    ["gte", 12],
    ["whisper", 14],
    ["florence", 16],
  ];
  const focusedSignals = {
    Text: [["qwen3", 28], ["llama-3", 24], ["gemma-3", 22], ["phi-3", 20]],
    Coding: [["qwen-coder", 34], ["codestral", 32], ["deepseek-coder", 32], ["starcoder", 28], ["codegemma", 26], ["codellama", 24], ["devstral", 22]],
    Vision: [["qwen2-vl", 34], ["qwen3-vl", 34], ["glm-4.6v", 36], ["glm4v", 34], ["florence", 30], ["llava", 24], ["smolvlm", 18]],
    OCR: [["florence", 34], ["trocr", 30], ["donut", 24], ["ocr", 18]],
    Embedding: [["qwen3-embedding", 36], ["bge", 30], ["gte", 28], ["nomic-embed", 26], ["mxbai", 24], ["e5", 22]],
    Voice: [["kokoro", 34], ["melo", 30], ["parler", 30], ["bark", 28], ["speecht5", 28], ["f5-tts", 28], ["cosyvoice", 26]],
    Speech: [["whisper-large-v3", 34], ["whisper", 28], ["parakeet", 20]],
  };

  let score = 0;
  for (const [signal, bonus] of genericSignals) {
    if (haystack.includes(signal)) {
      score += bonus;
    }
  }
  for (const [signal, bonus] of focusedSignals[focusTag] || []) {
    if (haystack.includes(signal)) {
      score += bonus;
    }
  }
  return score;
}

function sizeScoreFor(sizeBytes, focusTag) {
  const numeric = Number(sizeBytes || 0);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return 0;
  }
  const gb = numeric / 1e9;
  switch (focusTag) {
    case "Embedding":
      if (gb < 1.5) return 26;
      if (gb < 4.0) return 20;
      if (gb < 8.0) return 8;
      return -12;
    case "Vision":
    case "OCR":
      if (gb < 3.0) return 10;
      if (gb < 8.0) return 18;
      if (gb < 14.0) return 12;
      return -8;
    default:
      if (gb < 3.0) return 24;
      if (gb < 6.0) return 18;
      if (gb < 10.0) return 8;
      if (gb < 18.0) return 0;
      return -16;
  }
}

function popularityScoreFor(row) {
  const downloads = Number(row && row.downloads || 0);
  const likes = Number(row && row.likes || 0);
  const downloadScore = Math.min(Math.log10(Math.max(downloads, 0) + 1) * 12, 40);
  const likeScore = Math.min(Math.log10(Math.max(likes, 0) + 1) * 8, 24);
  return downloadScore + likeScore;
}

function recommendationScoreFor(row, focusTag) {
  let score = fitScoreFor(row && row.recommendedFitEstimation);
  score += formatScoreFor(row, focusTag);
  score += familyScoreFor(row, focusTag);
  score += sizeScoreFor(row && row.recommendedSizeBytes, focusTag);
  score += popularityScoreFor(row);
  score += (Array.isArray(row && row.capabilityTags) ? row.capabilityTags.length : 0) * 6;

  if (focusTag) {
    if (rowHasCapabilityTag(row, focusTag)) {
      score += 120;
    } else if (focusTag === "Vision" && rowHasCapabilityTag(row, "OCR")) {
      score += 45;
    } else if (focusTag === "Text" && rowHasCapabilityTag(row, "Coding")) {
      score += 20;
    }
  } else if (row && row.recommendedForThisMac) {
    score += 20;
  }

  if (row && row.staffPick) {
    score += 12;
  }
  return score;
}

function curatedRecommendedRows(rows, limit) {
  const normalizedLimit = Math.max(1, Number(limit) || 1);
  if (!Array.isArray(rows) || rows.length === 0) {
    return [];
  }
  const buckets = currentRecommendationBuckets(rows);
  if (buckets.length === 0) {
    return rows
      .slice()
      .sort((lhs, rhs) => recommendationScoreFor(rhs, "") - recommendationScoreFor(lhs, ""))
      .slice(0, normalizedLimit)
      .map((row, index) => ({
        ...row,
        recommendationReason: recommendationReasonFor(row, "", index, true),
      }));
  }

  const targets = recommendationTargets(buckets, normalizedLimit);
  const selected = [];
  const seen = new Set();

  for (const bucket of buckets) {
    const candidates = rows
      .filter(row => rowHasCapabilityTag(row, bucket.tag) && !seen.has(normalizeRepoId(row.modelKey)))
      .sort((lhs, rhs) => {
        const delta = recommendationScoreFor(rhs, bucket.tag) - recommendationScoreFor(lhs, bucket.tag);
        if (delta !== 0) {
          return delta;
        }
        return String(lhs.title || "").localeCompare(String(rhs.title || ""));
      });
    const targetCount = Math.min(Number(targets[bucket.tag] || 0), candidates.length);
    for (let index = 0; index < targetCount; index += 1) {
      const row = { ...candidates[index] };
      if (index === 0) {
        row.staffPick = true;
      }
      row.recommendationReason = recommendationReasonFor(row, bucket.tag, index, false);
      selected.push(row);
      seen.add(normalizeRepoId(row.modelKey));
    }
  }

  if (selected.length < normalizedLimit) {
    const fallback = rows
      .filter(row => !seen.has(normalizeRepoId(row.modelKey)))
      .sort((lhs, rhs) => {
        const delta = recommendationScoreFor(rhs, "") - recommendationScoreFor(lhs, "");
        if (delta !== 0) {
          return delta;
        }
        return String(lhs.title || "").localeCompare(String(rhs.title || ""));
      });
    fallback.slice(0, normalizedLimit - selected.length).forEach((row, index) => {
      selected.push({
        ...row,
        recommendationReason: recommendationReasonFor(row, "", index, true),
      });
    });
  }

  return selected.slice(0, normalizedLimit);
}

function normalizedRecommendationFit(raw) {
  return normalizeCapabilityToken(String(raw || "").replace(/_/g, ""));
}

function fitAdjustedReason(base, fit) {
  switch (fit) {
    case "fullgpuoffload":
    case "partialgpuoffload":
      return `${base} for this Mac`;
    case "fitwithoutgpu":
      return `${base} that can stay CPU-friendly`;
    case "willnotfit":
      return `${base} if you want to push this Mac`;
    default:
      return base;
  }
}

function recommendationReasonFor(row, focusTag, rank, fallbackOnly) {
  const fit = normalizedRecommendationFit(row && row.recommendedFitEstimation);
  const isPrimaryPick = Number(rank || 0) === 0;

  switch (String(focusTag || "")) {
    case "Text":
      return fitAdjustedReason(isPrimaryPick ? "Best everyday text starter" : "Higher-headroom text option", fit);
    case "Coding":
      return fitAdjustedReason(isPrimaryPick ? "Best coding starter" : "Higher-headroom coding option", fit);
    case "Embedding":
      return isPrimaryPick
        ? "Best embedding starter for local retrieval"
        : "Higher-capacity embedding option for local retrieval";
    case "Voice":
      return fitAdjustedReason(isPrimaryPick ? "Best Supervisor voice starter" : "Alternative local voice option", fit);
    case "Vision":
      return fitAdjustedReason(isPrimaryPick ? "Best vision starter" : "Alternative vision option", fit);
    case "OCR":
      return fitAdjustedReason(
        isPrimaryPick
          ? "Best OCR starter for docs and screenshots"
          : "Alternative OCR option for docs and screenshots",
        fit,
      );
    case "Speech":
      return fitAdjustedReason(isPrimaryPick ? "Best speech starter" : "Alternative speech option", fit);
    default:
      return fallbackOnly
        ? fitAdjustedReason(isPrimaryPick ? "Balanced local model pick" : "Alternative local model pick", fit)
        : "";
  }
}

function formatBytes(bytes) {
  const numeric = Number(bytes || 0);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return "0 B";
  }
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = numeric;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const digits = value >= 10 || unitIndex === 0 ? 0 : 1;
  return `${value.toFixed(digits)} ${units[unitIndex]}`;
}

function progressMessage(downloadedBytes, totalBytes, speedBytesPerSecond) {
  const downloaded = Number(downloadedBytes || 0);
  const total = Number(totalBytes || 0);
  const speed = Number(speedBytesPerSecond || 0);
  const parts = [];
  if (total > 0) {
    const percent = Math.max(0, Math.min(100, Math.round((downloaded / total) * 100)));
    parts.push(`${percent}%`);
    parts.push(`${formatBytes(downloaded)} / ${formatBytes(total)}`);
  } else if (downloaded > 0) {
    parts.push(formatBytes(downloaded));
  }
  if (speed > 0) {
    parts.push(`${formatBytes(speed)}/s`);
  }
  return parts.join(" · ") || "Downloading...";
}

function normalizeRepoId(value) {
  return String(value || "").trim();
}

function splitRepoId(repoId) {
  const normalized = normalizeRepoId(repoId);
  const parts = normalized.split("/");
  if (parts.length !== 2) {
    throw new Error(`Invalid model key: ${repoId}`);
  }
  return { owner: parts[0], model: parts[1] };
}

function encodeRepoId(repoId) {
  const { owner, model } = splitRepoId(repoId);
  return `${encodeURIComponent(owner)}/${encodeURIComponent(model)}`;
}

function encodeRepoFilePath(filePath) {
  return String(filePath || "")
    .split("/")
    .map(segment => encodeURIComponent(segment))
    .join("/");
}

function repoDisplayTitle(repoId) {
  const { model } = splitRepoId(repoId);
  return model
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function requestErrorFromStatus(statusCode, statusMessage, bodyText = "") {
  const trimmedBody = String(bodyText || "").trim();
  let parsedMessage = "";
  if (trimmedBody) {
    try {
      const decoded = JSON.parse(trimmedBody);
      parsedMessage = String(decoded.error || decoded.message || "").trim();
    } catch {
      parsedMessage = trimmedBody;
    }
  }

  if (statusCode === 401 || statusCode === 403) {
    return new Error(
      parsedMessage || "这个模型需要 Hugging Face 身份验证。请设置 HF_TOKEN 后重试。",
    );
  }
  if (statusCode === 429) {
    return new Error(
      parsedMessage || "Hugging Face 对这次请求进行了限流。请设置 HF_TOKEN 使用已认证配额后重试。",
    );
  }
  if (parsedMessage) {
    return new Error(parsedMessage);
  }
  return new Error(`Hugging Face 请求失败，状态为 ${statusCode || 0} ${statusMessage || ""}`.trim());
}

function transportForURL(urlString) {
  const protocol = new URL(urlString).protocol;
  if (protocol === "http:") {
    return http;
  }
  return https;
}

function requestOptionsFor(urlString, { headers = {}, timeoutMs, family } = {}) {
  const parsed = new URL(urlString);
  const options = {
    protocol: parsed.protocol,
    hostname: parsed.hostname,
    port: parsed.port || undefined,
    path: `${parsed.pathname}${parsed.search}`,
    headers,
    timeout: timeoutMs,
  };
  if (family === 4) {
    options.family = 4;
  }
  return options;
}

function sleep(ms) {
  return new Promise(resolve => {
    setTimeout(resolve, ms);
  });
}

function isRetryableRequestError(error) {
  const code = String(error && error.code || "").trim().toUpperCase();
  if (["ETIMEDOUT", "ECONNRESET", "EAI_AGAIN", "ENETUNREACH", "EHOSTUNREACH", "ECONNREFUSED"].includes(code)) {
    return true;
  }
  const message = String(error && error.message || "").toLowerCase();
  return message.includes("timed out")
    || message.includes("connection reset")
    || message.includes("temporarily unavailable");
}

function normalizedRequestError(error, urlString) {
  const host = huggingFaceHostLabel(urlString);
  const message = String(error && error.message || "").trim();
  const code = String(error && error.code || "").trim().toUpperCase();
  const wrap = text => {
    const wrapped = new Error(text);
    if (code) {
      wrapped.code = code;
    }
    return wrapped;
  };

  if (code === "ENOTFOUND" || code === "EAI_NONAME" || code === "EAI_AGAIN") {
    return wrap(
      `Hub 无法解析 ${host}。请检查网络或 DNS 访问；如果你在使用 Hugging Face 镜像，请设置 HF_ENDPOINT/XHUB_HF_BASE_URL。`,
    );
  }
  if (code === "ETIMEDOUT" || message.toLowerCase().includes("timed out")) {
    return wrap(
      `Hub 在请求超时前无法连接到 ${host}。请检查网络权限、代理设置，或按需设置 HF_ENDPOINT/XHUB_HF_BASE_URL。`,
    );
  }
  if (["ECONNRESET", "ECONNREFUSED", "ENETUNREACH", "EHOSTUNREACH"].includes(code)) {
    return wrap(
      `Hub 无法与 ${host} 建立稳定连接。请检查到 Hugging Face 的网络访问后重试。`,
    );
  }
  if (message) {
    return wrap(message);
  }
  return wrap(`Hub 无法完成发往 ${host} 的请求。`);
}

function requestFamiliesForAttempt(attemptIndex) {
  if (attemptIndex === 0) {
    return [4];
  }
  return [undefined];
}

function httpRequestBufferOnce(urlString, { headers = {}, timeoutMs = JSON_TIMEOUT_MS, redirectsLeft = MAX_REDIRECTS, family } = {}) {
  return new Promise((resolve, reject) => {
    const transport = transportForURL(urlString);
    const request = transport.get(
      requestOptionsFor(urlString, {
        headers,
        timeoutMs,
        family,
      }),
      response => {
        const statusCode = Number(response.statusCode || 0);
        const location = String(response.headers.location || "").trim();
        if (statusCode >= 300 && statusCode < 400 && location) {
          response.resume();
          if (redirectsLeft <= 0) {
            reject(new Error("连接 Hugging Face 时发生过多重定向。"));
            return;
          }
          const redirectedURL = new URL(location, urlString).toString();
          resolve(httpRequestBuffer(redirectedURL, { headers, timeoutMs, redirectsLeft: redirectsLeft - 1 }));
          return;
        }

        const chunks = [];
        response.on("data", chunk => {
          chunks.push(chunk);
        });
        response.on("end", () => {
          const body = Buffer.concat(chunks);
          if (statusCode < 200 || statusCode >= 300) {
            reject(requestErrorFromStatus(statusCode, response.statusMessage, body.toString("utf8")));
            return;
          }
          resolve({ response, body });
        });
      },
    );
    request.on("timeout", () => {
      const timeoutError = new Error("Hugging Face 请求超时。");
      timeoutError.code = "ETIMEDOUT";
      request.destroy(timeoutError);
    });
    request.on("error", error => {
      reject(normalizedRequestError(error, urlString));
    });
  });
}

async function httpRequestBuffer(urlString, options = {}) {
  let lastError = null;
  for (let attemptIndex = 0; attemptIndex <= REQUEST_RETRY_DELAYS_MS.length; attemptIndex += 1) {
    for (const family of requestFamiliesForAttempt(attemptIndex)) {
      try {
        return await httpRequestBufferOnce(urlString, { ...options, family });
      } catch (error) {
        lastError = error;
        if (!isRetryableRequestError(error)) {
          throw error;
        }
      }
    }
    if (attemptIndex < REQUEST_RETRY_DELAYS_MS.length) {
      await sleep(REQUEST_RETRY_DELAYS_MS[attemptIndex]);
    }
  }
  throw lastError || new Error(`Hub 无法完成发往 ${huggingFaceHostLabel(urlString)} 的请求。`);
}

async function fetchJSON(urlString) {
  const { body } = await httpRequestBuffer(urlString, {
    headers: requestHeaders({ acceptsJSON: true }),
  });
  const text = body.toString("utf8").trim();
  if (!text) {
    return null;
  }
  return JSON.parse(text);
}

function siblingName(sibling) {
  return String(sibling && (sibling.rfilename || sibling.path || sibling.name) || "").trim();
}

function siblingSize(sibling) {
  const direct = Number(sibling && sibling.size || 0);
  if (Number.isFinite(direct) && direct > 0) {
    return direct;
  }
  const lfsSize = Number(sibling && sibling.lfs && sibling.lfs.size || 0);
  if (Number.isFinite(lfsSize) && lfsSize > 0) {
    return lfsSize;
  }
  return 0;
}

function normalizedTags(row) {
  const tags = [];
  if (Array.isArray(row && row.tags)) {
    tags.push(...row.tags);
  }
  if (Array.isArray(row && row.cardData && row.cardData.tags)) {
    tags.push(...row.cardData.tags);
  }
  const pipeline = String(row && (row.pipeline_tag || row.pipelineTag) || "").trim();
  if (pipeline) {
    tags.push(pipeline);
  }
  return Array.from(new Set(tags.map(tag => String(tag || "").trim()).filter(Boolean)));
}

function normalizedSiblingNames(row) {
  return (Array.isArray(row && row.siblings) ? row.siblings : [])
    .map(siblingName)
    .filter(Boolean);
}

function hasAnyTag(tags, values) {
  const normalized = new Set(tags.map(normalizeCapabilityToken));
  return values.some(value => normalized.has(normalizeCapabilityToken(value)));
}

function containsAny(haystack, values) {
  const lowered = String(haystack || "").toLowerCase();
  return values.some(value => lowered.includes(String(value).toLowerCase()));
}

function detectFormatHint(repo) {
  const repoId = normalizeRepoId(repo && (repo.id || repo.modelId || repo.modelKey));
  const tags = normalizedTags(repo);
  const siblingNames = normalizedSiblingNames(repo).map(name => name.toLowerCase());
  const owner = repoId.split("/")[0] || "";
  const hasConfig = siblingNames.includes("config.json") || siblingNames.includes("xhub_model_manifest.json");
  const hasSFT = siblingNames.some(name => name.endsWith(".safetensors") || name.endsWith(".safetensors.index.json"));
  const hasNPZ = siblingNames.includes("weights.npz") || siblingNames.some(name => name.endsWith(".npz"));

  if ((owner === "mlx-community" || hasAnyTag(tags, ["mlx"])) && (hasNPZ || hasSFT || hasConfig)) {
    return "mlx";
  }
  if (hasConfig && (hasSFT || hasNPZ)) {
    return "transformers";
  }
  return "";
}

function shouldSkipRepo(repo) {
  if (!repo || !normalizeRepoId(repo.id || repo.modelId || repo.modelKey)) {
    return true;
  }
  if (repo.private || repo.gated) {
    return true;
  }
  const tags = normalizedTags(repo);
  if (Array.from(REPO_EXCLUDE_TAGS).some(tag => hasAnyTag(tags, [tag]))) {
    return true;
  }
  return detectFormatHint(repo) === "";
}

function capabilityTagsFor(repo) {
  const repoId = normalizeRepoId(repo && (repo.id || repo.modelId || repo.modelKey));
  const title = String(repo && (repo.cardData && repo.cardData.model_name || repo.name || repo.cardData && repo.cardData.title) || "").trim();
  const summary = String(repo && (repo.cardData && (repo.cardData.summary || repo.cardData.description) || repo.description) || "").trim();
  const pipelineTag = normalizeCapabilityToken(repo && (repo.pipeline_tag || repo.pipelineTag));
  const tags = normalizedTags(repo).map(normalizeCapabilityToken);
  const haystack = `${repoId} ${title} ${summary} ${pipelineTag} ${tags.join(" ")}`.toLowerCase();
  const out = [];
  const voiceSignals = ["text-to-speech", "tts", "voice", "kokoro", "melo", "parler", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"];

  if (
    ["image-text-to-text", "image-to-text", "visual-question-answering", "document-question-answering"].includes(pipelineTag) ||
    containsAny(haystack, ["vision", "vl", "llava", "glm4v", "glm-4.6v", "qwen2-vl", "qwen3-vl", "florence", "image"])
  ) {
    out.push("Vision");
  }
  if (containsAny(haystack, ["ocr", "document"])) {
    out.push("OCR");
  }
  if (
    pipelineTag === "feature-extraction" ||
    containsAny(haystack, ["embedding", "embed", "bge", "gte"])
  ) {
    out.push("Embedding");
  }
  if (containsAny(haystack, ["coder", "coding", "code"])) {
    out.push("Coding");
  }
  if (
    pipelineTag === "text-to-speech" ||
    pipelineTag === "text-to-audio" ||
    containsAny(haystack, voiceSignals)
  ) {
    out.push("Voice");
  }
  if (
    pipelineTag === "automatic-speech-recognition" ||
    (containsAny(haystack, ["whisper", "speech", "audio", "asr"]) && !containsAny(haystack, voiceSignals))
  ) {
    out.push("Speech");
  }
  if (out.length === 0) {
    out.push("Text");
  }
  return Array.from(new Set(out)).slice(0, 3);
}

function fileIsAllowed(name, formatHint, siblingNames) {
  const lowered = String(name || "").trim().toLowerCase();
  if (!lowered || lowered.endsWith("/")) {
    return false;
  }
  if (
    lowered.endsWith(".gguf") ||
    lowered.endsWith(".onnx") ||
    lowered.endsWith(".ot") ||
    lowered.endsWith(".ckpt") ||
    lowered.endsWith(".h5") ||
    lowered.endsWith(".pth") ||
    lowered.endsWith(".pt") ||
    lowered.endsWith(".msgpack")
  ) {
    return false;
  }
  if (
    lowered.endsWith(".png") ||
    lowered.endsWith(".jpg") ||
    lowered.endsWith(".jpeg") ||
    lowered.endsWith(".gif") ||
    lowered.endsWith(".webp") ||
    lowered.endsWith(".mp4")
  ) {
    return false;
  }

  if (
    lowered.endsWith(".json") ||
    lowered.endsWith(".txt") ||
    lowered.endsWith(".model") ||
    lowered.endsWith(".tiktoken") ||
    lowered.endsWith(".jinja") ||
    lowered.endsWith(".sentencepiece") ||
    lowered.endsWith(".bpe") ||
    lowered.endsWith(".py")
  ) {
    return true;
  }

  if (lowered.endsWith(".npz")) {
    return true;
  }
  if (lowered.endsWith(".safetensors") || lowered.endsWith(".safetensors.index.json")) {
    return true;
  }

  if (lowered.endsWith(".bin")) {
    const hasSafeTensors = siblingNames.some(value => value.endsWith(".safetensors") || value.endsWith(".safetensors.index.json"));
    if (formatHint !== "transformers") {
      return false;
    }
    if (isLikelyVoiceSidecarBinary(lowered)) {
      return true;
    }
    return !hasSafeTensors;
  }

  return false;
}

function isLikelyVoiceSidecarBinary(loweredName) {
  const value = String(loweredName || "").toLowerCase();
  return [
    "voice",
    "voices",
    "speaker",
    "speakers",
    "spk",
    "style",
    "phoneme",
    "g2p",
    "lexicon",
    "espeak",
  ].some(token => value.includes(token));
}

function selectDownloadFiles(repo) {
  const formatHint = detectFormatHint(repo);
  if (!formatHint) {
    return [];
  }
  const siblings = Array.isArray(repo && repo.siblings) ? repo.siblings : [];
  const siblingNames = siblings.map(siblingName).filter(Boolean).map(name => name.toLowerCase());
  const selected = siblings
    .filter(sibling => fileIsAllowed(siblingName(sibling), formatHint, siblingNames))
    .map(sibling => ({
      name: siblingName(sibling),
      size: siblingSize(sibling),
    }));

  const hasWeights = selected.some(file =>
    file.name.toLowerCase().endsWith(".safetensors") ||
    file.name.toLowerCase().endsWith(".npz") ||
    file.name.toLowerCase().endsWith(".bin"),
  );
  const hasConfig = selected.some(file => file.name.toLowerCase() === "config.json");
  if (!hasWeights || !hasConfig) {
    return [];
  }
  return selected.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
}

function estimatedDownloadSize(files) {
  return files.reduce((sum, file) => sum + Number(file.size || 0), 0);
}

function fitEstimationForSize(totalBytes) {
  const bytes = Number(totalBytes || 0);
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return "";
  }
  const memoryBytes = Number(os.totalmem() || 0);
  if (!Number.isFinite(memoryBytes) || memoryBytes <= 0) {
    return "";
  }
  const ratio = bytes / memoryBytes;
  if (ratio <= 0.18) {
    return "fullGPUOffload";
  }
  if (ratio <= 0.33) {
    return "partialGPUOffload";
  }
  if (ratio <= 0.55) {
    return "fitWithoutGPU";
  }
  return "willNotFit";
}

function searchResultRow(repo) {
  const repoId = normalizeRepoId(repo && (repo.id || repo.modelId || repo.modelKey));
  if (!repoId || shouldSkipRepo(repo)) {
    return null;
  }

  const files = selectDownloadFiles(repo);
  if (files.length === 0) {
    return null;
  }

  const sizeBytes = estimatedDownloadSize(files);
  const fit = fitEstimationForSize(sizeBytes);
  const title = String(repo && (repo.cardData && (repo.cardData.model_name || repo.cardData.title) || repo.name) || "").trim()
    || repoDisplayTitle(repoId);
  const summary = String(repo && (repo.cardData && (repo.cardData.summary || repo.cardData.description) || repo.description) || "")
    .trim()
    .replace(/\s+/g, " ");

  return {
    modelKey: repoId,
    title,
    summary,
    formatHint: detectFormatHint(repo),
    capabilityTags: capabilityTagsFor(repo),
    staffPick: false,
    recommendationReason: "",
    recommendedForThisMac: fit !== "willNotFit",
    recommendedFitEstimation: fit,
    recommendedSizeBytes: sizeBytes,
    downloadIdentifier: repoId,
    downloads: Number(repo && repo.downloads || 0),
    likes: Number(repo && repo.likes || 0),
  };
}

function searchURLForTerm(baseURL, term, limit) {
  const url = new URL("/api/models", baseURL);
  if (String(term || "").trim()) {
    url.searchParams.set("search", String(term).trim());
  }
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("sort", "downloads");
  url.searchParams.set("direction", "-1");
  return url.toString();
}

function modelInfoURL(baseURL, repoId) {
  return `${baseURL}/api/models/${encodeRepoId(repoId)}?blobs=true`;
}

function mergeRepoInfo(baseRepo, detailedRepo) {
  return {
    ...baseRepo,
    ...detailedRepo,
    tags: Array.isArray(detailedRepo && detailedRepo.tags) && detailedRepo.tags.length > 0
      ? detailedRepo.tags
      : baseRepo && baseRepo.tags,
    siblings: Array.isArray(detailedRepo && detailedRepo.siblings) && detailedRepo.siblings.length > 0
      ? detailedRepo.siblings
      : baseRepo && baseRepo.siblings,
    cardData: detailedRepo && detailedRepo.cardData ? detailedRepo.cardData : baseRepo && baseRepo.cardData,
  };
}

async function ensureModelInfo(repo) {
  if (Array.isArray(repo && repo.siblings) && repo.siblings.length > 0) {
    return repo;
  }
  const repoId = normalizeRepoId(repo && (repo.id || repo.modelId || repo.modelKey));
  if (!repoId) {
    return repo;
  }
  try {
    const { value } = await fetchJSONAcrossBaseURLs(baseURL => modelInfoURL(baseURL, repoId));
    return value;
  } catch {
    return repo;
  }
}

async function fetchJSONAcrossBaseURLs(buildURL, { preferredBaseURL = "" } = {}) {
  let lastError = null;
  for (const baseURL of huggingFaceBaseURLs(preferredBaseURL)) {
    try {
      const value = await fetchJSON(buildURL(baseURL));
      persistStoredHuggingFaceBaseURL(baseURL);
      return { value, baseURL };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error(`Hub 无法完成发往 ${huggingFaceHostLabel()} 的请求。`);
}

async function searchModels(searchTerm, limit, category) {
  const requestedLimit = Math.max(1, Math.min(25, Number(limit) || 12));
  const trimmedSearchTerm = String(searchTerm || "").trim();
  const normalizedCategory = normalizeCapabilityToken(category);
  const focusCategory = resolvedDiscoverCategory(normalizedCategory || trimmedSearchTerm);
  const searchTerms = expandedSearchTermsFor(trimmedSearchTerm, normalizedCategory);
  const categoryTagFilter = categoryTagFilterFor(trimmedSearchTerm, normalizedCategory);
  const perQueryLimit = trimmedSearchTerm
    ? Math.max(6, Math.min(12, requestedLimit * 2))
    : Math.max(4, Math.min(10, requestedLimit));

  const searchResponses = await Promise.allSettled(
    searchTerms.map(term => fetchJSONAcrossBaseURLs(baseURL => searchURLForTerm(baseURL, term, perQueryLimit))),
  );

  const rawCandidates = [];
  let firstSearchError = null;
  for (let index = 0; index < searchResponses.length; index += 1) {
    const response = searchResponses[index];
    if (response.status === "fulfilled") {
      if (Array.isArray(response.value.value)) {
        rawCandidates.push(...response.value.value);
      }
      continue;
    }
    if (!firstSearchError) {
      firstSearchError = response.reason;
    }
  }
  if (rawCandidates.length === 0 && firstSearchError) {
    throw firstSearchError;
  }

  const deduped = [];
  const seen = new Set();
  for (const candidate of rawCandidates) {
    const repoId = normalizeRepoId(candidate && (candidate.id || candidate.modelId || candidate.modelKey));
    if (!repoId || seen.has(repoId)) {
      continue;
    }
    seen.add(repoId);
    deduped.push(candidate);
  }

  const maxCandidates = Math.min(deduped.length, Math.max(requestedLimit * DISCOVER_OVERSCAN, requestedLimit + 8));
  const targetRowCount = Math.min(maxCandidates, Math.max(requestedLimit, requestedLimit + 6));
  const candidates = deduped.slice(0, maxCandidates);
  const detailResponses = await Promise.allSettled(
    candidates.map(candidate => ensureModelInfo(candidate)),
  );

  const rows = [];
  for (let index = 0; index < candidates.length; index += 1) {
    const candidate = candidates[index];
    const response = detailResponses[index];
    const detailed = response && response.status === "fulfilled"
      ? response.value
      : candidate;
    const row = searchResultRow(mergeRepoInfo(candidate, detailed));
    if (!row) {
      continue;
    }
    if (categoryTagFilter && !row.capabilityTags.some(tag => categoryTagFilter.has(tag))) {
      continue;
    }
    rows.push(row);
    if (rows.length >= targetRowCount) {
      break;
    }
  }

  const sortedRows = rows.sort((lhs, rhs) => {
    const delta = recommendationScoreFor(rhs, primaryFocusTagFor(focusCategory)) - recommendationScoreFor(lhs, primaryFocusTagFor(focusCategory));
    if (delta !== 0) {
      return delta;
    }
    return lhs.title.localeCompare(rhs.title);
  });

  const finalRows = (!trimmedSearchTerm && !focusCategory
    ? curatedRecommendedRows(sortedRows, requestedLimit)
    : sortedRows.slice(0, requestedLimit))
    .map(({ downloads, likes, ...row }) => row);

  writeJSON({ results: finalRows });
}

function ensureDirectory(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function marketModelDirectory(repoId) {
  const { owner, model } = splitRepoId(repoId);
  return path.join(marketDirectory(), owner, model);
}

function marketMetadata(repo, files) {
  const repoId = normalizeRepoId(repo && (repo.id || repo.modelId || repo.modelKey));
  const { owner, model } = splitRepoId(repoId);
  return {
    modelKey: repoId,
    owner,
    model,
    title: String(repo && (repo.cardData && (repo.cardData.model_name || repo.cardData.title) || repo.name) || "").trim() || repoDisplayTitle(repoId),
    summary: String(repo && (repo.cardData && (repo.cardData.summary || repo.cardData.description) || repo.description) || "").trim(),
    formatHint: detectFormatHint(repo),
    capabilityTags: capabilityTagsFor(repo),
    recommendedSizeBytes: estimatedDownloadSize(files),
    downloadedAt: Date.now(),
  };
}

function writeMarketMetadata(targetDirectory, repo, files) {
  const metadataPath = path.join(targetDirectory, MARKET_METADATA_FILE);
  const payload = JSON.stringify(marketMetadata(repo, files), null, 2);
  fs.writeFileSync(metadataPath, payload);
}

function fileAlreadyReady(destinationPath, expectedSize) {
  try {
    const stats = fs.statSync(destinationPath);
    if (!stats.isFile()) {
      return false;
    }
    const expected = Number(expectedSize || 0);
    if (expected > 0) {
      return stats.size === expected;
    }
    return stats.size > 0;
  } catch {
    return false;
  }
}

function resolveDownloadURL(baseURL, repoId, fileName) {
  return `${baseURL}/${encodeRepoId(repoId)}/resolve/${DEFAULT_BRANCH}/${encodeRepoFilePath(fileName)}?download=true`;
}

function downloadFileOnce(urlString, destinationPath, { onChunk, timeoutMs = DOWNLOAD_TIMEOUT_MS, redirectsLeft = MAX_REDIRECTS, family } = {}) {
  return new Promise((resolve, reject) => {
    const transport = transportForURL(urlString);
    const request = transport.get(
      requestOptionsFor(urlString, {
        headers: requestHeaders(),
        timeoutMs,
        family,
      }),
      response => {
        const statusCode = Number(response.statusCode || 0);
        const location = String(response.headers.location || "").trim();
        if (statusCode >= 300 && statusCode < 400 && location) {
          response.resume();
          if (redirectsLeft <= 0) {
            reject(new Error("从 Hugging Face 下载时发生过多重定向。"));
            return;
          }
          const redirectedURL = new URL(location, urlString).toString();
          resolve(downloadFile(redirectedURL, destinationPath, { onChunk, timeoutMs, redirectsLeft: redirectsLeft - 1 }));
          return;
        }

        if (statusCode < 200 || statusCode >= 300) {
          const chunks = [];
          response.on("data", chunk => chunks.push(chunk));
          response.on("end", () => {
            reject(requestErrorFromStatus(statusCode, response.statusMessage, Buffer.concat(chunks).toString("utf8")));
          });
          return;
        }

        ensureDirectory(path.dirname(destinationPath));
        const fileStream = fs.createWriteStream(destinationPath);
        let failed = false;

        const fail = error => {
          if (failed) {
            return;
          }
          failed = true;
          try {
            fileStream.close();
          } catch {}
          try {
            fs.unlinkSync(destinationPath);
          } catch {}
          reject(error);
        };

        response.on("data", chunk => {
          if (typeof onChunk === "function") {
            onChunk(chunk.length);
          }
        });
        response.on("error", fail);
        fileStream.on("error", fail);
        fileStream.on("finish", () => {
          fileStream.close(error => {
            if (error) {
              fail(error);
              return;
            }
            resolve();
          });
        });

        response.pipe(fileStream);
      },
    );
    request.on("timeout", () => {
      const timeoutError = new Error("Hugging Face 下载超时。");
      timeoutError.code = "ETIMEDOUT";
      request.destroy(timeoutError);
    });
    request.on("error", error => {
      reject(normalizedRequestError(error, urlString));
    });
  });
}

async function downloadFile(urlString, destinationPath, options = {}) {
  let lastError = null;
  for (let attemptIndex = 0; attemptIndex <= REQUEST_RETRY_DELAYS_MS.length; attemptIndex += 1) {
    for (const family of requestFamiliesForAttempt(attemptIndex)) {
      try {
        await downloadFileOnce(urlString, destinationPath, { ...options, family });
        return;
      } catch (error) {
        lastError = error;
        if (!isRetryableRequestError(error)) {
          throw error;
        }
      }
    }
    if (attemptIndex < REQUEST_RETRY_DELAYS_MS.length) {
      await sleep(REQUEST_RETRY_DELAYS_MS[attemptIndex]);
    }
  }
  throw lastError || new Error(`Hub 无法完成从 ${huggingFaceHostLabel(urlString)} 的下载。`);
}

async function downloadFileAcrossBaseURLs(repoId, fileName, destinationPath, options = {}) {
  const preferredBaseURL = normalizedBaseURL(options.preferredBaseURL || "");
  let lastError = null;
  for (const baseURL of huggingFaceBaseURLs(preferredBaseURL)) {
    try {
      await downloadFile(resolveDownloadURL(baseURL, repoId, fileName), destinationPath, options);
      persistStoredHuggingFaceBaseURL(baseURL);
      return;
    } catch (error) {
      lastError = error;
      try {
        fs.unlinkSync(destinationPath);
      } catch {}
    }
  }
  throw lastError || new Error(`Hub 无法完成从 ${huggingFaceHostLabel()} 的下载。`);
}

async function downloadModel(modelKey, wantedDownloadIdentifier) {
  const repoId = normalizeRepoId(wantedDownloadIdentifier || modelKey);
  if (!repoId) {
    throw new Error("缺少模型 key。");
  }

  const { value: repo, baseURL: resolvedBaseURL } = await fetchJSONAcrossBaseURLs(
    baseURL => modelInfoURL(baseURL, repoId),
  );
  if (repo.private || repo.gated) {
    throw new Error("这个 Hugging Face 模型需要身份验证。请设置 HF_TOKEN 后重试。");
  }

  const files = selectDownloadFiles(repo);
  if (files.length === 0) {
    throw new Error(`没有为 ${repoId} 找到受支持的本地模型文件。`);
  }

  const totalBytes = estimatedDownloadSize(files);
  let downloadedBytes = 0;
  const startedAt = Date.now();
  const targetDirectory = marketModelDirectory(repoId);
  ensureDirectory(targetDirectory);

  writeJSON({ type: "status", message: "Starting download..." });

  for (const file of files) {
    const destinationPath = path.join(targetDirectory, file.name);
    if (fileAlreadyReady(destinationPath, file.size)) {
      downloadedBytes += Number(file.size || 0);
      continue;
    }

    const partialPath = `${destinationPath}.part`;
    try {
      fs.unlinkSync(partialPath);
    } catch {}

    await downloadFileAcrossBaseURLs(repoId, file.name, partialPath, {
      preferredBaseURL: resolvedBaseURL,
      onChunk(chunkBytes) {
        downloadedBytes += Number(chunkBytes || 0);
        const elapsedSeconds = Math.max(1, (Date.now() - startedAt) / 1000);
        const speedBytesPerSecond = downloadedBytes / elapsedSeconds;
        writeJSON({
          type: "progress",
          message: progressMessage(downloadedBytes, totalBytes, speedBytesPerSecond),
          downloadedBytes,
          totalBytes,
          speedBytesPerSecond,
        });
      },
    });

    fs.renameSync(partialPath, destinationPath);
  }

  writeMarketMetadata(targetDirectory, { ...repo, id: repoId }, files);
  writeJSON({ type: "finalizing", message: "Finalizing model files..." });
  writeJSON({ type: "success", defaultIdentifier: repoId });
}

async function main() {
  const [, , command, arg1 = "", arg2 = "", arg3 = ""] = process.argv;
  if (command === "search") {
    await searchModels(arg1, arg2, arg3);
    return;
  }
  if (command === "download") {
    await downloadModel(arg1, arg2);
    return;
  }
  throw new Error(`Unsupported command: ${command || "(missing)"}`);
}

main().catch(error => {
  const message = String(error && error.message || "").trim()
    || String(error && error.stack || "").trim()
    || "Unexpected helper failure.";
  writeJSON(
    {
      type: "error",
      message,
    },
    process.stderr,
  );
  process.exitCode = 1;
});
