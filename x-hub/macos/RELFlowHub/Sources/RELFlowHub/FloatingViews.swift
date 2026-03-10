import SwiftUI
import AppKit
import RELFlowHubCore

extension Notification.Name {
    static let relflowhubOpenMain = Notification.Name("relflowhub.openMain")
}

struct FloatingRootView: View {
    @EnvironmentObject var store: HubStore
    @ObservedObject private var clientStore = ClientStore.shared

    var body: some View {
        Group {
            switch store.floatingMode {
            case .orb:
                // Pass all clients; the orb filters by TTL during animation so satellites
                // disappear even if the client list doesn't refresh.
                let sats = clientStore.clients
                OrbFloatingView(alert: store.topAlert(), satellites: sats)
                    .onTapGesture {
                        // Orb should not react to hover; only a single click action is supported.
                        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
                    }
            case .card:
                CardFloatingView(summary: SummaryStorage.load())
            }
        }
    }
}

struct OrbFloatingView: View {
    let alert: TopAlert
    let satellites: [HubClientHeartbeat]

    fileprivate struct SatelliteVisual: Identifiable, Equatable {
        let id: String
        let appName: String
        let activity: HubClientActivity
        let aiEnabled: Bool
        let seed: Double
        // Visual arrangement: each satellite gets a stable "orbit plane".
        // This is a cheap 2D projection (rotated ellipse) that reads as multi-plane orbits.
        let orbitPlaneAngle: Double
        let orbitRadiusMul: Double
    }

    @State private var fromRGBA: (Double, Double, Double, Double) = (0.0, 0.78, 0.59, 1.0)
    @State private var toRGBA: (Double, Double, Double, Double) = (0.0, 0.78, 0.59, 1.0)
    @State private var transitionStart: Date = .distantPast
    @State private var lastKind: TopAlertKind = .idle

    // Keep rotation phases continuous when omega changes (HubStore updates every ~2s).
    @State private var orbOmegaRef: Double = 0.10
    @State private var orbPhaseBase: Double = 0.0
    @State private var orbPhaseStartT: Double = 0.0
    @State private var satOmegaRef: Double = 0.18
    @State private var satPhaseBase: Double = 0.0
    @State private var satPhaseStartT: Double = 0.0

    private let satPresenceTTL: Double = 12.0

    private let points = ParticleCloud.points(count: 900, seed: 1)

    var body: some View {
        // Low-resource: keep the orb smooth when urgent, but run at a lower tick rate when idle/normal.
        let minInterval = (alert.kind == .meetingUrgent) ? (1.0 / 60.0) : (1.0 / 30.0)
        TimelineView(.animation(minimumInterval: minInterval, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let nowTs = ctx.date.timeIntervalSince1970
            let color = currentColor(now: ctx.date)

            let omegaTarget = orbOmegaTarget()
            let orbitOmegaTarget = satellitesOrbitOmegaTarget()

            // Continuous angles.
            let ay = orbPhaseBase + (t - orbPhaseStartT) * orbOmegaRef
            let ax = ay * 0.67
            let orbitPhase = satPhaseBase + (t - satPhaseStartT) * satOmegaRef

            let sat = satelliteVisuals(now: nowTs)

            let key = phaseKey(omegaTarget: omegaTarget, orbitOmegaTarget: orbitOmegaTarget)

            return ZStack {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)

                    // Important: keep BOTH the orb canvas and the satellites in the same centered
                    // square coordinate space. Otherwise, if the hosting view isn't perfectly
                    // square, the canvas draws in the top-left while satellites stay centered.
                    ZStack {
                        Canvas { context, _ in
                            draw(context: &context, side: side, t: t, ay: ay, ax: ax, rgba: color)
                        }
                        .frame(width: side, height: side)
                        .allowsHitTesting(false)

                        if !sat.shown.isEmpty {
                            SatellitesOrbitLayer(
                                satellites: sat.shown,
                                extraCount: sat.extra,
                                t: t,
                                orbitPhase: orbitPhase,
                                rgba: color,
                                side: side
                            )
                            .frame(width: side, height: side)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(width: side, height: side)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                // Initialize phase anchors once.
                if orbPhaseStartT == 0 || satPhaseStartT == 0 {
                    let t0 = Date().timeIntervalSinceReferenceDate
                    orbOmegaRef = omegaTarget
                    orbPhaseBase = 0
                    orbPhaseStartT = t0
                    satOmegaRef = orbitOmegaTarget
                    satPhaseBase = 0
                    satPhaseStartT = t0
                }
            }
            .onChange(of: key) { _ in
                let t0 = Date().timeIntervalSinceReferenceDate

                // Orb.
                let curAy = orbPhaseBase + (t0 - orbPhaseStartT) * orbOmegaRef
                orbPhaseBase = curAy.truncatingRemainder(dividingBy: 2.0 * Double.pi)
                orbPhaseStartT = t0
                orbOmegaRef = omegaTarget

                // Satellites.
                let curOp = satPhaseBase + (t0 - satPhaseStartT) * satOmegaRef
                satPhaseBase = curOp.truncatingRemainder(dividingBy: 2.0 * Double.pi)
                satPhaseStartT = t0
                satOmegaRef = orbitOmegaTarget
            }
        }
        .onChange(of: alert.kind) { newKind in
            // Smoothly transition between category colors.
            let now = Date()
            fromRGBA = currentColor(now: now)
            toRGBA = rgba(newKind.baseColor)
            transitionStart = now
            lastKind = newKind
        }
        .onAppear {
            lastKind = alert.kind
            let c = rgba(alert.kind.baseColor)
            fromRGBA = c
            toRGBA = c
            transitionStart = Date()
        }
    }

    private func phaseKey(omegaTarget: Double, orbitOmegaTarget: Double) -> String {
        // Discretize to avoid tiny float diffs.
        let a = Int((omegaTarget * 10_000).rounded())
        let b = Int((orbitOmegaTarget * 10_000).rounded())
        return "k=\(alert.kind.rawValue)|c=\(alert.count)|r=\(alert.urgentSecondsToMeeting ?? -1)|w=\(alert.urgentWindowSeconds ?? -1)|o=\(a)|so=\(b)"
    }

    private func satelliteVisuals(now: Double) -> (shown: [SatelliteVisual], extra: Int) {
        // Filter with TTL here so satellites disappear even if the client store does not publish.
        let live = satellites.filter { hb in
            if hb.updatedAt > now + 2.0 { return false }
            return (now - hb.updatedAt) < satPresenceTTL
        }

        let ordered = live
            .map { ($0, stableUnitSeed($0.appId)) }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.appName < b.0.appName
            }

        let shownCount = min(6, ordered.count)
        let planes = orbitPlanes(count: shownCount)
        let radiusMuls = orbitRadiusMultipliers(count: shownCount)

        var out: [SatelliteVisual] = []
        out.reserveCapacity(shownCount)
        for i in 0..<shownCount {
            let (hb, seed) = ordered[i]
            out.append(
                SatelliteVisual(
                    id: hb.appId,
                    appName: hb.appName,
                    activity: hb.activity,
                    aiEnabled: hb.aiEnabled,
                    seed: seed,
                    orbitPlaneAngle: planes[i],
                    orbitRadiusMul: radiusMuls[i]
                )
            )
        }
        return (shown: out, extra: max(0, ordered.count - out.count))
    }

    private func orbitPlanes(count: Int) -> [Double] {
        // Match your mental model:
        // - 1: horizontal
        // - 2: 0°, +45°
        // - 3: 0°, +45°, -45°
        // - 4-6: add +22.5°, -22.5°, then a second 0° (different radius) to keep all planes in
        //        the 0/±45/±22.5 family and avoid a vertical orbit.
        let d2r = Double.pi / 180.0
        let base: [Double] = [
            0.0 * d2r,
            45.0 * d2r,
            -45.0 * d2r,
            22.5 * d2r,
            -22.5 * d2r,
            0.0 * d2r,
        ]
        return Array(base.prefix(max(0, min(6, count))))
    }

    private func orbitRadiusMultipliers(count: Int) -> [Double] {
        // Slight stagger avoids visual collisions at orbit intersections.
        // Keep max radius conservative so satellites stay within the 198x198 panel bounds.
        let base: [Double] = [1.00, 0.97, 1.03, 0.94, 1.01, 0.91]
        return Array(base.prefix(max(0, min(6, count))))
    }

    private func stableUnitSeed(_ s: String) -> Double {
        // Deterministic seed in [0, 1). Not cryptographic; just stable mapping.
        var h: UInt64 = 1469598103934665603 // FNV-1a
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        // Use top 53 bits for a stable unit double.
        let v = Double((h >> 11) & ((1 << 53) - 1))
        return v / Double(1 << 53)
    }

    private func currentColor(now: Date) -> (Double, Double, Double, Double) {
        // 0.9s transition feels natural without looking laggy.
        let dt = now.timeIntervalSince(transitionStart)
        let p = max(0.0, min(1.0, dt / 0.9))
        return (
            lerp(fromRGBA.0, toRGBA.0, p),
            lerp(fromRGBA.1, toRGBA.1, p),
            lerp(fromRGBA.2, toRGBA.2, p),
            lerp(fromRGBA.3, toRGBA.3, p)
        )
    }

    private func urgencyUnit() -> Double {
        // 0 = just became urgent; 1 = imminent.
        guard (alert.kind == .meetingUrgent || alert.kind == .meetingHot || alert.kind == .meetingSoon),
              let remaining = alert.urgentSecondsToMeeting,
              let window = alert.urgentWindowSeconds,
              window > 0 else {
            return 0.0
        }
        let r = Double(max(0, remaining))
        let w = Double(window)
        return max(0.0, min(1.0, 1.0 - (r / w)))
    }

    private func orbitOmega() -> Double {
        // Keep satellites calm, but slightly more lively during urgency.
        let u = urgencyUnit()
        return 0.18 + 0.04 * u
    }

    private func satellitesOrbitOmegaTarget() -> Double {
        orbitOmega()
    }

    private func orbOmegaTarget() -> Double {
        let idleOmega = 0.10
        let u = urgencyUnit()
        let countBoost = 1.0 + min(0.18, Double(max(0, min(alert.count, 12))) * 0.015)
        switch alert.kind {
        case .idle:
            return idleOmega
        case .meetingSoon:
            return idleOmega * (1.18 + 0.16 * u)
        case .meetingHot:
            return idleOmega * (1.34 + 0.22 * u)
        case .mail:
            return idleOmega * 1.08 * countBoost
        case .message:
            return idleOmega * 1.12 * countBoost
        case .slack:
            return idleOmega * 1.10 * countBoost
        case .radar:
            return idleOmega * 1.18 * countBoost
        case .task:
            return idleOmega * 1.14 * countBoost
        case .meetingUrgent:
            return idleOmega * (1.50 + 0.35 * u)
        }
    }

    private func draw(context: inout GraphicsContext, side: CGFloat, t: Double, ay: Double, ax: Double, rgba: (Double, Double, Double, Double)) {
        let cx = side / 2
        let cy = side / 2
        // Leave a bit of margin for satellites to orbit within the 198x198 panel.
        let radius = side * 0.43

        let u = urgencyUnit()

        let cosY = cos(ay)
        let sinY = sin(ay)
        let cosX = cos(ax)
        let sinX = sin(ax)

        // Urgent/hot pulse (brightness + slight size): frequency increases as the meeting gets closer.
        let pulse: Double
        if alert.kind == .meetingUrgent || alert.kind == .meetingHot {
            let baseHz: Double = (alert.kind == .meetingUrgent) ? 1.2 : 0.75
            let maxHz: Double = (alert.kind == .meetingUrgent) ? 2.0 : 1.25
            let hz = baseHz + (maxHz - baseHz) * u
            pulse = 0.6 + 0.4 * ((sin(t * 2.0 * Double.pi * hz) + 1.0) / 2.0)
        } else {
            pulse = 0.0
        }

        for p in points {
            // Rotate around Y.
            let x1 = p.x * cosY + p.z * sinY
            let z1 = -p.x * sinY + p.z * cosY
            // Rotate around X.
            let y2 = p.y * cosX - z1 * sinX
            let z2 = p.y * sinX + z1 * cosX

            // Perspective projection.
            let depth = 1.9
            let denom = max(0.25, depth - z2)
            let s = 1.0 / denom

            let px = cx + CGFloat(x1 * s) * radius
            let py = cy + CGFloat(y2 * s) * radius

            // Depth-based alpha/size.
            let zN = max(-1.0, min(1.0, z2))
            let depthL = (zN + 1.0) / 2.0

            var a = 0.12 + 0.75 * depthL
            if alert.kind == .meetingUrgent || alert.kind == .meetingHot {
                a = min(1.0, a + 0.10 * pulse)
            }

            // Brightness increases for front points.
            let bright = 0.55 + 0.55 * depthL + ((alert.kind == .meetingUrgent || alert.kind == .meetingHot) ? 0.15 * pulse : 0.0)
            let r = min(1.0, rgba.0 * bright)
            let g = min(1.0, rgba.1 * bright)
            let b = min(1.0, rgba.2 * bright)

            let sizeP = CGFloat(0.75 + 1.45 * depthL) * ((alert.kind == .meetingUrgent || alert.kind == .meetingHot) ? CGFloat(1.0 + 0.05 * pulse) : 1.0)
            let rect = CGRect(x: px - sizeP / 2, y: py - sizeP / 2, width: sizeP, height: sizeP)
            // Soften the silhouette to avoid a visible "outer ring".
            let dx = Double((px - cx) / radius)
            let dy = Double((py - cy) / radius)
            let dist = min(1.0, sqrt(dx * dx + dy * dy))
            let edgeFade = smoothstep(1.0, 0.82, dist)

            // Very light "local flow" noise: modulate alpha slightly based on position + time.
            // This keeps the gaps transparent while avoiding a static "printed" look.
            let f1 = 0.5 + 0.5 * sin((x1 * 7.1 + y2 * 9.2 + z2 * 5.7) + t * 0.9)
            let f2 = 0.5 + 0.5 * sin((x1 * 13.7 - y2 * 8.6 + z2 * 11.4) - t * 0.6)
            let flow = 0.88 + 0.12 * (0.65 * f1 + 0.35 * f2)

            let a2 = a * edgeFade * flow
            context.fill(Path(ellipseIn: rect), with: .color(Color(.sRGB, red: r, green: g, blue: b, opacity: a2)))
        }
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        if edge0 == edge1 { return x < edge0 ? 0.0 : 1.0 }
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    private func rgba(_ c: Color) -> (Double, Double, Double, Double) {
        let ns = NSColor(c)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
        return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent), Double(rgb.alphaComponent))
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

private struct ParticlePoint {
    let x: Double
    let y: Double
    let z: Double
}

private enum ParticleCloud {
    static func points(count: Int, seed: UInt64) -> [ParticlePoint] {
        // Deterministic "random-ish" volume distribution.
        // This removes the hard silhouette you get from points strictly on a sphere surface.
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
            let j = 0.05
            x += (rng.nextUnit() - 0.5) * j
            y += (rng.nextUnit() - 0.5) * j
            z += (rng.nextUnit() - 0.5) * j

            // Normalize and apply a radius < 1 to distribute inside the sphere.
            let len = max(1e-6, sqrt(x * x + y * y + z * z))
            x /= len
            y /= len
            z /= len
            let u = rng.nextUnit()
            // Uniform in volume: r = u^(1/3). Bias slightly outward for a "shell" feel.
            let rr = pow(u, 1.0 / 3.0) * 0.96 + 0.04
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

private struct SatellitesOrbitLayer: View {
    let satellites: [OrbFloatingView.SatelliteVisual]
    let extraCount: Int
    let t: Double
    let orbitPhase: Double
    let rgba: (Double, Double, Double, Double)
    let side: CGFloat
    private let orbitSquash: CGFloat = 0.62

    var body: some View {
        let shown = satellites
        // Keep satellites fully inside the panel bounds.
        let rActive: CGFloat = side * 0.46
        let rIdle: CGFloat = side * 0.43

        let hue0 = baseHue(from: rgba)

        return ZStack {
            // No explicit orbit guide rings: keep the design clean.
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                SatelliteDotView(
                    s: s,
                    t: t,
                    orbitPhase: orbitPhase,
                    orbitSquash: orbitSquash,
                    rActive: rActive,
                    rIdle: rIdle,
                    color: satelliteColor(index: i, baseHue: hue0)
                )
            }

            if extraCount > 0 {
                extraBadge(extraCount, y: -rActive)
            }
        }
    }

    private func extraBadge(_ n: Int, y: CGFloat) -> some View {
        Text("+\(n)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.22))
            .clipShape(Capsule())
            .offset(x: 0, y: y)
    }

    private func baseHue(from rgba: (Double, Double, Double, Double)) -> Double {
        // Derive a hue from the orb color so the satellites feel related,
        // then offset each satellite hue slightly.
        let c = NSColor(deviceRed: CGFloat(rgba.0), green: CGFloat(rgba.1), blue: CGFloat(rgba.2), alpha: 1.0)
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h)
    }

    private func satelliteColor(index: Int, baseHue: Double) -> Color {
        // Fixed offsets keep the system readable (avoid random rainbow).
        let offsets: [Double] = [0.00, 0.10, -0.10, 0.20, -0.20, 0.30]
        let off = offsets[max(0, min(offsets.count - 1, index))]
        var h = baseHue + off
        if h < 0 { h += 1 }
        if h > 1 { h -= 1 }
        return Color(hue: h, saturation: 0.72, brightness: 1.0, opacity: 0.95)
    }
}

private struct SatelliteDotView: View {
    let s: OrbFloatingView.SatelliteVisual
    let t: Double
    let orbitPhase: Double
    let orbitSquash: CGFloat
    let rActive: CGFloat
    let rIdle: CGFloat
    let color: Color

    var body: some View {
        // Mix directions + per-satellite speed for a more "alive" system without extra GPU work.
        let dir: Double = (s.seed < 0.5) ? 1.0 : -1.0
        let speedMul: Double = 0.85 + 0.55 * s.seed // stable range [0.85, 1.40]
        let a = s.seed * 2.0 * Double.pi + orbitPhase * speedMul * dir
        let rr: CGFloat = ((s.activity == .active) ? rActive : rIdle) * CGFloat(s.orbitRadiusMul)

        // Project a tilted orbit as a rotated ellipse.
        let x0 = CGFloat(cos(a)) * rr
        let y0 = CGFloat(sin(a)) * rr * orbitSquash
        let ca = CGFloat(cos(s.orbitPlaneAngle))
        let sa = CGFloat(sin(s.orbitPlaneAngle))
        let x = x0 * ca - y0 * sa
        let y = x0 * sa + y0 * ca

        let baseOpacity: Double = (s.activity == .active) ? 1.0 : 0.5
        let breathe: Double = (s.activity == .active)
            ? (0.78 + 0.22 * ((sin(t * 2.0 * Double.pi * 0.8 + s.seed * 10.0) + 1.0) / 2.0))
            : 1.0

        // Subtle size variance: reads more organic, but doesn't distract.
        let baseSize: Double = (s.activity == .active) ? 6.2 : 5.4
        let size = CGFloat(max(4.9, min(6.9, baseSize + (s.seed - 0.5) * 0.75)))

        // Use a light radial gradient for a more "designed" satellite while staying GPU-cheap.
        let fill = RadialGradient(
            colors: [Color.white.opacity(0.82), color, color.opacity(0.55)],
            center: .topLeading,
            startRadius: 0,
            endRadius: Double(size) * 1.25
        )

        return Circle()
            .fill(fill)
            .opacity(baseOpacity * breathe)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 1.2, x: 0, y: 0)
            .overlay {
                if s.aiEnabled {
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                }
            }
            .offset(x: x, y: y)
    }
}

struct CardFloatingView: View {
    @EnvironmentObject var store: HubStore
    let summary: SummaryState

    // Drive the card carousel with a GCD timer. In a non-activating floating NSPanel,
    // RunLoop timers and TimelineView ticks can be unreliable depending on tracking modes.
    @State private var seconds: Int = 0
    @State private var ticker: DispatchSourceTimer?

    private let corner: CGFloat = 20

    private var weekday: String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEE"
        return f.string(from: Date()).uppercased()
    }

    private var weekdayColor: Color {
        // Sunday only should be red (common calendar convention).
        let w = Calendar.current.component(.weekday, from: Date())
        return (w == 1) ? .red : .primary
    }

    private var specialDayText: String {
        // Show special all-day events (e.g. holiday calendars) only when the card has no other content.
        let items = store.specialDaysToday
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if items.isEmpty { return "" }
        // Keep it short on the card; show at most 1-2 names.
        if items.count == 1 { return items[0] }
        return items.prefix(2).joined(separator: " • ")
    }

    private var lunarText: String {
        let cal = Calendar(identifier: .chinese)
        let dc = cal.dateComponents([.month, .day], from: Date())
        let m = dc.month ?? 0
        let d = dc.day ?? 0

        let monthNames = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let dayNames = [
            "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
        ]

        let mm = (m >= 1 && m < monthNames.count) ? monthNames[m] : ""
        let dd = (d >= 1 && d < dayNames.count) ? dayNames[d] : ""
        if mm.isEmpty || dd.isEmpty {
            return ""
        }
        return "\(mm)\(dd)"
    }

    private var monthDayText: String {
        let f = DateFormatter()
        // Keep it consistent with your request (Jan 30), independent of system locale.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    private struct CardItem: Identifiable {
        enum Kind {
            case meeting
            case radar
            case message
            case mail
            case slack
            case other
            case empty
        }

        let id: String
        let kind: Kind
        let tint: Color
        let headerLeft: String
        let headerRight: String
        let line2: String
        let line3: String
        let action: () -> Void
    }

    private struct CardPage: Identifiable {
        enum Kind {
            case meeting
            case radar
            case message
            case mail
            case slack
            case other
        }

        let id: String
        let kind: Kind
        let items: [CardItem]
    }

    private func formatMeetingTimeRange(start: Double, end: Double) -> String {
        let ds = Date(timeIntervalSince1970: start)
        let de = Date(timeIntervalSince1970: end)

        let mer = DateFormatter()
        mer.locale = Locale(identifier: "en_US_POSIX")
        mer.dateFormat = "a"
        let sMer = mer.string(from: ds)
        let eMer = mer.string(from: de)

        let fs = DateFormatter()
        fs.locale = Locale(identifier: "en_US_POSIX")
        fs.dateFormat = (sMer == eMer) ? "h:mm" : "h:mma"

        let fe = DateFormatter()
        fe.locale = Locale(identifier: "en_US_POSIX")
        fe.dateFormat = "h:mma"

        return "\(fs.string(from: ds)) - \(fe.string(from: de))"
    }

    private func meetingCountdownMinutes(startAt: Double, now: Double) -> String {
        let dt = startAt - now
        if dt <= 0 { return "Now" }
        let mins = max(1, Int(ceil(dt / 60.0)))
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            // Display as 2h:17m (more readable than 137m).
            return String(format: "%dh:%02dm", h, m)
        }
        return "\(mins)m"
    }

    private func notificationAgeText(createdAt: Double, now: Double) -> String {
        let dt = max(0, now - createdAt)
        let mins = Int(dt / 60.0)
        if mins >= 120 {
            return "\(mins / 60)h"
        }
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(max(1, mins))m"
    }

    private func notificationsSnapshot() -> [HubNotification] {
        if !store.notifications.isEmpty {
            return store.notifications
        }
        // Fallback: if the in-memory store is empty for any reason, read the persisted file.
        // This makes the card resilient even if it appears before IPC has warmed up.
        // IMPORTANT: don't call ensureHubDirectory() here because it may create/select a
        // different writable directory than the one HubStore persisted to (depending on
        // sandbox/AppGroup flags). Instead, probe all known locations.
        let dirs = SharedPaths.hubDirectoryCandidates()
        for dir in dirs {
            let url = dir.appendingPathComponent("notifications.json")
            if !FileManager.default.fileExists(atPath: url.path) { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            if let arr = try? JSONDecoder().decode([HubNotification].self, from: data) {
                return arr
            }
        }
        return []
    }

    private func cardPages(now: Double) -> [CardPage] {
        // 0) Urgent meeting breaks rotation.
        if let m = store.meetings
            .filter({ $0.isMeeting && !$0.id.isEmpty && !store.isMeetingDismissed($0, now: now) && $0.endAt > now })
            .sorted(by: { $0.startAt < $1.startAt })
            .first
        {
            let mins = Int(ceil(max(0, m.startAt - now) / 60.0))
            if mins <= store.meetingUrgentMinutes {
                let it = CardItem(
                    id: "urgent_\(m.id)|\(Int(m.startAt))",
                    kind: .meeting,
                    tint: Color(red: 1.0, green: 0.32, blue: 0.32),
                    headerLeft: "MEETING",
                    headerRight: (now >= m.startAt) ? "Now" : meetingCountdownMinutes(startAt: m.startAt, now: now),
                    line2: m.title,
                    line3: formatMeetingTimeRange(start: m.startAt, end: m.endAt),
                    action: { store.openMeeting(m) }
                )
                return [CardPage(id: "page_urgent", kind: .meeting, items: [it])]
            }
        }

        var pages: [CardPage] = []

        // Meetings page.
        let ms = store.meetings
            .filter { $0.isMeeting && !$0.id.isEmpty && !store.isMeetingDismissed($0, now: now) && $0.endAt > now }
            .sorted { $0.startAt < $1.startAt }

        func meetingTint(_ m: HubMeeting) -> Color {
            let mins = Int(ceil(max(0, m.startAt - now) / 60.0))
            if now < m.endAt {
                let urgentMin = max(1, store.meetingUrgentMinutes)
                let outerMin = max(urgentMin, store.calendarRemindMinutes)
                let hotMin = min(10, outerMin)
                let base = Color(red: 1.0, green: 0.64, blue: 0.64) // meeting family
                if mins <= urgentMin { return Color(red: 1.0, green: 0.32, blue: 0.32) }
                if mins <= hotMin, hotMin > urgentMin { return Color(red: 1.0, green: 0.48, blue: 0.34) }
                if mins <= outerMin { return base }
                // Still show it's a meeting (but subtle) even when it's far away.
                return base.opacity(0.55)
            }
            return Color.white.opacity(0.55)
        }

        if !ms.isEmpty {
            let items: [CardItem] = ms.prefix(2).map { m in
                CardItem(
                    id: "m_\(m.id)|\(Int(m.startAt))",
                    kind: .meeting,
                    tint: meetingTint(m),
                    headerLeft: "MEETING",
                    headerRight: meetingCountdownMinutes(startAt: m.startAt, now: now),
                    line2: m.title,
                    line3: formatMeetingTimeRange(start: m.startAt, end: m.endAt),
                    action: { store.openMeeting(m) }
                )
            }
            pages.append(CardPage(id: "page_meetings", kind: .meeting, items: items))
        }

        // Radar page: Top2 projects (display), click opens ALL today's new radars.
        do {
            let cal = Calendar.current
            let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
            let active = notificationsSnapshot().filter { ($0.snoozedUntil ?? 0) <= now }
            // Card is both a reminder and a quick info surface: keep showing today's radars
            // even after they've been opened, but only unread affects tint.
            let allFA = active.filter { store.isFATrackerRadarNotification($0) }

            // Prefer "today" (since midnight). If there are none (e.g. you worked late and
            // the last push was yesterday night), fall back to a rolling 24h window.
            let todayFA = allFA.filter { $0.createdAt >= todayStart }
            let recentFA = allFA.filter { $0.createdAt >= (now - 24 * 3600) }
            let shownFA = !todayFA.isEmpty ? todayFA : recentFA

            struct P { let name: String; let ids: [Int]; let unreadCount: Int }
            var byProject: [String: [Int]] = [:]
            var byProjectUnread: [String: Int] = [:]
            var allIds: [Int] = []
            for n in shownFA {
                let bodyLines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                let pn = (bodyLines.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let project = pn.isEmpty ? "(Unknown)" : pn

                var ids: [Int] = []
                if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
                    let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let raw = items.first(where: { $0.name == "radars" })?.value ?? ""
                    ids = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                if ids.isEmpty, bodyLines.count >= 2 {
                    // Backward-compatible: the agent writes a plain id list on line 2.
                    ids = bodyLines[1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    if ids.isEmpty {
                        // Fallback: tolerate whitespace-separated ids or tokens with punctuation.
                        ids = bodyLines[1]
                            .split(whereSeparator: { $0.isWhitespace })
                            .compactMap { tok in
                                let digits = tok.filter { $0.isNumber }
                                guard digits.count >= 5 else { return nil }
                                return Int(digits)
                            }
                    }
                }
                if ids.isEmpty { continue }

                byProject[project, default: []].append(contentsOf: ids)
                if n.unread {
                    byProjectUnread[project, default: 0] += ids.count
                }
                allIds.append(contentsOf: ids)
            }

            // De-dup all ids for click action.
            var seenAll: Set<Int> = []
            allIds = allIds.filter { seenAll.insert($0).inserted }

            // If we fail to parse radar ids for some reason, still show a radar page so the card
            // can rotate and offer a fallback click to open FA Tracker.
            if !byProject.isEmpty || !shownFA.isEmpty {
                var ps: [P] = []
                for (k, v0) in byProject {
                    var seen: Set<Int> = []
                    let ids = v0.filter { seen.insert($0).inserted }
                    ps.append(P(name: k, ids: ids, unreadCount: byProjectUnread[k, default: 0]))
                }
                if ps.isEmpty {
                    // Synthetic bucket with best-effort project name.
                    let firstProj = todayFA.compactMap { n -> String? in
                        let pn = n.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
                        let s = String(pn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }.first
                    ps = [P(name: firstProj ?? "(Unknown)", ids: [], unreadCount: shownFA.filter { $0.unread }.count)]
                }
                ps.sort { a, b in
                    if a.ids.count != b.ids.count { return a.ids.count > b.ids.count }
                    return a.name < b.name
                }
                let shown = Array(ps.prefix(2))
                let items: [CardItem] = shown.map { p in
                    let total = p.ids.count
                    let shownIds = p.ids.prefix(5).map { String($0) }.joined(separator: ", ")
                    let idsText: String = {
                        if p.ids.isEmpty {
                            return "Tap to open FA Tracker"
                        }
                        return (total <= 5) ? shownIds : "\(shownIds)  +\(total - 5)"
                    }()
                    let baseTint = Color(red: 1.0, green: 0.784, blue: 0.341) // #FFC857
                    // Keep family color even after "read" so the page type is obvious.
                    let tint = (p.unreadCount > 0) ? baseTint : baseTint.opacity(0.55)
                    return CardItem(
                        id: "rad_\(p.name)",
                        kind: .radar,
                        tint: tint,
                        headerLeft: "NEW RADAR",
                        headerRight: (p.unreadCount > 0) ? "\(p.unreadCount)" : (total > 0 ? "\(total)" : ""),
                        line2: p.name,
                        line3: idsText,
                        action: {
                            if !allIds.isEmpty {
                                store.openFATrackerForRadars(allIds, projectId: nil, fallbackURL: allIds.first.map { "rdar://\($0)" })
                            } else {
                                _ = store.openFATracker()
                            }
                            // Opening from the card counts as "seen".
                            for n in shownFA where n.unread {
                                store.markRead(n.id)
                            }
                        }
                    )
                }
                pages.append(CardPage(id: "page_radar", kind: .radar, items: items))
            }
        }

        // Messages/Mail/Slack/Other pages are driven by local push notifications.
        // For counts-only notifications (Mail/Messages/Slack), keep showing the card even after
        // the user opened the target app. This makes the card behave like a status dashboard.
        let activeNotifs = notificationsSnapshot().filter {
            guard ($0.snoozedUntil ?? 0) <= now else { return false }
            let key = $0.dedupeKey ?? ""
            let isCountsOnly = (key == "mail_unread" || key == "messages_unread" || key == "slack_updates")
            return $0.unread || isCountsOnly
        }
        func notifPage(source: String, kind: CardPage.Kind, tint: Color) -> CardPage? {
            let rows = activeNotifs.filter { $0.source == source }
            if rows.isEmpty { return nil }
            let items: [CardItem] = rows.prefix(2).map { n in
                let isCountsOnly = (n.dedupeKey == "mail_unread" || n.dedupeKey == "messages_unread" || n.dedupeKey == "slack_updates")
                let headerRight = isCountsOnly ? n.body : notificationAgeText(createdAt: n.createdAt, now: now)
                let line2 = isCountsOnly ? "Tap to open \(source)" : n.title
                let line3 = isCountsOnly ? "" : n.body
                return CardItem(
                    id: "n_\(n.id)",
                    kind: (source == "Messages" ? .message : (source == "Mail" ? .mail : .slack)),
                    tint: tint,
                    headerLeft: source.uppercased(),
                    headerRight: headerRight,
                    line2: line2,
                    line3: line3,
                    action: { store.openNotificationAction(n); store.markRead(n.id) }
                )
            }
            return CardPage(id: "page_\(source)", kind: kind, items: items)
        }

        if let p = notifPage(source: "Messages", kind: .message, tint: Color(red: 0.62, green: 0.90, blue: 0.62)) {
            pages.append(p)
        }
        if let p = notifPage(source: "Mail", kind: .mail, tint: Color(red: 0.35, green: 0.66, blue: 1.00)) {
            pages.append(p)
        }
        if let p = notifPage(source: "Slack", kind: .slack, tint: Color(red: 0.55, green: 0.45, blue: 1.0)) {
            pages.append(p)
        }

        // Other unread notifications (excluding FAtracker + Messages/Mail/Slack).
        let other = activeNotifs.filter { !["FAtracker", "Messages", "Mail", "Slack"].contains($0.source) }
        if !other.isEmpty {
            let items: [CardItem] = other.prefix(2).map { n in
                CardItem(
                    id: "n2_\(n.id)",
                    kind: .other,
                    tint: Color(red: 0.30, green: 0.58, blue: 1.0),
                    headerLeft: n.source.uppercased(),
                    headerRight: notificationAgeText(createdAt: n.createdAt, now: now),
                    line2: n.title,
                    line3: n.body,
                    action: { store.openNotificationAction(n); store.markRead(n.id) }
                )
            }
            pages.append(CardPage(id: "page_other", kind: .other, items: items))
        }

        if pages.isEmpty {
            // Keep a stable empty state.
            let it = CardItem(
                id: "empty",
                kind: .empty,
                tint: .secondary,
                headerLeft: "",
                headerRight: "",
                line2: "All clear",
                line3: "",
                action: { NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil) }
            )
            pages = [CardPage(id: "page_empty", kind: .other, items: [it])]
        }

        return pages
    }

    private func itemBox(_ item: CardItem) -> some View {
        // Use a subtle tinted background so different pages are visually distinguishable
        // (Meeting/Radar/Mail/Slack etc.) while keeping the overall widget-like material.
        // Slightly stronger tint so the page type reads at a glance.
        let bgA: Double = (item.kind == .empty) ? 0.06 : 0.22
        let borderA: Double = (item.kind == .empty) ? 0.12 : 0.40
        let tintBg = item.tint.opacity(bgA)
        return Button {
            item.action()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if item.kind == .empty {
                    Spacer(minLength: 0)
                    Text(item.line2)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 8) {
                        Text(item.headerLeft)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item.tint)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.headerRight)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(item.tint)
                            .lineLimit(1)
                    }
                    Text(item.line2)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    if !item.line3.isEmpty {
                        Text(item.line3)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tintBg, tintBg.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(item.tint.opacity(borderA), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: 56)
    }

    var body: some View {
        let _ = seconds // force periodic re-render
        let now = Date().timeIntervalSince1970
        let pages = cardPages(now: now)
        let pagesKey = pages.map { $0.id }.joined(separator: "|")

        let step = max(0, seconds / 6)
        let safeIdx = pages.isEmpty ? 0 : (step % pages.count)
        let page = pages[safeIdx]

        // Show special day only when there are no non-meeting pages (no unread counts, no radars, etc.).
        let showSpecialDay = !specialDayText.isEmpty && pages.allSatisfy { $0.kind == .meeting }

        return VStack(alignment: .leading, spacing: 8) {
                // Header row: weekday + lunar, right side month+day (same size)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(weekday)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(weekdayColor)
                    if !lunarText.isEmpty {
                        Text(lunarText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    Text(monthDayText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 4)
                .frame(height: 24, alignment: .top)

                if (showSpecialDay || (page.items.count == 1 && page.items[0].kind == .empty)) && !specialDayText.isEmpty {
                    Text(specialDayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if page.items.count == 1 {
                        Spacer(minLength: 0)
                        itemBox(page.items[0])
                        Spacer(minLength: 0)
                    } else {
                        ForEach(page.items.prefix(2)) { it in
                            itemBox(it)
                        }
                    }
                }
            }
            .padding(10)
            .frame(width: FloatingMode.card.panelSize.width, height: FloatingMode.card.panelSize.height)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Tap any empty area of the card to open the main app.
            // Item boxes are Buttons and should win the gesture competition.
            .onTapGesture {
                NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
            }
            // Only the header opens the main window; item boxes stay fully clickable.
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
                    }
            }
            .onAppear {
                if ticker == nil {
                    let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
                    t.schedule(deadline: .now() + 1.0, repeating: 1.0)
                    t.setEventHandler {
                        seconds &+= 1
                    }
                    t.resume()
                    ticker = t
                }
            }
            .onDisappear {
                ticker?.cancel()
                ticker = nil
            }
            // When the page set changes (meetings appear/disappear, radars updated), restart at the first page.
            .onChange(of: pagesKey) { _ in
                seconds = 0
            }
    }
}
