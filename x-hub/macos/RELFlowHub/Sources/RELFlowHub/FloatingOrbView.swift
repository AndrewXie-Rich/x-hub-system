import SwiftUI
import AppKit
import RELFlowHubCore

struct OrbFloatingView: View {
    let alert: TopAlert
    let devices: [GRPCDeviceStatusEntry]
    let pairedSurfaceClients: [HubClientHeartbeat]
    let snapshotUpdatedAtMs: Int64
    let particleDensity: OrbParticleDensity
    let particleSize: OrbParticleSize

    struct SatelliteVisual: Identifiable, Equatable {
        let id: String
        let kind: SatellitePresenceKind
        let deviceName: String
        let loadUnit: Double
        let recentTokens15m: Int64
        let seed: Double
        let orbitPhaseOffset: Double
        // Visual arrangement: each satellite gets a stable "orbit plane".
        // This is a cheap 2D projection (rotated ellipse) that reads as multi-plane orbits.
        let orbitPlaneAngle: Double
        let orbitRadiusFactor: Double
        let sizeTier: CGFloat
    }

    enum SatellitePresenceKind: Int, CaseIterable {
        case pairedSurfaceLocal = 0
        case xTerminalRemote = 1
        case genericRemote = 2

        var laneCapacity: Int {
            switch self {
            case .pairedSurfaceLocal:
                return 6
            case .xTerminalRemote:
                return 8
            case .genericRemote:
                return 10
            }
        }

        var sizeScale: CGFloat {
            switch self {
            case .pairedSurfaceLocal:
                return 1.08
            case .xTerminalRemote:
                return 0.96
            case .genericRemote:
                return 0.86
            }
        }

        var fillOpacityBoost: Double {
            switch self {
            case .pairedSurfaceLocal:
                return 0.08
            case .xTerminalRemote:
                return 0.04
            case .genericRemote:
                return 0.02
            }
        }

        var haloOpacity: Double {
            switch self {
            case .pairedSurfaceLocal:
                return 0.18
            case .xTerminalRemote:
                return 0.12
            case .genericRemote:
                return 0.06
            }
        }

        var ringOpacity: Double {
            switch self {
            case .pairedSurfaceLocal:
                return 0.22
            case .xTerminalRemote:
                return 0.12
            case .genericRemote:
                return 0.05
            }
        }

        var ringPaddingFactor: CGFloat {
            switch self {
            case .pairedSurfaceLocal:
                return 0.46
            case .xTerminalRemote:
                return 0.28
            case .genericRemote:
                return 0.18
            }
        }

        var brightnessBoost: Double {
            switch self {
            case .pairedSurfaceLocal:
                return 0.04
            case .xTerminalRemote:
                return 0.02
            case .genericRemote:
                return 0.0
            }
        }
    }

    private enum PresenceSource {
        case grpcDevice(GRPCDeviceStatusEntry)
        case pairedSurface(HubClientHeartbeat)

        var stableID: String {
            switch self {
            case .grpcDevice(let device):
                return device.deviceId
            case .pairedSurface(let client):
                return client.appId
            }
        }

        var displayName: String {
            switch self {
            case .grpcDevice(let device):
                let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? device.deviceId : name
            case .pairedSurface(let client):
                let name = client.appName.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? client.appId : name
            }
        }
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
    @State private var cachedSatellites: [SatelliteVisual] = []
    @State private var cachedSatelliteLastSeenAt: [String: Double] = [:]

    private let devicePresenceTTL: Double = 18.0
    private let deviceRecentActivityPresenceTTL: Double = 300.0
    private let deviceSoftPresenceTTL: Double = 90.0
    private let pairedSurfacePresenceTTL: Double = 12.0
    private let snapshotFreshnessTTL: Double = 20.0
    private let satellitePersistenceTTL: Double = 10.0

    private static let points = ParticleCloud.points(count: 720, seed: 1)

    var body: some View {
        let minInterval = timelineMinimumInterval()
        Group {
            if usesDisplayLinkedTimeline {
                TimelineView(.animation(minimumInterval: minInterval, paused: false)) { ctx in
                    renderOrbFrame(date: ctx.date)
                }
            } else {
                TimelineView(.periodic(from: .now, by: minInterval)) { ctx in
                    renderOrbFrame(date: ctx.date)
                }
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
            refreshSatellites()
        }
        .onChange(of: devices) { _ in
            refreshSatellites()
        }
        .onChange(of: pairedSurfaceClients) { _ in
            refreshSatellites()
        }
        .onChange(of: snapshotUpdatedAtMs) { _ in
            refreshSatellites()
        }
    }

    private var usesDisplayLinkedTimeline: Bool {
        alert.kind == .meetingUrgent || alert.kind == .meetingHot
    }

    @ViewBuilder
    private func renderOrbFrame(date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        let color = currentColor(now: date)

        let omegaTarget = orbOmegaTarget()
        let orbitOmegaTarget = satellitesOrbitOmegaTarget()

        // Continuous angles.
        let ay = orbPhaseBase + (t - orbPhaseStartT) * orbOmegaRef
        let ax = ay * 0.67
        let orbitPhase = satPhaseBase + (t - satPhaseStartT) * satOmegaRef

        let key = phaseKey(omegaTarget: omegaTarget, orbitOmegaTarget: orbitOmegaTarget)

        ZStack {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)

                // Important: keep BOTH the orb canvas and the satellites in the same centered
                // square coordinate space. Otherwise, if the hosting view isn't perfectly
                // square, the canvas draws in the top-left while satellites stay centered.
                ZStack {
                    // Transparent floating panels can exhibit temporal tearing when multiple
                    // async canvases race each other. Keep orb rendering on the main render path.
                    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
                        draw(context: &context, side: side, t: t, ay: ay, ax: ax, rgba: color)
                    }
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)

                    if !cachedSatellites.isEmpty {
                        SatellitesOrbitLayer(
                            satellites: cachedSatellites,
                            t: t,
                            orbitPhase: orbitPhase,
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

    private func phaseKey(omegaTarget: Double, orbitOmegaTarget: Double) -> String {
        // Discretize to avoid tiny float diffs.
        let a = Int((omegaTarget * 10_000).rounded())
        let b = Int((orbitOmegaTarget * 10_000).rounded())
        return "k=\(alert.kind.rawValue)|c=\(alert.count)|r=\(alert.urgentSecondsToMeeting ?? -1)|w=\(alert.urgentWindowSeconds ?? -1)|o=\(a)|so=\(b)|d=\(particleDensity.rawValue)|s=\(particleSize.rawValue)"
    }

    private func timelineMinimumInterval() -> Double {
        switch alert.kind {
        case .meetingUrgent:
            return 1.0 / 12.0
        case .meetingHot, .meetingSoon:
            return 1.0 / 8.0
        case .idle:
            return 1.0
        default:
            return 0.5
        }
    }

    private func satelliteVisuals(now: Double) -> [SatelliteVisual] {
        let liveDevices = devices.filter { device in
            deviceCountsAsLive(device, now: now)
        }
        let livePairedSurfaces = pairedSurfaceClients.filter { client in
            let updatedAt = client.updatedAt
            if updatedAt > now + 2.0 { return false }
            if updatedAt <= 0 { return false }
            return (now - updatedAt) < pairedSurfacePresenceTTL
        }

        let ordered = (liveDevices.map(PresenceSource.grpcDevice) + livePairedSurfaces.map(PresenceSource.pairedSurface))
            .map { source in
                (
                    source: source,
                    kind: satellitePresenceKind(for: source),
                    seed: stableUnitSeed(source.stableID)
                )
            }
            .sorted { a, b in
                if a.kind.rawValue != b.kind.rawValue {
                    return a.kind.rawValue < b.kind.rawValue
                }
                if a.seed != b.seed { return a.seed < b.seed }
                return a.source.displayName < b.source.displayName
            }

        var out: [SatelliteVisual] = []
        out.reserveCapacity(ordered.count)

        let grouped = Dictionary(grouping: ordered) { $0.kind }
        let orderedKinds = SatellitePresenceKind.allCases.sorted { $0.rawValue < $1.rawValue }
        let totalLaneCount = max(1, orderedKinds.reduce(into: 0) { partial, kind in
            partial += orbitLaneCount(itemCount: grouped[kind]?.count ?? 0, kind: kind)
        })
        let radiusFactors = orbitRadiusFactors(totalLaneCount: totalLaneCount)

        var laneCursor = 0
        for kind in orderedKinds {
            let items = grouped[kind] ?? []
            guard !items.isEmpty else { continue }

            let laneCount = orbitLaneCount(itemCount: items.count, kind: kind)
            for (index, item) in items.enumerated() {
                let laneInKind = index / max(1, kind.laneCapacity)
                let slotInLane = index % max(1, kind.laneCapacity)
                let globalLane = min(radiusFactors.count - 1, laneCursor + laneInKind)
                let phaseOffset = (item.seed * 2.0 * Double.pi)
                    + (2.0 * Double.pi * Double(slotInLane) / Double(max(1, kind.laneCapacity)))
                out.append(
                    SatelliteVisual(
                        id: item.source.stableID,
                        kind: kind,
                        deviceName: item.source.displayName,
                        loadUnit: presenceLoadUnit(item.source, now: now),
                        recentTokens15m: presenceRecentTokens15m(item.source, now: now),
                        seed: item.seed,
                        orbitPhaseOffset: phaseOffset,
                        orbitPlaneAngle: orbitPlaneAngle(kind: kind, laneInKind: laneInKind, globalLane: globalLane),
                        orbitRadiusFactor: radiusFactors[globalLane],
                        sizeTier: satelliteSizeTier(for: item.seed)
                    )
                )
            }
            laneCursor += laneCount
        }
        return out
    }

    private func satelliteSizeTier(for seed: Double) -> CGFloat {
        switch seed {
        case ..<0.18:
            return 0.72
        case ..<0.42:
            return 0.88
        case ..<0.68:
            return 1.06
        case ..<0.88:
            return 1.28
        default:
            return 1.52
        }
    }

    private func orbitPlaneAngle(kind: SatellitePresenceKind, laneInKind: Int, globalLane: Int) -> Double {
        let d2r = Double.pi / 180.0
        let baseAngles: [Double]
        switch kind {
        case .pairedSurfaceLocal:
            baseAngles = [0.0, 28.0, -28.0, 54.0, -54.0]
        case .xTerminalRemote:
            baseAngles = [16.0, -16.0, 42.0, -42.0, 68.0, -68.0]
        case .genericRemote:
            baseAngles = [8.0, -8.0, 24.0, -24.0, 40.0, -40.0, 58.0, -58.0]
        }
        let base = baseAngles[laneInKind % max(1, baseAngles.count)] * d2r
        let laneWave = Double((globalLane / max(1, baseAngles.count)) % 3) * 6.0 * d2r
        let laneSign: Double = (globalLane % 2 == 0) ? 1.0 : -1.0
        return base + laneWave * laneSign
    }

    private func orbitLaneCount(itemCount: Int, kind: SatellitePresenceKind) -> Int {
        guard itemCount > 0 else { return 0 }
        return Int(ceil(Double(itemCount) / Double(max(1, kind.laneCapacity))))
    }

    private func orbitRadiusFactors(totalLaneCount: Int) -> [Double] {
        let count = max(1, totalLaneCount)
        if count == 1 {
            return [0.458]
        }

        let minFactor = 0.424
        let maxFactor = 0.486
        let step = (maxFactor - minFactor) / Double(max(1, count - 1))
        let wobble: [Double] = [0.0, -0.003, 0.004, -0.001, 0.002, -0.002]

        return (0..<count).map { index in
            let base = minFactor + (Double(index) * step)
            let adjusted = base + wobble[index % wobble.count]
            return max(minFactor, min(maxFactor, adjusted))
        }
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

    private func snapshotAgeSeconds(now: Double) -> Double {
        guard snapshotUpdatedAtMs > 0 else { return Double.greatestFiniteMagnitude }
        let updatedAt = Double(snapshotUpdatedAtMs) / 1000.0
        return max(0.0, now - updatedAt)
    }

    private func deviceCountsAsLive(_ device: GRPCDeviceStatusEntry, now: Double) -> Bool {
        let lastSeen = Double(device.lastSeenAtMs) / 1000.0
        let recentActivityFresh = deviceRecentActivityAgeSeconds(device, now: now).map {
            $0 < deviceRecentActivityPresenceTTL
        } ?? false

        if lastSeen > now + 2.0 { return false }

        if device.connected {
            if lastSeen <= 0 {
                return recentActivityFresh || snapshotAgeSeconds(now: now) < snapshotFreshnessTTL
            }
            return (now - lastSeen) < devicePresenceTTL || recentActivityFresh
        }

        if lastSeen > 0, (now - lastSeen) < deviceSoftPresenceTTL {
            return true
        }

        return recentActivityFresh
    }

    private func deviceRecentActivityAgeSeconds(_ device: GRPCDeviceStatusEntry, now: Double) -> Double? {
        guard let activity = device.lastActivity, activity.createdAtMs > 0 else { return nil }
        let ageSec = max(0.0, now - (Double(activity.createdAtMs) / 1000.0))
        return ageSec > (deviceRecentActivityPresenceTTL * 6.0) ? nil : ageSec
    }

    private func deviceDisplayName(_ device: GRPCDeviceStatusEntry) -> String {
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? device.deviceId : name
    }

    private func satellitePresenceKind(for source: PresenceSource) -> SatellitePresenceKind {
        switch source {
        case .pairedSurface(let client):
            if isPairedSurfaceAppID(client.appId) {
                return .pairedSurfaceLocal
            }
            return isXTerminalAppID(client.appId) ? .xTerminalRemote : .genericRemote
        case .grpcDevice(let device):
            return isXTerminalAppID(device.appId) ? .xTerminalRemote : .genericRemote
        }
    }

    private func isPairedSurfaceAppID(_ appID: String) -> Bool {
        normalizedAppID(appID).hasPrefix("pairedsurface")
    }

    private func isXTerminalAppID(_ appID: String) -> Bool {
        let normalized = normalizedAppID(appID)
        guard !normalized.isEmpty else { return false }
        if normalized.hasPrefix("xterminal") || normalized.hasPrefix("axterminal") {
            return true
        }
        if normalized.contains("xterminal") || normalized.contains("axterminal") {
            return true
        }
        return normalized.hasPrefix("xt")
    }

    private func normalizedAppID(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func presenceRecentTokens15m(_ source: PresenceSource, now: Double) -> Int64 {
        switch source {
        case .grpcDevice(let device):
            return recentTokens15m(device, now: now)
        case .pairedSurface:
            return 0
        }
    }

    private func presenceLoadUnit(_ source: PresenceSource, now: Double) -> Double {
        switch source {
        case .grpcDevice(let device):
            return deviceLoadUnit(device, now: now)
        case .pairedSurface(let client):
            return pairedSurfaceLoadUnit(client, now: now)
        }
    }

    private func recentTokens15m(_ device: GRPCDeviceStatusEntry, now: Double) -> Int64 {
        guard let series = device.tokenSeries5m1h, !series.points.isEmpty else {
            return max(0, device.lastActivity?.totalTokens ?? 0)
        }
        let cutoffMs = Int64((now - (15.0 * 60.0)) * 1000.0)
        return series.points.reduce(into: 0) { partial, point in
            let bucketEnd = point.tMs + max(1, series.bucketMs)
            guard bucketEnd >= cutoffMs else { return }
            partial += max(0, point.tokens)
        }
    }

    private func deviceLoadUnit(_ device: GRPCDeviceStatusEntry, now: Double) -> Double {
        let tokens15m = recentTokens15m(device, now: now)
        let tokenUnit = min(1.0, Double(tokens15m) / 12_000.0)
        let streamUnit = min(0.18, Double(max(0, device.activeEventSubscriptions)) * 0.06)
        let freshActivityBoost: Double = {
            guard let activity = device.lastActivity, activity.createdAtMs > 0 else { return 0.0 }
            let ageSec = max(0.0, now - (Double(activity.createdAtMs) / 1000.0))
            guard ageSec < 180.0 else { return 0.0 }
            let freshness = ageSec < 30.0 ? 1.0 : (ageSec < 60.0 ? 0.65 : 0.28)
            let tokenMagnitude = max(0.08, min(0.34, Double(max(0, activity.totalTokens)) / 5_000.0))
            return freshness * tokenMagnitude
        }()
        return min(1.0, tokenUnit + streamUnit + freshActivityBoost)
    }

    private func pairedSurfaceLoadUnit(_ client: HubClientHeartbeat, now: Double) -> Double {
        let ageSec = max(0.0, now - client.updatedAt)
        let freshnessBoost = ageSec < 2.0 ? 0.06 : 0.0
        switch client.activity {
        case .active:
            return min(1.0, 0.84 + freshnessBoost)
        case .idle:
            return min(1.0, 0.18 + freshnessBoost)
        }
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

    private func pointStride() -> Int {
        let baseStride: Int
        switch alert.kind {
        case .meetingUrgent:
            baseStride = 1
        case .meetingHot, .meetingSoon:
            baseStride = 2
        case .idle:
            baseStride = 6
        default:
            baseStride = 4
        }
        return particleDensity.adjustedStride(baseStride)
    }

    private func draw(context: inout GraphicsContext, side: CGFloat, t: Double, ay: Double, ax: Double, rgba: (Double, Double, Double, Double)) {
        let cx = side / 2
        let cy = side / 2
        // Leave a bit of margin for device planets to orbit around the orb.
        let radius = side * 0.352
        let pointScale = max(0.40, side / 470.0)

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

        let strideValue = max(1, pointStride())
        context.withCGContext { cg in
            cg.setShouldAntialias(true)
            cg.setAllowsAntialiasing(true)

            for index in stride(from: 0, to: Self.points.count, by: strideValue) {
                let p = Self.points[index]
                // Rotate around Y.
                let x1 = p.x * cosY + p.z * sinY
                let z1 = -p.x * sinY + p.z * cosY
                // Rotate around X.
                let y2 = p.y * cosX - z1 * sinX
                let z2 = p.y * sinX + z1 * cosX

                // Perspective projection.
                let depth = 1.92
                let denom = max(0.28, depth - z2)
                let s = 1.0 / denom

                let px = cx + CGFloat(x1 * s) * radius
                let py = cy + CGFloat(y2 * s) * radius

                // Depth-based alpha/size.
                let zN = max(-1.0, min(1.0, z2))
                let depthL = (zN + 1.0) / 2.0

                var alpha = 0.15 + 0.76 * depthL
                if alert.kind == .meetingUrgent || alert.kind == .meetingHot {
                    alpha = min(1.0, alpha + 0.08 * pulse)
                }

                // Brightness increases for front points.
                let brightness = 0.62 + 0.46 * depthL + ((alert.kind == .meetingUrgent || alert.kind == .meetingHot) ? 0.12 * pulse : 0.0)
                let red = min(1.0, rgba.0 * brightness)
                let green = min(1.0, rgba.1 * brightness)
                let blue = min(1.0, rgba.2 * brightness)

                let sizeP = CGFloat(0.24 + 0.48 * depthL)
                    * pointScale
                    * particleSize.scale
                    * ((alert.kind == .meetingUrgent || alert.kind == .meetingHot) ? CGFloat(1.0 + 0.04 * pulse) : 1.0)
                let rect = CGRect(x: px - sizeP / 2, y: py - sizeP / 2, width: sizeP, height: sizeP)

                // Soften the silhouette to avoid a visible "outer ring".
                let dx = Double((px - cx) / radius)
                let dy = Double((py - cy) / radius)
                let dist = min(1.0, sqrt(dx * dx + dy * dy))
                let edgeFade = smoothstep(1.0, 0.72, dist)
                let alpha2 = alpha * edgeFade

                cg.setFillColor(
                    red: red,
                    green: green,
                    blue: blue,
                    alpha: alpha2
                )
                cg.fillEllipse(in: rect)
            }
        }
    }

    private func refreshSatellites(now: Double = Date().timeIntervalSince1970) {
        let freshSatellites = satelliteVisuals(now: now)
        let previousByID = Dictionary(uniqueKeysWithValues: cachedSatellites.map { ($0.id, $0) })
        let freshIDs = Set(freshSatellites.map(\.id))

        var merged: [SatelliteVisual] = []
        merged.reserveCapacity(max(cachedSatellites.count, freshSatellites.count))

        var retainedLastSeenAt: [String: Double] = [:]

        for satellite in freshSatellites {
            let mergedSatellite: SatelliteVisual
            if let previous = previousByID[satellite.id] {
                // Preserve each satellite's orbital geometry across snapshot refreshes so the
                // orbit stays continuous even when device presence data jitters.
                mergedSatellite = SatelliteVisual(
                    id: satellite.id,
                    kind: satellite.kind,
                    deviceName: satellite.deviceName,
                    loadUnit: previous.loadUnit * 0.72 + satellite.loadUnit * 0.28,
                    recentTokens15m: satellite.recentTokens15m,
                    seed: previous.seed,
                    orbitPhaseOffset: previous.orbitPhaseOffset,
                    orbitPlaneAngle: previous.orbitPlaneAngle,
                    orbitRadiusFactor: previous.orbitRadiusFactor,
                    sizeTier: previous.sizeTier
                )
            } else {
                mergedSatellite = satellite
            }
            merged.append(mergedSatellite)
            retainedLastSeenAt[satellite.id] = now
        }

        for satellite in cachedSatellites where !freshIDs.contains(satellite.id) {
            let lastSeenAt = cachedSatelliteLastSeenAt[satellite.id] ?? now
            guard (now - lastSeenAt) <= satellitePersistenceTTL else { continue }

            merged.append(
                SatelliteVisual(
                    id: satellite.id,
                    kind: satellite.kind,
                    deviceName: satellite.deviceName,
                    loadUnit: max(0.10, satellite.loadUnit * 0.92),
                    recentTokens15m: satellite.recentTokens15m,
                    seed: satellite.seed,
                    orbitPhaseOffset: satellite.orbitPhaseOffset,
                    orbitPlaneAngle: satellite.orbitPlaneAngle,
                    orbitRadiusFactor: satellite.orbitRadiusFactor,
                    sizeTier: satellite.sizeTier
                )
            )
            retainedLastSeenAt[satellite.id] = lastSeenAt
        }

        cachedSatellites = merged.sorted { lhs, rhs in
            if lhs.kind.rawValue != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            if lhs.seed != rhs.seed {
                return lhs.seed < rhs.seed
            }
            return lhs.id < rhs.id
        }
        cachedSatelliteLastSeenAt = retainedLastSeenAt
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
