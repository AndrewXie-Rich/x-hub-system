import Foundation
import Darwin

struct HubRemoteAccessRouteProbeSnapshot: Equatable {
    enum State: Equatable {
        case idle
        case skipped
        case resolving
        case resolved
        case failed
    }

    let state: State
    let host: String
    let statusText: String
    let detailText: String
    let addresses: [String]
    let updatedAt: TimeInterval

    static func idle() -> HubRemoteAccessRouteProbeSnapshot {
        HubRemoteAccessRouteProbeSnapshot(
            state: .idle,
            host: "",
            statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusIdle,
            detailText: HubUIStrings.Settings.GRPC.RemoteRoute.idleDetail,
            addresses: [],
            updatedAt: 0
        )
    }
}

struct HubRemoteAccessRouteProbeFailure: Error {
    let message: String
}

@MainActor
final class HubRemoteAccessRouteProbe: ObservableObject {
    typealias Resolver = @Sendable (String) async throws -> [String]

    static let shared = HubRemoteAccessRouteProbe()

    @Published private(set) var snapshot: HubRemoteAccessRouteProbeSnapshot = .idle()

    private let resolver: Resolver
    private let cacheTTL: TimeInterval

    private var resolveTask: Task<Void, Never>?
    private var generation: Int = 0
    private var resolvingHost: String = ""
    private var lastResolvedHost: String = ""
    private var lastResolvedAt: TimeInterval = 0

    init(
        resolver: Resolver? = nil,
        cacheTTL: TimeInterval = 45
    ) {
        self.resolver = resolver ?? HubRemoteAccessRouteProbe.resolveHostAddresses
        self.cacheTTL = max(5, cacheTTL)
    }

    func refresh(host rawHost: String?, force: Bool = false) {
        let classification = HubRemoteAccessHostClassification.classify(rawHost)
        let now = Date().timeIntervalSince1970

        switch classification.kind {
        case .missing:
            resolveTask?.cancel()
            resolvingHost = ""
            snapshot = HubRemoteAccessRouteProbeSnapshot(
                state: .skipped,
                host: "",
                statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusSkipped,
                detailText: HubUIStrings.Settings.GRPC.RemoteRoute.missingHostDetail,
                addresses: [],
                updatedAt: now
            )
            return
        case .lanOnly:
            resolveTask?.cancel()
            resolvingHost = ""
            snapshot = HubRemoteAccessRouteProbeSnapshot(
                state: .skipped,
                host: classification.displayHost ?? "",
                statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusSkipped,
                detailText: HubUIStrings.Settings.GRPC.RemoteRoute.lanOnlyDetail(classification.displayHost ?? ""),
                addresses: [],
                updatedAt: now
            )
            return
        case .rawIP(let scope):
            resolveTask?.cancel()
            resolvingHost = ""
            let host = classification.displayHost ?? ""
            snapshot = HubRemoteAccessRouteProbeSnapshot(
                state: .skipped,
                host: host,
                statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusSkipped,
                detailText: HubUIStrings.Settings.GRPC.RemoteRoute.rawIPDetail(
                    host,
                    scopeLabel: HubUIStrings.Settings.GRPC.RemoteRoute.ipScopeLabel(scope.rawValue)
                ),
                addresses: [host].filter { !$0.isEmpty },
                updatedAt: now
            )
            return
        case .stableNamed:
            break
        }

        let host = classification.displayHost ?? ""
        guard !host.isEmpty else { return }

        if !force {
            if snapshot.state == .resolving && resolvingHost == host {
                return
            }
            if lastResolvedHost == host, (now - lastResolvedAt) < cacheTTL {
                return
            }
        }

        resolveTask?.cancel()
        generation += 1
        let currentGeneration = generation
        resolvingHost = host
        snapshot = HubRemoteAccessRouteProbeSnapshot(
            state: .resolving,
            host: host,
            statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusResolving,
            detailText: HubUIStrings.Settings.GRPC.RemoteRoute.resolvingDetail(host),
            addresses: [],
            updatedAt: now
        )

        resolveTask = Task { [resolver] in
            do {
                let addresses = try await resolver(host)
                await MainActor.run {
                    guard currentGeneration == self.generation else { return }
                    self.resolvingHost = ""
                    self.lastResolvedHost = host
                    self.lastResolvedAt = Date().timeIntervalSince1970
                    self.snapshot = Self.makeResolvedSnapshot(host: host, addresses: addresses)
                }
            } catch {
                let failure = (error as? HubRemoteAccessRouteProbeFailure)?.message ?? error.localizedDescription
                await MainActor.run {
                    guard currentGeneration == self.generation else { return }
                    self.resolvingHost = ""
                    self.snapshot = HubRemoteAccessRouteProbeSnapshot(
                        state: .failed,
                        host: host,
                        statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusFailed,
                        detailText: HubUIStrings.Settings.GRPC.RemoteRoute.resolveFailed(host, detail: failure),
                        addresses: [],
                        updatedAt: Date().timeIntervalSince1970
                    )
                }
            }
        }
    }

    private static func makeResolvedSnapshot(host: String, addresses: [String]) -> HubRemoteAccessRouteProbeSnapshot {
        let cleaned = Array(
            Set(addresses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        ).sorted()
        let scopeSummary = cleaned
            .map { HubRemoteAccessHostClassification.classifyIPAddressScope($0).rawValue }
            .uniqued()
            .map { HubUIStrings.Settings.GRPC.RemoteRoute.ipScopeLabel($0) }
            .joined(separator: " · ")

        return HubRemoteAccessRouteProbeSnapshot(
            state: .resolved,
            host: host,
            statusText: HubUIStrings.Settings.GRPC.RemoteRoute.statusResolved,
            detailText: HubUIStrings.Settings.GRPC.RemoteRoute.resolvedDetail(
                host,
                count: cleaned.count,
                scopeSummary: scopeSummary
            ),
            addresses: cleaned,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    nonisolated static func resolveHostAddresses(_ host: String) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            try resolveHostAddressesSync(host)
        }.value
    }

    private nonisolated static func resolveHostAddressesSync(_ host: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var results: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &results)
        guard status == 0 else {
            let detail = String(cString: gai_strerror(status))
            throw HubRemoteAccessRouteProbeFailure(message: detail)
        }
        guard let results else {
            throw HubRemoteAccessRouteProbeFailure(message: "no_results")
        }
        defer { freeaddrinfo(results) }

        var addresses: [String] = []
        var seen = Set<String>()
        var cursor: UnsafeMutablePointer<addrinfo>? = results
        while let entry = cursor {
            if let hostString = numericHostString(entry.pointee.ai_addr, addrlen: entry.pointee.ai_addrlen),
               seen.insert(hostString).inserted {
                addresses.append(hostString)
            }
            cursor = entry.pointee.ai_next
        }

        guard !addresses.isEmpty else {
            throw HubRemoteAccessRouteProbeFailure(message: "no_numeric_addresses")
        }
        return addresses.sorted()
    }

    private nonisolated static func numericHostString(
        _ address: UnsafeMutablePointer<sockaddr>?,
        addrlen: socklen_t
    ) -> String? {
        guard let address else { return nil }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address,
            addrlen,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        let bytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
