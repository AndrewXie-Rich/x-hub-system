import AppKit
import SwiftUI

struct MemoryInspectorView: View {
    let ctx: AXProjectContext
    let memory: AXMemory?

    @State private var mdText: String = ""
    @State private var watcher: FileWatcher? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Memory")
                    .font(.headline)
                Spacer(minLength: 0)

                Button("Open") {
                    NSWorkspace.shared.open(ctx.memoryMarkdownURL)
                }
            }

            Divider()

            ScrollView {
                Text(mdText.isEmpty ? "(empty)" : mdText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
        .padding(10)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        .onAppear {
            refresh()
            let w = FileWatcher(url: ctx.memoryMarkdownURL) {
                refresh()
            }
            w.start()
            watcher = w
        }
        .onDisappear {
            watcher?.stop()
            watcher = nil
        }
        .onChange(of: memory?.updatedAt ?? 0) { _ in
            refresh()
        }
    }

    private func refresh() {
        if let memory {
            mdText = AXMemoryMarkdown.render(memory)
            return
        }
        if let s = try? String(contentsOf: ctx.memoryMarkdownURL, encoding: .utf8) {
            mdText = s
        } else {
            mdText = ""
        }
    }
}
