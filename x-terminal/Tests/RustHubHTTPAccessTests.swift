import Foundation
import Testing
@testable import XTerminal

struct RustHubHTTPAccessTests {
    @Test
    func accessKeyPrefersDirectEnvironmentValue() {
        let key = RustHubHTTPAccess.accessKey(
            environment: ["XHUB_RUST_HTTP_ACCESS_KEY": " direct-token \n"],
            baseDirs: []
        )
        #expect(key == "direct-token")
    }

    @Test
    func accessKeyReadsConfiguredFile() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyFile = root.appendingPathComponent("key.txt")
        try " file-token \n".write(to: keyFile, atomically: true, encoding: .utf8)

        let key = RustHubHTTPAccess.accessKey(
            environment: ["XHUB_RUST_HTTP_ACCESS_KEY_FILE": keyFile.path],
            baseDirs: []
        )

        #expect(key == "file-token")
    }

    @Test
    func accessKeyReadsRuntimeConfigCandidate() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let configDir = root.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try " candidate-token ".write(
            to: configDir.appendingPathComponent("xhubd_domain_access_key"),
            atomically: true,
            encoding: .utf8
        )

        let key = RustHubHTTPAccess.accessKey(environment: [:], baseDirs: [root])

        #expect(key == "candidate-token")
    }

    @Test
    func applyAccessKeyAddsBearerAndXHubHeaders() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let keyFile = root.appendingPathComponent("key.txt")
        try "header-token".write(to: keyFile, atomically: true, encoding: .utf8)
        RustHubHTTPAccess.resetCacheForTesting()
        defer { RustHubHTTPAccess.resetCacheForTesting() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:50151/ready")!)
        RustHubHTTPAccess.applyAccessKey(
            to: &request,
            environment: ["XHUB_RUST_HTTP_ACCESS_KEY_FILE": keyFile.path],
            baseDirs: []
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer header-token")
        #expect(request.value(forHTTPHeaderField: "X-XHub-Access-Key") == "header-token")
    }

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rust_hub_http_access_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
