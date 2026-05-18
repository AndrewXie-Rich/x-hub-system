import Foundation

private func terminalAccessShellSingleQuoted(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func terminalAccessShellDoubleQuoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func terminalAccessDoubleQuotedLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

private func terminalAccessNormalizedText(_ value: String?) -> String {
    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func terminalAccessEnvAssignmentBlock(
    baseURLEnvKey: String,
    baseURL: String,
    apiKeyEnvKey: String,
    apiKeyValue: String
) -> String {
    let normalizedBaseURL = terminalAccessNormalizedText(baseURL)
    let normalizedAPIKey = terminalAccessNormalizedText(apiKeyValue)
    let normalizedBaseURLEnvKey = terminalAccessNormalizedText(baseURLEnvKey).isEmpty
        ? "OPENAI_BASE_URL"
        : terminalAccessNormalizedText(baseURLEnvKey)
    let normalizedAPIKeyEnvKey = terminalAccessNormalizedText(apiKeyEnvKey).isEmpty
        ? "OPENAI_API_KEY"
        : terminalAccessNormalizedText(apiKeyEnvKey)

    var lines: [String] = []
    if !normalizedBaseURL.isEmpty {
        lines.append("\(normalizedBaseURLEnvKey)=\(terminalAccessShellSingleQuoted(normalizedBaseURL))")
    }
    if !normalizedAPIKey.isEmpty {
        lines.append("\(normalizedAPIKeyEnvKey)=\(terminalAccessShellSingleQuoted(normalizedAPIKey))")
    }
    return lines.joined(separator: "\n")
}

private func terminalAccessShellExports(from envBlock: String) -> String {
    String(envBlock)
        .split(whereSeparator: \.isNewline)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { line in
            if line.hasPrefix("export ") {
                return line
            }
            return line.contains("=") ? "export \(line)" : line
        }
        .joined(separator: "\n")
}

private func terminalAccessShellEnvReference(_ name: String) -> String {
    "${\(terminalAccessNormalizedText(name))}"
}

private func terminalAccessJoinSections(_ sections: [String]) -> String {
    sections
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
}

struct HubTerminalOpenAICompat: Codable, Equatable, Sendable {
    var baseURL: String
    var modelsURL: String
    var chatCompletionsURL: String
    var responsesURL: String?
    var authScheme: String
    var apiKeyEnvKey: String
    var baseURLEnvKey: String

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case modelsURL = "models_url"
        case chatCompletionsURL = "chat_completions_url"
        case responsesURL = "responses_url"
        case authScheme = "auth_scheme"
        case apiKeyEnvKey = "api_key_env_key"
        case baseURLEnvKey = "base_url_env_key"
    }
}

private struct TerminalAccessAPIErrorObj: Codable {
    var code: String
    var message: String
    var retryable: Bool?
}

struct HubTerminalAccessKey: Identifiable, Codable, Equatable, Sendable {
    var accessKeyID: String
    var authKind: String
    var status: String
    var statusReason: String
    var deviceID: String
    var userID: String
    var appID: String
    var name: String
    var note: String
    var tokenRedacted: String
    var enabled: Bool
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var expiresAtMs: Int64
    var lastUsedAtMs: Int64
    var lastUsedPeerIP: String
    var lastUsedTransport: String
    var revokedAtMs: Int64
    var revokeReason: String
    var revokedByUserID: String
    var revokedVia: String
    var createdByUserID: String
    var createdByAppID: String
    var createdVia: String
    var lastRotatedAtMs: Int64
    var rotationCount: Int
    var capabilities: [String]
    var scopes: [String]
    var allowedCidrs: [String]
    var policyMode: HubGRPCClientPolicyMode
    var trustProfilePresent: Bool
    var approvedTrustProfile: HubPairedTerminalTrustProfile?
    var connectEnvTemplate: String
    var connectEnv: String
    var openAICompat: HubTerminalOpenAICompat?
    var openAICompatEnvTemplate: String
    var openAICompatEnv: String

    var id: String { accessKeyID }

    enum CodingKeys: String, CodingKey {
        case accessKeyID = "access_key_id"
        case authKind = "auth_kind"
        case status
        case statusReason = "status_reason"
        case deviceID = "device_id"
        case userID = "user_id"
        case appID = "app_id"
        case name
        case note
        case tokenRedacted = "token_redacted"
        case enabled
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case expiresAtMs = "expires_at_ms"
        case lastUsedAtMs = "last_used_at_ms"
        case lastUsedPeerIP = "last_used_peer_ip"
        case lastUsedTransport = "last_used_transport"
        case revokedAtMs = "revoked_at_ms"
        case revokeReason = "revoke_reason"
        case revokedByUserID = "revoked_by_user_id"
        case revokedVia = "revoked_via"
        case createdByUserID = "created_by_user_id"
        case createdByAppID = "created_by_app_id"
        case createdVia = "created_via"
        case lastRotatedAtMs = "last_rotated_at_ms"
        case rotationCount = "rotation_count"
        case capabilities
        case scopes
        case allowedCidrs = "allowed_cidrs"
        case policyMode = "policy_mode"
        case trustProfilePresent = "trust_profile_present"
        case approvedTrustProfile = "approved_trust_profile"
        case connectEnvTemplate = "connect_env_template"
        case connectEnv = "connect_env"
        case openAICompat = "openai_compat"
        case openAICompatEnvTemplate = "openai_compat_env_template"
        case openAICompatEnv = "openai_compat_env"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessKeyID = (try? c.decode(String.self, forKey: .accessKeyID)) ?? ""
        authKind = (try? c.decode(String.self, forKey: .authKind)) ?? ""
        status = (try? c.decode(String.self, forKey: .status)) ?? ""
        statusReason = (try? c.decode(String.self, forKey: .statusReason)) ?? ""
        deviceID = (try? c.decode(String.self, forKey: .deviceID)) ?? ""
        userID = (try? c.decode(String.self, forKey: .userID)) ?? ""
        appID = (try? c.decode(String.self, forKey: .appID)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        tokenRedacted = (try? c.decode(String.self, forKey: .tokenRedacted)) ?? ""
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        createdAtMs = (try? c.decode(Int64.self, forKey: .createdAtMs)) ?? 0
        updatedAtMs = (try? c.decode(Int64.self, forKey: .updatedAtMs)) ?? 0
        expiresAtMs = (try? c.decode(Int64.self, forKey: .expiresAtMs)) ?? 0
        lastUsedAtMs = (try? c.decode(Int64.self, forKey: .lastUsedAtMs)) ?? 0
        lastUsedPeerIP = (try? c.decode(String.self, forKey: .lastUsedPeerIP)) ?? ""
        lastUsedTransport = (try? c.decode(String.self, forKey: .lastUsedTransport)) ?? ""
        revokedAtMs = (try? c.decode(Int64.self, forKey: .revokedAtMs)) ?? 0
        revokeReason = (try? c.decode(String.self, forKey: .revokeReason)) ?? ""
        revokedByUserID = (try? c.decode(String.self, forKey: .revokedByUserID)) ?? ""
        revokedVia = (try? c.decode(String.self, forKey: .revokedVia)) ?? ""
        createdByUserID = (try? c.decode(String.self, forKey: .createdByUserID)) ?? ""
        createdByAppID = (try? c.decode(String.self, forKey: .createdByAppID)) ?? ""
        createdVia = (try? c.decode(String.self, forKey: .createdVia)) ?? ""
        lastRotatedAtMs = (try? c.decode(Int64.self, forKey: .lastRotatedAtMs)) ?? 0
        rotationCount = (try? c.decode(Int.self, forKey: .rotationCount)) ?? 0
        capabilities = HubGRPCClientEntry.normalizedStrings((try? c.decode([String].self, forKey: .capabilities)) ?? [])
        scopes = HubGRPCClientEntry.normalizedStrings((try? c.decode([String].self, forKey: .scopes)) ?? [])
        allowedCidrs = (try? c.decode([String].self, forKey: .allowedCidrs)) ?? []
        trustProfilePresent = (try? c.decode(Bool.self, forKey: .trustProfilePresent)) ?? false
        approvedTrustProfile = try? c.decode(HubPairedTerminalTrustProfile.self, forKey: .approvedTrustProfile)
        connectEnvTemplate = (try? c.decode(String.self, forKey: .connectEnvTemplate)) ?? ""
        connectEnv = (try? c.decode(String.self, forKey: .connectEnv)) ?? ""
        openAICompat = try? c.decode(HubTerminalOpenAICompat.self, forKey: .openAICompat)
        openAICompatEnvTemplate = (try? c.decode(String.self, forKey: .openAICompatEnvTemplate)) ?? ""
        openAICompatEnv = (try? c.decode(String.self, forKey: .openAICompatEnv)) ?? ""

        if let rawMode = try? c.decode(String.self, forKey: .policyMode),
           let decodedMode = HubGRPCClientPolicyMode(rawValue: rawMode) {
            policyMode = decodedMode
        } else {
            policyMode = approvedTrustProfile == nil ? .legacyGrant : .newProfile
        }
    }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? accessKeyID : trimmed
    }

    var paidModelSelectionMode: HubPaidModelSelectionMode {
        approvedTrustProfile?.paidModelPolicy.mode ?? .off
    }

    var defaultWebFetchEnabled: Bool {
        approvedTrustProfile?.networkPolicy.defaultWebFetchEnabled ?? false
    }

    var dailyTokenLimit: Int {
        approvedTrustProfile?.budgetPolicy.dailyTokenLimit ?? 0
    }

    var supportsDirectBudgetAdjustment: Bool {
        policyMode == .newProfile
            && approvedTrustProfile != nil
            && status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "revoked"
    }
}

private struct HubTerminalAccessKeyListResponse: Codable {
    var ok: Bool
    var accessKeys: [HubTerminalAccessKey]?
    var error: TerminalAccessAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case accessKeys = "access_keys"
        case error
    }
}

private struct HubTerminalAccessKeyMutationResponse: Codable {
    var ok: Bool
    var clientToken: String?
    var accessKey: HubTerminalAccessKey?
    var error: TerminalAccessAPIErrorObj?

    enum CodingKeys: String, CodingKey {
        case ok
        case clientToken = "client_token"
        case accessKey = "access_key"
        case error
    }
}

struct HubTerminalAccessKeySecretEnvelope: Equatable, Sendable {
    var clientToken: String
    var accessKey: HubTerminalAccessKey

    var deliveryPack: HubTerminalAccessDeliveryPack {
        accessKey.deliveryPack(clientToken: clientToken)
    }

    var openAIBaseURL: String {
        accessKey.openAICompat?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var openAICompatEnv: String {
        accessKey.openAICompatEnv.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var smokeCurlCommand: String {
        let baseURL = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !token.isEmpty else { return "" }
        return """
curl -fsS \(terminalAccessShellSingleQuoted(baseURL + "/models")) \\
  -H \(terminalAccessShellSingleQuoted("Authorization: Bearer \(token)"))
"""
    }
}

struct HubTerminalAccessDeliveryPack: Equatable, Sendable {
    var title: String
    var accessKeyID: String
    var userID: String
    var appID: String
    var authScheme: String
    var baseURL: String
    var modelsURL: String
    var chatCompletionsURL: String
    var responsesURL: String
    var apiKeyEnvKey: String
    var baseURLEnvKey: String
    var apiKeyValue: String
    var envBlock: String
    var shellExports: String
    var smokeCurlCommand: String
    var includesSecret: Bool

    var sampleModelID: String {
        "MODEL_ID_HERE"
    }

    var supportsResponsesAPI: Bool {
        !responsesURL.isEmpty
    }

    var authDisplayText: String {
        let normalized = authScheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "bearer" {
            return "Bearer"
        }
        return normalized.capitalized
    }

    var endpointSummaryText: String {
        var lines: [String] = []
        if !modelsURL.isEmpty {
            lines.append("GET \(modelsURL)")
        }
        if !chatCompletionsURL.isEmpty {
            lines.append("POST \(chatCompletionsURL)")
        }
        if !responsesURL.isEmpty {
            lines.append("POST \(responsesURL)")
        }
        return lines.joined(separator: "\n")
    }

    var curlCommand: String {
        let targetURL = !responsesURL.isEmpty ? responsesURL : chatCompletionsURL
        guard !targetURL.isEmpty else { return "" }
        let requestBody: String
        if !responsesURL.isEmpty {
            requestBody = """
            {
              "model": "\(sampleModelID)",
              "input": "Reply with pong."
            }
            """
        } else {
            requestBody = """
            {
              "model": "\(sampleModelID)",
              "messages": [
                { "role": "user", "content": "Reply with pong." }
              ]
            }
            """
        }
        return """
        # 先用 GET /v1/models 选一个可用 model id
        curl -fsS \(terminalAccessShellSingleQuoted(targetURL)) \\
          -H \(terminalAccessShellDoubleQuoted("Authorization: Bearer \(terminalAccessShellEnvReference(apiKeyEnvKey))")) \\
          -H 'Content-Type: application/json' \\
          -d '\(requestBody)'
        """
    }

    var pythonSnippet: String {
        guard !baseURL.isEmpty else { return "" }
        if supportsResponsesAPI {
            return """
            # pip install openai
            import os
            from openai import OpenAI

            client = OpenAI(
                api_key=os.environ[\(terminalAccessDoubleQuotedLiteral(apiKeyEnvKey))],
                base_url=os.environ[\(terminalAccessDoubleQuotedLiteral(baseURLEnvKey))],
            )

            response = client.responses.create(
                model="\(sampleModelID)",
                input="Reply with pong.",
            )

            print(response.output_text)
            """
        }
        return """
        # pip install openai
        import os
        from openai import OpenAI

        client = OpenAI(
            api_key=os.environ[\(terminalAccessDoubleQuotedLiteral(apiKeyEnvKey))],
            base_url=os.environ[\(terminalAccessDoubleQuotedLiteral(baseURLEnvKey))],
        )

        completion = client.chat.completions.create(
            model="\(sampleModelID)",
            messages=[
                {"role": "user", "content": "Reply with pong."},
            ],
        )

        print(completion.choices[0].message.content)
        """
    }

    var nodeSnippet: String {
        guard !baseURL.isEmpty else { return "" }
        if supportsResponsesAPI {
            return """
            // npm install openai
            import OpenAI from "openai";

            const client = new OpenAI({
              apiKey: process.env[\(terminalAccessDoubleQuotedLiteral(apiKeyEnvKey))],
              baseURL: process.env[\(terminalAccessDoubleQuotedLiteral(baseURLEnvKey))],
            });

            const main = async () => {
              const response = await client.responses.create({
                model: "\(sampleModelID)",
                input: "Reply with pong.",
              });

              console.log(response.output_text);
            };

            main().catch(console.error);
            """
        }
        return """
        // npm install openai
        import OpenAI from "openai";

        const client = new OpenAI({
          apiKey: process.env[\(terminalAccessDoubleQuotedLiteral(apiKeyEnvKey))],
          baseURL: process.env[\(terminalAccessDoubleQuotedLiteral(baseURLEnvKey))],
        });

        const main = async () => {
          const completion = await client.chat.completions.create({
            model: "\(sampleModelID)",
            messages: [
              { role: "user", content: "Reply with pong." },
            ],
          });

          console.log(completion.choices[0]?.message?.content ?? "");
        };

        main().catch(console.error);
        """
    }

    var setupPackText: String {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "anonymous" : userID
        let normalizedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "external_terminal" : appID
        return terminalAccessJoinSections([
            """
            # Hub terminal delivery pack
            # name: \(title)
            # access_key_id: \(accessKeyID)
            # user_id: \(normalizedUserID)
            # app_id: \(normalizedAppID)
            # auth: \(authDisplayText)
            # secret: \(includesSecret ? "included_once" : "redacted_template")
            """,
            envBlock.isEmpty ? "" : """
            # .env
            \(envBlock)
            """,
            shellExports.isEmpty ? "" : """
            # shell export
            \(shellExports)
            """,
            endpointSummaryText.isEmpty ? "" : """
            # endpoints
            \(endpointSummaryText)
            """,
            smokeCurlCommand.isEmpty ? "" : """
            # smoke test
            \(smokeCurlCommand)
            """,
            pythonSnippet.isEmpty ? "" : """
            # python example
            \(pythonSnippet)
            """,
            nodeSnippet.isEmpty ? "" : """
            # node example
            \(nodeSnippet)
            """,
            curlCommand.isEmpty ? "" : """
            # curl example
            \(curlCommand)
            """
        ])
    }
}

struct HubTerminalAccessKeyDraft: Equatable, Sendable {
    var name: String = "Terminal Access"
    var userID: String = ""
    var note: String = ""
    var dailyTokenLimit: Int = 200_000
    var ttlHours: Int = 24
    var allowPaidModels: Bool = false
    var defaultWebFetchEnabled: Bool = true
    var appID: String = "external_terminal"

    var normalizedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Terminal Access" : trimmed
    }

    var normalizedUserID: String {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let fallback = normalizedName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return fallback.isEmpty ? "external_terminal" : fallback
    }

    var resolvedCapabilities: [String] {
        var out = ["models", "ai.generate.local"]
        if allowPaidModels {
            out.append("ai.generate.paid")
        }
        if defaultWebFetchEnabled {
            out.append("web.fetch")
        }
        return HubGRPCClientEntry.normalizedStrings(out)
    }

    var requestBody: [String: Any] {
        [
            "name": normalizedName,
            "user_id": normalizedUserID,
            "app_id": appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "external_terminal" : appID,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "ttl_sec": max(0, ttlHours) * 3600,
            "policy_mode": HubGRPCClientPolicyMode.newProfile.rawValue,
            "paid_model_selection_mode": allowPaidModels
                ? HubPaidModelSelectionMode.allPaidModels.rawValue
                : HubPaidModelSelectionMode.off.rawValue,
            "default_web_fetch_enabled": defaultWebFetchEnabled,
            "daily_token_limit": max(1, dailyTokenLimit),
            "capabilities": resolvedCapabilities,
            "scopes": resolvedCapabilities,
        ]
    }
}

enum TerminalAccessKeyHTTPClient {
    enum ClientError: LocalizedError {
        case badURL
        case badResponse
        case apiError(code: String, message: String)

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "普通 Terminal access key URL 无法构造。"
            case .badResponse:
                return "Hub 返回了无法识别的普通 Terminal access key 响应。"
            case .apiError(let code, let message):
                let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedMessage.isEmpty ? code : "\(code): \(normalizedMessage)"
            }
        }
    }

    static func pairingPort(grpcPort: Int) -> Int {
        max(1, min(65535, grpcPort + 1))
    }

    private static func baseURL(pairingPort: Int) -> URL? {
        URL(string: "http://127.0.0.1:\(pairingPort)")
    }

    private static func request(
        path: String,
        method: String,
        bodyJSON: [String: Any]?,
        adminToken: String,
        pairingPort: Int,
        timeoutSec: Double = 3.0
    ) async throws -> Data {
        guard let base = baseURL(pairingPort: pairingPort),
              let url = URL(string: path, relativeTo: base) else {
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
        guard response is HTTPURLResponse else {
            throw ClientError.badResponse
        }
        return data
    }

    static func list(
        adminToken: String,
        grpcPort: Int
    ) async throws -> [HubTerminalAccessKey] {
        let data = try await request(
            path: "/admin/clients/access-keys?auth_kind=hub_access_key",
            method: "GET",
            bodyJSON: nil,
            adminToken: adminToken,
            pairingPort: pairingPort(grpcPort: grpcPort)
        )
        guard let obj = try? JSONDecoder().decode(HubTerminalAccessKeyListResponse.self, from: data) else {
            throw ClientError.badResponse
        }
        if obj.ok {
            return obj.accessKeys ?? []
        }
        let error = obj.error
        throw ClientError.apiError(code: error?.code ?? "error", message: error?.message ?? "")
    }

    static func issue(
        draft: HubTerminalAccessKeyDraft,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubTerminalAccessKeySecretEnvelope {
        try await mutateWithSecret(
            path: "/admin/clients/access-keys",
            bodyJSON: draft.requestBody,
            adminToken: adminToken,
            grpcPort: grpcPort
        )
    }

    static func rotate(
        accessKeyID: String,
        note: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubTerminalAccessKeySecretEnvelope {
        try await mutateWithSecret(
            path: "/admin/clients/access-keys/\(accessKeyID)/rotate",
            bodyJSON: [
                "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            adminToken: adminToken,
            grpcPort: grpcPort
        )
    }

    static func revoke(
        accessKeyID: String,
        note: String,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubTerminalAccessKey {
        let data = try await request(
            path: "/admin/clients/access-keys/\(accessKeyID)/revoke",
            method: "POST",
            bodyJSON: [
                "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            adminToken: adminToken,
            pairingPort: pairingPort(grpcPort: grpcPort)
        )
        guard let obj = try? JSONDecoder().decode(HubTerminalAccessKeyMutationResponse.self, from: data) else {
            throw ClientError.badResponse
        }
        if obj.ok, let accessKey = obj.accessKey {
            return accessKey
        }
        let error = obj.error
        throw ClientError.apiError(code: error?.code ?? "error", message: error?.message ?? "")
    }

    static func updateDailyBudget(
        accessKeyID: String,
        dailyTokenLimit: Int,
        note: String? = nil,
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubTerminalAccessKey {
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var bodyJSON: [String: Any] = [
            "daily_token_limit": max(1, dailyTokenLimit),
        ]
        if !trimmedNote.isEmpty {
            bodyJSON["note"] = trimmedNote
        }
        return try await mutate(
            path: "/admin/clients/access-keys/\(accessKeyID)/update",
            bodyJSON: bodyJSON,
            adminToken: adminToken,
            grpcPort: grpcPort
        )
    }

    private static func mutate(
        path: String,
        bodyJSON: [String: Any],
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubTerminalAccessKey {
        let data = try await request(
            path: path,
            method: "POST",
            bodyJSON: bodyJSON,
            adminToken: adminToken,
            pairingPort: pairingPort(grpcPort: grpcPort)
        )
        guard let obj = try? JSONDecoder().decode(HubTerminalAccessKeyMutationResponse.self, from: data) else {
            throw ClientError.badResponse
        }
        if obj.ok, let accessKey = obj.accessKey {
            return accessKey
        }
        let error = obj.error
        throw ClientError.apiError(code: error?.code ?? "error", message: error?.message ?? "")
    }

    private static func mutateWithSecret(
        path: String,
        bodyJSON: [String: Any],
        adminToken: String,
        grpcPort: Int
    ) async throws -> HubTerminalAccessKeySecretEnvelope {
        let data = try await request(
            path: path,
            method: "POST",
            bodyJSON: bodyJSON,
            adminToken: adminToken,
            pairingPort: pairingPort(grpcPort: grpcPort)
        )
        guard let obj = try? JSONDecoder().decode(HubTerminalAccessKeyMutationResponse.self, from: data) else {
            throw ClientError.badResponse
        }
        if obj.ok,
           let accessKey = obj.accessKey,
           let clientToken = obj.clientToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clientToken.isEmpty {
            return HubTerminalAccessKeySecretEnvelope(
                clientToken: clientToken,
                accessKey: accessKey
            )
        }
        let error = obj.error
        throw ClientError.apiError(code: error?.code ?? "error", message: error?.message ?? "")
    }
}

extension HubTerminalAccessKey {
    func deliveryPack(clientToken: String? = nil) -> HubTerminalAccessDeliveryPack {
        let compat = openAICompat
        let baseURL = terminalAccessNormalizedText(compat?.baseURL)
        let modelsURL = terminalAccessNormalizedText(compat?.modelsURL).isEmpty
            ? (baseURL.isEmpty ? "" : "\(baseURL)/models")
            : terminalAccessNormalizedText(compat?.modelsURL)
        let chatCompletionsURL = terminalAccessNormalizedText(compat?.chatCompletionsURL).isEmpty
            ? (baseURL.isEmpty ? "" : "\(baseURL)/chat/completions")
            : terminalAccessNormalizedText(compat?.chatCompletionsURL)
        let responsesURL = terminalAccessNormalizedText(compat?.responsesURL).isEmpty
            ? (baseURL.isEmpty ? "" : "\(baseURL)/responses")
            : terminalAccessNormalizedText(compat?.responsesURL)
        let apiKeyEnvKey = terminalAccessNormalizedText(compat?.apiKeyEnvKey).isEmpty
            ? "OPENAI_API_KEY"
            : terminalAccessNormalizedText(compat?.apiKeyEnvKey)
        let baseURLEnvKey = terminalAccessNormalizedText(compat?.baseURLEnvKey).isEmpty
            ? "OPENAI_BASE_URL"
            : terminalAccessNormalizedText(compat?.baseURLEnvKey)
        let apiKeyValue = terminalAccessNormalizedText(clientToken).isEmpty
            ? terminalAccessNormalizedText(tokenRedacted)
            : terminalAccessNormalizedText(clientToken)
        let envBlockSource = terminalAccessNormalizedText(clientToken).isEmpty
            ? terminalAccessNormalizedText(openAICompatEnvTemplate)
            : terminalAccessNormalizedText(openAICompatEnv)
        let envBlock = envBlockSource.isEmpty
            ? terminalAccessEnvAssignmentBlock(
                baseURLEnvKey: baseURLEnvKey,
                baseURL: baseURL,
                apiKeyEnvKey: apiKeyEnvKey,
                apiKeyValue: apiKeyValue
            )
            : envBlockSource

        return HubTerminalAccessDeliveryPack(
            title: resolvedName,
            accessKeyID: accessKeyID,
            userID: userID,
            appID: appID,
            authScheme: terminalAccessNormalizedText(compat?.authScheme).isEmpty
                ? "bearer"
                : terminalAccessNormalizedText(compat?.authScheme),
            baseURL: baseURL,
            modelsURL: modelsURL,
            chatCompletionsURL: chatCompletionsURL,
            responsesURL: responsesURL,
            apiKeyEnvKey: apiKeyEnvKey,
            baseURLEnvKey: baseURLEnvKey,
            apiKeyValue: apiKeyValue,
            envBlock: envBlock,
            shellExports: terminalAccessShellExports(from: envBlock),
            smokeCurlCommand: terminalAccessNormalizedText(clientToken).isEmpty || modelsURL.isEmpty
                ? ""
                : """
                curl -fsS \(terminalAccessShellSingleQuoted(modelsURL)) \\
                  -H \(terminalAccessShellSingleQuoted("Authorization: Bearer \(terminalAccessNormalizedText(clientToken))"))
                """,
            includesSecret: !terminalAccessNormalizedText(clientToken).isEmpty
        )
    }
}
