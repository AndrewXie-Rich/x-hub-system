import SwiftUI
import AppKit

struct ProjectSidebarView: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var projectListStore: XTProjectListStore
    @EnvironmentObject private var workSurfaceStore: XTWorkSurfaceStore

    let isActive: Bool

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    var body: some View {
        let snapshot = projectListSnapshot
        let selectedProjectId = snapshot.selectedProjectId
        let selectedSupplementalRefreshKey = isActive ? sidebarSupplementalRefreshKey : nil

        VStack(spacing: 0) {
            List(selection: selectedProjectBinding) {
                Section {
                    Label("Home", systemImage: "house")
                        .tag(AXProjectRegistry.globalHomeId)
                }

                Section("Projects") {
                    ForEach(snapshot.projects) { project in
                        let isSelected = selectedProjectId == project.projectId
                        ProjectRowView(
                            project: project,
                            isSelected: isSelected,
                            supplementalRefreshKey: isSelected ? selectedSupplementalRefreshKey : nil
                        )
                        .equatable()
                            .tag(project.projectId)
                            .contextMenu {
                                Button("接上次进度") {
                                    appModel.presentResumeBrief(projectId: project.projectId)
                                }

                                Button("Open Project Folder") {
                                    let url = URL(fileURLWithPath: project.rootPath)
                                    appModel.openWorkspaceURL(url)
                                }
                                Button("Remove from List") {
                                    appModel.removeProject(project.projectId)
                                }
                            }
                    }
                    .onMove { offsets, destination in
                        appModel.moveProjects(from: offsets, to: destination)
                    }
                    .moveDisabled(snapshot.projectCount <= 1)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, maxWidth: 320)
        }
    }

    private var projectListSnapshot: XTProjectListSnapshot {
        projectListStore.snapshot
    }

    private var workSurfaceSnapshot: XTWorkSurfaceSnapshot {
        workSurfaceStore.snapshot
    }

    private var sidebarSupplementalRefreshKey: ProjectSidebarSupplementalRefreshKey? {
        guard let selectedProjectId = projectListSnapshot.selectedProjectId,
              workSurfaceSnapshot.selectedProjectId == selectedProjectId else {
            return nil
        }
        return ProjectSidebarSupplementalRefreshKey(
            selectedProjectId: selectedProjectId,
            selectedPane: workSurfaceSnapshot.selectedPane,
            projectConfig: workSurfaceSnapshot.projectConfig
        )
    }

    private var selectedProjectBinding: Binding<String?> {
        Binding(
            get: { projectListSnapshot.selectedProjectId },
            set: { nextProjectId in
                guard let nextProjectId else {
                    appModel.selectedProjectId = nil
                    return
                }
                appModel.selectProject(nextProjectId)
            }
        )
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ProjectSidebarView requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ProjectSidebarSupplementalRefreshKey: Equatable {
    let selectedProjectId: String
    let selectedPane: AXProjectPane
    let projectConfig: AXProjectConfig?
}

private struct ProjectRowView: View, Equatable {
    @Environment(\.xtAppModelReference) private var appModelReference
    let project: AXProjectEntry
    let isSelected: Bool
    let supplementalRefreshKey: ProjectSidebarSupplementalRefreshKey?

    static func == (lhs: ProjectRowView, rhs: ProjectRowView) -> Bool {
        lhs.project == rhs.project &&
            lhs.isSelected == rhs.isSelected &&
            lhs.supplementalRefreshKey == rhs.supplementalRefreshKey
    }

    var body: some View {
        let shouldLoadSupplementalMetadata = isSelected && supplementalRefreshKey != nil
        let governancePresentation = shouldLoadSupplementalMetadata
            ? ProjectGovernancePresentation(
                resolved: appModel.resolvedProjectGovernance(for: project)
            )
            : nil
        let latestSessionSummary = shouldLoadSupplementalMetadata
            ? appModel.sessionSummaryPresentation(projectId: project.projectId)
            : nil

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(project.displayName)
                    .font(.callout)
                    .lineLimit(1)

                if latestSessionSummary != nil {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(latestSessionSummary?.helpText ?? "")
                }
            }

            if isSelected,
               let s = project.statusDigest,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let latestSessionSummary {
                Text(latestSessionSummary.badgeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(latestSessionSummary.helpText)
            }

            if let governancePresentation {
                ProjectSidebarGovernanceTierCards(
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
                    }
                )
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("ProjectRowView requires xtAppModelReference")
        }
        return appModelReference
    }
}

private struct ProjectSidebarGovernanceTierCards: View {
    let presentation: ProjectGovernancePresentation
    let onExecutionTierTap: () -> Void
    let onSupervisorTierTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            tierCard(
                title: "A-Tier",
                token: executionTier.shortToken,
                label: executionTier.localizedShortLabel,
                color: ProjectGovernanceComposerAccentTone.forExecutionTier(executionTier).color,
                help: presentation.effectiveExecutionLabel,
                action: onExecutionTierTap
            )

            tierCard(
                title: "S-Tier",
                token: supervisorTier.shortToken,
                label: supervisorTier.localizedShortLabel,
                color: ProjectGovernanceComposerAccentTone.forSupervisorTier(supervisorTier).color,
                help: presentation.effectiveSupervisorLabel,
                action: onSupervisorTierTap
            )
        }
    }

    private var executionTier: AXProjectExecutionTier {
        presentation.effectiveExecutionTier ?? presentation.executionTier
    }

    private var supervisorTier: AXProjectSupervisorInterventionTier {
        presentation.effectiveSupervisorInterventionTier ?? presentation.supervisorInterventionTier
    }

    private func tierCard(
        title: String,
        token: String,
        label: String,
        color: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(token)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(color)
                    .frame(minWidth: 22, alignment: .leading)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.24), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(title)：\(help)")
    }
}
