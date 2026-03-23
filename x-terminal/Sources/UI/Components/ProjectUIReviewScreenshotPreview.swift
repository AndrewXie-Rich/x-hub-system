import AppKit
import SwiftUI

struct ProjectUIReviewScreenshotPreview: View {
    let url: URL
    var title: String? = "页面快照"
    var height: CGFloat = 180
    var maxHeight: CGFloat = 220
    var cornerRadius: CGFloat = 12
    var allowsExpandedPreview: Bool = false

    @State private var image: NSImage?
    @State private var showsExpandedPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Group {
                if let image {
                    previewContent(image: image)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                        ProgressView()
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if image != nil, allowsExpandedPreview {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .padding(8)
                }
            }
        }
        .task(id: url.path) {
            image = NSImage(contentsOf: url)
        }
        .sheet(isPresented: $showsExpandedPreview) {
            ProjectUIReviewScreenshotLightbox(
                url: url,
                title: title,
                image: image
            )
        }
    }

    @ViewBuilder
    private func previewContent(image: NSImage) -> some View {
        if allowsExpandedPreview {
            Button {
                showsExpandedPreview = true
            } label: {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .buttonStyle(.plain)
            .help("点击查看大图")
        } else {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct ProjectUIReviewScreenshotLightbox: View {
    let url: URL
    let title: String?
    let image: NSImage?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedTitle)
                        .font(.headline)
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.bordered)

                Button("Open File") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("加载截图中…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
                .padding(8)
            }
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .frame(minWidth: 820, minHeight: 620)
    }

    private var resolvedTitle: String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "页面快照" : trimmed
    }
}
