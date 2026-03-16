import SwiftUI

struct ProjectUIReviewWorkspaceView: View {
    let ctx: AXProjectContext
    let emptyTitle: String
    let emptyMessage: String
    let helperText: String?

    @State private var latestReview: XTUIReviewPresentation?
    @State private var isRefreshing = false
    @State private var showHistorySheet = false
    @State private var statusMessage = ""
    @State private var statusIsError = false

    init(
        ctx: AXProjectContext,
        emptyTitle: String = "暂无浏览器 UI review",
        emptyMessage: String = "该项目还没有最近一次浏览器页面自观察结果。",
        helperText: String? = nil
    ) {
        self.ctx = ctx
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.helperText = helperText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let latestReview {
                ProjectUIReviewCard(
                    review: latestReview,
                    onShowHistory: { showHistorySheet = true },
                    onResampleSnapshot: refreshSnapshot,
                    isResampling: isRefreshing
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        refreshSnapshot()
                    } label: {
                        if isRefreshing {
                            Label("Sampling…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Run Snapshot", systemImage: "camera.viewfinder")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRefreshing)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: ctx.root.path) {
            reload()
        }
        .sheet(isPresented: $showHistorySheet) {
            ProjectUIReviewHistorySheet(ctx: ctx)
        }
    }

    private func reload() {
        latestReview = XTUIReviewPresentation.loadLatestBrowserPage(for: ctx)
    }

    private func refreshSnapshot() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = ""
        statusIsError = false

        Task {
            let call = ToolCall(
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("snapshot"),
                    "probe_depth": .string("standard")
                ]
            )

            let result: ToolResult
            do {
                result = try await ToolExecutor.execute(call: call, projectRoot: ctx.root)
            } catch {
                await MainActor.run {
                    statusMessage = "Snapshot failed: \(error.localizedDescription)"
                    statusIsError = true
                    isRefreshing = false
                }
                return
            }

            await MainActor.run {
                reload()
                statusMessage = ToolResultHumanSummary.body(for: result)
                statusIsError = !result.ok
                isRefreshing = false
            }
        }
    }
}
