import Foundation

struct HubBonjourDiscoveryResult: Sendable {
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String?
    var hubInstanceID: String?
    var lanDiscoveryName: String?
}

struct HubBonjourDiscoveryOutcome: Sendable {
    var candidates: [HubBonjourDiscoveryResult]
}

@MainActor
final class HubBonjourDiscoverySession: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private let timeoutSec: TimeInterval
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var results: [HubBonjourDiscoveryResult] = []
    private var continuation: CheckedContinuation<HubBonjourDiscoveryOutcome, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    init(timeoutSec: TimeInterval) {
        self.timeoutSec = max(0.5, timeoutSec)
        super.init()
    }

    func discover() async -> HubBonjourDiscoveryOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            browser.delegate = self
            browser.searchForServices(ofType: "_axhub._tcp.", inDomain: "local.")
            timeoutTask = Task { [weak self] in
                guard let self else { return }
                let nanos = UInt64(self.timeoutSec * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                await MainActor.run {
                    self.finish()
                }
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !finished else { return }
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: timeoutSec)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        finish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        finish()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !finished else { return }
        guard let result = Self.parse(service: sender) else { return }
        results.append(result)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        if !services.contains(where: { $0 === sender }) {
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        browser.stop()
        services.forEach {
            $0.stop()
            $0.delegate = nil
        }
        services.removeAll()
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: HubBonjourDiscoveryOutcome(candidates: Self.deduplicated(results)))
    }

    private static func parse(service: NetService) -> HubBonjourDiscoveryResult? {
        guard service.port > 0 else { return nil }
        let host = normalizedHostName(service.hostName) ?? normalizedTrimmed(service.name)
        guard let host else { return nil }

        let txtData = service.txtRecordData() ?? Data()
        let txtRecord = NetService.dictionary(fromTXTRecord: txtData)
        let grpcPort = Int(txtString(txtRecord["grpc_port"])) ?? 50051
        let pairingPort = Int(txtString(txtRecord["pairing_port"])) ?? Int(service.port)
        let internetHost = normalizedTrimmed(txtString(txtRecord["internet_host"]))
        let hubInstanceID = normalizedTrimmed(txtString(txtRecord["hub_instance_id"]))
        let lanDiscoveryName = normalizedTrimmed(txtString(txtRecord["lan_discovery_name"])) ?? normalizedTrimmed(service.name)

        return HubBonjourDiscoveryResult(
            host: host,
            pairingPort: max(1, min(65_535, pairingPort)),
            grpcPort: max(1, min(65_535, grpcPort)),
            internetHost: internetHost,
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: lanDiscoveryName
        )
    }

    private static func txtString(_ data: Data?) -> String {
        guard let data, let text = String(data: data, encoding: .utf8) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHostName(_ raw: String?) -> String? {
        let trimmed = normalizedTrimmed(raw)
        guard var value = trimmed else { return nil }
        if value.hasSuffix(".") {
            value.removeLast()
        }
        return value
    }

    private static func normalizedTrimmed(_ raw: String?) -> String? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func deduplicated(_ rawResults: [HubBonjourDiscoveryResult]) -> [HubBonjourDiscoveryResult] {
        var mergedByKey: [String: HubBonjourDiscoveryResult] = [:]
        var orderedKeys: [String] = []

        for result in rawResults {
            let key = discoveryKey(for: result)
            if let existing = mergedByKey[key] {
                mergedByKey[key] = preferredResult(existing, result)
            } else {
                mergedByKey[key] = result
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { mergedByKey[$0] }
    }

    private static func discoveryKey(for result: HubBonjourDiscoveryResult) -> String {
        if let hubInstanceID = normalizedTrimmed(result.hubInstanceID)?.lowercased() {
            return "id:\(hubInstanceID)"
        }
        return [
            normalizeHost(result.host),
            String(result.pairingPort),
            String(result.grpcPort),
            normalizeHost(result.internetHost)
        ].joined(separator: "|")
    }

    private static func preferredResult(
        _ lhs: HubBonjourDiscoveryResult,
        _ rhs: HubBonjourDiscoveryResult
    ) -> HubBonjourDiscoveryResult {
        candidateScore(lhs) >= candidateScore(rhs) ? lhs : rhs
    }

    private static func candidateScore(_ result: HubBonjourDiscoveryResult) -> Int {
        var score = 0
        if normalizedTrimmed(result.internetHost) != nil { score += 4 }
        if normalizedTrimmed(result.hubInstanceID) != nil { score += 3 }
        if normalizedTrimmed(result.lanDiscoveryName) != nil { score += 2 }
        if normalizedTrimmed(result.host) != nil { score += 1 }
        return score
    }

    private static func normalizeHost(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(".") {
            return String(value.dropLast())
        }
        return value
    }
}

enum HubBonjourDiscovery {
    @MainActor
    static func discover(
        timeoutSec: TimeInterval = 1.8
    ) async -> HubBonjourDiscoveryOutcome {
        let session = HubBonjourDiscoverySession(timeoutSec: timeoutSec)
        return await session.discover()
    }
}
