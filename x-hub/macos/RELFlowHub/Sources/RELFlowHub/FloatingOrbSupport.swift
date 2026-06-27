import SwiftUI
import AppKit
import RELFlowHubCore

struct ParticlePoint {
    let x: Double
    let y: Double
    let z: Double
}

enum ParticleCloud {
    static func points(count: Int, seed: UInt64) -> [ParticlePoint] {
        // Deterministic "random-ish" volume distribution.
        // Keep most points near the outer shell so the orb reads dense without needing
        // an excessive point count, but retain some inner depth so it doesn't look flat.
        let n = max(64, count)
        let ga = Double.pi * (3.0 - sqrt(5.0))
        var pts: [ParticlePoint] = []
        pts.reserveCapacity(n)

        var rng = SplitMix64(seed: seed)
        for i in 0..<n {
            // Fibonacci direction.
            let y0 = 1.0 - (Double(i) + 0.5) * (2.0 / Double(n))
            let r0 = sqrt(max(0.0, 1.0 - y0 * y0))
            let theta = ga * Double(i)
            var x = cos(theta) * r0
            var y = y0
            var z = sin(theta) * r0

            // Add small deterministic jitter.
            let j = 0.04
            x += (rng.nextUnit() - 0.5) * j
            y += (rng.nextUnit() - 0.5) * j
            z += (rng.nextUnit() - 0.5) * j

            // Normalize and apply a radius < 1 to distribute inside the sphere.
            let len = max(1e-6, sqrt(x * x + y * y + z * z))
            x /= len
            y /= len
            z /= len
            let u = rng.nextUnit()
            let shellMix = rng.nextUnit()
            let rr: Double
            if shellMix < 0.78 {
                rr = 0.80 + pow(u, 0.28) * 0.16
            } else if shellMix < 0.95 {
                rr = 0.46 + pow(u, 0.70) * 0.28
            } else {
                rr = 0.18 + pow(u, 1.02) * 0.16
            }
            pts.append(ParticlePoint(x: x * rr, y: y * rr, z: z * rr))
        }
        return pts
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

struct SatellitesOrbitLayer: View {
    let satellites: [OrbFloatingView.SatelliteVisual]
    let t: Double
    let orbitPhase: Double
    let side: CGFloat
    private let orbitSquash: CGFloat = 0.68

    var body: some View {
        let shown = satellites

        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            draw(
                context: &context,
                satellites: shown
            )
        }
    }

    private struct SatelliteRenderState {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let baseOpacity: Double
        let depth: Double
    }

    private struct SatelliteDrawNode {
        let id: String
        let rect: CGRect
        let palette: SatellitePalette
        let baseOpacity: Double
        let depth: Double
    }

    private struct SatellitePalette {
        let base: NSColor
        let bright: NSColor
        let shadow: NSColor
    }

    private func satellitePalette(for satellite: OrbFloatingView.SatelliteVisual, index: Int) -> SatellitePalette {
        let load = max(0.0, min(1.0, satellite.loadUnit))
        let bucket = min(5, max(0, Int((load * 6.0).rounded(.down))))

        let palette: (base: NSColor, bright: NSColor, shadow: NSColor)
        switch bucket {
        case 0:
            palette = (
                NSColor(deviceRed: 0.36, green: 0.93, blue: 0.66, alpha: 1.0),
                NSColor(deviceRed: 0.78, green: 1.0, blue: 0.90, alpha: 1.0),
                NSColor(deviceRed: 0.06, green: 0.33, blue: 0.21, alpha: 1.0)
            )
        case 1:
            palette = (
                NSColor(deviceRed: 0.24, green: 0.82, blue: 0.48, alpha: 1.0),
                NSColor(deviceRed: 0.72, green: 0.98, blue: 0.82, alpha: 1.0),
                NSColor(deviceRed: 0.08, green: 0.30, blue: 0.18, alpha: 1.0)
            )
        case 2:
            palette = (
                NSColor(deviceRed: 0.90, green: 0.74, blue: 0.24, alpha: 1.0),
                NSColor(deviceRed: 1.0, green: 0.92, blue: 0.62, alpha: 1.0),
                NSColor(deviceRed: 0.45, green: 0.28, blue: 0.08, alpha: 1.0)
            )
        case 3:
            palette = (
                NSColor(deviceRed: 0.98, green: 0.58, blue: 0.22, alpha: 1.0),
                NSColor(deviceRed: 1.0, green: 0.84, blue: 0.58, alpha: 1.0),
                NSColor(deviceRed: 0.43, green: 0.18, blue: 0.06, alpha: 1.0)
            )
        case 4:
            palette = (
                NSColor(deviceRed: 0.95, green: 0.38, blue: 0.22, alpha: 1.0),
                NSColor(deviceRed: 1.0, green: 0.76, blue: 0.62, alpha: 1.0),
                NSColor(deviceRed: 0.40, green: 0.12, blue: 0.08, alpha: 1.0)
            )
        default:
            palette = (
                NSColor(deviceRed: 0.86, green: 0.22, blue: 0.24, alpha: 1.0),
                NSColor(deviceRed: 1.0, green: 0.66, blue: 0.70, alpha: 1.0),
                NSColor(deviceRed: 0.34, green: 0.08, blue: 0.11, alpha: 1.0)
            )
        }

        let brightnessBoost = CGFloat((Double(index % 3) * 0.010) + satellite.kind.brightnessBoost)
        return SatellitePalette(
            base: palette.base.blended(withFraction: brightnessBoost, of: .white) ?? palette.base,
            bright: palette.bright.blended(withFraction: brightnessBoost * 0.32, of: .white) ?? palette.bright,
            shadow: palette.shadow
        )
    }

    private func draw(
        context: inout GraphicsContext,
        satellites: [OrbFloatingView.SatelliteVisual]
    ) {
        let center = CGPoint(x: side / 2, y: side / 2)
        context.withCGContext { cg in
            cg.setShouldAntialias(true)
            cg.setAllowsAntialiasing(true)

            let drawNodes = satellites.enumerated().map { index, satellite in
                let render = satelliteRenderState(
                    satellite,
                    satelliteCount: satellites.count
                )
                let palette = satellitePalette(for: satellite, index: index)
                return SatelliteDrawNode(
                    id: satellite.id,
                    rect: CGRect(
                        x: center.x + render.x - render.size / 2,
                        y: center.y + render.y - render.size / 2,
                        width: render.size,
                        height: render.size
                    ),
                    palette: palette,
                    baseOpacity: render.baseOpacity,
                    depth: render.depth
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.depth - rhs.depth) > 0.0001 {
                    return lhs.depth < rhs.depth
                }
                return lhs.id < rhs.id
            }

            for node in drawNodes {
                drawPlanet(
                    cg: cg,
                    rect: node.rect,
                    palette: node.palette,
                    baseOpacity: node.baseOpacity
                )
            }
        }
    }

    private func drawPlanet(
        cg: CGContext,
        rect: CGRect,
        palette: SatellitePalette,
        baseOpacity: Double
    ) {
        let fillColor = palette.base.withAlphaComponent(baseOpacity)
        cg.setFillColor(fillColor.cgColor)
        cg.fillEllipse(in: rect)

        // Keep just a whisper of edge definition so the dot stays readable on bright orb states.
        cg.setStrokeColor(palette.shadow.withAlphaComponent(baseOpacity * 0.06).cgColor)
        cg.setLineWidth(max(0.28, rect.width * 0.010))
        cg.strokeEllipse(in: rect.insetBy(dx: rect.width * 0.022, dy: rect.height * 0.022))
    }

    private func satelliteRenderState(
        _ satellite: OrbFloatingView.SatelliteVisual,
        satelliteCount: Int
    ) -> SatelliteRenderState {
        let dir: Double = (satellite.seed < 0.5) ? 1.0 : -1.0
        let speedMul: Double = 0.92 + 0.36 * satellite.seed
        let angle = satellite.orbitPhaseOffset + orbitPhase * speedMul * dir
        let rr: CGFloat = side * CGFloat(satellite.orbitRadiusFactor)

        let x0 = CGFloat(cos(angle)) * rr
        let y0 = CGFloat(sin(angle)) * rr * orbitSquash
        let ca = CGFloat(cos(satellite.orbitPlaneAngle))
        let sa = CGFloat(sin(satellite.orbitPlaneAngle))
        let x = x0 * ca - y0 * sa
        let y = x0 * sa + y0 * ca

        let baseOpacity = min(0.88, max(0.32, 0.48 + (0.16 * satellite.loadUnit) + satellite.kind.fillOpacityBoost))
        let breatheHz: Double = 0.32 + (0.72 * satellite.loadUnit)
        let breathe: Double = 0.94 + (0.06 * ((sin(t * 2.0 * Double.pi * breatheHz + satellite.seed * 10.0) + 1.0) / 2.0))

        let densityScale = max(0.52, 1.0 - (Double(max(0, satelliteCount - 10)) * 0.016))
        let baseSize = max(4.2, side * 0.0118 * densityScale)
        let loadSizeBoost = side * 0.0022 * CGFloat(satellite.loadUnit) * densityScale
        let size = max(
            baseSize,
            min(
                side * 0.026,
                (baseSize + loadSizeBoost) * satellite.kind.sizeScale * satellite.sizeTier
            )
        )
        return SatelliteRenderState(
            x: x,
            y: y,
            size: size,
            baseOpacity: baseOpacity * breathe,
            depth: Double(sin(angle))
        )
    }
}

private struct SatelliteDotView: View {
    let s: OrbFloatingView.SatelliteVisual
    let satelliteCount: Int
    let t: Double
    let orbitPhase: Double
    let orbitSquash: CGFloat
    let side: CGFloat
    let color: Color

    var body: some View {
        // Keep orbital mechanics stable per satellite.
        // Transient load should only affect color/shine, not angular position,
        // otherwise each snapshot refresh can look like a backward jump.
        let dir: Double = (s.seed < 0.5) ? 1.0 : -1.0
        let speedMul: Double = 0.92 + 0.36 * s.seed
        let a = s.orbitPhaseOffset + orbitPhase * speedMul * dir
        let rr: CGFloat = side * CGFloat(s.orbitRadiusFactor)

        // Project a tilted orbit as a rotated ellipse.
        let x0 = CGFloat(cos(a)) * rr
        let y0 = CGFloat(sin(a)) * rr * orbitSquash
        let ca = CGFloat(cos(s.orbitPlaneAngle))
        let sa = CGFloat(sin(s.orbitPlaneAngle))
        let x = x0 * ca - y0 * sa
        let y = x0 * sa + y0 * ca

        let baseOpacity = min(1.0, max(0.46, 0.62 + (0.26 * s.loadUnit) + s.kind.fillOpacityBoost))
        let breatheHz: Double = 0.32 + (0.72 * s.loadUnit)
        let breathe: Double = 0.78 + (0.22 * ((sin(t * 2.0 * Double.pi * breatheHz + s.seed * 10.0) + 1.0) / 2.0))

        let densityScale = max(0.52, 1.0 - (Double(max(0, satelliteCount - 10)) * 0.018))
        let baseSize = max(4.8, side * 0.015 * densityScale)
        let loadSizeBoost = side * 0.0045 * CGFloat(s.loadUnit) * densityScale
        let size = max(
            baseSize,
            min(
                side * 0.028,
                (baseSize + loadSizeBoost + CGFloat((s.seed - 0.5) * 0.8)) * s.kind.sizeScale
            )
        )
        let ringSize = size * (1.0 + s.kind.ringPaddingFactor)

        return ZStack {
            if s.kind.haloOpacity > 0.01 {
                Circle()
                    .fill(color.opacity(s.kind.haloOpacity * breathe))
                    .frame(width: size * 1.85, height: size * 1.85)
            }
            Circle()
                .fill(color)
                .opacity(baseOpacity * breathe)
                .frame(width: size, height: size)
            if s.kind.ringOpacity > 0.01 {
                Circle()
                    .stroke(Color.white.opacity(s.kind.ringOpacity), lineWidth: max(0.7, side * 0.0017))
                    .frame(width: ringSize, height: ringSize)
            }
            Circle()
                .fill(Color.white.opacity(0.10 + (0.07 * s.loadUnit)))
                .frame(width: size * 0.28, height: size * 0.28)
                .offset(x: -size * 0.12, y: -size * 0.12)
        }
        .offset(x: x, y: y)
    }
}
