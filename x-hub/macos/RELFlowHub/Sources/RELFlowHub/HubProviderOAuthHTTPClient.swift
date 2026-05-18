import Foundation

enum HubProviderOAuthHTTPClient {
    enum Provider: String, CaseIterable, Identifiable, Sendable {
        case codex
        case claude
        case gemini
        case antigravity

        var id: String { rawValue }

        var title: String {
            switch self {
            case .codex:
                return "Codex"
            case .claude:
                return "Claude"
            case .gemini:
                return "Gemini"
            case .antigravity:
                return "Antigravity"
            }
        }
    }

    struct OAuthLoginStart: Codable, Equatable, Sendable {
        var ok: Bool
        var provider: String
        var state: String
        var authURL: String
        var redirectURI: String
        var status: String
        var expiresAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case ok
            case provider
            case state
            case authURL = "auth_url"
            case redirectURI = "redirect_uri"
            case status
            case expiresAtMs = "expires_at_ms"
        }
    }

    struct OAuthLoginSubmit: Codable, Equatable, Sendable {
        var ok: Bool
        var error: String
        var provider: String
        var state: String
        var status: String
    }

    struct OAuthLoginStatus: Codable, Equatable, Sendable {
        var ok: Bool
        var error: String
        var provider: String
        var state: String
        var status: String
        var expiresAtMs: Int64
        var updatedAtMs: Int64
        var authURL: String
        var redirectURI: String
        var statusMessage: String
        var accountKey: String
        var email: String
        var authFilePath: String
        var imported: Int

        var isTerminal: Bool {
            status == "ok" || status == "error" || status == "expired" || status == "unknown"
        }

        enum CodingKeys: String, CodingKey {
            case ok
            case error
            case provider
            case state
            case status
            case expiresAtMs = "expires_at_ms"
            case updatedAtMs = "updated_at_ms"
            case authURL = "auth_url"
            case redirectURI = "redirect_uri"
            case statusMessage = "status_message"
            case accountKey = "account_key"
            case email
            case authFilePath = "auth_file_path"
            case imported
        }
    }

    enum ClientError: LocalizedError {
        case badURL
        case badResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "Hub OAuth 管理接口地址无效。"
            case .badResponse:
                return "Hub OAuth 管理接口返回了无法识别的数据。"
            case .apiError(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "Hub OAuth 管理接口请求失败。" : trimmed
            }
        }
    }

    static func pairingPort(grpcPort: Int) -> Int {
        max(1, min(65535, grpcPort + 1))
    }

    static func startLogin(
        provider: Provider,
        adminToken: String,
        grpcPort: Int
    ) async throws -> OAuthLoginStart {
        let body: [String: Any] = [
            "provider": provider.rawValue,
        ]
        let data = try await request(
            path: "/admin/provider-keys/oauth/start",
            method: "POST",
            queryItems: [],
            bodyJSON: body,
            adminToken: adminToken,
            grpcPort: grpcPort,
            timeoutSec: 8.0
        )
        let decoded = try decodeEnvelope(OAuthLoginStart.self, from: data)
        guard decoded.ok else {
            throw ClientError.apiError("oauth_start_failed")
        }
        return decoded
    }

    static func submitCallback(
        provider: String,
        state: String,
        redirectURL: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> OAuthLoginSubmit {
        let body: [String: Any] = [
            "provider": provider,
            "state": state,
            "redirect_url": redirectURL,
        ]
        let data = try await request(
            path: "/admin/provider-keys/oauth/callback",
            method: "POST",
            queryItems: [],
            bodyJSON: body,
            adminToken: adminToken,
            grpcPort: grpcPort,
            timeoutSec: 8.0
        )
        let decoded = try decodeEnvelope(OAuthLoginSubmit.self, from: data)
        guard decoded.ok else {
            throw ClientError.apiError(decoded.error)
        }
        return decoded
    }

    static func status(
        state: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> OAuthLoginStatus {
        let data = try await request(
            path: "/admin/provider-keys/oauth/status",
            method: "GET",
            queryItems: [URLQueryItem(name: "state", value: state)],
            bodyJSON: nil,
            adminToken: adminToken,
            grpcPort: grpcPort,
            timeoutSec: 5.0
        )
        return try decodeEnvelope(OAuthLoginStatus.self, from: data)
    }

    private static func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyJSON: [String: Any]?,
        adminToken: String,
        grpcPort: Int,
        timeoutSec: Double
    ) async throws -> Data {
        guard var components = URLComponents(string: "http://127.0.0.1:\(pairingPort(grpcPort: grpcPort))") else {
            throw ClientError.badURL
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ClientError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = max(1.0, min(30.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        if let bodyJSON {
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyJSON, options: [])
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.badResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.apiError(apiErrorMessage(from: data))
        }
        return data
    }

    private static func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ClientError.apiError(apiErrorMessage(from: data))
        }
    }

    private static func apiErrorMessage(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let error = obj["error"] as? String {
            return error
        }
        if let error = obj["error"] as? [String: Any] {
            return [
                error["message"],
                error["code"],
            ]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        }
        return [
            obj["message"],
            obj["detail"],
        ]
        .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? ""
    }
}
