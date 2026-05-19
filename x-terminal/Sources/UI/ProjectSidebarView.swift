import SwiftUI
import AppKit

struct ProjectSidebarView: View {
    @Environment(\.xtAppModelReference) private var appModelReference
    @EnvironmentObject private var projectSidebarProjectionStore: XTCoreProjectSidebarProjectionStore

    let isActive: Bool

    init(isActive: Bool = true) {
        self.isActive = isActive
    }

    @ViewBuilder
    var body: some View {
        if isActive {
            activeProjectList
        } else {
            Color.clear
                .frame(minWidth: 220, maxWidth: 320, maxHeight: .infinity)
        }
    }

    private var activeProjectList: some View {
        let snapshot = projectSidebarProjectionStore.snapshot

        return VStack(spacing: 0) {
            List(selection: selectedProjectBinding) {
                Section {
                    Label("Home", systemImage: "house")
                        .tag(AXProjectRegistry.globalHomeId)
                }

                Section("Projects") {
                    ForEach(snapshot.rows) { row in
                        ProjectRowView(
                            row: row
                        )
                        .equatable()
                            .tag(row.id)
                            .contextMenu {
                                Button("接上次进度") {
                                    appModel.presentResumeBrief(projectId: row.id)
                                }

                                Button("Open Project Folder") {
                                    let url = URL(fileURLWithPath: row.rootPath)
                                    appModel.openWorkspaceURL(url)
                                }
                                Button("Remove from List") {
                                    appModel.removeProject(row.id)
                                }
                            }
                    }
                    .onMove { offsets, destination in
                        appModel.moveProjects(from: offsets, to: destination)
                    }
                    .moveDisabled(snapshot.rows.count <= 1)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, maxWidth: 320)
        }
    }

    private var selectedProjectBinding: Binding<String?> {
        Binding(
            get: { projectSidebarProjectionStore.snapshot.selectedProjectId },
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

private struct ProjectRowView: View, Equatable {
    @Environment(\.xtAppModelReference) private var appModelReference
    let row: XTCoreProjectSidebarRowProjection

    static func == (lhs: ProjectRowView, rhs: ProjectRowView) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.displayName)
                    .font(.callout)
                    .lineLimit(1)

                if row.resumeBadgeText != nil {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(row.resumeHelpText ?? "")
                }
            }

            if let s = row.statusDigest {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let resumeBadgeText = row.resumeBadgeText {
                Text(resumeBadgeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(row.resumeHelpText ?? "")
            }

            if let governance = row.governance {
                ProjectSidebarGovernanceTierCards(
                    governance: governance,
                    onExecutionTierTap: {
                        appModel.requestProjectSettingsFocus(
                            projectId: row.id,
                            destination: .executionTier
                        )
                    },
                    onSupervisorTierTap: {
                        appModel.requestProjectSettingsFocus(
                            projectId: row.id,
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
    let governance: XTCoreProjectSidebarGovernanceProjection
    let onExecutionTierTap: () -> Void
    let onSupervisorTierTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            tierCard(
                title: "A-Tier",
                token: governance.executionTierToken,
                label: governance.executionTierLabel,
                color: ProjectGovernanceComposerAccentTone.forExecutionTier(governance.executionTier).color,
                help: governance.executionTierHelp,
                action: onExecutionTierTap
            )

            tierCard(
                title: "S-Tier",
                token: governance.supervisorTierToken,
                label: governance.supervisorTierLabel,
                color: ProjectGovernanceComposerAccentTone.forSupervisorTier(governance.supervisorTier).color,
                help: governance.supervisorTierHelp,
                action: onSupervisorTierTap
            )
        }
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
