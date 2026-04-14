import AppKit
import SwiftUI

struct ProjectTerminalView: View {
    let ctx: AXProjectContext
    @ObservedObject var session: TerminalSessionModel
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.ensureStarted()
        }
    }

    private var header: some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Terminal")
                    .font(.system(.body, design: .monospaced))
                Text(ctx.displayName())
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let code = session.lastExitCode {
                    terminalStatusChip("exit=\(code)", color: .secondary)
                }

                terminalStatusChip(
                    session.isRunning ? "running" : "stopped",
                    color: session.isRunning ? .green : .secondary
                )
            }

            ProjectGovernanceCompactSummaryView(
                presentation: governancePresentation,
                configuration: .operationalDense,
                onExecutionTierTap: { openGovernance(.executionTier) },
                onSupervisorTierTap: { openGovernance(.supervisorTier) },
                onReviewCadenceTap: { openGovernance(.heartbeatReview) },
                onStatusTap: { openGovernance(.overview) },
                onCalloutTap: { openGovernance(.overview) }
            )

            ProjectGovernanceQuickAccessStrip(
                selectedDestination: nil,
                governancePresentation: governancePresentation,
                displayStyle: .compact,
                onSelect: openGovernance
            )

            HStack(spacing: 10) {
                Text("Project-bound shell")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button("Restart") {
                    session.stop()
                    session.ensureStarted()
                }

                Button("Clear") {
                    session.clearOutput()
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
    }

    private var transcript: some View {
        TranscriptTextView(attributedText: transcriptAttributed)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Type a command…", text: $session.draft)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        session.sendLine()
                    }

                Button("Send") {
                    session.sendLine()
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Ctrl+C") {
                    session.sendCtrlC()
                }

                if let err = session.lastError, !err.isEmpty {
                    Text(err)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var transcriptAttributed: NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return NSAttributedString(
            string: session.output.isEmpty ? "(empty)" : session.output,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    private var projectId: String {
        AXProjectRegistryStore.projectId(forRoot: ctx.root)
    }

    private var projectConfig: AXProjectConfig {
        if appModel.projectContext?.root.standardizedFileURL == ctx.root.standardizedFileURL,
           let config = appModel.projectConfig {
            return config
        }
        return (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
    }

    private var governancePresentation: ProjectGovernancePresentation {
        ProjectGovernancePresentation(
            resolved: appModel.resolvedProjectGovernance(for: ctx, config: projectConfig)
        )
    }

    private func openGovernance(_ destination: XTProjectGovernanceDestination) {
        appModel.requestProjectSettingsFocus(
            projectId: projectId,
            destination: destination,
            preserveCurrentPane: true
        )
    }

    private func terminalStatusChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }
}
