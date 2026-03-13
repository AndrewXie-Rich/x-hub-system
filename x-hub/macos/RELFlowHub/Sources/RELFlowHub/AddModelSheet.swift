import AppKit
import SwiftUI
import RELFlowHubCore

private enum LocalBackendOption: String, CaseIterable, Identifiable {
    case mlx
    case transformers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mlx:
            return "MLX"
        case .transformers:
            return "Transformers"
        }
    }
}

private struct DetectedLocalModelMetadata {
    var modelFormat: String
    var taskKinds: [String]
    var inputModalities: [String]
    var outputModalities: [String]
    var offlineReady: Bool
    var resourceProfile: ModelResourceProfile
    var trustProfile: ModelTrustProfile
    var processorRequirements: ModelProcessorRequirements
    var sourceSummary: String

    static func defaults(backend: String, quant: String = "", paramsB: Double = 0.0) -> DetectedLocalModelMetadata {
        let defaultTaskKinds = LocalModelCapabilityDefaults.defaultTaskKinds(forBackend: backend)
        let modelFormat = LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
        return DetectedLocalModelMetadata(
            modelFormat: modelFormat,
            taskKinds: defaultTaskKinds,
            inputModalities: LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: defaultTaskKinds),
            outputModalities: LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: defaultTaskKinds),
            offlineReady: LocalModelCapabilityDefaults.defaultOfflineReady(backend: backend, modelPath: "/local"),
            resourceProfile: LocalModelCapabilityDefaults.defaultResourceProfile(backend: backend, quant: quant, paramsB: paramsB),
            trustProfile: LocalModelCapabilityDefaults.defaultTrustProfile(),
            processorRequirements: LocalModelCapabilityDefaults.defaultProcessorRequirements(
                backend: backend,
                modelFormat: modelFormat,
                taskKinds: defaultTaskKinds
            ),
            sourceSummary: "inferred"
        )
    }
}

@MainActor
struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var backend: LocalBackendOption = .mlx
    @State private var modelPath: String = ""
    @State private var modelId: String = ""
    @State private var modelName: String = ""
    @State private var quant: String = ""
    @State private var ctx: Int = 8192
    @State private var paramsBText: String = ""
    @State private var role: String = "general"
    @State private var extraRolesText: String = ""
    @State private var showAdvanced: Bool = false
    @State private var errorText: String = ""
    @State private var isAdding: Bool = false
    @State private var progressText: String = ""
    @State private var detectedMetadata: DetectedLocalModelMetadata = .defaults(backend: "mlx")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Model")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Backend", selection: $backend) {
                            ForEach(LocalBackendOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Select Folder…") {
                                pickFolder()
                            }

                            Text(modelPath.isEmpty ? "No folder selected" : modelPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                HStack {
                    TextField("Model ID", text: $modelId)
                    TextField("Name", text: $modelName)
                }

                HStack(spacing: 10) {
                    Text("Detected: \(backend.title) · \(detectedMetadata.modelFormat) · \(taskSummary())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(showAdvanced ? "Hide Advanced" : "Advanced...") {
                        showAdvanced.toggle()
                    }
                    .buttonStyle(.link)
                }

                HStack(spacing: 10) {
                    Text("Resources: \(quantText()) · ctx \(ctx) · \(paramsText()) · \(detectedMetadata.resourceProfile.preferredDevice)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("Source: \(detectedMetadata.sourceSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if showAdvanced {
                    HStack {
                        TextField("Quant (e.g. int4/bf16/fp16)", text: $quant)
                        Stepper("ctx \(ctx)", value: $ctx, in: 512...131072, step: 512)
                    }

                    TextField("ParamsB (e.g. 8.0)", text: $paramsBText)
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Role")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Role", selection: $role) {
                            Text("General").tag("general")
                            Text("Translate").tag("translate")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra Roles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("comma-separated", text: $extraRolesText)
                    }
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isAdding {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressText.isEmpty ? "Working..." : progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    Task { @MainActor in
                        await addModelAsync()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAdding || modelPath.isEmpty || modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onChange(of: backend) { _ in
            guard !modelPath.isEmpty else { return }
            detectMetadata(for: URL(fileURLWithPath: modelPath, isDirectory: true))
        }
    }

    private func pickFolder() {
        if isAdding {
            return
        }
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Select"
        if p.runModal() == .OK, let url = p.url {
            modelPath = url.path

            let folder = url.lastPathComponent
            if modelName.isEmpty { modelName = folder }
            if modelId.isEmpty { modelId = sanitizeId(folder) }

            detectMetadata(for: url)
        }
    }

    private func detectMetadata(for url: URL) {
        errorText = ""
        let folder = url.lastPathComponent
        let config = readConfigJSON(dir: url)
        let manifest = XHubLocalModelManifestLoader.load(from: url)

        if let manifest,
           let manifestBackend = LocalBackendOption(rawValue: manifest.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
           manifestBackend != backend {
            backend = manifestBackend
            return
        }

        if let c = detectContextLength(config: config), c > 0 {
            ctx = c
        } else {
            ctx = 8192
        }

        if quant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quant = detectQuant(folder: folder, config: config)
        }

        if paramsBText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let pb = detectParamsB(folder: folder, dir: url, quant: quant),
           pb > 0 {
            paramsBText = String(format: "%.1f", pb)
        }

        let pb = Double(paramsBText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let resolved = resolveMetadata(for: url, config: config, paramsB: pb, surfaceErrors: false)
        if let metadata = resolved.metadata {
            detectedMetadata = metadata
        } else if let error = resolved.error {
            detectedMetadata = DetectedLocalModelMetadata.defaults(
                backend: backend.rawValue,
                quant: quant,
                paramsB: pb
            )
            errorText = error
        }
    }

    private func readConfigJSON(dir: URL) -> [String: Any]? {
        let p = dir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj as? [String: Any]
    }

    private func detectContextLength(config: [String: Any]?) -> Int? {
        guard let c = config else { return nil }
        let keys = [
            "max_position_embeddings",
            "model_max_length",
            "n_positions",
            "seq_length",
            "max_seq_len",
        ]
        for k in keys {
            if let v = c[k] as? Int { return v }
            if let v = c[k] as? Double { return Int(v) }
            if let v = c[k] as? String, let i = Int(v) { return i }
        }
        return nil
    }

    private func detectQuant(folder: String, config: [String: Any]?) -> String {
        if let c = config, let td = c["torch_dtype"] as? String {
            let s = td.lowercased()
            if s.contains("bfloat16") { return "bf16" }
            if s.contains("float16") { return "fp16" }
            if s.contains("float32") { return "fp32" }
        }
        return inferQuant(folder)
    }

    private func detectParamsB(folder: String, dir: URL, quant: String) -> Double? {
        do {
            let s = folder
            let r = try NSRegularExpression(pattern: "(?i)(\\d+(?:\\.\\d+)?)\\s*b")
            if let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let rr = Range(m.range(at: 1), in: s) {
                return Double(String(s[rr]))
            }
        } catch {
            // ignore
        }

        let bpp: Double
        let q = quant.lowercased()
        if q.contains("int4") || q == "4" {
            bpp = 0.5
        } else if q.contains("int8") || q == "8" {
            bpp = 1.0
        } else if q.contains("bf16") || q.contains("fp16") {
            bpp = 2.0
        } else {
            bpp = 2.0
        }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for u in files {
            let ext = u.pathExtension.lowercased()
            if ext == "safetensors" || (ext == "npz" && u.lastPathComponent == "weights.npz") {
                if let sz = try? u.resourceValues(forKeys: keys).fileSize {
                    total += Int64(sz)
                }
            }
        }
        if total <= 0 { return nil }
        let params = Double(total) / max(0.1, bpp)
        return params / 1_000_000_000.0
    }

    private func inferQuant(_ name: String) -> String {
        let s = name.lowercased()
        if s.contains("int4") || s.contains("4bit") || s.contains("_4") { return "int4" }
        if s.contains("int8") || s.contains("8bit") || s.contains("_8") { return "int8" }
        if s.contains("bf16") { return "bf16" }
        if s.contains("fp16") { return "fp16" }
        return backend == .mlx ? "int4" : "fp16"
    }

    private func taskSummary() -> String {
        let taskKinds = detectedMetadata.taskKinds.isEmpty ? ["unknown"] : detectedMetadata.taskKinds
        return taskKinds.joined(separator: ", ")
    }

    private func quantText() -> String {
        let q = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "(quant unknown)" : q
    }

    private func paramsText() -> String {
        let s = paramsBText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Double(s), v > 0 {
            return String(format: "%.1fB", v)
        }
        return "paramsB unknown"
    }

    private func sanitizeId(_ s: String) -> String {
        let ok = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".map { $0 })
        let low = s.lowercased()
        var out = ""
        for ch in low {
            if ok.contains(ch) {
                out.append(ch)
            } else if ch == " " {
                out.append("_")
            }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }

    private func resolveMetadata(
        for url: URL,
        config: [String: Any]?,
        paramsB: Double,
        surfaceErrors: Bool
    ) -> (metadata: DetectedLocalModelMetadata?, error: String?) {
        let manifest = XHubLocalModelManifestLoader.load(from: url)
        let normalizedBackend = (manifest?.backend ?? backend.rawValue).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedBackend == LocalBackendOption.mlx.rawValue || normalizedBackend == LocalBackendOption.transformers.rawValue else {
            return (nil, "Unsupported local backend '\(normalizedBackend)'. v1 only accepts MLX or Transformers.")
        }

        if normalizedBackend == LocalBackendOption.mlx.rawValue {
            let cfg = url.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: cfg.path) else {
                return (nil, "Selected folder is not a valid MLX model folder (missing config.json).")
            }
            return (
                DetectedLocalModelMetadata(
                    modelFormat: manifest?.modelFormat ?? "mlx",
                    taskKinds: manifest?.taskKinds ?? ["text_generate"],
                    inputModalities: manifest?.inputModalities ?? ["text"],
                    outputModalities: manifest?.outputModalities ?? ["text"],
                    offlineReady: manifest?.offlineReady ?? true,
                    resourceProfile: manifest?.resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
                        backend: normalizedBackend,
                        quant: quant,
                        paramsB: paramsB
                    ),
                    trustProfile: manifest?.trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile(),
                    processorRequirements: manifest?.processorRequirements ?? ModelProcessorRequirements(
                        tokenizerRequired: true,
                        processorRequired: false,
                        featureExtractorRequired: false
                    ),
                    sourceSummary: manifest == nil ? "inferred" : XHubLocalModelManifestLoader.fileName
                ),
                nil
            )
        }

        let cfg = url.appendingPathComponent("config.json")
        guard manifest != nil || FileManager.default.fileExists(atPath: cfg.path) else {
            return (nil, "Transformers import requires config.json or xhub_model_manifest.json in the selected folder.")
        }

        if let manifest {
            return (
                DetectedLocalModelMetadata(
                    modelFormat: manifest.modelFormat,
                    taskKinds: manifest.taskKinds,
                    inputModalities: manifest.inputModalities,
                    outputModalities: manifest.outputModalities,
                    offlineReady: manifest.offlineReady,
                    resourceProfile: manifest.resourceProfile,
                    trustProfile: manifest.trustProfile,
                    processorRequirements: manifest.processorRequirements,
                    sourceSummary: XHubLocalModelManifestLoader.fileName
                ),
                nil
            )
        }

        guard let inferred = inferTransformersMetadata(folder: url.lastPathComponent, config: config, paramsB: paramsB) else {
            let msg = "Transformers folder is missing xhub_model_manifest.json, and task kind could not be inferred from config.json. Add a manifest to declare embedding / speech_to_text / vision_understand / ocr."
            return (nil, msg)
        }
        return (inferred, nil)
    }

    private func inferTransformersMetadata(
        folder: String,
        config: [String: Any]?,
        paramsB: Double
    ) -> DetectedLocalModelMetadata? {
        let architectures = ((config?["architectures"] as? [String]) ?? []).joined(separator: " ").lowercased()
        let modelType = (config?["model_type"] as? String ?? "").lowercased()
        let nameSignal = folder.lowercased()
        let haystack = [architectures, modelType, nameSignal].joined(separator: " ")

        let modelFormat = "hf_transformers"
        let trustProfile = LocalModelCapabilityDefaults.defaultTrustProfile()
        let baseProfile = LocalModelCapabilityDefaults.defaultResourceProfile(
            backend: LocalBackendOption.transformers.rawValue,
            quant: quant,
            paramsB: paramsB
        )

        if containsAny(haystack, keywords: ["whisper", "wav2vec", "hubert", "speech", "asr", "ctc"]) {
            return DetectedLocalModelMetadata(
                modelFormat: modelFormat,
                taskKinds: ["speech_to_text"],
                inputModalities: ["audio"],
                outputModalities: ["text", "segments"],
                offlineReady: true,
                resourceProfile: baseProfile,
                trustProfile: trustProfile,
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: false,
                    processorRequired: true,
                    featureExtractorRequired: true
                ),
                sourceSummary: "inferred: config/audio"
            )
        }

        if containsAny(haystack, keywords: ["trocr", "donut", "ocr"]) {
            return DetectedLocalModelMetadata(
                modelFormat: modelFormat,
                taskKinds: ["ocr"],
                inputModalities: ["image"],
                outputModalities: ["text", "spans"],
                offlineReady: true,
                resourceProfile: baseProfile,
                trustProfile: trustProfile,
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: true,
                    featureExtractorRequired: true
                ),
                sourceSummary: "inferred: config/ocr"
            )
        }

        if containsAny(haystack, keywords: ["llava", "blip", "siglip", "clip", "florence", "pix2struct", "vision"]) {
            return DetectedLocalModelMetadata(
                modelFormat: modelFormat,
                taskKinds: ["vision_understand"],
                inputModalities: ["image"],
                outputModalities: ["text"],
                offlineReady: true,
                resourceProfile: baseProfile,
                trustProfile: trustProfile,
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: true,
                    featureExtractorRequired: true
                ),
                sourceSummary: "inferred: config/vision"
            )
        }

        if containsAny(haystack, keywords: ["bge", "gte", "e5", "mpnet", "sentence", "jina", "embed"]) {
            return DetectedLocalModelMetadata(
                modelFormat: modelFormat,
                taskKinds: ["embedding"],
                inputModalities: ["text"],
                outputModalities: ["embedding"],
                offlineReady: true,
                resourceProfile: baseProfile,
                trustProfile: trustProfile,
                processorRequirements: ModelProcessorRequirements(
                    tokenizerRequired: true,
                    processorRequired: false,
                    featureExtractorRequired: false
                ),
                sourceSummary: "inferred: config/embedding"
            )
        }

        return nil
    }

    private func containsAny(_ haystack: String, keywords: [String]) -> Bool {
        keywords.contains { haystack.contains($0) }
    }

    private func validateAndBuildEntry() -> ModelCatalogEntry? {
        errorText = ""
        let id = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            errorText = "Model ID is required."
            return nil
        }
        if modelPath.isEmpty {
            errorText = "Please select a model folder."
            return nil
        }

        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        let pb = Double(paramsBText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let modelURL = URL(fileURLWithPath: modelPath, isDirectory: true)
        let config = readConfigJSON(dir: modelURL)
        let resolved: DetectedLocalModelMetadata
        let result = resolveMetadata(for: modelURL, config: config, paramsB: pb, surfaceErrors: true)
        if let metadata = result.metadata {
            resolved = metadata
        } else {
            let error = result.error ?? "Model capabilities could not be resolved."
            errorText = error
            return nil
        }

        if resolved.taskKinds.isEmpty {
            errorText = "Model capabilities could not be determined. Add xhub_model_manifest.json with task_kinds/input_modalities/output_modalities."
            return nil
        }

        var roles: [String] = []
        let baseRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseRole.isEmpty {
            roles.append(baseRole)
        }
        let extra = extraRolesText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        roles.append(contentsOf: extra)

        var uniq: [String] = []
        var seen: Set<String> = []
        for r in roles {
            if seen.contains(r) { continue }
            seen.insert(r)
            uniq.append(r)
        }

        return ModelCatalogEntry(
            id: id,
            name: name.isEmpty ? id : name,
            backend: backend.rawValue,
            quant: q.isEmpty ? inferQuant(modelURL.lastPathComponent) : q,
            contextLength: max(512, ctx),
            paramsB: max(0.0, pb),
            modelPath: modelPath,
            roles: uniq,
            note: "catalog",
            modelFormat: resolved.modelFormat,
            taskKinds: resolved.taskKinds,
            inputModalities: resolved.inputModalities,
            outputModalities: resolved.outputModalities,
            offlineReady: resolved.offlineReady,
            resourceProfile: resolved.resourceProfile,
            trustProfile: resolved.trustProfile,
            processorRequirements: resolved.processorRequirements
        )
    }

    private func addModelAsync() async {
        if isAdding { return }
        isAdding = true
        progressText = "Preparing..."
        defer {
            isAdding = false
            progressText = ""
        }

        guard var entry = validateAndBuildEntry() else {
            return
        }

        if SharedPaths.isSandboxedProcess() {
            progressText = "Importing model into Hub storage..."
            let base = SharedPaths.ensureHubDirectory()
            let dst = base.appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(entry.id, isDirectory: true)
            let src = URL(fileURLWithPath: entry.modelPath, isDirectory: true)

            var accessed = false
            if src.startAccessingSecurityScopedResource() {
                accessed = true
            }
            defer {
                if accessed {
                    src.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dst.path) {
                        try fm.removeItem(at: dst)
                    }
                    try fm.copyItem(at: src, to: dst)
                }.value
                entry.modelPath = dst.path
                entry.note = "managed_copy"
            } catch {
                errorText = "Model import failed (sandbox).\n\n\(error.localizedDescription)"
                return
            }
        }

        progressText = "Saving..."
        var cat = ModelCatalogStorage.load()
        if let idx = cat.models.firstIndex(where: { $0.id == entry.id }) {
            cat.models[idx] = entry
        } else {
            cat.models.append(entry)
        }
        ModelCatalogStorage.save(cat)
        ModelStore.shared.upsertCatalogModel(entry)

        dismiss()
    }
}
