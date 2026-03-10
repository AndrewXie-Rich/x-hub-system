import Foundation

enum AXProjectStackDetector {
    struct Detection: Equatable {
        var swiftPackage: Bool
        var node: Bool
        var python: Bool
        var rust: Bool
        var go: Bool
        var dotnet: Bool
        var maven: Bool
        var gradle: Bool

        var any: Bool {
            swiftPackage || node || python || rust || go || dotnet || maven || gradle
        }
    }

    static func detect(forProjectRoot root: URL) -> Detection {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        let set = Set(names)

        let swiftPackage = set.contains("Package.swift")
        let node = set.contains("package.json")
        let python = set.contains("pyproject.toml")
            || set.contains("requirements.txt")
            || set.contains("requirements-dev.txt")
            || set.contains("Pipfile")
            || set.contains("setup.py")
            || set.contains("poetry.lock")
        let rust = set.contains("Cargo.toml")
        let go = set.contains("go.mod")
        let maven = set.contains("pom.xml")
        let gradle = set.contains("build.gradle")
            || set.contains("build.gradle.kts")
            || set.contains("settings.gradle")
            || set.contains("settings.gradle.kts")
            || set.contains("gradlew")
            || set.contains("gradlew.bat")

        let dotnet = names.contains(where: { n in
            let t = n.lowercased()
            return t.hasSuffix(".sln") || t.hasSuffix(".csproj") || t.hasSuffix(".fsproj") || t.hasSuffix(".vbproj")
        })

        return Detection(
            swiftPackage: swiftPackage,
            node: node,
            python: python,
            rust: rust,
            go: go,
            dotnet: dotnet,
            maven: maven,
            gradle: gradle
        )
    }

    static func recommendedVerifyCommands(forProjectRoot root: URL) -> [String] {
        let d = detect(forProjectRoot: root)

        // Prefer a single default to keep the "verify after changes" loop fast.
        if d.swiftPackage { return ["swift test"] }
        if d.node {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            let set = Set(names)
            if set.contains("pnpm-lock.yaml") { return ["pnpm test"] }
            if set.contains("yarn.lock") { return ["yarn test"] }
            if set.contains("bun.lockb") { return ["bun test"] }
            return ["npm test"]
        }
        if d.python { return ["python -m pytest"] }
        if d.rust { return ["cargo test"] }
        if d.go { return ["go test ./..."] }
        if d.dotnet { return ["dotnet test"] }
        if d.maven { return ["mvn test"] }
        if d.gradle {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            let set = Set(names)
            if set.contains("gradlew") { return ["./gradlew test"] }
            return ["gradle test"]
        }
        return []
    }

    static func filterApplicableVerifyCommands(_ commands: [String], forProjectRoot root: URL) -> [String] {
        let d = detect(forProjectRoot: root)

        func keepAsCustom(_ cmd: String) -> Bool {
            // If the command changes directory or points at a subproject explicitly,
            // we can't reliably validate it from just the root markers; assume the user knows what they're doing.
            let s = cmd.lowercased()
            return s.contains("cd ") || s.contains("&&") || s.contains("||") || s.contains(";") ||
                s.contains("--package-path") || s.contains("--prefix") || s.contains("--cwd")
        }

        func applicable(_ cmd: String) -> Bool {
            let t = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return false }
            if keepAsCustom(t) { return true }

            let s = t.lowercased()

            if s == "swift test" || s.hasPrefix("swift test ") { return d.swiftPackage }
            if s == "npm test" || s.hasPrefix("npm test ") { return d.node }
            if s == "yarn test" || s.hasPrefix("yarn test ") { return d.node }
            if s == "pnpm test" || s.hasPrefix("pnpm test ") { return d.node }
            if s == "bun test" || s.hasPrefix("bun test ") { return d.node }

            if s == "python -m pytest" || s.hasPrefix("python -m pytest ") { return d.python }
            if s == "python3 -m pytest" || s.hasPrefix("python3 -m pytest ") { return d.python }

            if s == "cargo test" || s.hasPrefix("cargo test ") { return d.rust }
            if s == "go test ./..." || s.hasPrefix("go test ") { return d.go }
            if s == "dotnet test" || s.hasPrefix("dotnet test ") { return d.dotnet }
            if s == "mvn test" || s.hasPrefix("mvn test ") { return d.maven }
            if s == "./gradlew test" || s.hasPrefix("./gradlew test ") { return d.gradle }
            if s == "gradle test" || s.hasPrefix("gradle test ") { return d.gradle }

            // Unknown command: keep it.
            return true
        }

        return commands.filter { applicable($0) }
    }
}
