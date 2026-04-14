import AppKit
import SwiftUI
import RELFlowHubCore

private enum LocalBackendOption: String {
    case mlx
    case transformers
    case llamaCpp = "llama.cpp"

    var title: String {
        switch self {
        case .mlx:
            return HubUIStrings.Models.AddLocal.backendTitle(rawValue)
        case .transformers:
            return HubUIStrings.Models.AddLocal.backendTitle(rawValue)
        case .llamaCpp:
            return HubUIStrings.Models.AddLocal.backendTitle(rawValue)
        }
    }
}

private struct DetectedLocalModelMetadata {
    var modelFormat: String
    var maxContextLength: Int?
    var defaultLoadProfile: LocalModelLoadProfile?
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
            maxContextLength: nil,
            defaultLoadProfile: nil,
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

    @State private var autoDetectedBackend: LocalBackendOption = .mlx
    @State private var autoDetectedRuntimeProviderID: String = ""
    @State private var backendDetectionSource: String = "backend default"
    @State private var modelPath: String = ""
    @State private var modelId: String = ""
    @State private var modelName: String = ""
    @State private var quant: String = ""
    @State private var ctx: Int = 8192
    @State private var paramsBText: String = ""
    @State private var showAdvanced: Bool = false
    @State private var errorText: String = ""
    @State private var warningText: String = ""
    @State private var isAdding: Bool = false
    @State private var progressText: String = ""
    @State private var detectedMetadata: DetectedLocalModelMetadata = .defaults(backend: "mlx")
    @State private var importRuntimeReadiness: LocalModelImportRuntimeReadiness = .empty(providerID: "mlx")
    @State private var folderIntegrityIssue: LocalModelFolderIntegrityIssue?

    private var resolvedBackend: LocalBackendOption {
        autoDetectedBackend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddLocal.title)
                        .font(.headline)
                    Text(HubUIStrings.Models.AddLocal.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isAdding {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progressText.isEmpty ? HubUIStrings.Models.AddLocal.processing : progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    folderCard
                    identityCard
                    readinessCard

                    if !errorText.isEmpty {
                        issueBanner(errorText, tint: .red)
                    }

                    if !warningText.isEmpty {
                        issueBanner(warningText, tint: .orange)
                    }

                    if showAdvanced {
                        advancedCard
                    }
                }
                .padding(.bottom, 6)
            }

            HStack(spacing: 10) {
                Button(showAdvanced ? HubUIStrings.Models.AddLocal.hideAdvanced : HubUIStrings.Models.AddLocal.showAdvanced) {
                    showAdvanced.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()

                Button(HubUIStrings.Models.AddLocal.cancel) {
                    dismiss()
                }

                Button(HubUIStrings.Models.AddLocal.add) {
                    Task { @MainActor in
                        await addModelAsync()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAdding || modelPath.isEmpty || modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 620, height: 660)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                summaryPill(HubUIStrings.Models.AddLocal.format, value: "\(resolvedBackend.title) · \(detectedMetadata.modelFormat)", tint: .blue)
                summaryPill(HubUIStrings.Models.AddLocal.runtime, value: executionSummary(), tint: importRuntimeReadiness.canLoadNow ? .green : .orange)
                summaryPill(HubUIStrings.Models.AddLocal.directory, value: folderStatusSummary(), tint: folderIntegrityIssue == nil ? .green : .orange)
            }

            HStack(spacing: 6) {
                ForEach(summaryTags(), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            Text(HubUIStrings.Models.AddLocal.resourceSummary(context: ctx, quant: quantText(), params: paramsText(), preferredDevice: detectedMetadata.resourceProfile.preferredDevice))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(HubUIStrings.Models.AddLocal.folderSection)
                        .font(.subheadline.weight(.semibold))
                    Text(modelPath.isEmpty ? HubUIStrings.Models.AddLocal.folderHint : folderPathSummary())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(HubUIStrings.Models.AddLocal.chooseDirectory) {
                    pickFolder()
                }
            }

            if !modelPath.isEmpty {
                Text(modelPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HubUIStrings.Models.AddLocal.identitySection)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddLocal.modelID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(HubUIStrings.Models.AddLocal.modelIDPlaceholder, text: $modelId)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddLocal.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(HubUIStrings.Models.AddLocal.displayNamePlaceholder, text: $modelName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HubUIStrings.Models.AddLocal.readinessSection)
                .font(.subheadline.weight(.semibold))

            keyValueRow(label: HubUIStrings.Models.AddLocal.task, value: taskSummary())
            keyValueRow(label: HubUIStrings.Models.AddLocal.runtime, value: executionSummary())
            keyValueRow(label: HubUIStrings.Models.AddLocal.source, value: detectionSourceSummary())

            if !importRuntimeReadiness.statusSummary.isEmpty {
                keyValueRow(
                    label: HubUIStrings.Models.AddLocal.runtime,
                    value: importRuntimeReadiness.statusSummary,
                    tint: importRuntimeReadiness.canLoadNow ? .secondary : .orange
                )
            }

            if let folderIntegrityIssue {
                keyValueRow(label: HubUIStrings.Models.AddLocal.directory, value: folderIntegrityIssue.userMessage, tint: .orange)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HubUIStrings.Models.AddLocal.advancedSection)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddLocal.quant)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(HubUIStrings.Models.AddLocal.quantPlaceholder, text: $quant)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(HubUIStrings.Models.AddLocal.context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(HubUIStrings.Models.AddLocal.contextStepper(ctx), value: $ctx, in: 512...131072, step: 512)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(HubUIStrings.Models.AddLocal.paramsB)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(HubUIStrings.Models.AddLocal.paramsBPlaceholder, text: $paramsBText)
                    .textFieldStyle(.roundedBorder)
            }

            Text(HubUIStrings.Models.AddLocal.runtimeEngine(technicalRuntimeProviderSummary()))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func summaryPill(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func keyValueRow(label: String, value: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private func issueBanner(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryTags() -> [String] {
        var tags: [String] = []
        tags.append(contentsOf: detectedMetadata.taskKinds.map { LocalTaskRoutingCatalog.shortTitle(for: $0) })
        tags.append(contentsOf: detectedMetadata.inputModalities.prefix(2).map(HubUIStrings.Models.AddLocal.inputTag))
        tags.append(contentsOf: detectedMetadata.outputModalities.prefix(2).map(HubUIStrings.Models.AddLocal.outputTag))
        return Array(NSOrderedSet(array: tags)) as? [String] ?? tags
    }

    private func folderPathSummary() -> String {
        URL(fileURLWithPath: modelPath).lastPathComponent
    }

    private func pickFolder() {
        if isAdding {
            return
        }
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = HubUIStrings.Models.AddLocal.choosePrompt
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
        warningText = ""
        autoDetectedRuntimeProviderID = ""
        folderIntegrityIssue = LocalModelFolderIntegrityPolicy.issue(modelPath: url.path)
        let folder = url.lastPathComponent
        let config = readConfigJSON(dir: url)
        let manifest = XHubLocalModelManifestLoader.load(from: url)
        let backendDetection = LocalModelImportDetector.detectBackend(
            for: url,
            manifest: manifest,
            config: config
        )
        if let detectedBackend = LocalBackendOption(rawValue: backendDetection.backend) {
            autoDetectedBackend = detectedBackend
        }
        backendDetectionSource = backendDetection.sourceSummary

        if let manifestDefaultContext = manifest?.defaultLoadProfile?.contextLength, manifestDefaultContext > 0 {
            ctx = manifestDefaultContext
        } else if let c = detectContextLength(config: config), c > 0 {
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
            let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()
            let runtimeProviderID = resolvedRuntimeProviderID(
                backend: resolvedBackend.rawValue,
                modelPath: url.path,
                taskKinds: metadata.taskKinds,
                helperBinaryPath: helperBinaryPath
            )
            autoDetectedRuntimeProviderID = runtimeProviderID
            let effectiveProviderID = runtimeProviderID.isEmpty ? resolvedBackend.rawValue : runtimeProviderID
            let previewCatalog = previewCatalogSnapshot(
                modelURL: url,
                backend: resolvedBackend.rawValue,
                runtimeProviderID: effectiveProviderID,
                quant: quant,
                contextLength: ctx,
                paramsB: pb,
                metadata: metadata
            )
            let runtimeStatus = AIRuntimeStatusStorage.load()
            let importWarning = LocalModelRuntimeCompatibilityPolicy.importWarning(
                modelPath: url.path,
                backend: resolvedBackend.rawValue,
                taskKinds: metadata.taskKinds,
                executionProviderID: effectiveProviderID,
                catalogSnapshot: previewCatalog,
                helperBinaryPath: helperBinaryPath,
                probeLaunchConfig: HubStore.shared.localRuntimePythonProbeLaunchConfig(
                    preferredProviderID: effectiveProviderID
                ),
                pythonPath: HubStore.shared.preferredLocalProviderPythonPath(
                    preferredProviderID: effectiveProviderID
                )
            ) ?? ""
            let providerHint = (HubStore.shared.aiRuntimeProviderHelpTextByProvider[effectiveProviderID] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            importRuntimeReadiness = LocalModelImportDetector.detectRuntimeReadiness(
                for: effectiveProviderID,
                runtimeStatus: runtimeStatus,
                importWarning: importWarning,
                providerHint: providerHint,
                autoRecoveryAvailable: HubStore.shared.canAutoRecoverRuntime(
                    for: effectiveProviderID,
                    runtimeStatus: runtimeStatus
                )
            )
            warningText = visibleIssueText(
                from: importRuntimeReadiness.issueText,
                folderIntegrityIssue: folderIntegrityIssue
            )
        } else if let error = resolved.error {
            detectedMetadata = DetectedLocalModelMetadata.defaults(
                backend: resolvedBackend.rawValue,
                quant: quant,
                paramsB: pb
            )
            autoDetectedRuntimeProviderID = ""
            importRuntimeReadiness = .empty(providerID: resolvedBackend.rawValue)
            folderIntegrityIssue = LocalModelFolderIntegrityPolicy.issue(modelPath: url.path)
            errorText = error
        }
    }

    private func resolvedRuntimeProviderID(
        backend: String,
        modelPath: String,
        taskKinds: [String],
        helperBinaryPath: String
    ) -> String {
        LocalModelExecutionProviderResolver.suggestedRuntimeProviderID(
            backend: backend,
            modelPath: modelPath,
            taskKinds: taskKinds,
            helperBinaryPath: helperBinaryPath
        ) ?? ""
    }

    private func previewCatalogSnapshot(
        modelURL: URL,
        backend: String,
        runtimeProviderID: String,
        quant: String,
        contextLength: Int,
        paramsB: Double,
        metadata: DetectedLocalModelMetadata
    ) -> ModelCatalogSnapshot {
        var catalog = ModelCatalogStorage.load()
        let normalizedModelPath = modelURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        catalog.models.removeAll {
            $0.modelPath.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedModelPath
        }

        let normalizedBackend = backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRuntimeProviderID = runtimeProviderID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let explicitRuntimeProviderID: String? =
            normalizedRuntimeProviderID.isEmpty || normalizedRuntimeProviderID == normalizedBackend
            ? nil
            : normalizedRuntimeProviderID
        let candidateID = modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "preview-\(modelURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            : modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? modelURL.lastPathComponent
            : modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        catalog.models.append(
            ModelCatalogEntry(
                id: candidateID,
                name: candidateName,
                backend: normalizedBackend,
                runtimeProviderID: explicitRuntimeProviderID,
                quant: quant,
                contextLength: contextLength,
                maxContextLength: metadata.maxContextLength,
                paramsB: paramsB,
                modelPath: normalizedModelPath,
                modelFormat: metadata.modelFormat,
                defaultLoadProfile: metadata.defaultLoadProfile,
                taskKinds: metadata.taskKinds,
                inputModalities: metadata.inputModalities,
                outputModalities: metadata.outputModalities,
                offlineReady: metadata.offlineReady,
                resourceProfile: metadata.resourceProfile,
                trustProfile: metadata.trustProfile,
                processorRequirements: metadata.processorRequirements
            )
        )
        catalog.updatedAt = Date().timeIntervalSince1970
        return catalog
    }

    private func readConfigJSON(dir: URL) -> [String: Any]? {
        let p = dir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj as? [String: Any]
    }

    private func detectContextLength(config: [String: Any]?) -> Int? {
        guard let c = config else { return nil }
        if let detected = detectContextLength(in: c) {
            return detected
        }
        if let textConfig = c["text_config"] as? [String: Any],
           let detected = detectContextLength(in: textConfig) {
            return detected
        }
        return nil
    }

    private func detectContextLength(in object: [String: Any]) -> Int? {
        let keys = [
            "max_position_embeddings",
            "model_max_length",
            "n_positions",
            "seq_length",
            "max_seq_len",
        ]
        for k in keys {
            if let v = object[k] as? Int { return v }
            if let v = object[k] as? Double { return Int(v) }
            if let v = object[k] as? String, let i = Int(v) { return i }
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
        return resolvedBackend == .mlx || resolvedBackend == .llamaCpp ? "int4" : "fp16"
    }

    private func taskSummary() -> String {
        let taskKinds = detectedMetadata.taskKinds.isEmpty ? [HubUIStrings.Models.AddLocal.unknownTask] : detectedMetadata.taskKinds
        return taskKinds
            .map { LocalTaskRoutingCatalog.shortTitle(for: $0) }
            .joined(separator: ", ")
    }

    private func effectiveRuntimeProviderID() -> String {
        let providerID = autoDetectedRuntimeProviderID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !providerID.isEmpty {
            return providerID
        }
        return resolvedBackend.rawValue
    }

    private func executionSummary() -> String {
        guard !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HubUIStrings.Models.AddLocal.waitingFolderScan
        }
        switch effectiveRuntimeProviderID() {
        case "mlx":
            return HubUIStrings.Models.AddLocal.builtinMLXRuntime
        case "mlx_vlm":
            return HubUIStrings.Models.AddLocal.localAuxRuntime
        case "llama.cpp":
            return HubUIStrings.Models.AddLocal.localAuxRuntime
        case "transformers":
            return HubUIStrings.Models.AddLocal.localAuxRuntime
        default:
            return HubUIStrings.Models.AddLocal.automatic
        }
    }

    private func technicalRuntimeProviderSummary() -> String {
        switch effectiveRuntimeProviderID() {
        case "mlx":
            return "mlx"
        case "llama.cpp":
            return "llama.cpp"
        case "transformers":
            return "transformers"
        default:
            return effectiveRuntimeProviderID()
        }
    }

    private func folderStatusSummary() -> String {
        guard !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HubUIStrings.Models.AddLocal.notSelected
        }
        return folderIntegrityIssue == nil ? HubUIStrings.Models.AddLocal.ready : HubUIStrings.Models.AddLocal.incomplete
    }

    private func visibleIssueText(
        from issueText: String,
        folderIntegrityIssue: LocalModelFolderIntegrityIssue?
    ) -> String {
        let trimmed = issueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let folderIntegrityIssue else { return trimmed }
        return trimmed == folderIntegrityIssue.userMessage ? "" : trimmed
    }

    private func quantText() -> String {
        let q = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? HubUIStrings.Models.AddLocal.unknownQuant : q
    }

    private func paramsText() -> String {
        let s = paramsBText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Double(s), v > 0 {
            return String(format: "%.1fB", v)
        }
        return HubUIStrings.Models.AddLocal.unknownParams
    }

    private func detectionSourceSummary() -> String {
        let parts = [
            humanizedDetectionSource(backendDetectionSource),
            humanizedDetectionSource(detectedMetadata.sourceSummary),
        ].filter { !$0.isEmpty }
        return HubUIStrings.Formatting.middleDotSeparated(parts)
    }

    private func humanizedDetectionSource(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return HubUIStrings.Models.AddLocal.humanizedDetectionSource(trimmed) ?? trimmed
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
        let normalizedBackend = (
            manifest?.backend
            ?? autoDetectedBackend.rawValue
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedBackend == LocalBackendOption.mlx.rawValue
            || normalizedBackend == LocalBackendOption.transformers.rawValue
            || normalizedBackend == LocalBackendOption.llamaCpp.rawValue else {
            return (nil, HubUIStrings.Models.AddLocal.unsupportedBackend(normalizedBackend))
        }

        if normalizedBackend == LocalBackendOption.mlx.rawValue {
            let cfg = url.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: cfg.path) else {
                return (nil, HubUIStrings.Models.AddLocal.invalidMLXDirectory)
            }
            let capability = LocalModelImportDetector.detectCapabilities(
                for: url,
                backend: normalizedBackend,
                manifest: manifest,
                config: config
            )
            return (
                DetectedLocalModelMetadata(
                    modelFormat: capability?.modelFormat ?? manifest?.modelFormat ?? "mlx",
                    maxContextLength: manifest?.maxContextLength ?? detectContextLength(config: config),
                    defaultLoadProfile: manifest?.defaultLoadProfile ?? LocalModelLoadProfile(contextLength: max(512, ctx)),
                    taskKinds: capability?.taskKinds ?? manifest?.taskKinds ?? ["text_generate"],
                    inputModalities: capability?.inputModalities ?? manifest?.inputModalities ?? ["text"],
                    outputModalities: capability?.outputModalities ?? manifest?.outputModalities ?? ["text"],
                    offlineReady: manifest?.offlineReady ?? true,
                    resourceProfile: manifest?.resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
                        backend: normalizedBackend,
                        quant: quant,
                        paramsB: paramsB
                    ),
                    trustProfile: manifest?.trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile(),
                    processorRequirements: capability?.processorRequirements ?? manifest?.processorRequirements ?? ModelProcessorRequirements(
                        tokenizerRequired: true,
                        processorRequired: false,
                        featureExtractorRequired: false
                    ),
                    sourceSummary: capability?.sourceSummary ?? (manifest == nil ? "inferred" : XHubLocalModelManifestLoader.fileName)
                ),
                nil
            )
        }

        if normalizedBackend == LocalBackendOption.llamaCpp.rawValue {
            let hasGGUFFile = (
                try? FileManager.default.contentsOfDirectory(atPath: url.path)
            )?.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".gguf") }) ?? false
            guard manifest != nil || hasGGUFFile else {
                return (nil, HubUIStrings.Models.AddLocal.invalidGGUFDirectory)
            }

            let capability = LocalModelImportDetector.detectCapabilities(
                for: url,
                backend: normalizedBackend,
                manifest: manifest,
                config: config
            )
            let resolvedModelFormat = capability?.modelFormat ?? manifest?.modelFormat ?? "gguf"
            let resolvedTaskKinds = capability?.taskKinds ?? manifest?.taskKinds ?? ["text_generate"]
            let maxContextLength = manifest?.maxContextLength ?? detectContextLength(config: config)
            return (
                DetectedLocalModelMetadata(
                    modelFormat: resolvedModelFormat,
                    maxContextLength: maxContextLength,
                    defaultLoadProfile: manifest?.defaultLoadProfile ?? LocalModelLoadProfile(contextLength: max(512, maxContextLength ?? ctx)),
                    taskKinds: resolvedTaskKinds,
                    inputModalities: capability?.inputModalities ?? manifest?.inputModalities ?? ["text"],
                    outputModalities: capability?.outputModalities ?? manifest?.outputModalities ?? ["text"],
                    offlineReady: manifest?.offlineReady ?? true,
                    resourceProfile: manifest?.resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
                        backend: normalizedBackend,
                        quant: quant,
                        paramsB: paramsB
                    ),
                    trustProfile: manifest?.trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile(),
                    processorRequirements: capability?.processorRequirements ?? manifest?.processorRequirements ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(
                        backend: normalizedBackend,
                        modelFormat: resolvedModelFormat,
                        taskKinds: resolvedTaskKinds
                    ),
                    sourceSummary: capability?.sourceSummary ?? (manifest == nil ? "inferred" : XHubLocalModelManifestLoader.fileName)
                ),
                nil
            )
        }

        let cfg = url.appendingPathComponent("config.json")
        guard manifest != nil || FileManager.default.fileExists(atPath: cfg.path) else {
            return (nil, HubUIStrings.Models.AddLocal.invalidTransformersDirectory)
        }

        if let manifest {
            return (
                DetectedLocalModelMetadata(
                    modelFormat: manifest.modelFormat,
                    maxContextLength: manifest.maxContextLength ?? detectContextLength(config: config),
                    defaultLoadProfile: manifest.defaultLoadProfile ?? LocalModelLoadProfile(contextLength: max(512, ctx)),
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

        guard let inferred = LocalModelImportDetector.detectCapabilities(
            for: url,
            backend: normalizedBackend,
            manifest: nil,
            config: config
        ) else {
            return (nil, HubUIStrings.Models.AddLocal.transformersNeedManifest)
        }
        let maxContextLength = detectContextLength(config: config)
        let defaultLoadProfile = LocalModelLoadProfile(contextLength: max(512, maxContextLength ?? ctx))
        let baseProfile = LocalModelCapabilityDefaults.defaultResourceProfile(
            backend: normalizedBackend,
            quant: quant,
            paramsB: paramsB
        )
        return (
            DetectedLocalModelMetadata(
                modelFormat: inferred.modelFormat,
                maxContextLength: maxContextLength,
                defaultLoadProfile: defaultLoadProfile,
                taskKinds: inferred.taskKinds,
                inputModalities: inferred.inputModalities,
                outputModalities: inferred.outputModalities,
                offlineReady: true,
                resourceProfile: baseProfile,
                trustProfile: LocalModelCapabilityDefaults.defaultTrustProfile(),
                processorRequirements: inferred.processorRequirements,
                sourceSummary: inferred.sourceSummary
            ),
            nil
        )
    }

    private func validateAndBuildEntry() -> ModelCatalogEntry? {
        errorText = ""
        let id = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            errorText = HubUIStrings.Models.AddLocal.modelIDRequired
            return nil
        }
        if modelPath.isEmpty {
            errorText = HubUIStrings.Models.AddLocal.directoryRequired
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
            let error = result.error ?? HubUIStrings.Models.AddLocal.cannotResolveCapabilities
            errorText = error
            return nil
        }

        if resolved.taskKinds.isEmpty {
            errorText = HubUIStrings.Models.AddLocal.missingTaskKinds
            return nil
        }

        return ModelCatalogEntry(
            id: id,
            name: name.isEmpty ? id : name,
            backend: resolvedBackend.rawValue,
            runtimeProviderID: autoDetectedRuntimeProviderID.isEmpty ? nil : autoDetectedRuntimeProviderID,
            quant: q.isEmpty ? inferQuant(modelURL.lastPathComponent) : q,
            contextLength: max(512, ctx),
            maxContextLength: resolved.maxContextLength,
            paramsB: max(0.0, pb),
            modelPath: modelPath,
            roles: nil,
            note: "catalog",
            modelFormat: resolved.modelFormat,
            defaultLoadProfile: resolved.defaultLoadProfile,
            taskKinds: resolved.taskKinds,
            inputModalities: resolved.inputModalities,
            outputModalities: resolved.outputModalities,
            offlineReady: resolved.offlineReady,
            voiceProfile: LocalModelCapabilityDefaults.defaultVoiceProfile(
                modelID: id,
                name: name.isEmpty ? id : name,
                note: "catalog",
                taskKinds: resolved.taskKinds,
                outputModalities: resolved.outputModalities
            ),
            resourceProfile: resolved.resourceProfile,
            trustProfile: resolved.trustProfile,
            processorRequirements: resolved.processorRequirements
        )
    }

    private func addModelAsync() async {
        if isAdding { return }
        isAdding = true
        progressText = HubUIStrings.Models.AddLocal.preparing
        defer {
            isAdding = false
            progressText = ""
        }

        guard var entry = validateAndBuildEntry() else {
            return
        }

        if SharedPaths.isSandboxedProcess() {
            progressText = HubUIStrings.Models.AddLocal.importingIntoHubStorage
            let base = SharedPaths.ensureHubDirectory()
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
                let sourceEntry = entry
                entry = try await Task.detached(priority: .userInitiated) {
                    try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
                        sourceEntry,
                        sandboxed: true,
                        baseDir: base
                    )
                }.value
            } catch {
                errorText = HubUIStrings.Models.AddLocal.sandboxImportFailed(error.localizedDescription)
                return
            }
        }

        progressText = HubUIStrings.Models.AddLocal.saving
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
