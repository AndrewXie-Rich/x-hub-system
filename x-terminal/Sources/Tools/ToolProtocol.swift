import Foundation

enum ToolName: String, Codable, CaseIterable, Sendable {
    case read_file
    case write_file
    case delete_path
    case move_path
    case list_dir
    case search
    case run_command
    case process_start
    case process_status
    case process_logs
    case process_stop
    case git_status
    case git_diff
    case git_commit
    case git_push
    case git_apply_check
    case git_apply
    case pr_create
    case ci_read
    case ci_trigger

    case session_list
    case session_resume
    case session_compact
    case agentImportRecord = "agent.import.record"
    case memory_snapshot
    case project_snapshot

    // Device automation (project-scoped + trusted automation gated)
    case deviceUIObserve = "device.ui.observe"
    case deviceUIAct = "device.ui.act"
    case deviceUIStep = "device.ui.step"
    case deviceClipboardRead = "device.clipboard.read"
    case deviceClipboardWrite = "device.clipboard.write"
    case deviceScreenCapture = "device.screen.capture"
    case deviceBrowserControl = "device.browser.control"
    case deviceAppleScript = "device.applescript"

    // Networking (via Hub Bridge)
    case need_network
    case bridge_status
    case skills_search = "skills.search"
    case skills_pin = "skills.pin"
    case summarize
    case supervisorVoicePlayback = "supervisor.voice.playback"
    case run_local_task
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
    var skill_calls: [GovernedSkillCall]? = nil
    var final: String?
    var guidance_ack: ToolGuidanceAckPayload?

    init(
        tool_calls: [ToolCall]? = nil,
        skill_calls: [GovernedSkillCall]? = nil,
        final: String? = nil,
        guidance_ack: ToolGuidanceAckPayload? = nil
    ) {
        self.tool_calls = tool_calls
        self.skill_calls = skill_calls
        self.final = final
        self.guidance_ack = guidance_ack
    }
}

struct GovernedSkillCall: Codable, Equatable, Sendable {
    var id: String
    var skill_id: String
    var intent_families: [String]? = nil
    var payload: [String: JSONValue]

    init(
        id: String = UUID().uuidString,
        skill_id: String,
        intent_families: [String]? = nil,
        payload: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.skill_id = skill_id
        self.intent_families = intent_families
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        skill_id = try container.decode(String.self, forKey: .skill_id)
        intent_families = try? container.decode([String].self, forKey: .intent_families)
        payload = (try? container.decode([String: JSONValue].self, forKey: .payload)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case id
        case skill_id
        case intent_families
        case payload
    }
}

enum ToolGuidanceAckStatus: String, Codable, Equatable, Sendable {
    case accepted
    case deferred
    case rejected
}

struct ToolGuidanceAckPayload: Codable, Equatable, Sendable {
    var injection_id: String?
    var status: ToolGuidanceAckStatus
    var note: String?
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
    static let defaultProfile: ToolProfile = .minimal

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
                .agentImportRecord,
                .memory_snapshot,
                .project_snapshot,
                .bridge_status,
                .skills_search,
                .skills_pin,
                .summarize,
                .supervisorVoicePlayback,
                .run_local_task,
            ]
        case .coding:
            return [
                .read_file,
                .write_file,
                .delete_path,
                .move_path,
                .list_dir,
                .search,
                .run_command,
                .process_start,
                .process_status,
                .process_logs,
                .process_stop,
                .git_status,
                .git_diff,
                .git_commit,
                .git_apply_check,
                .git_apply,
                .session_list,
                .session_resume,
                .session_compact,
                .agentImportRecord,
                .memory_snapshot,
                .project_snapshot,
                .bridge_status,
                .skills_search,
                .skills_pin,
                .summarize,
                .supervisorVoicePlayback,
                .run_local_task,
            ]
        case .full:
            return [
                .read_file,
                .write_file,
                .delete_path,
                .move_path,
                .list_dir,
                .search,
                .run_command,
                .process_start,
                .process_status,
                .process_logs,
                .process_stop,
                .git_status,
                .git_diff,
                .git_commit,
                .git_push,
                .git_apply_check,
                .git_apply,
                .pr_create,
                .ci_read,
                .ci_trigger,
                .session_list,
                .session_resume,
                .session_compact,
                .agentImportRecord,
                .memory_snapshot,
                .project_snapshot,
                .need_network,
                .bridge_status,
                .skills_search,
                .skills_pin,
                .summarize,
                .supervisorVoicePlayback,
                .run_local_task,
                .web_fetch,
                .web_search,
                .browser_read,
            ]
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
        usableTools(grantedTools(profileRaw: profileRaw, allowTokens: allowTokens, denyTokens: denyTokens))
    }

    static func sortedTools(_ tools: Set<ToolName>) -> [ToolName] {
        ToolName.allCases.filter { tools.contains($0) }
    }

    static func runtimeRequiredTools(for tool: ToolName) -> Set<ToolName> {
        switch tool {
        case .deviceUIStep:
            return [.deviceUIStep, .deviceUIObserve, .deviceUIAct]
        default:
            return [tool]
        }
    }

    static func usableTools(_ tools: Set<ToolName>) -> Set<ToolName> {
        Set(tools.filter { runtimeRequiredTools(for: $0).isSubset(of: tools) })
    }

    static func grantedTools(profileRaw: String, allowTokens: [String], denyTokens: [String]) -> Set<ToolName> {
        let profile = parseProfile(profileRaw)
        var allowed = tools(for: profile)
        allowed.formUnion(expandPolicyTokens(normalizePolicyTokens(allowTokens)))
        allowed.subtract(expandPolicyTokens(normalizePolicyTokens(denyTokens)))
        return allowed
    }

    static func toolSpec(_ tool: ToolName) -> String {
        switch tool {
        case .read_file:
            return "- read_file {path, sandbox?}"
        case .write_file:
            return "- write_file {path, content, sandbox?}"
        case .delete_path:
            return "- delete_path {path, recursive?, force?, sandbox?}"
        case .move_path:
            return "- move_path {from, to, overwrite?, create_dirs?, sandbox?}"
        case .list_dir:
            return "- list_dir {path, sandbox?}"
        case .search:
            return "- search {pattern, path?, glob?, sandbox?}"
        case .run_command:
            return "- run_command {command, timeout_sec?, sandbox?}"
        case .process_start:
            return "- process_start {command, name?, process_id?, cwd?, env?, restart_on_exit?}"
        case .process_status:
            return "- process_status {process_id?, include_exited?}"
        case .process_logs:
            return "- process_logs {process_id, tail_lines?, max_bytes?}"
        case .process_stop:
            return "- process_stop {process_id, force?}"
        case .git_status:
            return "- git_status {}"
        case .git_diff:
            return "- git_diff {cached?}"
        case .git_commit:
            return "- git_commit {message, all?, allow_empty?, paths?}"
        case .git_push:
            return "- git_push {remote?, branch?, set_upstream?}"
        case .git_apply_check:
            return "- git_apply_check {patch}"
        case .git_apply:
            return "- git_apply {patch}"
        case .pr_create:
            return "- pr_create {title?, body?, base?, head?, draft?, fill?, labels?, reviewers?}"
        case .ci_read:
            return "- ci_read {provider?, workflow?, branch?, commit?, limit?}"
        case .ci_trigger:
            return "- ci_trigger {provider?, workflow, ref?, inputs?}"
        case .session_list:
            return "- session_list {project_id?, limit?}"
        case .session_resume:
            return "- session_resume {session_id?}"
        case .session_compact:
            return "- session_compact {session_id?}"
        case .agentImportRecord:
            return "- agent.import.record {staging_id?|id?|import_id?|selector?|skill_id?|project_id?}"
        case .memory_snapshot:
            return "- memory_snapshot {mode?, project_id?}"
        case .project_snapshot:
            return "- project_snapshot {}"
        case .deviceUIObserve:
            return "- device.ui.observe {target_role?, target_title?, target_identifier?, target_description?, target_value_contains?, max_results?}"
        case .deviceUIAct:
            return "- device.ui.act {action, value?, target_role?, target_title?, target_identifier?, target_description?, target_value_contains?, target_index?}"
        case .deviceUIStep:
            return "- device.ui.step {action, value?, target_role?, target_title?, target_identifier?, target_description?, target_value_contains?, target_index?, max_results?}"
        case .deviceClipboardRead:
            return "- device.clipboard.read {}"
        case .deviceClipboardWrite:
            return "- device.clipboard.write {text|content|value}"
        case .deviceScreenCapture:
            return "- device.screen.capture {path?}"
        case .deviceBrowserControl:
            return "- device.browser.control {action=open|open_url|navigate|snapshot|extract|click|type|upload, url?, session_id?, selector?, field_role?, text|content|value?, secret_item_id?|secret_scope?|secret_name?|secret_project_id?, path?, grant_id?, timeout_sec?, max_bytes?, probe_depth?}"
        case .deviceAppleScript:
            return "- device.applescript {source}"
        case .bridge_status:
            return "- bridge_status {}"
        case .need_network:
            return "- need_network {seconds, reason?}"
        case .skills_search:
            return "- skills.search {query, source_filter?, project_id?, limit?}"
        case .skills_pin:
            return "- skills.pin {skill_id, package_sha256, scope?, project_id?, note?}"
        case .summarize:
            return "- summarize {url?|path?|text|content|value, focus?, format?, max_chars?, grant_id?, timeout_sec?, max_bytes?}"
        case .supervisorVoicePlayback:
            return "- supervisor.voice.playback {action?=status|preview|speak|stop, text|content|value?}"
        case .run_local_task:
            return "- run_local_task {task_kind, model_id?|model?|preferred_model_id?, prompt?|text?|content?|value?|texts?|audio_path?|image_path?|image_paths?|multimodal_messages?|input?|options?, device_id?, timeout_sec?} // XT auto-binds a runnable local model when model args are omitted and Hub inventory is ready"
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
                    .agentImportRecord,
                    .memory_snapshot,
                    .project_snapshot,
                    .bridge_status,
                    .skills_search,
                    .summarize,
                    .supervisorVoicePlayback,
                    .run_local_task,
                ])
            case "group:fs":
                out.formUnion([.read_file, .write_file, .delete_path, .move_path, .list_dir, .search])
            case "group:runtime":
                out.formUnion([
                    .run_command,
                    .process_start,
                    .process_status,
                    .process_logs,
                    .process_stop,
                    .session_list,
                    .session_resume,
                    .session_compact,
                    .project_snapshot,
                    .run_local_task,
                ])
            case "group:git":
                out.formUnion([.git_status, .git_diff, .git_commit, .git_push, .git_apply_check, .git_apply])
            case "group:delivery":
                out.formUnion([.git_push, .pr_create, .ci_read, .ci_trigger])
            case "group:network":
                out.formUnion([.bridge_status, .need_network, .web_fetch, .web_search, .browser_read])
            case "group:device_automation":
                out.formUnion([.deviceUIObserve, .deviceUIAct, .deviceUIStep, .deviceClipboardRead, .deviceClipboardWrite, .deviceScreenCapture, .deviceBrowserControl, .deviceAppleScript])
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
        case .ci_read:
            return .safe
        case .session_list, .session_resume, .session_compact, .agentImportRecord, .memory_snapshot, .project_snapshot:
            return .safe
        case .process_status, .process_logs:
            return .safe
        case .deviceUIObserve:
            return .needsConfirm
        case .deviceUIAct:
            return .needsConfirm
        case .deviceUIStep:
            return .needsConfirm
        case .deviceClipboardRead, .deviceClipboardWrite:
            return .safe
        case .deviceScreenCapture:
            return .needsConfirm
        case .deviceBrowserControl:
            return .needsConfirm
        case .deviceAppleScript:
            return .needsConfirm
        case .bridge_status:
            return .safe
        case .need_network:
            return .safe
        case .skills_search, .skills_pin, .summarize, .supervisorVoicePlayback, .run_local_task:
            return .safe
        case .web_fetch, .web_search, .browser_read:
            // Network approvals are handled in Hub; avoid local confirmations.
            return .safe
        case .write_file, .delete_path, .move_path, .run_command, .process_start, .process_stop, .git_commit, .git_push, .git_apply, .pr_create, .ci_trigger:
            return .needsConfirm
        }
    }

    static func isAlwaysConfirm(call: ToolCall) -> Bool {
        // A small guardrail: even in auto mode, force confirmation for blatantly dangerous commands.
        switch call.tool {
        case .run_command:
            guard case .string(let cmd)? = call.args["command"] else { return false }
            let s = cmd.lowercased()
            let bad = ["sudo ", "shutdown", "reboot", "rm -rf /", "rm -rf /*", ":(){ :|:& };:"]
            return bad.contains(where: { s.contains($0) })
        case .delete_path:
            guard case .string(let path)? = call.args["path"] else { return false }
            let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty || normalized == "." || normalized == "./" || normalized == "/"
        default:
            return false
        }
    }
}
