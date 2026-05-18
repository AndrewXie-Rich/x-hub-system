import Foundation
import RELFlowHubCore

enum RustProviderKeySnapshotSupport {
    private static let snapshotPath = "/provider/runtime-snapshot"

    static func loadSnapshot(
        runtimeBaseDir: URL = SharedPaths.ensureHubDirectory(),
        baseURL: String = RustHubRuntimeSupport.defaultHTTPBaseURL,
        accessKey: String? = RustHubRuntimeSupport.httpAccessKey()
    ) async -> ProviderKeyStoreSnapshot? {
        guard let url = runtimeSnapshotURL(baseURL: baseURL, runtimeBaseDir: runtimeBaseDir) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        if let accessKey,
           !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(accessKey)", forHTTPHeaderField: "Authorization")
            request.setValue(accessKey, forHTTPHeaderField: "X-XHub-Access-Key")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                return nil
            }
            return ProviderKeyStorage.loadRustRuntimeSnapshotData(data)
        } catch {
            return nil
        }
    }

    static func runtimeSnapshotURL(baseURL: String, runtimeBaseDir: URL) -> URL? {
        let normalizedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBase.isEmpty,
              var components = URLComponents(string: normalizedBase + snapshotPath) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "runtime_base_dir", value: runtimeBaseDir.standardizedFileURL.path)
        ]
        return components.url
    }
}
