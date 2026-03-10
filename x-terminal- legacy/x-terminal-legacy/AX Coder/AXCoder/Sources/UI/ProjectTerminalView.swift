import AppKit
import SwiftUI

struct ProjectTerminalView: View {
    let ctx: AXProjectContext
    @ObservedObject var session: TerminalSessionModel

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
        HStack(spacing: 10) {
            Text("Terminal")
                .font(.system(.body, design: .monospaced))
            Text(ctx.root.lastPathComponent)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if let code = session.lastExitCode {
                Text("exit=\(code)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if session.isRunning {
                Text("running")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("stopped")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Button("Restart") {
                session.stop()
                session.ensureStarted()
            }

            Button("Clear") {
                session.clearOutput()
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
}

