import SwiftUI

typealias XTTransientUpdateSleep = @Sendable (UInt64) async -> Void

private let xtTransientUpdateLiveSleep: XTTransientUpdateSleep = { nanoseconds in
    try? await Task.sleep(nanoseconds: nanoseconds)
}

@MainActor
final class XTTransientUpdateFeedbackState: ObservableObject {
    @Published private(set) var isHighlighted = false
    @Published private(set) var showsBadge = false

    private let highlightDurationNs: UInt64
    private let sleep: XTTransientUpdateSleep
    private var clearTask: Task<Void, Never>?

    init(
        highlightDurationNs: UInt64 = 1_800_000_000,
        sleep: @escaping XTTransientUpdateSleep = xtTransientUpdateLiveSleep
    ) {
        self.highlightDurationNs = highlightDurationNs
        self.sleep = sleep
    }

    func trigger() {
        clearTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            isHighlighted = true
            showsBadge = true
        }

        let highlightDurationNs = self.highlightDurationNs
        let sleep = self.sleep
        clearTask = Task { [weak self] in
            await sleep(highlightDurationNs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    self.isHighlighted = false
                    self.showsBadge = false
                }
                self.clearTask = nil
            }
        }
    }

    func cancel(resetState: Bool = false) {
        clearTask?.cancel()
        clearTask = nil
        guard resetState else { return }
        isHighlighted = false
        showsBadge = false
    }

}

struct XTTransientUpdateBadge: View {
    let tint: Color
    var title: String = "已更新"
    var font: Font = .caption2.monospaced()
    var fontWeight: Font.Weight? = nil
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 3

    var body: some View {
        Text(title)
            .font(font)
            .fontWeight(fontWeight)
            .foregroundStyle(tint)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct XTTransientUpdateCardChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isFocused: Bool
    let isUpdated: Bool
    let focusTint: Color
    let updateTint: Color
    let baseBackground: Color
    let baseBorder: Color
    var baseLineWidth: CGFloat = 1
    var emphasizedLineWidth: CGFloat = 1.5
    var focusBackgroundOpacity: Double = 0.12
    var focusBorderOpacity: Double = 0.6
    var focusShadowOpacity: Double = 0.16
    var updateBackgroundOpacity: Double = 0.14
    var updateBorderOpacity: Double = 0.38
    var updateShadowOpacity: Double = 0.16
    var shadowRadius: CGFloat = 8
    var shadowYOffset: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .clipShape(shape)
            .overlay(
                shape.stroke(borderColor, lineWidth: lineWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowYOffset)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var lineWidth: CGFloat {
        isFocused || isUpdated ? emphasizedLineWidth : baseLineWidth
    }

    private var backgroundColor: Color {
        if isFocused {
            return focusTint.opacity(focusBackgroundOpacity)
        }
        if isUpdated {
            return updateTint.opacity(updateBackgroundOpacity)
        }
        return baseBackground
    }

    private var borderColor: Color {
        if isFocused {
            return focusTint.opacity(focusBorderOpacity)
        }
        if isUpdated {
            return updateTint.opacity(updateBorderOpacity)
        }
        return baseBorder
    }

    private var shadowColor: Color {
        if isFocused {
            return focusTint.opacity(focusShadowOpacity)
        }
        if isUpdated {
            return updateTint.opacity(updateShadowOpacity)
        }
        return .clear
    }
}

extension View {
    func xtTransientUpdateCardChrome(
        cornerRadius: CGFloat,
        isFocused: Bool = false,
        isUpdated: Bool,
        focusTint: Color,
        updateTint: Color,
        baseBackground: Color,
        baseBorder: Color = .clear,
        baseLineWidth: CGFloat = 1,
        emphasizedLineWidth: CGFloat = 1.5,
        focusBackgroundOpacity: Double = 0.12,
        focusBorderOpacity: Double = 0.6,
        focusShadowOpacity: Double = 0.16,
        updateBackgroundOpacity: Double = 0.14,
        updateBorderOpacity: Double = 0.38,
        updateShadowOpacity: Double = 0.16,
        shadowRadius: CGFloat = 8,
        shadowYOffset: CGFloat = 2
    ) -> some View {
        modifier(
            XTTransientUpdateCardChromeModifier(
                cornerRadius: cornerRadius,
                isFocused: isFocused,
                isUpdated: isUpdated,
                focusTint: focusTint,
                updateTint: updateTint,
                baseBackground: baseBackground,
                baseBorder: baseBorder,
                baseLineWidth: baseLineWidth,
                emphasizedLineWidth: emphasizedLineWidth,
                focusBackgroundOpacity: focusBackgroundOpacity,
                focusBorderOpacity: focusBorderOpacity,
                focusShadowOpacity: focusShadowOpacity,
                updateBackgroundOpacity: updateBackgroundOpacity,
                updateBorderOpacity: updateBorderOpacity,
                updateShadowOpacity: updateShadowOpacity,
                shadowRadius: shadowRadius,
                shadowYOffset: shadowYOffset
            )
        )
    }
}
