import Foundation

@MainActor
final class SandboxManager: ObservableObject {
    static let shared = SandboxManager()

    @Published private(set) var activeSandboxIDs: Set<UUID> = []
    @Published private(set) var lastErrors: [UUID: String] = [:]

    var providerType: SandboxProviderType = .local
    var configuration: SandboxConfiguration = .default

    private var sandboxes: [UUID: any SandboxProvider] = [:]
    private var lastAccessAt: [UUID: Date] = [:]

    private init() {}

    func createSandbox(for projectId: UUID) async throws -> any SandboxProvider {
        if let existing = sandboxes[projectId] {
            touch(projectId)
            return existing
        }

        let provider = try makeProvider(for: projectId)
        do {
            try await provider.initialize()
            sandboxes[projectId] = provider
            touch(projectId)
            activeSandboxIDs = Set(sandboxes.keys)
            lastErrors.removeValue(forKey: projectId)
            return provider
        } catch {
            lastErrors[projectId] = String(describing: error)
            throw error
        }
    }

    func createSandbox(forProjectRoot root: URL) async throws -> any SandboxProvider {
        try await createSandbox(for: sandboxID(forProjectRoot: root))
    }

    func getSandbox(for projectId: UUID) -> (any SandboxProvider)? {
        guard let sandbox = sandboxes[projectId] else {
            return nil
        }
        touch(projectId)
        return sandbox
    }

    func getSandbox(forProjectRoot root: URL) -> (any SandboxProvider)? {
        getSandbox(for: sandboxID(forProjectRoot: root))
    }

    func destroySandbox(for projectId: UUID) async throws {
        guard let sandbox = sandboxes.removeValue(forKey: projectId) else {
            activeSandboxIDs.remove(projectId)
            lastAccessAt.removeValue(forKey: projectId)
            lastErrors.removeValue(forKey: projectId)
            return
        }

        activeSandboxIDs = Set(sandboxes.keys)
        lastAccessAt.removeValue(forKey: projectId)

        do {
            try await sandbox.cleanup()
            lastErrors.removeValue(forKey: projectId)
        } catch {
            lastErrors[projectId] = "cleanup_failed: \(error)"
            throw error
        }
    }

    func destroySandbox(forProjectRoot root: URL) async throws {
        try await destroySandbox(for: sandboxID(forProjectRoot: root))
    }

    func cleanupInactiveSandboxes(maxIdleTime: TimeInterval = 30 * 60) async {
        let now = Date()
        let staleProjectIDs = lastAccessAt.compactMap { id, lastAccess -> UUID? in
            now.timeIntervalSince(lastAccess) > maxIdleTime ? id : nil
        }

        for projectId in staleProjectIDs {
            do {
                try await destroySandbox(for: projectId)
            } catch {
                print("Sandbox cleanup failed for project \(projectId): \(error)")
            }
        }
    }

    func destroyAllSandboxes() async {
        let allProjectIDs = Array(sandboxes.keys)
        for projectId in allProjectIDs {
            do {
                try await destroySandbox(for: projectId)
            } catch {
                print("Sandbox cleanup failed for project \(projectId): \(error)")
            }
        }
    }

    private func makeProvider(for projectId: UUID) throws -> any SandboxProvider {
        switch providerType {
        case .local:
            return try LocalSandboxProvider(projectId: projectId, configuration: configuration)
        case .docker, .kubernetes:
            throw SandboxError.unsupportedOperation("Sandbox provider not implemented: \(providerType.rawValue)")
        }
    }

    private func touch(_ projectId: UUID) {
        lastAccessAt[projectId] = Date()
    }

    private func sandboxID(forProjectRoot root: URL) -> UUID {
        let stableProjectId = AXProjectRegistryStore.projectId(forRoot: root)
            .lowercased()
            .filter { $0.isHexDigit }

        let padded = String(stableProjectId.prefix(32)).padding(
            toLength: 32,
            withPad: "0",
            startingAt: 0
        )
        let chars = Array(padded)
        guard chars.count == 32 else {
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        }

        let uuidString =
            String(chars[0..<8]) + "-" +
            String(chars[8..<12]) + "-" +
            String(chars[12..<16]) + "-" +
            String(chars[16..<20]) + "-" +
            String(chars[20..<32])

        return UUID(uuidString: uuidString)
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")
            ?? UUID()
    }
}
