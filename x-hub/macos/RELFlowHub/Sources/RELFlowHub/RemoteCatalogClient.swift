import Foundation
import RELFlowHubCore

enum RemoteCatalogClient {
    static let defaultBaseURL = URL(string: RemoteProviderEndpoints.remoteCatalogBaseURLString)!

    struct ModelsResponse: Decodable {
        var data: [ModelItem]
    }

    struct ModelItem: Decodable {
        var id: String
    }

    static func fetchModelIds(apiKey: String, baseURL: URL = defaultBaseURL, timeoutSec: Double = 10.0) async throws -> [String] {
        var url = baseURL
        url.appendPathComponent("models")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = max(2.0, min(60.0, timeoutSec))
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("RELFlowHub/1.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status >= 200 && status < 300 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let msg = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = msg.isEmpty ? "" : " \(msg)"
            throw NSError(
                domain: "relflowhub",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Remote Catalog /models failed (status=\(status)).\(suffix)"]
            )
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        var out: [String] = []
        var seen: Set<String> = []
        for item in decoded.data {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty { continue }
            if seen.contains(id) { continue }
            seen.insert(id)
            out.append(id)
        }
        return out
    }
}
