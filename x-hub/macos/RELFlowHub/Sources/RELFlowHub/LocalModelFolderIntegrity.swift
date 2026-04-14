import Foundation

struct LocalModelFolderIntegrityIssue: Equatable {
    var code: String
    var summary: String
    var detail: String

    var userMessage: String {
        joinedFolderIntegrityMessage(summary: summary, detail: detail)
    }
}

private func joinedFolderIntegrityMessage(summary: String, detail: String) -> String {
    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSummary.isEmpty else { return trimmedDetail }
    guard !trimmedDetail.isEmpty else { return trimmedSummary }
    let separator = trimmedSummary.hasSuffix("。")
        || trimmedSummary.hasSuffix(".")
        || trimmedSummary.hasSuffix("！")
        || trimmedSummary.hasSuffix("？")
        ? ""
        : " "
    return "\(trimmedSummary)\(separator)\(trimmedDetail)"
}

enum LocalModelFolderIntegrityPolicy {
    static func issue(modelPath: String) -> LocalModelFolderIntegrityIssue? {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        return issue(modelURL: URL(fileURLWithPath: trimmedPath, isDirectory: true))
    }

    private static func issue(modelURL: URL) -> LocalModelFolderIntegrityIssue? {
        if let missingModelPathIssue = missingModelPathIssue(modelURL: modelURL) {
            return missingModelPathIssue
        }
        let fileNames = lowercasedDirectoryEntries(at: modelURL)
        if let partialDownloadIssue = partialDownloadIssue(modelURL: modelURL, fileNames: fileNames) {
            return partialDownloadIssue
        }
        for indexName in ["model.safetensors.index.json", "consolidated.safetensors.index.json"] {
            let indexURL = modelURL.appendingPathComponent(indexName)
            if let issue = missingShardIssue(indexURL: indexURL, modelURL: modelURL) {
                return issue
            }
        }
        return nil
    }

    private static func missingModelPathIssue(
        modelURL: URL
    ) -> LocalModelFolderIntegrityIssue? {
        var isDirectory: ObjCBool = false
        guard !FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        let strings = HubUIStrings.Models.RuntimeCompatibility.self
        return LocalModelFolderIntegrityIssue(
            code: "model_path_missing",
            summary: strings.missingModelPathSummary,
            detail: strings.missingModelPathDetail
        )
    }

    private static func partialDownloadIssue(
        modelURL: URL,
        fileNames: Set<String>
    ) -> LocalModelFolderIntegrityIssue? {
        let partialFiles = fileNames
            .filter { $0.hasSuffix(".part") || $0.hasPrefix("downloading_") }
            .sorted()
        guard !partialFiles.isEmpty else { return nil }
        let examples = partialFiles.prefix(3).joined(separator: ", ")
        let count = partialFiles.count
        let strings = HubUIStrings.Models.RuntimeCompatibility.self
        return LocalModelFolderIntegrityIssue(
            code: "model_download_incomplete",
            summary: strings.partialDownloadSummary,
            detail: strings.partialDownloadDetail(count: count, examples: examples)
        )
    }

    private static func missingShardIssue(
        indexURL: URL,
        modelURL: URL
    ) -> LocalModelFolderIntegrityIssue? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let weightMap = object["weight_map"] as? [String: Any] else { return nil }

        let expectedFiles = Set(
            weightMap.values.compactMap { raw in
                let token = (raw as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return token.isEmpty ? nil : token
            }
        )
        guard !expectedFiles.isEmpty else { return nil }

        let missingFiles = expectedFiles
            .filter { !FileManager.default.fileExists(atPath: modelURL.appendingPathComponent($0).path) }
            .sorted()
        guard !missingFiles.isEmpty else { return nil }

        let examples = missingFiles.prefix(3).joined(separator: ", ")
        let count = missingFiles.count
        let strings = HubUIStrings.Models.RuntimeCompatibility.self
        return LocalModelFolderIntegrityIssue(
            code: "model_shards_missing",
            summary: strings.missingShardsSummary,
            detail: strings.missingShardsDetail(count: count, examples: examples)
        )
    }

    private static func lowercasedDirectoryEntries(at directory: URL) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }
}
