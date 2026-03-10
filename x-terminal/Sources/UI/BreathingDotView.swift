import SwiftUI

struct BreathingDotView: View {
    var label: String
    var isActive: Bool

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .opacity(isActive ? (pulse ? 0.25 : 1.0) : 1.0)
                .onAppear {
                    pulse = false
                    if isActive {
                        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                }
                .onChange(of: isActive) { active in
                    pulse = false
                    if active {
                        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                            pulse = true
                        }
                    }
                }

            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(label) \(isActive ? "running" : "idle")")
    }
}
