import SwiftUI

struct ThinkingDotsView: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(dots)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .onReceive(timer) { _ in
                phase = (phase + 1) % 4
            }
            .onDisappear {
                phase = 0
            }
    }

    private var dots: String {
        switch phase {
        case 0: return ""
        case 1: return "."
        case 2: return ".."
        default: return "..."
        }
    }
}
