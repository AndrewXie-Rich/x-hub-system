import Foundation
import RELFlowHubCore

extension ModelStore {
    func applyCommandResults(
        _ decodedResults: [CommandResultFile],
        invalidURLs: [URL]
    ) {
        for entry in decodedResults {
            lastResultByModelId[entry.result.modelId] = entry.result
            if let pending = pendingByModelId[entry.result.modelId],
               pending.reqId == entry.result.reqId {
                pendingByModelId.removeValue(forKey: entry.result.modelId)
            }
            try? FileManager.default.removeItem(at: entry.url)
        }

        for url in invalidURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated static func collectCommandResults(
        directories: [URL]? = nil
    ) -> (decoded: [CommandResultFile], invalid: [URL]) {
        let directories = directories ?? commandResultDirectoryCandidates()
        guard !directories.isEmpty else { return ([], []) }

        let decoder = JSONDecoder()
        let fileManager = FileManager.default
        var decoded: [CommandResultFile] = []
        var invalid: [URL] = []
        var seenFiles: Set<String> = []

        for directory in directories {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in files where url.pathExtension.lowercased() == "json" {
                let standardizedPath = url.standardizedFileURL.path
                guard seenFiles.insert(standardizedPath).inserted else { continue }
                guard let data = try? Data(contentsOf: url) else {
                    invalid.append(url)
                    continue
                }
                guard let result = try? decoder.decode(ModelCommandResult.self, from: data) else {
                    invalid.append(url)
                    continue
                }
                decoded.append(CommandResultFile(url: url, result: result))
            }
        }

        return (decoded, invalid)
    }

    nonisolated static func commandResultDirectoryCandidates() -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL?) {
            guard let url else { return }
            let standardizedPath = url.standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted else { return }
            out.append(url)
        }

        append(SharedPaths.appGroupDirectory()?.appendingPathComponent("model_results", isDirectory: true))
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent("model_results", isDirectory: true))
        }
        return out
    }
}
