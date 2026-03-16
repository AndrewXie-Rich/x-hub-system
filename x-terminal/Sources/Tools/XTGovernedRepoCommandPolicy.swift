import Foundation

enum XTGovernedRepoCommandProfile: String, CaseIterable, Sendable {
    case test
    case build
    case backup
}

func xtValidateGovernedRepoCommand(
    _ raw: String,
    profile: XTGovernedRepoCommandProfile
) -> String? {
    let trimmed = xtNormalizedGovernedRepoCommand(raw)
    guard !trimmed.isEmpty else { return nil }
    if profile == .backup {
        return xtValidateGovernedRepoBackupCommand(trimmed)
    }
    guard !xtGovernedRepoCommandContainsUnsafeShellOperators(trimmed) else {
        return nil
    }

    let lowered = trimmed.lowercased()
    let allowedPrefixes = xtGovernedRepoCommandPrefixes(for: profile)
    guard allowedPrefixes.contains(where: { prefix in
        lowered == prefix || lowered.hasPrefix(prefix + " ")
    }) else {
        return nil
    }
    return trimmed
}

func xtGovernedRepoCommandProfile(for raw: String) -> XTGovernedRepoCommandProfile? {
    if xtValidateGovernedRepoCommand(raw, profile: .backup) != nil {
        return .backup
    }
    if xtValidateGovernedRepoCommand(raw, profile: .test) != nil {
        return .test
    }
    if xtValidateGovernedRepoCommand(raw, profile: .build) != nil {
        return .build
    }
    return nil
}

func xtGovernedRepoCommandProfile(for call: ToolCall) -> XTGovernedRepoCommandProfile? {
    guard call.tool == .run_command,
          case .string(let rawCommand)? = call.args["command"] else {
        return nil
    }
    return xtGovernedRepoCommandProfile(for: rawCommand)
}

func xtGovernedRepoCommandContainsUnsafeShellOperators(_ command: String) -> Bool {
    let forbiddenTokens = [
        "&&",
        "||",
        ";",
        "|",
        ">",
        "<",
        "$(",
        "`",
        "\n"
    ]
    return forbiddenTokens.contains(where: { command.contains($0) })
}

func xtGovernedRepoCommandPrefixes(
    for profile: XTGovernedRepoCommandProfile
) -> [String] {
    switch profile {
    case .test:
        return [
            "swift test",
            "swift package test",
            "npm test",
            "npm run test",
            "npm run smoke",
            "npm exec vitest",
            "pnpm test",
            "pnpm run test",
            "pnpm run smoke",
            "pnpm vitest",
            "yarn test",
            "yarn smoke",
            "bun test",
            "bun run test",
            "pytest",
            "python -m pytest",
            "python3 -m pytest",
            "go test",
            "cargo test",
            "xcodebuild test",
            "gradle test",
            "./gradlew test",
            "mvn test",
            "bundle exec rspec",
            "rspec",
            "ctest",
            "deno test",
            "vitest",
            "npx vitest"
        ]
    case .build:
        return [
            "swift build",
            "swift package resolve",
            "npm run build",
            "pnpm run build",
            "yarn build",
            "bun run build",
            "cargo build",
            "go build",
            "xcodebuild build",
            "gradle build",
            "./gradlew build",
            "mvn package"
        ]
    case .backup:
        return []
    }
}

private func xtNormalizedGovernedRepoCommand(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func xtValidateGovernedRepoBackupCommand(_ command: String) -> String? {
    let canonical = """
mkdir -p .ax-backups && /usr/bin/tar -czf ".ax-backups/project-backup-$(/bin/date +%Y%m%d-%H%M%S).tgz" --exclude .git --exclude .build --exclude .ax-backups .
"""
    return command == canonical ? canonical : nil
}
