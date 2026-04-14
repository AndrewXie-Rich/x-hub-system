import SwiftUI
import AppKit
import RELFlowHubCore

extension Notification.Name {
    static let relflowhubOpenMain = Notification.Name("relflowhub.openMain")
}

struct FloatingRootView: View {
    @EnvironmentObject var store: HubStore
    @State private var grpcDevicesStatus: GRPCDevicesStatusSnapshot = .empty()
    @State private var grpcDevicesStatusRefreshInFlight: Bool = false
    @StateObject private var clientStore = ClientStore.shared

    var body: some View {
        Group {
            if store.suppressFloatingContent {
                Color.clear
            } else {
                switch store.floatingMode {
                case .orb:
                    OrbFloatingView(
                        alert: store.topAlert(),
                        devices: grpcDevicesStatus.devices,
                        pairedSurfaceClients: pairedSurfaceClients,
                        snapshotUpdatedAtMs: grpcDevicesStatus.updatedAtMs
                    )
                        .onTapGesture {
                            // Orb should not react to hover; only a single click action is supported.
                            NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
                        }
                case .card:
                    CardFloatingView(summary: SummaryStorage.load())
                }
            }
        }
        .onAppear {
            refreshGRPCDevicesStatus()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            refreshGRPCDevicesStatus()
        }
    }

    private var pairedSurfaceClients: [HubClientHeartbeat] {
        clientStore.liveClients().filter { client in
            let appID = client.appId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !appID.isEmpty else { return false }
            if appID.hasPrefix("sys_") { return false }
            if appID == "hub" || appID == "relflowhub" { return false }
            return true
        }
    }

    private func refreshGRPCDevicesStatus() {
        guard !grpcDevicesStatusRefreshInFlight else { return }
        grpcDevicesStatusRefreshInFlight = true

        Task.detached(priority: .utility) {
            let snapshot = GRPCDevicesStatusStorage.load()
            await MainActor.run {
                grpcDevicesStatus = snapshot
                grpcDevicesStatusRefreshInFlight = false
            }
        }
    }
}

struct OrbFloatingView: View {
    let alert: TopAlert
    let devices: [GRPCDeviceStatusEntry]
    let pairedSurfaceClients: [HubClientHeartbeat]
    let snapshotUpdatedAtMs: Int64

    fileprivate struct SatelliteVisual: Identifiable, Equatable {
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

    fileprivate enum SatellitePresenceKind: Int, CaseIterable {
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

    private let points = ParticleCloud.points(count: 2520, seed: 1)

    var body: some View {
        // Keep the orb readable without burning the main thread.
        let minInterval: Double = {
            switch alert.kind {
            case .meetingUrgent:
                return 1.0 / 30.0
            case .meetingHot, .meetingSoon:
                return 1.0 / 26.0
            case .idle:
                return 1.0 / 20.0
            default:
                return 1.0 / 22.0
            }
        }()
        TimelineView(.animation(minimumInterval: minInterval, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let color = currentColor(now: ctx.date)

            let omegaTarget = orbOmegaTarget()
            let orbitOmegaTarget = satellitesOrbitOmegaTarget()

            // Continuous angles.
            let ay = orbPhaseBase + (t - orbPhaseStartT) * orbOmegaRef
            let ax = ay * 0.67
            let orbitPhase = satPhaseBase + (t - satPhaseStartT) * satOmegaRef

            let key = phaseKey(omegaTarget: omegaTarget, orbitOmegaTarget: orbitOmegaTarget)

            return ZStack {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)

                    // Important: keep BOTH the orb canvas and the satellites in the same centered
                    // square coordinate space. Otherwise, if the hosting view isn't perfectly
                    // square, the canvas draws in the top-left while satellites stay centered.
                    ZStack {
                        // Transparent floating panels can exhibit temporal tearing when multiple
                        // async canvases race each other. Keep orb rendering on the main render path.
                        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, _ in
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

    private func phaseKey(omegaTarget: Double, orbitOmegaTarget: Double) -> String {
        // Discretize to avoid tiny float diffs.
        let a = Int((omegaTarget * 10_000).rounded())
        let b = Int((orbitOmegaTarget * 10_000).rounded())
        return "k=\(alert.kind.rawValue)|c=\(alert.count)|r=\(alert.urgentSecondsToMeeting ?? -1)|w=\(alert.urgentWindowSeconds ?? -1)|o=\(a)|so=\(b)"
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
        switch alert.kind {
        case .meetingUrgent, .meetingHot, .meetingSoon, .idle:
            return 1
        default:
            return 1
        }
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

            for index in stride(from: 0, to: points.count, by: strideValue) {
                let p = points[index]
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

private struct ParticlePoint {
    let x: Double
    let y: Double
    let z: Double
}

private enum ParticleCloud {
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

private struct SatellitesOrbitLayer: View {
    let satellites: [OrbFloatingView.SatelliteVisual]
    let t: Double
    let orbitPhase: Double
    let side: CGFloat
    private let orbitSquash: CGFloat = 0.68

    var body: some View {
        let shown = satellites

        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, _ in
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
        return HubUIStrings.FloatingCard.Lunar.label(
            month: dc.month ?? 0,
            day: dc.day ?? 0
        )
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
        if dt <= 0 { return HubUIStrings.MainPanel.Meeting.inProgress }
        let mins = max(1, Int(ceil(dt / 60.0)))
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0
                ? HubUIStrings.FloatingCard.compactHours(h)
                : HubUIStrings.FloatingCard.compactHoursMinutes(hours: h, minutes: m)
        }
        return HubUIStrings.FloatingCard.compactMinutes(mins)
    }

    private func notificationAgeText(createdAt: Double, now: Double) -> String {
        let dt = max(0, now - createdAt)
        let mins = Int(dt / 60.0)
        if mins >= 120 {
            return HubUIStrings.FloatingCard.compactHours(mins / 60)
        }
        if mins >= 60 {
            return HubUIStrings.FloatingCard.compactHoursMinutes(hours: mins / 60, minutes: mins % 60)
        }
        return HubUIStrings.FloatingCard.compactMinutes(max(1, mins))
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

    private func openNotificationFromFloating(_ notification: HubNotification) {
        let presentation = hubNotificationPresentation(for: notification)
        switch presentation.primaryAction {
        case .inspect, .none:
            store.presentNotificationInspector(notification)
            store.markRead(notification.id)
        case .openTarget:
            store.openNotificationAction(notification)
            store.markRead(notification.id)
        }
    }

    private func floatingNotificationHeader(_ notification: HubNotification) -> String {
        let presentation = hubNotificationPresentation(for: notification)
        if let badge = presentation.badge?.trimmingCharacters(in: .whitespacesAndNewlines),
           !badge.isEmpty {
            return badge
        }
        let source = hubNotificationDisplaySource(notification)
        return source.isEmpty ? HubUIStrings.FloatingCard.defaultNotificationHeader : source
    }

    private func floatingNotificationLine2(_ notification: HubNotification) -> String {
        let presentation = hubNotificationPresentation(for: notification)
        let title = (presentation.displayTitle ?? notification.title).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        if !presentation.subline.isEmpty {
            return presentation.subline
        }
        return HubUIStrings.FloatingCard.defaultHubUpdate
    }

    private func floatingNotificationLine3(_ notification: HubNotification) -> String {
        let presentation = hubNotificationPresentation(for: notification)
        if let nextStep = presentation.recommendedNextStep, !nextStep.isEmpty {
            return "\(HubUIStrings.Menu.NotificationRow.nextStepPrefix)\(nextStep)"
        }
        if let executionSurface = presentation.executionSurface, !executionSurface.isEmpty {
            return "\(HubUIStrings.Menu.NotificationRow.executionSurfacePrefix)\(executionSurface)"
        }
        if !presentation.subline.isEmpty {
            return presentation.subline
        }
        if let relevance = presentation.relevance, !relevance.isEmpty {
            return relevance
        }
        return ""
    }

    private func floatingNotificationTint(_ notification: HubNotification) -> Color {
        let presentation = hubNotificationPresentation(for: notification)
        switch presentation.group {
        case .actionRequired:
            return Color(red: 0.30, green: 0.58, blue: 1.0)
        case .advisory:
            return Color(red: 0.23, green: 0.70, blue: 0.74)
        case .background:
            return Color.secondary.opacity(0.72)
        }
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
                    headerLeft: HubUIStrings.MainPanel.Inbox.meetingsSection,
                    headerRight: (now >= m.startAt) ? HubUIStrings.MainPanel.Meeting.inProgress : meetingCountdownMinutes(startAt: m.startAt, now: now),
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
                    headerLeft: HubUIStrings.MainPanel.Inbox.meetingsSection,
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
                let project = pn.isEmpty ? HubUIStrings.FloatingCard.unnamedProject : pn

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
                    ps = [P(name: firstProj ?? HubUIStrings.FloatingCard.unnamedProject, ids: [], unreadCount: shownFA.filter { $0.unread }.count)]
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
                            return HubUIStrings.FloatingCard.openFATracker
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
                        headerLeft: HubUIStrings.FloatingCard.radarHeader,
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
                let presentation = hubNotificationPresentation(for: n)
                let headerRight = isCountsOnly ? n.body : notificationAgeText(createdAt: n.createdAt, now: now)
                let line2 = isCountsOnly
                    ? HubUIStrings.FloatingCard.openSource(source)
                    : ((presentation.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? presentation.displayTitle!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : n.title)
                let line3 = isCountsOnly
                    ? ""
                    : floatingNotificationSummaryLine(
                        subline: presentation.subline,
                        nextStep: presentation.recommendedNextStep,
                        fallbackBody: n.body
                    )
                return CardItem(
                    id: "n_\(n.id)",
                    kind: (source == "Messages" ? .message : (source == "Mail" ? .mail : .slack)),
                    tint: tint,
                    headerLeft: source.uppercased(),
                    headerRight: headerRight,
                    line2: line2,
                    line3: line3,
                    action: { openNotificationFromFloating(n) }
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
        let otherPresented = activeNotifs
            .filter { !["FAtracker", "Messages", "Mail", "Slack"].contains($0.source) }
            .map { ($0, hubNotificationPresentation(for: $0)) }
            .sorted { lhs, rhs in
                let lGroup = lhs.1.group
                let rGroup = rhs.1.group
                let rank: (HubNotificationPresentationGroup) -> Int = { group in
                    switch group {
                    case .actionRequired:
                        return 0
                    case .advisory:
                        return 1
                    case .background:
                        return 2
                    }
                }
                if rank(lGroup) != rank(rGroup) {
                    return rank(lGroup) < rank(rGroup)
                }
                return lhs.0.createdAt > rhs.0.createdAt
            }

        let priorityOther = otherPresented.filter { $0.1.group != .background }
        let backgroundOther = otherPresented.filter { $0.1.group == .background }
        let shownOther = priorityOther.isEmpty ? Array(backgroundOther.prefix(1)) : Array(priorityOther.prefix(2))

        if !shownOther.isEmpty {
            let items: [CardItem] = shownOther.map { entry in
                let n = entry.0
                return CardItem(
                    id: "n2_\(n.id)",
                    kind: .other,
                    tint: floatingNotificationTint(n),
                    headerLeft: floatingNotificationHeader(n),
                    headerRight: notificationAgeText(createdAt: n.createdAt, now: now),
                    line2: floatingNotificationLine2(n),
                    line3: floatingNotificationLine3(n),
                    action: { openNotificationFromFloating(n) }
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
                line2: HubUIStrings.FloatingCard.allClear,
                line3: "",
                action: { NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil) }
            )
            pages = [CardPage(id: "page_empty", kind: .other, items: [it])]
        }

        return pages
    }

    private func floatingNotificationSummaryLine(
        subline: String,
        nextStep: String?,
        fallbackBody: String
    ) -> String {
        let trimmedSubline = subline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSubline.isEmpty {
            return trimmedSubline
        }

        let trimmedNextStep = (nextStep ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNextStep.isEmpty {
            return trimmedNextStep
        }

        return fallbackBody
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
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
