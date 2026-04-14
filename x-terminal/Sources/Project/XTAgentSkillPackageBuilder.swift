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
        var packagedFiles = try collectPackageFiles(root: root)
        guard !packagedFiles.isEmpty else {
            throw NSError(
                domain: "xterminal.agent_skill_package",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No packageable files found in skill directory."]
            )
        }

        let cleanupDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-agent-skill-package-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanupDirectoryURL, withIntermediateDirectories: true)
        let stagingRootURL = cleanupDirectoryURL.appendingPathComponent("package-root", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
        let packageURL = cleanupDirectoryURL.appendingPathComponent("skill.tgz")

        let sourceManifestObject = try buildSourceManifestObject(
            root: root,
            packagedFiles: packagedFiles,
            importReport: importReport
        )
        let sourceManifestData = try encodeJSONObject(
            sourceManifestObject,
            errorDomain: "xterminal.agent_skill_package",
            errorCode: 2,
            failureMessage: "Failed to encode package source manifest as UTF-8."
        )
        upsertPackagedFile(
            relativePath: "skill.json",
            data: sourceManifestData,
            into: &packagedFiles
        )

        let uploadManifestData = try buildUploadManifestData(
            sourceManifestObject: sourceManifestObject,
            packagedFiles: packagedFiles
        )
        let manifestJSON = try requireUTF8String(
            uploadManifestData,
            errorDomain: "xterminal.agent_skill_package",
            errorCode: 3,
            failureMessage: "Failed to encode package manifest as UTF-8."
        )

        try stagePackagedFiles(packagedFiles, in: stagingRootURL)

        let tarArgs = ["-czf", packageURL.path, "-C", stagingRootURL.path] + packagedFiles.map(\.relativePath)
        let tarResult = try ProcessCapture.run("/usr/bin/tar", tarArgs, cwd: nil, timeoutSec: 30.0)
        guard tarResult.exitCode == 0 else {
            throw NSError(
                domain: "xterminal.agent_skill_package",
                code: Int(tarResult.exitCode),
                userInfo: [NSLocalizedDescriptionKey: tarResult.combined]
            )
        }

        return XTAgentSkillPackageBuildResult(
            packageURL: packageURL,
            cleanupDirectoryURL: cleanupDirectoryURL,
            manifestJSON: manifestJSON,
            includedRelativePaths: packagedFiles.map(\.relativePath)
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

    private static let sourceManifestTransientKeys: Set<String> = [
        "files",
        "package_sha256",
        "manifest_sha256",
        "package_path",
        "manifest_path",
        "signature",
    ]

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

    private static func buildSourceManifestObject(
        root: URL,
        packagedFiles: [PackagedFile],
        importReport: XTAgentSkillImportPreflightReport
    ) throws -> [String: Any] {
        let frontmatter = parseFrontmatter(
            (try? String(contentsOf: root.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        )
        var manifest = try loadExistingSourceManifestObject(from: packagedFiles) ?? [:]
        for key in sourceManifestTransientKeys {
            manifest.removeValue(forKey: key)
        }

        let existingCapabilities = stringArrayValue(
            manifest["capabilities_required"]
                ?? manifest["required_capabilities"]
                ?? manifest["capabilities"]
        )
        let resolvedSkillId = firstNonEmpty(
            stringValue(manifest["skill_id"]),
            stringValue(manifest["id"]),
            importReport.manifest.skillId
        )
        let resolvedCapabilities = existingCapabilities.isEmpty
            ? importReport.manifest.normalizedCapabilities
            : existingCapabilities
        let existingIntentFamilies = stringArrayValue(manifest["intent_families"])
        let resolvedIntentFamilies = !importReport.manifest.intentFamilies.isEmpty
            ? importReport.manifest.intentFamilies
            : !existingIntentFamilies.isEmpty
                ? existingIntentFamilies
                : XTAgentSkillImportNormalizer.canonicalIntentFamilies(
                    skillId: resolvedSkillId,
                    normalizedCapabilities: resolvedCapabilities
                )
        let resolvedCapabilityFamilies = XTAgentSkillImportNormalizer.canonicalCapabilityFamilies(
            intentFamilies: resolvedIntentFamilies,
            normalizedCapabilities: resolvedCapabilities
        )
        let resolvedCapabilityProfiles = XTSkillCapabilityProfileSupport.capabilityProfiles(
            for: resolvedCapabilityFamilies
        )

        let resolvedRiskLevel = firstNonEmpty(
            normalizedRiskLevel(
                stringValue(manifest["risk_level"])
                    ?? stringValue(manifest["riskLevel"])
                    ?? stringValue(manifest["risk_profile"])
            ),
            importReport.manifest.riskLevel
        )
        let resolvedRequiresGrant = boolValue(manifest["requires_grant"] ?? manifest["requiresGrant"])
            ?? importReport.manifest.requiresGrant

        manifest["schema_version"] = firstNonEmpty(
            stringValue(manifest["schema_version"]),
            stringValue(manifest["manifest_version"]),
            "xhub.skill_manifest.v1"
        )
        manifest["skill_id"] = resolvedSkillId
        manifest["name"] = firstNonEmpty(
            stringValue(manifest["name"]),
            stringValue(manifest["title"]),
            frontmatter["name"],
            importReport.manifest.displayName,
            resolvedSkillId
        )
        manifest["version"] = firstNonEmpty(
            stringValue(manifest["version"]),
            stringValue(manifest["skill_version"]),
            frontmatter["version"],
            "0.0.0-local"
        )
        manifest["description"] = firstNonEmpty(
            stringValue(manifest["description"]),
            stringValue(manifest["summary"]),
            frontmatter["description"],
            "Imported from X-Terminal"
        )
        manifest["entrypoint"] = resolvedEntrypoint(
            from: manifest,
            relativePaths: packagedFiles.map(\.relativePath)
        )
        manifest["capabilities_required"] = resolvedCapabilities
        manifest["intent_families"] = resolvedIntentFamilies
        manifest["capability_families"] = resolvedCapabilityFamilies
        manifest["capability_profiles"] = resolvedCapabilityProfiles
        manifest["grant_floor"] = XTSkillCapabilityProfileSupport.grantFloor(
            for: resolvedCapabilityFamilies,
            requiresGrant: resolvedRequiresGrant,
            riskLevel: resolvedRiskLevel
        )
        manifest["approval_floor"] = XTSkillCapabilityProfileSupport.approvalFloor(
            for: resolvedCapabilityFamilies
        )
        manifest["risk_level"] = resolvedRiskLevel
        manifest["requires_grant"] = resolvedRequiresGrant
        manifest["network_policy"] = resolvedNetworkPolicy(from: manifest)
        manifest["publisher"] = resolvedPublisher(from: manifest)
        manifest["install_hint"] = firstNonEmpty(
            stringValue(manifest["install_hint"]),
            stringValue((manifest["install"] as? [String: Any])?["command"]),
            "Imported via X-Terminal"
        )

        return manifest
    }

    private static func buildUploadManifestData(
        sourceManifestObject: [String: Any],
        packagedFiles: [PackagedFile]
    ) throws -> Data {
        var manifest = sourceManifestObject
        manifest["files"] = packagedFiles.map { file in
            [
                "path": file.relativePath,
                "sha256": sha256Hex(file.data),
            ]
        }
        return try encodeJSONObject(
            manifest,
            errorDomain: "xterminal.agent_skill_package",
            errorCode: 4,
            failureMessage: "Failed to encode upload manifest JSON."
        )
    }

    private static func loadExistingSourceManifestObject(
        from packagedFiles: [PackagedFile]
    ) throws -> [String: Any]? {
        guard let manifestFile = packagedFiles.first(where: { $0.relativePath.lowercased() == "skill.json" }) else {
            return nil
        }
        guard !manifestFile.data.isEmpty else {
            return nil
        }
        let root = try JSONSerialization.jsonObject(with: manifestFile.data)
        guard let object = root as? [String: Any] else {
            throw NSError(
                domain: "xterminal.agent_skill_package",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Existing skill.json is not a JSON object."]
            )
        }
        return object
    }

    private static func upsertPackagedFile(
        relativePath: String,
        data: Data,
        into packagedFiles: inout [PackagedFile]
    ) {
        packagedFiles.removeAll { $0.relativePath.lowercased() == relativePath.lowercased() }
        packagedFiles.append(PackagedFile(relativePath: relativePath, data: data))
        packagedFiles.sort { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    private static func stagePackagedFiles(
        _ packagedFiles: [PackagedFile],
        in stagingRootURL: URL
    ) throws {
        for file in packagedFiles {
            let destinationURL = stagingRootURL.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: destinationURL)
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

    private static func resolvedEntrypoint(
        from manifest: [String: Any],
        relativePaths: [String]
    ) -> [String: Any] {
        let entrypoint = manifest["entrypoint"] as? [String: Any] ?? [:]
        let runner = manifest["runner"] as? [String: Any] ?? [:]
        let fallback = inferEntrypoint(relativePaths: relativePaths)
        let args = !stringArrayValue(entrypoint["args"]).isEmpty
            ? stringArrayValue(entrypoint["args"])
            : !stringArrayValue(entrypoint["arguments"]).isEmpty
                ? stringArrayValue(entrypoint["arguments"])
                : stringArrayValue(manifest["args"])

        return [
            "runtime": firstNonEmpty(
                stringValue(entrypoint["runtime"]),
                stringValue(manifest["runtime"]),
                stringValue(entrypoint["type"]),
                fallback.runtime
            ),
            "command": firstNonEmpty(
                stringValue(entrypoint["command"]),
                stringValue(entrypoint["exec"]),
                stringValue(manifest["command"]),
                stringValue(manifest["main"]),
                stringValue(runner["command"]),
                manifest["entrypoint"] as? String,
                fallback.command
            ),
            "args": args.isEmpty ? fallback.args : args,
        ]
    }

    private static func resolvedNetworkPolicy(from manifest: [String: Any]) -> [String: Any] {
        let networkPolicy = manifest["network_policy"] as? [String: Any] ?? [:]
        return [
            "direct_network_forbidden": boolValue(networkPolicy["direct_network_forbidden"]) ?? true,
        ]
    }

    private static func resolvedPublisher(from manifest: [String: Any]) -> [String: Any] {
        let publisher = manifest["publisher"] as? [String: Any] ?? [:]
        return [
            "publisher_id": firstNonEmpty(
                stringValue(publisher["publisher_id"]),
                stringValue(manifest["publisher_id"]),
                stringValue(publisher["id"]),
                stringValue(manifest["author_id"]),
                stringValue(manifest["author"]),
                "local.agent_import"
            ),
        ]
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

    private static func encodeJSONObject(
        _ object: [String: Any],
        errorDomain: String,
        errorCode: Int,
        failureMessage: String
    ) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NSError(
                domain: errorDomain,
                code: errorCode,
                userInfo: [NSLocalizedDescriptionKey: failureMessage]
            )
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func requireUTF8String(
        _ data: Data,
        errorDomain: String,
        errorCode: Int,
        failureMessage: String
    ) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: errorDomain,
                code: errorCode,
                userInfo: [NSLocalizedDescriptionKey: failureMessage]
            )
        }
        return text
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func stringArrayValue(_ value: Any?) -> [String] {
        switch value {
        case let array as [Any]:
            return array.compactMap { item in
                let raw: String
                switch item {
                case let string as String:
                    raw = string
                case let number as NSNumber:
                    raw = number.stringValue
                default:
                    raw = ""
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        default:
            return []
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "y", "on":
                return true
            case "0", "false", "no", "n", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func normalizedRiskLevel(_ raw: String?) -> String {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "moderate":
            return "medium"
        case "low", "medium", "high", "critical":
            return (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return ""
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
