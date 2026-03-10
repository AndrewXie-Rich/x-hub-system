import SwiftUI

// A tiny, dependency-free sparkline for token usage.
// Keeps the device manager UI lightweight (no Charts dependency).

struct TokenSparkline: View {
    var points: [GRPCTokenSeriesPoint]
    var strokeColor: Color = .accentColor
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let values = points.map { max(0.0, Double($0.tokens)) }
            let maxV = max(values.max() ?? 0.0, 1.0)
            let n = values.count

            Path { p in
                guard n >= 2 else { return }
                for i in 0..<n {
                    let x = size.width * CGFloat(i) / CGFloat(max(1, n - 1))
                    let yRatio = CGFloat(values[i] / maxV)
                    let y = size.height * (1.0 - yRatio)
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        }
        .frame(minHeight: 14)
    }
}

