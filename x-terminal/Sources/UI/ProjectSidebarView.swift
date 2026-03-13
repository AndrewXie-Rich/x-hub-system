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

        VStack(alignment: .leading, spacing: 2) {
            Text(project.displayName)
                .lineLimit(1)
            if let s = project.statusDigest, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
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
