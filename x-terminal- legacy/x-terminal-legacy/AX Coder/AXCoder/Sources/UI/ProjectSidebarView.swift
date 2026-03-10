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
    let project: AXProjectEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.displayName)
                .lineLimit(1)
            if let s = project.statusDigest, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(s)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
