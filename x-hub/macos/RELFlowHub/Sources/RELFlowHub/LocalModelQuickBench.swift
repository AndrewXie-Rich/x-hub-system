import Foundation
import Darwin
import RELFlowHubCore

struct LocalRuntimeCommandLaunchConfig: Sendable {
    let executable: String
    let argumentsPrefix: [String]
    let environment: [String: String]
    let baseDirPath: String
}

struct LocalRuntimePythonProbeLaunchConfig: Sendable {
    let executable: String
    let argumentsPrefix: [String]
    let environment: [String: String]
    let resolvedPythonPath: String
}

struct LocalBenchFixtureDescriptor: Codable, Sendable, Equatable, Identifiable, Hashable {
    var id: String
    var taskKind: String
    var title: String
    var description: String
    var providerIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case taskKind
        case title
        case description
        case providerIDs
    }

    enum SnakeCodingKeys: String, CodingKey {
        case id
        case taskKind = "task_kind"
        case title
        case description
        case providerIDs = "provider_ids"
    }

    init(
        id: String,
        taskKind: String,
        title: String,
        description: String,
        providerIDs: [String] = []
    ) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.taskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerIDs = providerIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.init(
            id: (try? c.decode(String.self, forKey: .id))
                ?? (try? s.decode(String.self, forKey: .id))
                ?? "",
            taskKind: (try? c.decode(String.self, forKey: .taskKind))
                ?? (try? s.decode(String.self, forKey: .taskKind))
                ?? "",
            title: (try? c.decode(String.self, forKey: .title))
                ?? (try? s.decode(String.self, forKey: .title))
                ?? "",
            description: (try? c.decode(String.self, forKey: .description))
                ?? (try? s.decode(String.self, forKey: .description))
                ?? "",
            providerIDs: (try? c.decode([String].self, forKey: .providerIDs))
                ?? (try? s.decode([String].self, forKey: .providerIDs))
                ?? []
        )
    }
}

private struct LocalBenchFixturePack: Codable {
    var schemaVersion: String
    var fixtures: [LocalBenchFixtureDescriptor]
}

private final class LocalBenchFixturePackCacheEntry: NSObject {
    let pack: LocalBenchFixturePack

    init(pack: LocalBenchFixturePack) {
        self.pack = pack
    }
}

enum LocalBenchFixtureCatalog {
    private static let processedBundleName = "RELFlowHub_RELFlowHub.bundle"
    private static let packFileName = "bench_fixture_pack.v1.json"
    nonisolated(unsafe) private static let packCache = NSCache<NSString, LocalBenchFixturePackCacheEntry>()

    static func packURL() -> URL? {
        resolvePackURL(searchRoots: candidateSearchRoots())
    }

    static func fixtures(for taskKind: String, providerID: String) -> [LocalBenchFixtureDescriptor] {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return load().fixtures.filter { fixture in
            guard fixture.taskKind == normalizedTaskKind else { return false }
            if fixture.providerIDs.isEmpty {
                return true
            }
            return fixture.providerIDs.contains(normalizedProviderID)
        }
    }

    static func fixture(id: String) -> LocalBenchFixtureDescriptor? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return load().fixtures.first(where: { $0.id == normalizedID })
    }

    static func defaultFixtureID(for taskKind: String, providerID: String) -> String? {
        fixtures(for: taskKind, providerID: providerID).first?.id
    }

    static func resolvePackURL(searchRoots: [URL]) -> URL? {
        let fm = FileManager.default
        for root in deduplicatedSearchRoots(searchRoots) {
            for candidate in packFileCandidates(under: root) {
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func load() -> LocalBenchFixturePack {
        let cacheKey = NSString(string: "default")
        if let cached = packCache.object(forKey: cacheKey) {
            return cached.pack
        }
        let decoded: LocalBenchFixturePack
        if let url = packURL(),
           let data = try? Data(contentsOf: url),
           let pack = try? JSONDecoder().decode(LocalBenchFixturePack.self, from: data) {
            decoded = pack
        } else {
            decoded = LocalBenchFixturePack(schemaVersion: "", fixtures: [])
        }
        packCache.setObject(LocalBenchFixturePackCacheEntry(pack: decoded), forKey: cacheKey)
        return decoded
    }

    private static func candidateSearchRoots() -> [URL] {
        var roots: [URL] = []

        if let bundledResource = Bundle.main.url(forResource: "RELFlowHub_RELFlowHub", withExtension: "bundle") {
            roots.append(bundledResource)
        }

        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL)
            roots.append(resourceURL.appendingPathComponent(processedBundleName, isDirectory: true))
        }

        if let executableURL = Bundle.main.executableURL ?? defaultExecutableURL() {
            let executableDir = executableURL.deletingLastPathComponent()
            roots.append(executableDir)
            roots.append(executableDir.appendingPathComponent(processedBundleName, isDirectory: true))
        }

        let sourceResourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        roots.append(sourceResourcesURL)

        return deduplicatedSearchRoots(roots)
    }

    private static func packFileCandidates(under root: URL) -> [URL] {
        [
            root.appendingPathComponent(packFileName, isDirectory: false),
            root.appendingPathComponent("BenchFixtures", isDirectory: true)
                .appendingPathComponent(packFileName, isDirectory: false),
        ]
    }

    private static func deduplicatedSearchRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        var deduplicated: [URL] = []
        for root in roots {
            let standardized = root.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                deduplicated.append(standardized)
            }
        }
        return deduplicated
    }

    private static func defaultExecutableURL() -> URL? {
        guard let firstArgument = CommandLine.arguments.first,
              !firstArgument.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: firstArgument, isDirectory: false)
    }
}

enum LocalRuntimeCommandError: LocalizedError {
    case runtimeLaunchConfigUnavailable
    case invalidRequestPayload
    case runFailed(String)
    case timedOut(String)
    case invalidJSON(String)

    var errorDescription: String? {
        let strings = HubUIStrings.Models.Review.QuickBenchRunner.self
        switch self {
        case .runtimeLaunchConfigUnavailable:
            return strings.runtimeLaunchConfigUnavailable
        case .invalidRequestPayload:
            return strings.invalidRequestPayload
        case .runFailed(let message):
            return message
        case .timedOut(let command):
            return strings.timedOut(command)
        case .invalidJSON(let message):
            return message
        }
    }
}

enum LocalRuntimeCommandRunner {
    static func run(
        command: String,
        requestData: Data,
        launchConfig: LocalRuntimeCommandLaunchConfig,
        timeoutSec: TimeInterval = 45.0
    ) throws -> Data {
        guard (try? JSONSerialization.jsonObject(with: requestData, options: [])) != nil else {
            throw LocalRuntimeCommandError.invalidRequestPayload
        }

        LocalRuntimeHelperBridgePreflight.performIfNeeded(
            requestData: requestData,
            launchConfig: launchConfig
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchConfig.executable)
        process.arguments = launchConfig.argumentsPrefix + [command, "-"]
        process.environment = launchConfig.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            throw LocalRuntimeCommandError.runFailed(String(describing: error))
        }

        stdinPipe.fileHandleForWriting.write(requestData)
        try? stdinPipe.fileHandleForWriting.close()

        let waitResult = semaphore.wait(timeout: .now() + max(3.0, timeoutSec))
        if waitResult == .timedOut {
            process.terminate()
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            if semaphore.wait(timeout: .now() + 1.0) == .timedOut {
                throw LocalRuntimeCommandError.timedOut(command)
            }
        }

        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw LocalRuntimeCommandError.runFailed(stderr.isEmpty ? stdout : stderr)
        }

        guard let data = stdout.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) != nil else {
            throw LocalRuntimeCommandError.invalidJSON(stdout.isEmpty ? stderr : stdout)
        }
        return data
    }
}
