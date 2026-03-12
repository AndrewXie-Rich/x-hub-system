import CryptoKit
import Foundation

struct XTAgentSkillPackageBuildResult: Sendable {
    var packageURL: URL
    var cleanupDirectoryURL: URL
    var manifestJSON: String
    var includedRelativePaths: [String]
}

enum XTAgentSkillPackageBuilder {
    static func build(
        skillDirectoryURL: URL,
        importReport: XTAgentSkillImportPreflightReport
    ) throws -> XTAgentSkillPackageBuildResult {
        let root = skillDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let includedFiles = try collectPackageFiles(root: root)
        guard !includedFiles.isEmpty else {
            throw NSError(
                domain: "xterminal.agent_skill_package",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No packageable files found in skill directory."]
            )
        }

        let cleanupDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-agent-skill-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanupDirectoryURL, withIntermediateDirectories: true)
        let packageURL = cleanupDirectoryURL.appendingPathComponent("skill.tgz")

        let tarArgs = ["-czf", packageURL.path, "-C", root.path] + includedFiles.map(\.relativePath)
        let tarResult = try ProcessCapture.run("/usr/bin/tar", tarArgs, cwd: nil, timeoutSec: 30.0)
        guard tarResult.exitCode == 0 else {
            throw NSError(
                domain: "xterminal.agent_skill_package",
                code: Int(tarResult.exitCode),
                userInfo: [NSLocalizedDescriptionKey: tarResult.combined]
            )
        }

        let frontmatter = parseFrontmatter(
            (try? String(contentsOf: root.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        )
        let manifest = SkillPackageManifest(
            schemaVersion: "xhub.skill_manifest.v1",
            skillId: importReport.manifest.skillId,
            name: firstNonEmpty(frontmatter["name"], importReport.manifest.displayName, importReport.manifest.skillId),
            version: firstNonEmpty(frontmatter["version"], "0.0.0-local"),
            description: firstNonEmpty(frontmatter["description"], "Imported from X-Terminal"),
            entrypoint: inferEntrypoint(relativePaths: includedFiles.map(\.relativePath)),
            capabilitiesRequired: importReport.manifest.normalizedCapabilities,
            networkPolicy: .init(directNetworkForbidden: true),
            files: includedFiles.map { file in
                SkillPackageManifestFile(path: file.relativePath, sha256: sha256Hex(file.data))
            },
            publisher: .init(publisherId: "local.agent_import"),
            installHint: "Imported via X-Terminal"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        guard let manifestJSON = String(data: manifestData, encoding: .utf8) else {
            throw NSError(
                domain: "xterminal.agent_skill_package",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode package manifest as UTF-8."]
            )
        }

        return XTAgentSkillPackageBuildResult(
            packageURL: packageURL,
            cleanupDirectoryURL: cleanupDirectoryURL,
            manifestJSON: manifestJSON,
            includedRelativePaths: includedFiles.map(\.relativePath)
        )
    }

    static func cleanup(_ result: XTAgentSkillPackageBuildResult) {
        try? FileManager.default.removeItem(at: result.cleanupDirectoryURL)
    }

    private struct PackagedFile {
        var relativePath: String
        var data: Data
    }

    private struct SkillPackageManifest: Codable {
        var schemaVersion: String
        var skillId: String
        var name: String
        var version: String
        var description: String
        var entrypoint: SkillPackageEntrypoint
        var capabilitiesRequired: [String]
        var networkPolicy: SkillPackageNetworkPolicy
        var files: [SkillPackageManifestFile]
        var publisher: SkillPackagePublisher
        var installHint: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case skillId = "skill_id"
            case name
            case version
            case description
            case entrypoint
            case capabilitiesRequired = "capabilities_required"
            case networkPolicy = "network_policy"
            case files
            case publisher
            case installHint = "install_hint"
        }
    }

    private struct SkillPackageEntrypoint: Codable {
        var runtime: String
        var command: String
        var args: [String]
    }

    private struct SkillPackageNetworkPolicy: Codable {
        var directNetworkForbidden: Bool

        enum CodingKeys: String, CodingKey {
            case directNetworkForbidden = "direct_network_forbidden"
        }
    }

    private struct SkillPackageManifestFile: Codable {
        var path: String
        var sha256: String
    }

    private struct SkillPackagePublisher: Codable {
        var publisherId: String

        enum CodingKeys: String, CodingKey {
            case publisherId = "publisher_id"
        }
    }

    private static func collectPackageFiles(root: URL) throws -> [PackagedFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [PackagedFile] = []
        while let next = enumerator.nextObject() as? URL {
            let name = next.lastPathComponent
            let lower = name.lowercased()
            if name.hasPrefix(".") && lower != "skill.md" {
                enumerator.skipDescendants()
                continue
            }
            if lower == "node_modules" {
                enumerator.skipDescendants()
                continue
            }
            let values = try next.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                continue
            }
            guard shouldIncludeInPackage(url: next) else { continue }
            let relativePath = relativePath(of: next, under: root)
            guard !relativePath.isEmpty else { continue }
            let data = try Data(contentsOf: next)
            files.append(PackagedFile(relativePath: relativePath, data: data))
        }

        return files.sorted { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private static func inferEntrypoint(relativePaths: [String]) -> SkillPackageEntrypoint {
        let normalized = Set(relativePaths.map { $0.lowercased() })
        if normalized.contains("dist/main.js") {
            return SkillPackageEntrypoint(runtime: "node", command: "node", args: ["dist/main.js"])
        }
        if normalized.contains("main.js") {
            return SkillPackageEntrypoint(runtime: "node", command: "node", args: ["main.js"])
        }
        if normalized.contains("dist/main.py") {
            return SkillPackageEntrypoint(runtime: "python", command: "python3", args: ["dist/main.py"])
        }
        if normalized.contains("main.py") {
            return SkillPackageEntrypoint(runtime: "python", command: "python3", args: ["main.py"])
        }
        if normalized.contains("run.sh") {
            return SkillPackageEntrypoint(runtime: "shell", command: "bash", args: ["run.sh"])
        }
        if normalized.contains("main.sh") {
            return SkillPackageEntrypoint(runtime: "shell", command: "bash", args: ["main.sh"])
        }
        return SkillPackageEntrypoint(runtime: "text", command: "cat", args: ["SKILL.md"])
    }

    private static func shouldIncludeInPackage(url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        if lower == "skill.md" || lower == "package.json" || lower == "agent.plugin.json" || lower == "openclaw.plugin.json" {
            return true
        }
        switch url.pathExtension.lowercased() {
        case "js", "ts", "mjs", "cjs", "mts", "cts", "jsx", "tsx", "py", "sh", "bash", "zsh", "md", "json", "yaml", "yml", "txt":
            return true
        default:
            return false
        }
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedURL == resolvedRoot || resolvedURL.hasPrefix(resolvedRoot + "/") else {
            return ""
        }
        if resolvedURL == resolvedRoot {
            return ""
        }
        return String(resolvedURL.dropFirst(resolvedRoot.count + 1))
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return [:] }
        let remainder = String(normalized.dropFirst(4))
        guard let closingRange = remainder.range(of: "\n---") else { return [:] }
        let block = String(remainder[..<closingRange.lowerBound])
        var values: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = raw[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = raw[raw.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty, !value.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
