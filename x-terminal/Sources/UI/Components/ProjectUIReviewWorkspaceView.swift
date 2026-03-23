import SwiftUI

struct ProjectUIReviewWorkspaceView: View {
    let ctx: AXProjectContext
    let emptyTitle: String
    let emptyMessage: String
    let helperText: String?
    let showsScreenshotPreview: Bool
    let reloadNonce: Int
    let onSnapshotResolved: ((ToolResult) -> Void)?

    @State private var latestReview: XTUIReviewPresentation?
    @StateObject private var uiReviewActions = XTUIReviewActionState()
    @StateObject private var updateFeedback = XTTransientUpdateFeedbackState()
    @State private var lastObservedReviewSignature: String?

    init(
        ctx: AXProjectContext,
        emptyTitle: String = "暂无浏览器 UI review",
        emptyMessage: String = "该项目还没有最近一次浏览器页面自观察结果。",
        helperText: String? = nil,
        showsScreenshotPreview: Bool = false,
        reloadNonce: Int = 0,
        onSnapshotResolved: ((ToolResult) -> Void)? = nil
    ) {
        self.ctx = ctx
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.helperText = helperText
        self.showsScreenshotPreview = showsScreenshotPreview
        self.reloadNonce = reloadNonce
        self.onSnapshotResolved = onSnapshotResolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let latestReview {
                ProjectUIReviewCard(
                    review: latestReview,
                    onShowHistory: { uiReviewActions.presentHistory() },
                    onResampleSnapshot: {
                        Task {
                            await uiReviewActions.runSnapshot(
                                in: ctx,
                                onSnapshotResolved: onSnapshotResolved
                            )
                        }
                    },
                    isResampling: uiReviewActions.isResampling,
                    showsScreenshotPreview: showsScreenshotPreview
                )
                .projectUIReviewWorkspaceChrome(
                    isUpdated: updateFeedback.isHighlighted,
                    tint: reviewTintColor
                )
                .overlay(alignment: .topTrailing) {
                    if updateFeedback.showsBadge {
                        XTTransientUpdateBadge(tint: reviewTintColor)
                            .padding(.top, 10)
                            .padding(.trailing, 10)
                    }
                }
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
                        Task {
                            await uiReviewActions.runSnapshot(
                                in: ctx,
                                onSnapshotResolved: onSnapshotResolved
                            )
                        }
                    } label: {
                        if uiReviewActions.isResampling {
                            Label("Sampling…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Run Snapshot", systemImage: "camera.viewfinder")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(uiReviewActions.isResampling)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .projectUIReviewWorkspaceChrome(
                    isUpdated: updateFeedback.isHighlighted,
                    tint: reviewTintColor
                )
                .overlay(alignment: .topTrailing) {
                    if updateFeedback.showsBadge {
                        XTTransientUpdateBadge(tint: reviewTintColor)
                            .padding(.top, 10)
                            .padding(.trailing, 10)
                    }
                }
            }

            if !uiReviewActions.statusMessage.isEmpty {
                Text(uiReviewActions.statusMessage)
                    .font(.caption)
                    .foregroundStyle(uiReviewActions.statusIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: "\(ctx.root.path)#\(reloadNonce)#\(uiReviewActions.refreshNonce)") {
            reload()
        }
        .onAppear {
            lastObservedReviewSignature = observedReviewSignature
        }
        .onChange(of: observedReviewSignature) { newValue in
            defer { lastObservedReviewSignature = newValue }
            guard let lastObservedReviewSignature, lastObservedReviewSignature != newValue else {
                return
            }
            updateFeedback.trigger()
        }
        .onChange(of: uiReviewActions.refreshNonce) { refreshNonce in
            guard refreshNonce > 0 else { return }
            updateFeedback.trigger()
        }
        .onDisappear {
            updateFeedback.cancel(resetState: true)
        }
        .sheet(isPresented: $uiReviewActions.showHistorySheet) {
            ProjectUIReviewHistorySheet(ctx: ctx)
        }
    }

    private func reload() {
        latestReview = XTUIReviewPresentation.loadLatestBrowserPage(for: ctx)
    }

    private var observedReviewSignature: String {
        latestReview?.transientUpdateSignature ?? "none"
    }

    private var reviewTintColor: Color {
        guard let latestReview else { return .accentColor }
        switch latestReview.verdict {
        case .ready:
            return .green
        case .attentionNeeded:
            return .orange
        case .insufficientEvidence:
            return .red
        }
    }
}

private extension View {
    func projectUIReviewWorkspaceChrome(
        isUpdated: Bool,
        tint: Color
    ) -> some View {
        xtTransientUpdateCardChrome(
            cornerRadius: 14,
            isUpdated: isUpdated,
            focusTint: tint,
            updateTint: tint,
            baseBackground: .clear,
            baseBorder: .clear,
            updateBackgroundOpacity: 0.04,
            updateBorderOpacity: 0.24,
            updateShadowOpacity: 0.12
        )
    }
}
