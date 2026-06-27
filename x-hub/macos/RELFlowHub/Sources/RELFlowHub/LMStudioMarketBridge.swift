import Foundation
import Darwin
import RELFlowHubCore

enum LMStudioMarketBridge {
    static func helperBinaryPath() -> String {
        LocalHelperBridgeDiscovery.discoverHelperBinary()
    }

    static func lmStudioHomeDirectory(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default
    ) -> URL {
        let pointerURL = homeDirectory.appendingPathComponent(".lmstudio-home-pointer")
        if let rawPointer = try? String(contentsOf: pointerURL, encoding: .utf8) {
            let pointedPath = rawPointer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !pointedPath.isEmpty {
                let pointedURL = URL(fileURLWithPath: pointedPath, isDirectory: true).standardizedFileURL
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: pointedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return pointedURL
                }
            }
        }
        return homeDirectory
            .appendingPathComponent(".lmstudio", isDirectory: true)
            .standardizedFileURL
    }

    static func legacyDownloadedModelsDirectory(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default
    ) -> URL {
        lmStudioHomeDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
            .appendingPathComponent("models", isDirectory: true)
    }

    static func marketDownloadedModelsDirectory(
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> URL {
        LocalModelManagedStorage.managedModelsDirectory(baseDir: baseDir)
            .appendingPathComponent("_market", isDirectory: true)
    }

    static func downloadedModelsDisplayPath(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> String {
        let homePath = homeDirectory.standardizedFileURL.path
        let downloadsPath = marketDownloadedModelsDirectory(baseDir: baseDir).standardizedFileURL.path
        guard downloadsPath.hasPrefix(homePath) else { return downloadsPath }
        let suffix = String(downloadsPath.dropFirst(homePath.count))
        return "~" + suffix
    }

    static func searchModels(
        query: String,
        category: String = "",
        limit: Int = 12
    ) async throws -> [LMStudioMarketResult] {
        do {
            return try searchModelsViaSDKHelper(query: query, category: category, limit: limit)
        } catch let helperError {
            do {
                return try await searchModelsViaURLSession(query: query, category: category, limit: limit)
            } catch let fallbackError {
                let helperMessage = helperError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackMessage = fallbackError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackMessage.isEmpty, helperMessage != fallbackMessage {
                    throw LMStudioMarketBridgeError.searchFailed(
                        HubUIStrings.Models.MarketBridge.helperFallbackDetail(
                            fallback: fallbackMessage,
                            helper: helperMessage
                        )
                    )
                }
                throw fallbackError
            }
        }
    }

    static func downloadRecommended(
        modelKey: String,
        downloadIdentifier: String? = nil,
        progress: @escaping @Sendable (String) -> Void
    ) throws {
        let key = modelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw LMStudioMarketBridgeError.downloadFailed(HubUIStrings.Models.MarketBridge.missingModelKey)
        }
        try downloadRecommendedViaSDKHelper(
            modelKey: key,
            downloadIdentifier: downloadIdentifier,
            progress: progress
        )
    }

    static func loadDownloadedModels(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> [LMStudioDownloadedModelDescriptor] {
        var descriptors: [LMStudioDownloadedModelDescriptor] = []
        descriptors.append(
            contentsOf: fallbackDownloadedDescriptorsFromManagedMarket(
                baseDir: baseDir,
                fileManager: fileManager
            )
        )
        let cacheURL = lmStudioHomeDirectory(
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
            .appendingPathComponent(".internal", isDirectory: true)
            .appendingPathComponent("model-index-cache.json")
        if let data = try? Data(contentsOf: cacheURL),
           let payload = try? JSONSerialization.jsonObject(with: data, options: []),
           let root = payload as? [String: Any],
           let rows = root["models"] as? [[String: Any]] {
            descriptors.append(contentsOf: rows.compactMap(downloadedDescriptor(from:)))
        }

        descriptors.append(
            contentsOf: fallbackDownloadedDescriptorsFromFilesystem(
                homeDirectory: homeDirectory,
                fileManager: fileManager
            )
        )

        return mergedDownloadedDescriptors(descriptors)
            .sorted { lhs, rhs in
                if lhs.isBundled != rhs.isBundled {
                    return !lhs.isBundled
                }
                if lhs.displayName != rhs.displayName {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    static func catalogEntries(
        from downloadedModels: [LMStudioDownloadedModelDescriptor],
        helperBinaryPath: String = helperBinaryPath()
    ) -> [ModelCatalogEntry] {
        downloadedModels.compactMap { descriptor in
            catalogEntry(from: descriptor, helperBinaryPath: helperBinaryPath)
        }
    }

    private static func searchModelsViaSDKHelper(
        query: String,
        category: String,
        limit: Int
    ) throws -> [LMStudioMarketResult] {
        let result = try runSDKHelperCommand(
            command: "search",
            arguments: [
                query.trimmingCharacters(in: .whitespacesAndNewlines),
                String(max(1, min(25, limit))),
                category.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            timeoutSec: 60.0
        )
        guard result.terminationStatus == 0 else {
            throw LMStudioMarketBridgeError.searchFailed(cleanedProcessFailureDetail(result))
        }
        return try decodeSDKSearchResults(from: result.stdout)
    }

    private static func downloadRecommendedViaSDKHelper(
        modelKey: String,
        downloadIdentifier: String?,
        progress: @escaping @Sendable (String) -> Void
    ) throws {
        let result = try runSDKHelperCommand(
            command: "download",
            arguments: [
                modelKey,
                downloadIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            ],
            timeoutSec: 3600.0,
            onOutputUpdate: { output in
                let status = lastSDKHelperMessage(from: output)
                if !status.isEmpty {
                    progress(status)
                }
            }
        )
        let events = helperEvents(from: result.stdout)
        let succeeded = events.contains { $0.type == "success" }
        guard result.terminationStatus == 0 || succeeded else {
            throw LMStudioMarketBridgeError.downloadFailed(cleanedProcessFailureDetail(result))
        }
    }

    static func decodeSDKSearchResults(from rawOutput: String) throws -> [LMStudioMarketResult] {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.invalidModelDiscoveryOutput)
        }
        let envelope: LMStudioSDKSearchEnvelope
        do {
            envelope = try JSONDecoder().decode(LMStudioSDKSearchEnvelope.self, from: data)
        } catch {
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.unreadableModelDiscoveryResult)
        }

        return envelope.results.map { item in
            LMStudioMarketResult(
                modelKey: item.modelKey,
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? displayTitle(for: item.modelKey)
                    : item.title,
                summary: item.summary,
                formatHint: item.formatHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "transformers"
                    : item.formatHint,
                capabilityTags: item.capabilityTags.isEmpty
                    ? capabilityTags(for: item.modelKey, summary: item.summary)
                    : item.capabilityTags,
                staffPick: item.staffPick ?? false,
                recommendationReason: item.recommendationReason ?? "",
                recommendedForThisMac: item.recommendedForThisMac ?? false,
                recommendedFitEstimation: item.recommendedFitEstimation ?? "",
                recommendedSizeBytes: item.recommendedSizeBytes ?? 0,
                downloadIdentifier: item.downloadIdentifier ?? "",
                downloaded: false,
                inLibrary: false
            )
        }
    }

    private static func helperEvents(from rawOutput: String) -> [LMStudioSDKHelperEvent] {
        sanitizedTerminalOutput(rawOutput)
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
                guard let data = trimmed.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(LMStudioSDKHelperEvent.self, from: data)
            }
    }

    private static func lastSDKHelperMessage(from rawOutput: String) -> String {
        for event in helperEvents(from: rawOutput).reversed() {
            let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty && event.type != "success" {
                return message
            }
        }
        return ""
    }

    static func parseSearchResultsFromTerminalOutput(_ rawOutput: String) -> [LMStudioMarketResult] {
        let sanitized = sanitizedTerminalOutput(rawOutput)
        let lines = sanitized.components(separatedBy: .newlines)
        var results: [LMStudioMarketResult] = []
        var seen: Set<String> = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("?") || line.contains("navigate") || line.contains("select") {
                continue
            }
            if line.hasPrefix("Searching for models") || line.hasPrefix("No exact match found") {
                continue
            }

            let normalized = line.hasPrefix("❯")
                ? String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                : line

            guard let parsed = parseSearchLine(normalized),
                  seen.insert(parsed.modelKey).inserted else {
                continue
            }

            results.append(
                LMStudioMarketResult(
                    modelKey: parsed.modelKey,
                    title: displayTitle(for: parsed.modelKey),
                    summary: parsed.summary,
                    formatHint: "mlx",
                    capabilityTags: capabilityTags(for: parsed.modelKey, summary: parsed.summary),
                    staffPick: false,
                    recommendationReason: "",
                    recommendedForThisMac: false,
                    recommendedFitEstimation: "",
                    recommendedSizeBytes: 0,
                    downloadIdentifier: "",
                    downloaded: false,
                    inLibrary: false
                )
            )
        }

        return results
    }

    static func marketKeyMatchesDescriptor(
        _ marketKey: String,
        descriptor: LMStudioDownloadedModelDescriptor
    ) -> Bool {
        let keyParts = normalizedMarketKeyParts(marketKey)
        guard keyParts.count == 2 else { return false }

        let requestedUser = keyParts[0]
        let requestedTokens = matchingTokens(from: keyParts[1])
        guard !requestedTokens.isEmpty else { return false }

        let descriptorUser = descriptor.user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !descriptorUser.isEmpty && descriptorUser != requestedUser {
            return false
        }

        let candidateTokens = descriptorMatchingTokens(descriptor)
        return requestedTokens.isSubset(of: candidateTokens)
    }

    static func marketKeyMatchesModel(
        _ marketKey: String,
        model: HubModel
    ) -> Bool {
        let keyParts = normalizedMarketKeyParts(marketKey)
        guard keyParts.count == 2 else { return false }

        if let exactKey = extractedMarketKey(fromModelPath: model.modelPath ?? ""),
           exactKey == normalizedMarketKey(marketKey) {
            return true
        }

        let requestedTokens = matchingTokens(from: keyParts[1])
        guard !requestedTokens.isEmpty else { return false }

        let haystacks = [
            model.id,
            model.name,
            model.modelPath ?? "",
            model.note ?? "",
        ]
        let modelTokens = Set(haystacks.flatMap { matchingTokens(from: $0) })
        return requestedTokens.isSubset(of: modelTokens)
    }

    private static func catalogEntry(
        from descriptor: LMStudioDownloadedModelDescriptor,
        helperBinaryPath: String
    ) -> ModelCatalogEntry? {
        guard !descriptor.isBundled else { return nil }
        guard descriptor.isDirectoryModel else { return nil }
        let path = descriptor.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        guard LocalModelFolderIntegrityPolicy.issue(modelPath: path) == nil else { return nil }

        let modelURL = URL(fileURLWithPath: path, isDirectory: true)
        let manifest = XHubLocalModelManifestLoader.load(from: modelURL)
        let config = readConfigJSON(in: modelURL)
        let backend = preferredBackend(
            for: descriptor,
            modelURL: modelURL,
            manifest: manifest,
            config: config
        )
        guard backend == "mlx" || backend == "transformers" || backend == "llama.cpp" else { return nil }

        let inferredCapabilities = LocalModelImportDetector.detectCapabilities(
            for: modelURL,
            backend: backend,
            manifest: manifest,
            config: config
        )
        let taskKinds = inferredCapabilities?.taskKinds ?? taskKinds(
            forDomain: descriptor.domain,
            modelName: descriptor.model
        )
        guard !taskKinds.isEmpty else { return nil }

        let modelFormat = inferredCapabilities?.modelFormat
            ?? manifest?.modelFormat
            ?? defaultModelFormat(forBackend: backend, descriptor: descriptor)
        let maxContextLength = max(
            512,
            descriptor.contextLength > 0 ? descriptor.contextLength : detectContextLength(config)
        )
        let quant = normalizedQuantLabel(descriptor.quantLabel, fileName: descriptor.file)
        let paramsB = descriptor.paramsB
        let resourceProfile = manifest?.resourceProfile ?? LocalModelCapabilityDefaults.defaultResourceProfile(
            backend: backend,
            quant: quant,
            paramsB: paramsB
        )
        let trustProfile = manifest?.trustProfile ?? LocalModelCapabilityDefaults.defaultTrustProfile()
        let processorRequirements = inferredCapabilities?.processorRequirements
            ?? manifest?.processorRequirements
            ?? LocalModelCapabilityDefaults.defaultProcessorRequirements(
                backend: backend,
                modelFormat: modelFormat,
                taskKinds: taskKinds
            )
        let runtimeProviderID = LocalModelExecutionProviderResolver.suggestedRuntimeProviderID(
            backend: backend,
            modelPath: path,
            taskKinds: taskKinds,
            helperBinaryPath: helperBinaryPath
        )
        let defaultLoadProfile = (manifest?.defaultLoadProfile ?? LocalModelLoadProfile(contextLength: maxContextLength))
            .normalized(maxContextLength: maxContextLength)
        let modelID = stableCatalogModelID(for: descriptor)
        let name = descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? displayTitle(for: "\(descriptor.user)/\(descriptor.model)")
            : descriptor.displayName
        let note = marketManagedNote(for: descriptor)
        let outputModalities = inferredCapabilities?.outputModalities
            ?? manifest?.outputModalities
            ?? LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: taskKinds)

        let entry = ModelCatalogEntry(
            id: modelID,
            name: name,
            backend: backend,
            runtimeProviderID: runtimeProviderID,
            quant: quant,
            contextLength: maxContextLength,
            maxContextLength: maxContextLength,
            paramsB: paramsB,
            modelPath: path,
            roles: nil,
            note: note,
            modelFormat: modelFormat,
            defaultLoadProfile: defaultLoadProfile,
            taskKinds: taskKinds,
            inputModalities: inferredCapabilities?.inputModalities
                ?? manifest?.inputModalities
                ?? LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: taskKinds),
            outputModalities: outputModalities,
            offlineReady: manifest?.offlineReady ?? true,
            voiceProfile: LocalModelCapabilityDefaults.defaultVoiceProfile(
                modelID: modelID,
                name: name,
                note: note,
                taskKinds: taskKinds,
                outputModalities: outputModalities
            ),
            resourceProfile: resourceProfile,
            trustProfile: trustProfile,
            processorRequirements: processorRequirements
        )
        return LocalModelExecutionProviderResolver.backfilled(
            entry,
            helperBinaryPath: helperBinaryPath
        )
    }

    private static func marketManagedNote(
        for descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let source = descriptor.sourceDirectoryType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "xhub_market" {
            return "market_managed"
        }
        return "lmstudio_managed"
    }

    private static func readConfigJSON(in directory: URL) -> [String: Any]? {
        let configURL = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func mergedDownloadedDescriptors(
        _ descriptors: [LMStudioDownloadedModelDescriptor]
    ) -> [LMStudioDownloadedModelDescriptor] {
        var merged: [LMStudioDownloadedModelDescriptor] = []
        var seenPaths = Set<String>()
        var seenMarketKeys = Set<String>()

        for descriptor in descriptors {
            let pathKey = standardizedDescriptorPath(descriptor)
            let marketKey = normalizedDescriptorMarketKey(descriptor)
            if !pathKey.isEmpty, seenPaths.contains(pathKey) {
                continue
            }
            if !marketKey.isEmpty, seenMarketKeys.contains(marketKey) {
                continue
            }
            if !pathKey.isEmpty {
                seenPaths.insert(pathKey)
            }
            if !marketKey.isEmpty {
                seenMarketKeys.insert(marketKey)
            }
            merged.append(descriptor)
        }

        return merged
    }

    private static func standardizedDescriptorPath(
        _ descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let path = descriptor.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
    }

    private static func normalizedDescriptorMarketKey(
        _ descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let user = descriptor.user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let model = descriptor.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !user.isEmpty, !model.isEmpty else { return "" }
        return "\(user)/\(model)"
    }

    private static func fallbackDownloadedDescriptorsFromFilesystem(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> [LMStudioDownloadedModelDescriptor] {
        let root = legacyDownloadedModelsDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        guard let ownerDirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var descriptors: [LMStudioDownloadedModelDescriptor] = []
        for ownerDirectory in ownerDirectories {
            guard fileManager.directoryExists(atPath: ownerDirectory.path) else { continue }
            let owner = ownerDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !owner.isEmpty else { continue }
            guard let modelDirectories = try? fileManager.contentsOfDirectory(
                at: ownerDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for modelDirectory in modelDirectories where fileManager.directoryExists(atPath: modelDirectory.path) {
                let model = modelDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else { continue }
                guard let descriptor = fallbackDownloadedDescriptor(
                    owner: owner,
                    model: model,
                    directoryURL: modelDirectory,
                    sourceDirectoryType: "downloaded",
                    fileManager: fileManager
                ) else {
                    continue
                }
                descriptors.append(descriptor)
            }
        }
        return descriptors
    }

    private static func fallbackDownloadedDescriptorsFromManagedMarket(
        baseDir: URL,
        fileManager: FileManager
    ) -> [LMStudioDownloadedModelDescriptor] {
        let root = marketDownloadedModelsDirectory(baseDir: baseDir)
        guard fileManager.directoryExists(atPath: root.path) else { return [] }
        guard let ownerDirectories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var descriptors: [LMStudioDownloadedModelDescriptor] = []
        for ownerDirectory in ownerDirectories where fileManager.directoryExists(atPath: ownerDirectory.path) {
            let owner = ownerDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !owner.isEmpty else { continue }
            guard let modelDirectories = try? fileManager.contentsOfDirectory(
                at: ownerDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for modelDirectory in modelDirectories where fileManager.directoryExists(atPath: modelDirectory.path) {
                let model = modelDirectory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !model.isEmpty else { continue }
                guard let descriptor = fallbackDownloadedDescriptor(
                    owner: owner,
                    model: model,
                    directoryURL: modelDirectory,
                    sourceDirectoryType: "xhub_market",
                    fileManager: fileManager
                ) else {
                    continue
                }
                descriptors.append(descriptor)
            }
        }
        return descriptors
    }

    private static func fallbackDownloadedDescriptor(
        owner: String,
        model: String,
        directoryURL: URL,
        sourceDirectoryType: String,
        fileManager: FileManager
    ) -> LMStudioDownloadedModelDescriptor? {
        guard fileManager.directoryExists(atPath: directoryURL.path) else { return nil }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let fileNames = entries.map(\.lastPathComponent)
        guard directoryLooksLikeDownloadedModel(fileNames: fileNames) else {
            return nil
        }

        let marketKey = "\(owner)/\(model)"
        let preferredEntry = preferredModelEntryPoint(in: directoryURL, fileNames: fileNames)
        let preferredFile = preferredEntry?.lastPathComponent ?? ""

        return LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: marketKey,
            displayName: displayTitle(for: marketKey),
            defaultIdentifier: fallbackDefaultIdentifier(for: model),
            user: owner,
            model: model,
            file: preferredFile,
            format: fallbackFormat(fileNames: fileNames),
            quantLabel: fallbackQuantLabel(modelName: model),
            domain: fallbackDomain(modelName: model),
            contextLength: 0,
            directoryPath: directoryURL.path,
            entryPointPath: preferredEntry?.path ?? directoryURL.path,
            sourceDirectoryType: sourceDirectoryType,
            paramsB: 0.0
        )
    }

    private static func directoryLooksLikeDownloadedModel(fileNames: [String]) -> Bool {
        let lowered = Set(fileNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let markerFiles: Set<String> = [
            "config.json",
            "xhub_model_manifest.json",
            "model.safetensors.index.json",
            "consolidated.safetensors.index.json",
            "weights.npz",
            "processor_config.json",
            "preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "generation_config.json",
        ]
        if !lowered.isDisjoint(with: markerFiles) {
            return true
        }
        return lowered.contains(where: { name in
            name.hasSuffix(".gguf") || name.hasSuffix(".safetensors")
        })
    }

    private static func preferredModelEntryPoint(
        in directoryURL: URL,
        fileNames: [String]
    ) -> URL? {
        let preferredNames = [
            "model.safetensors.index.json",
            "consolidated.safetensors.index.json",
            "weights.npz",
            "model.safetensors",
            "config.json",
        ]
        let byLoweredName = Dictionary(uniqueKeysWithValues: fileNames.map {
            ($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0)
        })
        for preferredName in preferredNames {
            if let match = byLoweredName[preferredName] {
                return directoryURL.appendingPathComponent(match)
            }
        }
        if let gguf = fileNames.first(where: { $0.lowercased().hasSuffix(".gguf") }) {
            return directoryURL.appendingPathComponent(gguf)
        }
        if let safetensors = fileNames.first(where: { $0.lowercased().hasSuffix(".safetensors") }) {
            return directoryURL.appendingPathComponent(safetensors)
        }
        return nil
    }

    private static func fallbackDefaultIdentifier(for model: String) -> String {
        sanitizedIdentifier(model)
    }

    private static func fallbackFormat(fileNames: [String]) -> String {
        let lowered = fileNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if lowered.contains(where: { $0.hasSuffix(".gguf") }) {
            return "gguf"
        }
        if lowered.contains("weights.npz") {
            return "mlx"
        }
        if lowered.contains(where: { $0.hasSuffix(".safetensors") || $0.hasSuffix(".safetensors.index.json") }) {
            return "safetensors"
        }
        return "safetensors"
    }

    private static func fallbackQuantLabel(modelName: String) -> String {
        let lowered = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for token in ["2bit", "3bit", "4bit", "5bit", "6bit", "8bit", "bf16", "fp16", "fp32", "q4", "q8"] {
            if lowered.contains(token) {
                return token
            }
        }
        return ""
    }

    private static func fallbackDomain(modelName: String) -> String {
        let lowered = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.contains("embed") {
            return "embedding"
        }
        if containsAny(lowered, values: ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]) {
            return "voice"
        }
        if lowered.contains("vision")
            || lowered.contains("ocr")
            || lowered.contains("-vl")
            || lowered.contains("glm4v")
            || lowered.contains("glm-4.6v")
            || lowered.contains("qwen2-vl")
            || lowered.contains("qwen3-vl")
            || lowered.contains("florence") {
            return "vision"
        }
        if lowered.contains("audio")
            || lowered.contains("whisper")
            || lowered.contains("asr")
            || lowered.contains("speech") {
            return "audio"
        }
        return "llm"
    }

    private static func detectContextLength(_ config: [String: Any]?) -> Int {
        guard let config else { return 8192 }
        for key in ["max_position_embeddings", "context_length", "n_ctx", "max_seq_len", "seq_length"] {
            if let value = config[key] as? Int, value > 0 {
                return value
            }
            if let value = config[key] as? NSNumber, value.intValue > 0 {
                return value.intValue
            }
        }
        return 8192
    }

    private static func defaultModelFormat(
        forBackend backend: String,
        descriptor: LMStudioDownloadedModelDescriptor
    ) -> String {
        let normalizedFormat = descriptor.format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedFormat == "gguf" {
            return "gguf"
        }
        return LocalModelCapabilityDefaults.defaultModelFormat(forBackend: backend)
    }

    private static func preferredBackend(
        for descriptor: LMStudioDownloadedModelDescriptor,
        modelURL: URL,
        manifest: XHubLocalModelManifest?,
        config: [String: Any]?
    ) -> String {
        let manifestBackend = (manifest?.backend ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !manifestBackend.isEmpty {
            return manifestBackend
        }

        let normalizedFormat = descriptor.format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedFormat {
        case "mlx":
            return "mlx"
        case "gguf":
            return "llama.cpp"
        case "transformers", "hf", "hf_transformers":
            return "transformers"
        default:
            return LocalModelImportDetector.detectBackend(
                for: modelURL,
                manifest: manifest,
                config: config
            ).backend
        }
    }

    private static func taskKinds(
        forDomain domain: String,
        modelName: String
    ) -> [String] {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedDomain == "embedding" || normalizedName.contains("embed") {
            return ["embedding"]
        }
        if normalizedDomain == "voice"
            || containsAny(normalizedName, values: ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]) {
            return ["text_to_speech"]
        }
        if normalizedDomain.contains("speech") || normalizedDomain.contains("audio") {
            if containsAny(normalizedName, values: ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]) {
                return ["text_to_speech"]
            }
            if containsAny(normalizedName, values: ["whisper", "asr", "wav2vec", "hubert", "ctc"]) {
                return ["speech_to_text"]
            }
            return ["speech_to_text"]
        }
        if normalizedDomain.contains("vision")
            || normalizedDomain.contains("image")
            || normalizedName.contains("vision")
            || normalizedName.contains("llava")
            || normalizedName.contains("glm4v")
            || normalizedName.contains("glm-4.6v")
            || normalizedName.contains("qwen2-vl")
            || normalizedName.contains("qwen3-vl")
            || normalizedName.contains("florence")
            || normalizedName.contains("ocr") {
            return ["vision_understand", "ocr"]
        }
        return ["text_generate"]
    }

    private static func stableCatalogModelID(for descriptor: LMStudioDownloadedModelDescriptor) -> String {
        let parts = [
            descriptor.defaultIdentifier,
            descriptor.quantLabel,
            descriptor.file.replacingOccurrences(of: ".", with: "-"),
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let seed = parts.isEmpty ? descriptor.id : parts.joined(separator: "-")
        return sanitizedIdentifier(seed)
    }

    private static func sanitizedIdentifier(_ raw: String) -> String {
        let lower = raw.lowercased()
        let replaced = lower.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: "-",
            options: .regularExpression
        )
        let collapsed = replaced.replacingOccurrences(
            of: #"-+"#,
            with: "-",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? UUID().uuidString.lowercased() : trimmed
    }

    private static func downloadedDescriptor(from row: [String: Any]) -> LMStudioDownloadedModelDescriptor? {
        let indexedModelIdentifier = stringValue(row["indexedModelIdentifier"])
        let displayName = stringValue(row["displayName"])
        let defaultIdentifier = stringValue(row["defaultIdentifier"])
        let user = stringValue(row["user"])
        let model = stringValue(row["model"])
        let file = stringValue(row["file"])
        let format = stringValue(row["format"])
        let domain = stringValue(row["domain"])
        let contextLength = intValue(row["contextLength"])
        let sourceDirectoryType = stringValue(row["sourceDirectoryType"])
        let paramsB = paramsValue(row["params"])
        let quantLabel: String = {
            if let quant = row["quant"] as? [String: Any] {
                return stringValue(quant["name"])
            }
            return ""
        }()
        let entryPoint = row["entryPoint"] as? [String: Any] ?? [:]
        let entryPointPath = stringValue(entryPoint["absPath"])
        let directoryPath = stringValue(row["concreteModelDirAbsolutePath"])

        let hasIdentity = !indexedModelIdentifier.isEmpty || (!user.isEmpty && !model.isEmpty)
        guard hasIdentity else { return nil }

        return LMStudioDownloadedModelDescriptor(
            indexedModelIdentifier: indexedModelIdentifier,
            displayName: displayName,
            defaultIdentifier: defaultIdentifier,
            user: user,
            model: model,
            file: file,
            format: format,
            quantLabel: quantLabel,
            domain: domain,
            contextLength: contextLength,
            directoryPath: directoryPath,
            entryPointPath: entryPointPath,
            sourceDirectoryType: sourceDirectoryType,
            paramsB: paramsB
        )
    }

    private static func paramsValue(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber {
            return number.doubleValue
        }
        let text = stringValue(raw)
        guard !text.isEmpty else { return 0.0 }
        let normalized = text.lowercased()
        let multiplier: Double
        if normalized.contains("b") {
            multiplier = 1.0
        } else if normalized.contains("m") {
            multiplier = 0.001
        } else {
            multiplier = 1.0
        }
        let digits = normalized.replacingOccurrences(
            of: #"[^0-9.]"#,
            with: "",
            options: .regularExpression
        )
        if let value = Double(digits) {
            return value * multiplier
        }
        return 0.0
    }

    private static func normalizedQuantLabel(_ quant: String, fileName: String) -> String {
        let quantToken = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !quantToken.isEmpty {
            return quantToken.lowercased()
        }
        let lower = fileName.lowercased()
        if lower.contains("4bit") { return "4bit" }
        if lower.contains("8bit") { return "8bit" }
        if lower.contains("bf16") { return "bf16" }
        if lower.contains("fp16") { return "fp16" }
        return ""
    }

    private static func capabilityTags(for modelKey: String, summary: String) -> [String] {
        let haystack = "\(modelKey) \(summary)".lowercased()
        var out: [String] = []
        let voiceSignals = ["text-to-speech", "text_to_speech", "tts", "voice", "kokoro", "melo", "parler", "vits", "bark", "speecht5", "f5-tts", "cosyvoice", "chattts"]
        if haystack.contains("vision")
            || haystack.contains("vlm")
            || haystack.contains("llava")
            || haystack.contains("glm-4.6v")
            || haystack.contains("glm4v")
            || haystack.contains("qwen2-vl")
            || haystack.contains("qwen3-vl")
            || haystack.contains("florence")
            || haystack.contains("image") {
            out.append("Vision")
        }
        if haystack.contains("ocr") {
            out.append("OCR")
        }
        if haystack.contains("embed") {
            out.append("Embedding")
        }
        if haystack.contains("coder") || haystack.contains("coding") || haystack.contains("code") {
            out.append("Coding")
        }
        if containsAny(haystack, values: voiceSignals) {
            out.append("Voice")
        }
        if out.isEmpty {
            out.append("Text")
        }
        return Array(out.prefix(3))
    }

    static func displayTitle(for modelKey: String) -> String {
        let base = modelKey.split(separator: "/").last.map(String.init) ?? modelKey
        let words = base
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { token -> String in
                let raw = String(token)
                if raw.uppercased() == raw {
                    return raw
                }
                if raw.count <= 3 {
                    return raw.uppercased()
                }
                return String(raw.prefix(1)).uppercased() + String(raw.dropFirst())
            }
        return words.joined(separator: " ")
    }

    private static func parseSearchLine(_ line: String) -> (modelKey: String, summary: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") else { return nil }

        guard let regex = modelKeySearchRegex else { return nil }
        let nsrange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: nsrange),
              let keyRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        let modelKey = String(trimmed[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelKey.contains("/") else { return nil }

        let summary: String
        if let dashRange = trimmed.range(of: " — ") {
            summary = String(trimmed[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            summary = ""
        }
        return (modelKey, summary)
    }

    private static func runSDKHelperCommand(
        command: String,
        arguments: [String],
        timeoutSec: TimeInterval,
        onOutputUpdate: (@Sendable (String) -> Void)? = nil
    ) throws -> LMStudioCLIProcessResult {
        guard let scriptPath = marketHelperScriptPath() else {
            if command == "download" {
                throw LMStudioMarketBridgeError.downloadFailed(HubUIStrings.Models.MarketBridge.missingBundledBridge)
            }
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.missingBundledBridge)
        }
        guard let nodeLaunch = nodeLaunchConfig() else {
            if command == "download" {
                throw LMStudioMarketBridgeError.downloadFailed(HubUIStrings.Models.MarketBridge.missingNodeRuntime)
            }
            throw LMStudioMarketBridgeError.searchFailed(HubUIStrings.Models.MarketBridge.missingNodeRuntime)
        }
        let realHome = SharedPaths.realHomeDirectory()
        let hubDirectory = SharedPaths.ensureHubDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHome.path
        environment["PWD"] = realHome.path
        environment["XHUB_REAL_HOME"] = realHome.path
        environment["XHUB_HUB_DIR"] = hubDirectory.path
        environment["XHUB_MARKET_DIR"] = marketDownloadedModelsDirectory(baseDir: hubDirectory).path

        return runProcessCommand(
            executablePath: nodeLaunch.executablePath,
            arguments: nodeLaunch.argumentsPrefix + [scriptPath, command] + arguments,
            currentDirectoryURL: realHome,
            environment: environment,
            timeoutSec: timeoutSec,
            onOutputUpdate: onOutputUpdate
        )
    }

    private static func marketHelperScriptPath() -> String? {
        if let resourceURL = Bundle.main.resourceURL {
            let candidates = [
                resourceURL.appendingPathComponent("lmstudio_market_bridge.cjs"),
                resourceURL
                    .appendingPathComponent("RELFlowHub_RELFlowHub.bundle", isDirectory: true)
                    .appendingPathComponent("lmstudio_market_bridge.cjs"),
                resourceURL
                    .appendingPathComponent("RELFlowHub_RELFlowHub.bundle", isDirectory: true)
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("lmstudio_market_bridge.cjs"),
            ]
            if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })?.path {
                return path
            }
        }

        let sourceCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("lmstudio_market_bridge.cjs")
        if FileManager.default.fileExists(atPath: sourceCandidate.path) {
            return sourceCandidate.path
        }

        return nil
    }

    private static func nodeLaunchConfig() -> LMStudioNodeLaunchConfig? {
        let fileManager = FileManager.default

        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "relflowhub_node")?.path,
           fileManager.isExecutableFile(atPath: bundled) {
            return LMStudioNodeLaunchConfig(executablePath: bundled, argumentsPrefix: [])
        }
        if let bundledResource = Bundle.main.resourceURL?.appendingPathComponent("relflowhub_node").path,
           fileManager.isExecutableFile(atPath: bundledResource) {
            return LMStudioNodeLaunchConfig(executablePath: bundledResource, argumentsPrefix: [])
        }

        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if fileManager.isExecutableFile(atPath: candidate) {
                return LMStudioNodeLaunchConfig(executablePath: candidate, argumentsPrefix: [])
            }
        }

        if fileManager.isExecutableFile(atPath: "/usr/bin/env") {
            let probe = runProcessCommand(
                executablePath: "/usr/bin/env",
                arguments: ["node", "--version"],
                timeoutSec: 3.0
            )
            if probe.terminationStatus == 0 {
                return LMStudioNodeLaunchConfig(executablePath: "/usr/bin/env", argumentsPrefix: ["node"])
            }
        }

        return nil
    }

    private static func runCLICommand(
        helperBinaryPath: String,
        arguments: [String],
        timeoutSec: TimeInterval,
        stopWhen: (@Sendable (String) -> Bool)? = nil,
        onOutputUpdate: (@Sendable (String) -> Void)? = nil
    ) -> LMStudioCLIProcessResult {
        let realHome = SharedPaths.realHomeDirectory()
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = realHome.path
        environment["PWD"] = realHome.path
        return runProcessCommand(
            executablePath: helperBinaryPath,
            arguments: arguments,
            currentDirectoryURL: realHome,
            environment: environment,
            timeoutSec: timeoutSec,
            stopWhen: stopWhen,
            onOutputUpdate: onOutputUpdate
        )
    }

    private static func runProcessCommand(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL = SharedPaths.realHomeDirectory(),
        environment: [String: String]? = nil,
        timeoutSec: TimeInterval,
        stopWhen: (@Sendable (String) -> Bool)? = nil,
        onOutputUpdate: (@Sendable (String) -> Void)? = nil
    ) -> LMStudioCLIProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let accumulator = LMStudioCLIOutputAccumulator()
        let processBox = LMStudioProcessBox(process)
        let semaphore = DispatchSemaphore(value: 0)

        let append: @Sendable (Data, Bool) -> Void = { data, toStdout in
            guard !data.isEmpty else { return }
            let combined = accumulator.append(data, toStdout: toStdout)

            onOutputUpdate?(combined)
            if stopWhen?(combined) == true, processBox.process.isRunning {
                accumulator.setTerminatedByCallback()
                processBox.process.terminate()
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            append(data, true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            append(data, false)
        }
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return LMStudioCLIProcessResult(
                stdout: "",
                stderr: "ProcessError: \(error.localizedDescription)",
                timedOut: false,
                terminatedByCallback: false,
                terminationStatus: -1
            )
        }

        var timedOut = false
        let waitResult = semaphore.wait(timeout: .now() + timeoutSec)
        if waitResult == .timedOut {
            timedOut = true
            if process.isRunning {
                process.terminate()
            }
            if semaphore.wait(timeout: .now() + 2.0) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 1.0)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let trailingStdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let trailingStderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        append(trailingStdout, true)
        append(trailingStderr, false)

        let stdout = accumulator.stdoutString()
        let stderr = accumulator.stderrString()
        return LMStudioCLIProcessResult(
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut,
            terminatedByCallback: accumulator.terminatedByCallback,
            terminationStatus: process.terminationStatus
        )
    }

    static func helperFailureDetail(
        from rawOutput: String,
        timedOut: Bool,
        terminationStatus: Int32
    ) -> String {
        for event in helperEvents(from: rawOutput).reversed() {
            guard event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "error" else {
                continue
            }
            let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !message.isEmpty {
                return message
            }
        }

        let output = sanitizedTerminalOutput(rawOutput)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !(line.hasPrefix("{") && line.hasSuffix("}"))
            }
            .suffix(4)
            .joined(separator: " ")
        if !output.isEmpty {
            return output
        }
        if timedOut {
            return HubUIStrings.Models.MarketBridge.helperTimedOut
        }
        return HubUIStrings.Models.MarketBridge.helperExitStatus(terminationStatus)
    }

    private static func cleanedProcessFailureDetail(_ result: LMStudioCLIProcessResult) -> String {
        helperFailureDetail(
            from: result.combinedOutput,
            timedOut: result.timedOut,
            terminationStatus: result.terminationStatus
        )
    }

    private static func lastMeaningfulOutputLine(_ rawOutput: String) -> String {
        let lines = sanitizedTerminalOutput(rawOutput)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !line.hasPrefix("?")
                    && !line.contains("navigate")
                    && !line.contains("select")
            }
        return lines.last ?? ""
    }

    private static func sanitizedTerminalOutput(_ rawOutput: String) -> String {
        var text = applyBackspaces(rawOutput)
        if let regex = terminalEscapeRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        text = text.replacingOccurrences(of: "\r", with: "\n")
        if let regex = nonPrintableControlRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }

    private static func applyBackspaces(_ rawOutput: String) -> String {
        var buffer: [Character] = []
        buffer.reserveCapacity(rawOutput.count)
        for character in rawOutput {
            if character == "\u{8}" {
                if !buffer.isEmpty {
                    buffer.removeLast()
                }
                continue
            }
            buffer.append(character)
        }
        return String(buffer)
    }

    private static func descriptorMatchingTokens(_ descriptor: LMStudioDownloadedModelDescriptor) -> Set<String> {
        let rawValues = [
            descriptor.model,
            descriptor.displayName,
            descriptor.defaultIdentifier,
            descriptor.file,
            descriptor.indexedModelIdentifier,
        ]
        return Set(rawValues.flatMap { matchingTokens(from: $0) })
    }

    static func normalizedMarketKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedMarketKeyParts(_ raw: String) -> [String] {
        normalizedMarketKey(raw)
            .split(separator: "/", maxSplits: 1)
            .map(String.init)
    }

    private static func extractedMarketKey(fromModelPath rawPath: String) -> String? {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let standardized = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        let components = standardized
            .split(separator: "/")
            .map { String($0).lowercased() }

        if let marketIndex = components.firstIndex(of: "_market"),
           components.count > marketIndex + 2 {
            return "\(components[marketIndex + 1])/\(components[marketIndex + 2])"
        }

        if let lmstudioIndex = components.firstIndex(of: ".lmstudio"),
           let modelsIndex = components[(lmstudioIndex + 1)...].firstIndex(of: "models"),
           components.count > modelsIndex + 2 {
            return "\(components[modelsIndex + 1])/\(components[modelsIndex + 2])"
        }

        return nil
    }

    private static func matchingTokens(from raw: String) -> Set<String> {
        let lower = raw.lowercased()
        let components = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(
            components.filter { token in
                token.count >= 2 && !matchingStopWords.contains(token)
            }
        )
    }

    static func stringValue(_ raw: Any?) -> String {
        (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let value = raw as? Int {
            return value
        }
        if let text = raw as? String, let value = Int(text) {
            return value
        }
        return 0
    }
}

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }
}
