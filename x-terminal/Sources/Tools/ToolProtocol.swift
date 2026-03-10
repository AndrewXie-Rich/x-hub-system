import Foundation

enum ToolName: String, Codable, CaseIterable, Sendable {
    case read_file
    case write_file
    case list_dir
    case search
    case run_command
    case git_status
    case git_diff
    case git_apply_check
    case git_apply

    case session_list
    case session_resume
    case session_compact
    case memory_snapshot
    case project_snapshot

    // Networking (via Hub Bridge)
    case need_network
    case bridge_status
    case web_fetch
    case web_search
    case browser_read
}

enum ToolProfile: String, Codable, CaseIterable, Sendable {
    case minimal
    case coding
    case full
}

struct ToolCall: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var tool: ToolName
    var args: [String: JSONValue]

    init(id: String = UUID().uuidString, tool: ToolName, args: [String: JSONValue]) {
        self.id = id
        self.tool = tool
        self.args = args
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        tool = try c.decode(ToolName.self, forKey: .tool)
        args = (try? c.decode([String: JSONValue].self, forKey: .args)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case tool
        case args
    }
}

struct ToolActionEnvelope: Codable, Equatable, Sendable {
    // Either tool_calls or final must be present.
    var tool_calls: [ToolCall]?
    var final: String?
}

struct ToolResult: Codable, Equatable, Sendable {
    var id: String
    var tool: ToolName
    var ok: Bool
    var output: String
}

enum ToolRisk: Equatable, Sendable {
    case safe
    case needsConfirm
    case alwaysConfirm
}

enum ToolPolicy {
    static let defaultProfile: ToolProfile = .full

    static func parseProfile(_ raw: String?) -> ToolProfile {
        let token = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ToolProfile(rawValue: token) ?? defaultProfile
    }

    static func profileOptionsText() -> String {
        ToolProfile.allCases.map { $0.rawValue }.joined(separator: ", ")
    }

    static func tools(for profile: ToolProfile) -> Set<ToolName> {
        switch profile {
        case .minimal:
            return [
                .read_file,
                .list_dir,
                .search,
                .git_status,
                .git_diff,
                .session_list,
                .session_resume,
                .session_compact,
                .memory_snapshot,
                .project_snapshot,
                .bridge_status,
            ]
        case .coding:
            return [
                .read_file,
                .write_file,
                .list_dir,
                .search,
                .run_command,
                .git_status,
                .git_diff,
                .git_apply_check,
                .git_apply,
                .session_list,
                .session_resume,
                .session_compact,
                .memory_snapshot,
                .project_snapshot,
                .bridge_status,
            ]
        case .full:
            return Set(ToolName.allCases)
        }
    }

    static func parsePolicyTokens(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func normalizePolicyTokens(_ tokens: [String]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for token in tokens {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !t.isEmpty else { continue }
            guard !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

    static func effectiveAllowedTools(profileRaw: String, allowTokens: [String], denyTokens: [String]) -> Set<ToolName> {
        let profile = parseProfile(profileRaw)
        var allowed = tools(for: profile)
        allowed.formUnion(expandPolicyTokens(normalizePolicyTokens(allowTokens)))
        allowed.subtract(expandPolicyTokens(normalizePolicyTokens(denyTokens)))
        return allowed
    }

    static func sortedTools(_ tools: Set<ToolName>) -> [ToolName] {
        ToolName.allCases.filter { tools.contains($0) }
    }

    static func toolSpec(_ tool: ToolName) -> String {
        switch tool {
        case .read_file:
            return "- read_file {path, sandbox?}"
        case .write_file:
            return "- write_file {path, content, sandbox?}"
        case .list_dir:
            return "- list_dir {path, sandbox?}"
        case .search:
            return "- search {pattern, glob?, sandbox?}"
        case .run_command:
            return "- run_command {command, timeout_sec?, sandbox?}"
        case .git_status:
            return "- git_status {}"
        case .git_diff:
            return "- git_diff {cached?}"
        case .git_apply_check:
            return "- git_apply_check {patch}"
        case .git_apply:
            return "- git_apply {patch}"
        case .session_list:
            return "- session_list {project_id?, limit?}"
        case .session_resume:
            return "- session_resume {session_id?}"
        case .session_compact:
            return "- session_compact {session_id?}"
        case .memory_snapshot:
            return "- memory_snapshot {mode?, project_id?}"
        case .project_snapshot:
            return "- project_snapshot {}"
        case .bridge_status:
            return "- bridge_status {}"
        case .need_network:
            return "- need_network {seconds, reason?}"
        case .web_fetch:
            return "- web_fetch {url, grant_id, timeout_sec?, max_bytes?}"
        case .web_search:
            return "- web_search {query, grant_id, timeout_sec?, max_results?, max_bytes?}"
        case .browser_read:
            return "- browser_read {url, grant_id, timeout_sec?, max_bytes?}"
        }
    }

    private static func expandPolicyTokens(_ tokens: [String]) -> Set<ToolName> {
        var out = Set<ToolName>()
        for token in tokens {
            switch token {
            case "*", "all":
                out.formUnion(ToolName.allCases)
            case "group:readonly":
                out.formUnion([
                    .read_file,
                    .list_dir,
                    .search,
                    .git_status,
                    .git_diff,
                    .session_list,
                    .memory_snapshot,
                    .project_snapshot,
                    .bridge_status,
                ])
            case "group:fs":
                out.formUnion([.read_file, .write_file, .list_dir, .search])
            case "group:runtime":
                out.formUnion([.run_command, .session_list, .session_resume, .session_compact, .project_snapshot])
            case "group:git":
                out.formUnion([.git_status, .git_diff, .git_apply_check, .git_apply])
            case "group:network":
                out.formUnion([.bridge_status, .need_network, .web_fetch, .web_search, .browser_read])
            case "group:coding":
                out.formUnion(tools(for: .coding))
            case "group:minimal":
                out.formUnion(tools(for: .minimal))
            case "group:full":
                out.formUnion(tools(for: .full))
            default:
                if let tool = ToolName(rawValue: token) {
                    out.insert(tool)
                }
            }
        }
        return out
    }

    static func risk(for call: ToolCall) -> ToolRisk {
        switch call.tool {
        case .read_file, .list_dir, .search, .git_status, .git_diff:
            return .safe
        case .git_apply_check:
            return .safe
        case .session_list, .session_resume, .session_compact, .memory_snapshot, .project_snapshot:
            return .safe
        case .bridge_status:
            return .safe
        case .need_network:
            return .safe
        case .web_fetch, .web_search, .browser_read:
            // Network approvals are handled in Hub; avoid local confirmations.
            return .safe
        case .write_file, .run_command, .git_apply:
            return .needsConfirm
        }
    }

    static func isAlwaysConfirm(call: ToolCall) -> Bool {
        // A small guardrail: even in auto mode, force confirmation for blatantly dangerous commands.
        if call.tool != .run_command { return false }
        guard case .string(let cmd)? = call.args["command"] else { return false }
        let s = cmd.lowercased()
        let bad = ["sudo ", "shutdown", "reboot", "rm -rf /", "rm -rf /*", ":(){ :|:& };:"]
        return bad.contains(where: { s.contains($0) })
    }
}
