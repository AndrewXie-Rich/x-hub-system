enum ToolSandboxMode: String, CaseIterable {
    case host
    case sandbox
}

enum ToolSandboxPolicy {
    static func usesSandbox(mode: ToolSandboxMode, requested: Bool?) -> Bool {
        mode == .sandbox || requested == true
    }

    static func denialCode(mode: ToolSandboxMode, requested: Bool?, tool: String) -> String? {
        if mode == .sandbox && requested == false { return "sandbox_downgrade_denied" }
        guard usesSandbox(mode: mode, requested: requested) else { return nil }
        let supported = ["read_file", "write_file", "list_dir", "search", "run_command"]
        return supported.contains(tool) ? nil : "sandbox_tool_not_supported"
    }
}
