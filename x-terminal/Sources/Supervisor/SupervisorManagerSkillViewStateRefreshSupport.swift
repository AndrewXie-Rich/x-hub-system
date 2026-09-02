import Foundation

extension SupervisorManager {
    func supervisorSkillViewStateInputFingerprint(
        projects: [AXProjectEntry]
    ) -> String {
        guard let appModel else { return "no-app" }
        let fileManager = FileManager.default

        return projects.map { project in
            guard let ctx = appModel.projectContext(for: project.projectId) else {
                return [
                    project.projectId,
                    project.displayName,
                    project.rootPath,
                    "missing-context"
                ].joined(separator: "^")
            }

            return [
                project.projectId,
                project.displayName,
                project.rootPath,
                supervisorSkillViewStateFileFingerprint(ctx.supervisorSkillCallsURL, fileManager: fileManager),
                supervisorSkillViewStateFileFingerprint(ctx.resolvedSkillsCacheURL, fileManager: fileManager),
                supervisorSkillViewStateFileFingerprint(ctx.rawLogURL, fileManager: fileManager),
                supervisorSkillViewStateFileFingerprint(ctx.supervisorReviewNotesURL, fileManager: fileManager),
                supervisorSkillViewStateFileFingerprint(ctx.supervisorGuidanceInjectionsURL, fileManager: fileManager),
                supervisorSkillViewStateFileFingerprint(ctx.configURL, fileManager: fileManager)
            ].joined(separator: "^")
        }
        .joined(separator: "|")
    }

    func supervisorSkillViewStateFileFingerprint(
        _ url: URL,
        fileManager: FileManager
    ) -> String {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return "missing:\(url.lastPathComponent)"
        }
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return "\(url.lastPathComponent):\(fileSize):\(String(format: "%.3f", modifiedAt))"
    }

    func refreshResolvedSkillsCacheSynchronouslyForSkillViewState(
        projects: [AXProjectEntry]
    ) {
        guard let appModel else { return }

        for project in projects {
            guard let ctx = appModel.projectContext(for: project.projectId) else { continue }
            let hubBaseDir = HubPaths.baseDir()
            guard XTResolvedSkillsCacheStore.activeSnapshot(for: ctx, hubBaseDir: hubBaseDir) == nil else {
                continue
            }

            let awaitingRecords = SupervisorProjectSkillCallStore.load(for: ctx)
                .calls
                .filter { $0.status == .awaitingAuthorization }
            guard !awaitingRecords.isEmpty else { continue }

            let remoteStateDirPath = awaitingRecords
                .compactMap { record in
                    self.normalizedSupervisorHubStateDirPath(record.hubStateDirPath)
                }
                .first
            guard let remoteStateDirPath else { continue }

            refreshResolvedSkillsCacheSynchronouslyIfPossible(
                project: project,
                ctx: ctx,
                remoteStateDirPath: remoteStateDirPath
            )
        }
    }
}
