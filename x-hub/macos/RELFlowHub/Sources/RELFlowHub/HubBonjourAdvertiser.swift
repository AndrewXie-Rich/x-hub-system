import Foundation
import Security
import RELFlowHubCore

private struct HubBonjourIdentity: Codable, Equatable {
    var schemaVersion: String
    var hubInstanceID: String
    var lanDiscoveryName: String
    var createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case hubInstanceID = "hub_instance_id"
        case lanDiscoveryName = "lan_discovery_name"
        case createdAtMs = "created_at_ms"
    }
}

@MainActor
final class HubBonjourAdvertiser: NSObject, @preconcurrency NetServiceDelegate {
    struct Metadata: Equatable {
        var hubInstanceID: String
        var lanDiscoveryName: String
    }

    private struct PublishSignature: Equatable {
        var serviceName: String
        var pairingPort: Int
        var txtRecord: [String: String]
    }

    private var service: NetService?
    private var signature: PublishSignature?
    private(set) var metadata: Metadata?
    private(set) var lastError: String = ""

    func publish(
        runtimeBaseDir: URL,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?
    ) {
        let identity = Self.resolveIdentity(runtimeBaseDir: runtimeBaseDir)
        metadata = Metadata(
            hubInstanceID: identity.hubInstanceID,
            lanDiscoveryName: identity.lanDiscoveryName
        )

        let txtRecord = Self.makeTXTRecord(
            identity: identity,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost
        )
        let nextSignature = PublishSignature(
            serviceName: identity.lanDiscoveryName,
            pairingPort: pairingPort,
            txtRecord: txtRecord
        )
        if signature == nextSignature, service != nil {
            return
        }

        stop()

        let publishedService = NetService(
            domain: "local.",
            type: "_axhub._tcp.",
            name: identity.lanDiscoveryName,
            port: Int32(max(1, min(65_535, pairingPort)))
        )
        publishedService.delegate = self
        publishedService.includesPeerToPeer = false
        publishedService.setTXTRecord(NetService.data(fromTXTRecord: txtRecord.mapValues { Data($0.utf8) }))
        publishedService.publish()

        service = publishedService
        signature = nextSignature
        lastError = ""
    }

    func stop() {
        service?.stop()
        service?.delegate = nil
        service = nil
        signature = nil
    }

    func netServiceDidPublish(_ sender: NetService) {
        lastError = ""
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        lastError = "bonjour_publish_failed_\(code)"
        service = nil
        signature = nil
    }

    private static func resolveIdentity(runtimeBaseDir: URL) -> HubBonjourIdentity {
        let fileURL = runtimeBaseDir.appendingPathComponent("hub_identity.json", isDirectory: false)
        if let existing = loadIdentity(fileURL: fileURL) {
            return existing
        }

        let hubInstanceID = "hub_" + randomHex(length: 20)
        let suffix = hubInstanceID
            .replacingOccurrences(of: "hub_", with: "")
            .prefix(10)
        let identity = HubBonjourIdentity(
            schemaVersion: "xhub.hub_identity.v1",
            hubInstanceID: hubInstanceID,
            lanDiscoveryName: "axhub-\(suffix)",
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000.0)
        )
        saveIdentity(identity, fileURL: fileURL)
        return identity
    }

    private static func loadIdentity(fileURL: URL) -> HubBonjourIdentity? {
        guard let data = try? Data(contentsOf: fileURL),
              var identity = try? JSONDecoder().decode(HubBonjourIdentity.self, from: data) else {
            return nil
        }
        let normalizedID = normalizeHubInstanceID(identity.hubInstanceID)
        let normalizedName = normalizeLanDiscoveryName(identity.lanDiscoveryName)
        guard !normalizedID.isEmpty, !normalizedName.isEmpty else { return nil }
        identity.hubInstanceID = normalizedID
        identity.lanDiscoveryName = normalizedName
        if identity.schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            identity.schemaVersion = "xhub.hub_identity.v1"
        }
        if identity.createdAtMs <= 0 {
            identity.createdAtMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        }
        return identity
    }

    private static func saveIdentity(_ identity: HubBonjourIdentity, fileURL: URL) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(identity)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Ignore persistence failures; advertisement can still proceed in-memory.
        }
    }

    private static func normalizeHubInstanceID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        guard normalized.range(of: #"^[a-z0-9][a-z0-9_-]{7,63}$"#, options: .regularExpression) != nil else {
            return ""
        }
        return normalized
    }

    private static func normalizeLanDiscoveryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed
            .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard normalized.range(of: #"^[a-z0-9][a-z0-9-]{2,62}$"#, options: .regularExpression) != nil else {
            return ""
        }
        return normalized
    }

    private static func makeTXTRecord(
        identity: HubBonjourIdentity,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String?
    ) -> [String: String] {
        var out: [String: String] = [
            "schema": "xhub.bonjour.v1",
            "service": "axhub",
            "hub_instance_id": identity.hubInstanceID,
            "lan_discovery_name": identity.lanDiscoveryName,
            "pairing_port": String(max(1, min(65_535, pairingPort))),
            "grpc_port": String(max(1, min(65_535, grpcPort))),
        ]
        let trimmedInternetHost = (internetHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInternetHost.isEmpty {
            out["internet_host"] = trimmedInternetHost
        }
        return out
    }

    private static func randomHex(length: Int) -> String {
        let count = max(1, (length + 1) / 2)
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            let raw = bytes.map { String(format: "%02x", $0) }.joined()
            return String(raw.prefix(length))
        }
        let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        if fallback.count >= length {
            return String(fallback.prefix(length))
        }
        return fallback.padding(toLength: length, withPad: "0", startingAt: 0)
    }
}
