import SwiftUI

struct SupervisorXTReadyIncidentBoardSection: View {
    let presentation: SupervisorXTReadyIncidentPresentation
    let canOpenCanonicalMemorySyncStatusFile: Bool
    let onExportReport: () -> Void
    let onOpenReport: () -> Void
    let onRetryCanonicalMemorySync: () -> Void
    let onOpenCanonicalMemorySyncStatusFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: presentation.iconName)
                    .foregroundColor(toneColor(presentation.iconTone))
                Text(presentation.title)
                    .font(.headline)

                Spacer()

                Text(presentation.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onExportReport) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("立即导出 XT 就绪事件报告")

                Button(action: onOpenReport) {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .disabled(!presentation.canOpenReport)
                .help("打开导出文件")

                Button(action: onRetryCanonicalMemorySync) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("重推当前 Supervisor 组合视图和项目胶囊的 canonical memory")

                Button(action: onOpenCanonicalMemorySyncStatusFile) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(!canOpenCanonicalMemorySyncStatusFile)
                .help("打开 canonical memory 同步状态文件")
            }

            SupervisorXTReadyIncidentLineView(presentation.statusLine)
            SupervisorXTReadyIncidentLineView(presentation.strictE2ELine)
            SupervisorXTReadyIncidentLineView(presentation.missingIncidentLine)
            SupervisorXTReadyIncidentLineView(presentation.strictIssueLine)
            if let hubRuntimeLine = presentation.hubRuntimeLine {
                SupervisorXTReadyIncidentLineView(hubRuntimeLine)
            }
            if let hubRuntimeIssueLine = presentation.hubRuntimeIssueLine {
                SupervisorXTReadyIncidentLineView(hubRuntimeIssueLine)
            }
            if let hubRuntimeDetailLine = presentation.hubRuntimeDetailLine {
                SupervisorXTReadyIncidentLineView(hubRuntimeDetailLine)
            }
            if let hubRuntimeNextLine = presentation.hubRuntimeNextLine {
                SupervisorXTReadyIncidentLineView(hubRuntimeNextLine)
            }
            SupervisorXTReadyIncidentLineView(presentation.memoryAssemblyLine)
            if let memoryAssemblyIssueLine = presentation.memoryAssemblyIssueLine {
                SupervisorXTReadyIncidentLineView(memoryAssemblyIssueLine)
            }
            if let memoryAssemblyDetailLine = presentation.memoryAssemblyDetailLine {
                SupervisorXTReadyIncidentLineView(memoryAssemblyDetailLine)
            }
            if let canonicalRetryStatusLine = presentation.canonicalRetryStatusLine {
                SupervisorXTReadyIncidentLineView(canonicalRetryStatusLine)
            }
            if let canonicalRetryMetaLine = presentation.canonicalRetryMetaLine {
                SupervisorXTReadyIncidentLineView(canonicalRetryMetaLine)
            }
            if let canonicalRetryDetailLine = presentation.canonicalRetryDetailLine {
                SupervisorXTReadyIncidentLineView(canonicalRetryDetailLine)
            }
            SupervisorXTReadyIncidentLineView(presentation.reportLine)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}

private struct SupervisorXTReadyIncidentLineView: View {
    let line: SupervisorXTReadyIncidentLinePresentation

    init(_ line: SupervisorXTReadyIncidentLinePresentation) {
        self.line = line
    }

    var body: some View {
        let text = Text(line.text)
            .font(.caption2)
            .foregroundStyle(toneColor(line.tone))
            .lineLimit(line.lineLimit)

        if line.isSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private func toneColor(_ tone: SupervisorHeaderControlTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}
