import Foundation

struct RustHubRemoteEntryClassificationSnapshot: Decodable, Equatable, Sendable {
    var kind: String
    var scope: String
    var stable: Bool
    var encryptedPrivateCandidate: Bool
    var reasonCode: String

    enum CodingKeys: String, CodingKey {
        case kind
        case scope
        case stable
        case encryptedPrivateCandidate = "encrypted_private_candidate"
        case reasonCode = "reason_code"
    }
}

struct RustHubRemoteEntryCandidateSnapshot: Decodable, Equatable, Sendable {
    var routeKind: String
    var source: String
    var host: String
    var publicBaseURL: String
    var usable: Bool
    var requiresSamePrivateNetwork: Bool
    var requiresMTLS: Bool
    var classification: RustHubRemoteEntryClassificationSnapshot
    var denyCode: String?

    enum CodingKeys: String, CodingKey {
        case routeKind = "route_kind"
        case source
        case host
        case publicBaseURL = "public_base_url"
        case usable
        case requiresSamePrivateNetwork = "requires_same_private_network"
        case requiresMTLS = "requires_mtls"
        case classification
        case denyCode = "deny_code"
    }

    var stableRemoteHost: String? {
        let directHost = Self.normalizedHost(host)
        if let directHost,
           usable,
           HubRemoteHostPolicy.isFormalRemoteHost(directHost) {
            return directHost
        }
        guard usable,
              let hostFromURL = Self.host(fromPublicBaseURL: publicBaseURL),
              HubRemoteHostPolicy.isFormalRemoteHost(hostFromURL) else {
            return nil
        }
        return hostFromURL
    }

    private static func normalizedHost(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func host(fromPublicBaseURL raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return host
    }
}

struct RustHubRemoteEntryCandidatesSnapshot: Decodable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.rust_hub.remote_entry_candidates.v1"

    var schemaVersion: String
    var ok: Bool
    var source: String
    var recommendedSetup: String
    var preferred: RustHubRemoteEntryCandidateSnapshot?
    var candidates: [RustHubRemoteEntryCandidateSnapshot]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case source
        case recommendedSetup = "recommended_setup"
        case preferred
        case candidates
    }

    var preferredStableRemoteHost: String? {
        guard ok, schemaVersion == Self.currentSchemaVersion else { return nil }
        if let host = preferred?.stableRemoteHost {
            return host
        }
        return candidates.first { $0.stableRemoteHost != nil }?.stableRemoteHost
    }
}

enum RustHubRemoteEntryCandidatesClient {
    struct FetchResult: Equatable {
        var ok: Bool
        var snapshot: RustHubRemoteEntryCandidatesSnapshot?
        var errorCode: String
        var errorMessage: String
        var httpStatus: Int
    }

    static func fetch(
        baseURL: URL = RustHubReadinessClient.defaultBaseURL(),
        timeout: TimeInterval = 1.0
    ) async -> FetchResult {
        let url = baseURL
            .appendingPathComponent("network")
            .appendingPathComponent("remote-entry-candidates")

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            RustHubHTTPAccess.applyAccessKey(to: &request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                return FetchResult(
                    ok: false,
                    snapshot: nil,
                    errorCode: "http_\(statusCode)",
                    errorMessage: "Rust Hub remote-entry request failed with HTTP \(statusCode)",
                    httpStatus: statusCode
                )
            }
            let snapshot = try decode(data)
            return FetchResult(
                ok: snapshot.ok && snapshot.preferredStableRemoteHost != nil,
                snapshot: snapshot,
                errorCode: snapshot.ok ? "" : "remote_entry_candidates_not_ok",
                errorMessage: snapshot.ok ? "" : "Rust Hub remote-entry candidates returned ok=false",
                httpStatus: statusCode
            )
        } catch {
            return FetchResult(
                ok: false,
                snapshot: nil,
                errorCode: "network_error",
                errorMessage: error.localizedDescription,
                httpStatus: 0
            )
        }
    }

    static func decode(_ data: Data) throws -> RustHubRemoteEntryCandidatesSnapshot {
        try JSONDecoder().decode(RustHubRemoteEntryCandidatesSnapshot.self, from: data)
    }
}
