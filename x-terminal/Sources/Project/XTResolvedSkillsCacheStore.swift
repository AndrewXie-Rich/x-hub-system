import Dispatch
import Foundation

private actor XTResolvedSkillsCacheRemoteRefreshScope {
    func withAXHubStateDir<T>(
        _ path: String?,
        operation: @Sendable () async -> T
    ) async -> T {
        guard let normalizedPath = XTResolvedSkillsCacheStore.normalizedRemoteStateDirPath(path) else {
            return await operation()
        }

        let key = "AXHUBCTL_STATE_DIR"
        let previous = getenv(key).flatMap { String(validatingUTF8: $0) }
        setenv(key, normalizedPath, 1)
        defer {
            if let previous {
                setenv(key, previous, 1)
            } else {
                unsetenv(key)
            }
        }
        return await operation()
    }
}

enum XTResolvedSkillsCacheStore {
    private static let queue = DispatchQueue(label: "xterminal.resolved_skills_cache_store")
    private static let remoteRefreshScope = XTResolvedSkillsCacheRemoteRefreshScope()

    static func url(for ctx: AXProjectContext) -> URL {
        ctx.resolvedSkillsCacheURL
    }

    static func load(for ctx: AXProjectContext) -> XTResolvedSkillsCacheSnapshot? {
        queue.sync {
            loadUnlocked(for: ctx)
        }
    }

    static func activeSnapshot(
        for ctx: AXProjectContext,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000.0)
    ) -> XTResolvedSkillsCacheSnapshot? {
        queue.sync {
            guard let snapshot = loadUnlocked(for: ctx) else { return nil }
            guard snapshot.expiresAtMs >= nowMs else { return nil }
            let normalizedSource = snapshot.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedSource.hasPrefix("hub_resolved_skills_snapshot"),
               snapshot.hubIndexUpdatedAtMs <= 0 {
                return nil
            }
            let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
            let currentEpoch = AXSkillsLibrary.resolvedSkillsCacheEpochState(
                projectId: snapshot.projectId,
                projectName: snapshot.projectName,
                projectRoot: ctx.root,
                config: config,
                hubBaseDir: HubPaths.baseDir()
            )
            guard snapshot.profileEpoch == currentEpoch.profileEpoch,
                  snapshot.trustRootSetHash == currentEpoch.trustRootSetHash,
                  snapshot.revocationEpoch == currentEpoch.revocationEpoch,
                  snapshot.officialChannelSnapshotID == currentEpoch.officialChannelSnapshotID,
                  snapshot.runtimeSurfaceHash == currentEpoch.runtimeSurfaceHash else {
                return nil
            }
            return snapshot
        }
    }

    @discardableResult
    static func refreshFromHub(
        projectId: String,
        projectName: String? = nil,
        context: AXProjectContext,
        hubBaseDir: URL? = nil,
        ttlMs: Int64 = 15 * 60 * 1000,
        nowMs: Int64? = nil
    ) -> XTResolvedSkillsCacheSnapshot? {
        queue.sync {
            guard let snapshot = AXSkillsLibrary.resolvedSkillsCacheSnapshot(
                projectId: projectId,
                projectName: projectName,
                projectRoot: context.root,
                config: try? AXProjectStore.loadOrCreateConfig(for: context),
                hubBaseDir: hubBaseDir,
                ttlMs: ttlMs,
                nowMs: nowMs
            ) else {
                return nil
            }
            saveUnlocked(snapshot, for: context)
            return snapshot
        }
    }

    @discardableResult
    static func refreshFromHubIfPossible(
        projectId: String,
        projectName: String? = nil,
        context: AXProjectContext,
        hubBaseDir: URL? = nil,
        remoteStateDirPath: String? = nil,
        ttlMs: Int64 = 15 * 60 * 1000,
        nowMs: Int64? = nil,
        force: Bool = false
    ) async -> XTResolvedSkillsCacheSnapshot? {
        let effectiveRemoteStateDirPath =
            normalizedRemoteStateDirPath(remoteStateDirPath)
            ?? normalizedRemoteStateDirPath(load(for: context)?.remoteStateDirPath)
            ?? normalizedRemoteStateDirPath(ProcessInfo.processInfo.environment["AXHUBCTL_STATE_DIR"])

        return await remoteRefreshScope.withAXHubStateDir(effectiveRemoteStateDirPath) {
            if !force, let active = activeSnapshot(for: context) {
                return active
            }

            let explicitStateDir = effectiveRemoteStateDirPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
            if shouldAttemptImplicitRemoteRefresh(remoteStateDirPath: effectiveRemoteStateDirPath),
               await HubPairingCoordinator.shared.hasHubEnv(stateDir: explicitStateDir),
               let remote = await buildRemoteSnapshot(
                   projectId: projectId,
                   projectName: projectName,
                   context: context,
                   hubBaseDir: hubBaseDir,
                   remoteStateDirPath: effectiveRemoteStateDirPath,
                   ttlMs: ttlMs,
                   nowMs: nowMs
               ) {
                queue.sync {
                    saveUnlocked(remote, for: context)
                }
                return remote
            }

            return refreshFromHub(
                projectId: projectId,
                projectName: projectName,
                context: context,
                hubBaseDir: hubBaseDir,
                ttlMs: ttlMs,
                nowMs: nowMs
            )
        }
    }

    static func clear(for ctx: AXProjectContext) {
        queue.sync {
            try? FileManager.default.removeItem(at: url(for: ctx))
        }
    }

    private static func loadUnlocked(for ctx: AXProjectContext) -> XTResolvedSkillsCacheSnapshot? {
        let cacheURL = url(for: ctx)
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(XTResolvedSkillsCacheSnapshot.self, from: data),
              snapshot.schemaVersion == XTResolvedSkillsCacheSnapshot.currentSchemaVersion else {
            return nil
        }
        return snapshot
    }

    private static func saveUnlocked(_ snapshot: XTResolvedSkillsCacheSnapshot, for ctx: AXProjectContext) {
        try? ctx.ensureDirs()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: url(for: ctx))
    }

    private static func shouldAttemptImplicitRemoteRefresh(
        remoteStateDirPath: String?
    ) -> Bool {
        !hasExplicitLocalHubOverrideWithoutRemoteStateDir(remoteStateDirPath: remoteStateDirPath)
    }

    private static func hasExplicitLocalHubOverrideWithoutRemoteStateDir(
        remoteStateDirPath: String?
    ) -> Bool {
        guard HubPaths.baseDirOverride() != nil else { return false }
        return normalizedRemoteStateDirPath(remoteStateDirPath) == nil
    }

    fileprivate static func normalizedRemoteStateDirPath(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func buildRemoteSnapshot(
        projectId: String,
        projectName: String?,
        context: AXProjectContext,
        hubBaseDir: URL?,
        remoteStateDirPath: String?,
        ttlMs: Int64,
        nowMs: Int64?
    ) async -> XTResolvedSkillsCacheSnapshot? {
        let resolved = await HubIPCClient.listResolvedSkills(projectId: projectId)
        guard resolved.ok else { return nil }

        let packageSHA256s = Array(
            Set(
                resolved.skills
                    .map(\.skill.packageSHA256)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        var manifestJSONBySHA: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for packageSHA256 in packageSHA256s {
                group.addTask {
                    let manifest = await HubIPCClient.getSkillManifest(packageSHA256: packageSHA256)
                    guard manifest.ok else { return (packageSHA256, nil) }
                    let normalizedManifest = manifest.manifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (packageSHA256, normalizedManifest.isEmpty ? nil : normalizedManifest)
                }
            }

            for await (packageSHA256, manifestJSON) in group {
                guard let manifestJSON else { continue }
                manifestJSONBySHA[packageSHA256] = manifestJSON
            }
        }

        return AXSkillsLibrary.resolvedSkillsCacheSnapshot(
            projectId: projectId,
            projectName: projectName,
            resolvedSkills: resolved.skills,
            manifestJSONBySHA: manifestJSONBySHA,
            source: resolved.source,
            projectRoot: context.root,
            config: try? AXProjectStore.loadOrCreateConfig(for: context),
            hubBaseDir: hubBaseDir,
            remoteStateDirPath: remoteStateDirPath,
            ttlMs: ttlMs,
            nowMs: nowMs
        )
    }
}
