import Foundation
import RELFlowHubCore

struct LocalModelAccessBookmarkRecord: Codable, Equatable {
    var path: String
    var bookmarkDataBase64: String
    var updatedAt: TimeInterval
}

struct LocalModelAccessBookmarkSnapshot: Codable, Equatable {
    var records: [LocalModelAccessBookmarkRecord]
    var updatedAt: TimeInterval

    static func empty() -> LocalModelAccessBookmarkSnapshot {
        LocalModelAccessBookmarkSnapshot(records: [], updatedAt: 0)
    }
}

enum LocalModelAccessBookmarkStore {
    static func url(baseDir: URL = SharedPaths.ensureHubDirectory()) -> URL {
        baseDir.appendingPathComponent("local_model_access_bookmarks.json")
    }

    static func load(
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> LocalModelAccessBookmarkSnapshot {
        let snapshotURL = url(baseDir: baseDir)
        guard fileManager.fileExists(atPath: snapshotURL.path),
              let data = try? Data(contentsOf: snapshotURL),
              let decoded = try? JSONDecoder().decode(LocalModelAccessBookmarkSnapshot.self, from: data) else {
            return .empty()
        }
        return normalized(decoded)
    }

    static func save(
        _ snapshot: LocalModelAccessBookmarkSnapshot,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) {
        let snapshotURL = url(baseDir: baseDir)
        do {
            try fileManager.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(normalized(snapshot))
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            HubDiagnostics.log("local_model_access_bookmark_save_failed error=\(error.localizedDescription)")
        }
    }

    static func persistBookmarkIfPossible(
        for url: URL,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default,
        now: TimeInterval = Date().timeIntervalSince1970
    ) {
        let standardizedURL = url.standardizedFileURL
        let normalizedPath = standardizedURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty else { return }

        do {
            let data = try standardizedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var snapshot = load(baseDir: baseDir, fileManager: fileManager)
            let record = LocalModelAccessBookmarkRecord(
                path: normalizedPath,
                bookmarkDataBase64: data.base64EncodedString(),
                updatedAt: now
            )
            if let index = snapshot.records.firstIndex(where: { $0.path == normalizedPath }) {
                snapshot.records[index] = record
            } else {
                snapshot.records.append(record)
            }
            snapshot.updatedAt = now
            save(snapshot, baseDir: baseDir, fileManager: fileManager)
        } catch {
            HubDiagnostics.log(
                "local_model_access_bookmark_persist_failed path=\(normalizedPath) error=\(error.localizedDescription)"
            )
        }
    }

    static func withScopedAccess<T>(
        to url: URL,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default,
        body: () throws -> T
    ) throws -> T {
        let standardizedURL = url.standardizedFileURL
        if let bookmarkURL = resolvedBookmarkURL(
            for: standardizedURL,
            baseDir: baseDir,
            fileManager: fileManager
        ) {
            let accessed = bookmarkURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    bookmarkURL.stopAccessingSecurityScopedResource()
                }
            }
            return try body()
        }

        let accessed = standardizedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    static func resolvedBookmarkURL(
        for url: URL,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> URL? {
        let snapshot = load(baseDir: baseDir, fileManager: fileManager)
        return resolvedBookmarkURL(for: url, snapshot: snapshot)
    }

    static func resolvedBookmarkURL(
        for url: URL,
        snapshot: LocalModelAccessBookmarkSnapshot
    ) -> URL? {
        let normalizedRecords = Dictionary(uniqueKeysWithValues: normalized(snapshot).records.map { ($0.path, $0) })
        for candidatePath in candidateLookupPaths(for: url) {
            guard let record = normalizedRecords[candidatePath],
                  let data = Data(base64Encoded: record.bookmarkDataBase64) else {
                continue
            }
            var stale = false
            guard let resolvedURL = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else {
                continue
            }
            return resolvedURL.standardizedFileURL
        }
        return nil
    }

    static func candidateLookupPaths(for url: URL) -> [String] {
        let standardizedPath = url.standardizedFileURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !standardizedPath.isEmpty else { return [] }
        var candidates: [String] = []
        var currentURL = URL(fileURLWithPath: standardizedPath)
        while true {
            let path = currentURL.standardizedFileURL.path
            if !path.isEmpty {
                candidates.append(path)
            }
            let parentURL = currentURL.deletingLastPathComponent().standardizedFileURL
            if parentURL.path == currentURL.standardizedFileURL.path {
                break
            }
            currentURL = parentURL
        }
        return candidates
    }

    private static func normalized(
        _ snapshot: LocalModelAccessBookmarkSnapshot
    ) -> LocalModelAccessBookmarkSnapshot {
        var deduped: [String: LocalModelAccessBookmarkRecord] = [:]
        for record in snapshot.records {
            let path = URL(fileURLWithPath: record.path).standardizedFileURL.path
            guard !path.isEmpty else { continue }
            let normalizedRecord = LocalModelAccessBookmarkRecord(
                path: path,
                bookmarkDataBase64: record.bookmarkDataBase64,
                updatedAt: record.updatedAt
            )
            if let existing = deduped[path], existing.updatedAt > normalizedRecord.updatedAt {
                continue
            }
            deduped[path] = normalizedRecord
        }
        let records = deduped.values.sorted {
            if $0.path == $1.path {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.path < $1.path
        }
        return LocalModelAccessBookmarkSnapshot(records: records, updatedAt: snapshot.updatedAt)
    }
}
