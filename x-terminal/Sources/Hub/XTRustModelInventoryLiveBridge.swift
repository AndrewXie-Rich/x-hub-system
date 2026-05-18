import Foundation

struct XTRustModelInventoryLiveBridgeConfiguration: Equatable {
    var enabled: Bool
    var snapshotPath: String?
    var httpBaseURL: String?
}

struct XTRustModelInventoryLiveBridgeSnapshot: Equatable {
    var projection: XTRustModelInventoryProjection
    var source: String
}

enum XTRustModelInventoryLiveBridgeResult: Equatable {
    case disabled
    case unavailable(reasonCode: String)
    case loaded(XTRustModelInventoryLiveBridgeSnapshot)
}

enum XTRustModelInventoryLiveBridge {
    static let enabledDefaultsKey = "xterminal_rust_model_inventory_bridge_enabled"
    static let snapshotPathDefaultsKey = "xterminal_rust_model_inventory_snapshot_path"
    static let httpBaseURLDefaultsKey = "xterminal_rust_model_inventory_http_base_url"

    private static let testingLock = NSLock()
    private static var configurationOverrideForTesting: XTRustModelInventoryLiveBridgeConfiguration?

    static func loadIfEnabled(runtimeBaseDir: URL) async -> XTRustModelInventoryLiveBridgeResult {
        let config = configuration()
        guard config.enabled else {
            return .disabled
        }

        if let snapshotPath = nonEmpty(config.snapshotPath) {
            return loadSnapshotFile(path: snapshotPath)
        }

        if let httpBaseURL = nonEmpty(config.httpBaseURL) {
            return await loadHTTPInventory(
                baseURLString: httpBaseURL,
                runtimeBaseDir: runtimeBaseDir
            )
        }

        return .unavailable(reasonCode: "no_rust_inventory_bridge_source")
    }

    static func configuration(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> XTRustModelInventoryLiveBridgeConfiguration {
        if let override = withTestingLock({ configurationOverrideForTesting }) {
            return override
        }

        return XTRustModelInventoryLiveBridgeConfiguration(
            enabled: truthy(environment["XHUB_RUST_MODEL_INVENTORY_BRIDGE"])
                || truthy(environment["XT_RUST_MODEL_INVENTORY_BRIDGE"])
                || defaults.bool(forKey: enabledDefaultsKey),
            snapshotPath: nonEmpty(environment["XHUB_RUST_MODEL_INVENTORY_SNAPSHOT_PATH"])
                ?? nonEmpty(defaults.string(forKey: snapshotPathDefaultsKey)),
            httpBaseURL: nonEmpty(environment["XHUB_RUST_MODEL_INVENTORY_HTTP_BASE_URL"])
                ?? nonEmpty(defaults.string(forKey: httpBaseURLDefaultsKey))
        )
    }

    static func installConfigurationOverrideForTesting(
        _ override: XTRustModelInventoryLiveBridgeConfiguration?
    ) {
        withTestingLock {
            configurationOverrideForTesting = override
        }
    }

    static func resetConfigurationOverrideForTesting() {
        installConfigurationOverrideForTesting(nil)
    }

    private static func loadSnapshotFile(path: String) -> XTRustModelInventoryLiveBridgeResult {
        do {
            let expanded = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            let data = try Data(contentsOf: url)
            return try decodeLoadedSnapshot(
                data: data,
                source: "rust_inventory_snapshot_file"
            )
        } catch let error as XTRustModelInventoryLiveBridgeError {
            return .unavailable(reasonCode: error.reasonCode)
        } catch {
            return .unavailable(reasonCode: "snapshot_file_read_failed")
        }
    }

    private static func loadHTTPInventory(
        baseURLString: String,
        runtimeBaseDir: URL
    ) async -> XTRustModelInventoryLiveBridgeResult {
        guard let baseURL = URL(string: baseURLString) else {
            return .unavailable(reasonCode: "invalid_http_base_url")
        }

        var components = URLComponents(
            url: baseURL
                .appendingPathComponent("model")
                .appendingPathComponent("inventory"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "runtime_base_dir", value: runtimeBaseDir.path),
            URLQueryItem(name: "now_ms", value: String(Int64(Date().timeIntervalSince1970 * 1000.0))),
        ]
        guard let url = components?.url else {
            return .unavailable(reasonCode: "invalid_inventory_url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unavailable(reasonCode: "invalid_http_response")
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                return .unavailable(reasonCode: "http_status_\(httpResponse.statusCode)")
            }
            return try decodeLoadedSnapshot(
                data: data,
                source: "rust_inventory_http"
            )
        } catch let error as XTRustModelInventoryLiveBridgeError {
            return .unavailable(reasonCode: error.reasonCode)
        } catch {
            return .unavailable(reasonCode: "http_inventory_fetch_failed")
        }
    }

    private static func decodeLoadedSnapshot(
        data: Data,
        source: String
    ) throws -> XTRustModelInventoryLiveBridgeResult {
        guard !rawDataContainsPotentialSecretMaterial(data) else {
            throw XTRustModelInventoryLiveBridgeError(reasonCode: "secret_material_detected")
        }

        let projection = try XTRustModelInventoryProjection.decode(from: data)
        guard projection.schemaVersion == "xhub.model_inventory.v1" else {
            throw XTRustModelInventoryLiveBridgeError(reasonCode: "invalid_inventory_schema")
        }
        guard !projection.containsPotentialSecretMaterial else {
            throw XTRustModelInventoryLiveBridgeError(reasonCode: "secret_material_detected")
        }

        return .loaded(
            XTRustModelInventoryLiveBridgeSnapshot(
                projection: projection,
                source: source
            )
        )
    }

    private static func rawDataContainsPotentialSecretMaterial(_ data: Data) -> Bool {
        guard let raw = String(data: data, encoding: .utf8)?.lowercased() else {
            return false
        }
        return raw.contains("sk-")
            || raw.contains("api_key")
            || raw.contains("refresh_token")
            || raw.contains("password")
    }

    private static func truthy(_ raw: String?) -> Bool {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on", "enabled":
            return true
        default:
            return false
        }
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func withTestingLock<T>(_ body: () -> T) -> T {
        testingLock.lock()
        defer { testingLock.unlock() }
        return body()
    }
}

private struct XTRustModelInventoryLiveBridgeError: Error {
    var reasonCode: String
}
