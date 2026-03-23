import SwiftUI
import AppKit

struct ProjectSidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appModel.selectedProjectId) {
                Section {
                    Label("Home", systemImage: "house")
                        .tag(AXProjectRegistry.globalHomeId)
                }

                Section("Projects") {
                    ForEach(appModel.sortedProjects) { project in
                        ProjectRowView(project: project)
                            .tag(project.projectId)
                            .contextMenu {
                                Button("接上次进度") {
                                    appModel.presentResumeBrief(projectId: project.projectId)
                                }
                                .disabled(appModel.sessionSummaryPresentation(projectId: project.projectId) == nil)

                                Button("Open Project Folder") {
                                    let url = URL(fileURLWithPath: project.rootPath)
                                    NSWorkspace.shared.open(url)
                                }
                                Button("Remove from List") {
                                    appModel.removeProject(project.projectId)
                                }
                            }
                    }
                    .onMove { offsets, destination in
                        appModel.moveProjects(from: offsets, to: destination)
                    }
                    .moveDisabled(appModel.sortedProjects.count <= 1)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, maxWidth: 320)
        }
    }
}

private struct ProjectRowView: View {
    @EnvironmentObject private var appModel: AppModel
    let project: AXProjectEntry

    var body: some View {
        let governed = appModel.governedAuthorityPresentation(for: project)
        let governancePresentation = ProjectGovernancePresentation(
            resolved: appModel.resolvedProjectGovernance(for: project)
        )
        let latestSessionSummary = appModel.sessionSummaryPresentation(projectId: project.projectId)
        let latestUIReview = XTUIReviewPresentation.loadLatestBrowserPage(
            for: AXProjectContext(root: URL(fileURLWithPath: project.rootPath, isDirectory: true))
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(project.displayName)
                    .lineLimit(1)

                if latestSessionSummary != nil {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(latestSessionSummary?.helpText ?? "")
                }
            }
            if let s = project.statusDigest, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let latestSessionSummary {
                Text(latestSessionSummary.badgeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(latestSessionSummary.helpText)
            }

            if let latestUIReview {
                ProjectUIReviewCompactSummaryView(review: latestUIReview)
                    .help("\(latestUIReview.compactStatusText)\n\(latestUIReview.updatedText)")
            }

            ProjectGovernanceCompactSummaryView(
                presentation: governancePresentation,
                onExecutionTierTap: {
                    appModel.requestProjectSettingsFocus(
                        projectId: project.projectId,
                        destination: .executionTier
                    )
                },
                onSupervisorTierTap: {
                    appModel.requestProjectSettingsFocus(
                        projectId: project.projectId,
                        destination: .supervisorTier
                    )
                },
                onReviewCadenceTap: {
                    appModel.requestProjectSettingsFocus(
                        projectId: project.projectId,
                        destination: .heartbeatReview
                    )
                },
                onStatusTap: {
                    appModel.requestProjectSettingsFocus(
                        projectId: project.projectId,
                        destination: .overview
                    )
                },
                onCalloutTap: {
                    appModel.requestProjectSettingsFocus(
                        projectId: project.projectId,
                        destination: .overview
                    )
                }
            )

            if governed.hasAnyVisibleSignal {
                HStack(spacing: 4) {
                    if governed.deviceAuthorityConfigured {
                        projectGovernedChip("Device", color: .green)
                    }
                    if governed.localAutoApproveConfigured {
                        projectGovernedChip("Local Auto", color: .orange)
                    }
                    if governed.governedReadableRootCount > 0 {
                        projectGovernedChip("Read+\(governed.governedReadableRootCount)", color: .blue)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func projectGovernedChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
