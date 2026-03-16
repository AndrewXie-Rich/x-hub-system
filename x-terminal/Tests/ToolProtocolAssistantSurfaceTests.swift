import Testing
@testable import XTerminal

struct ToolProtocolAssistantSurfaceTests {

    @Test
    func assistantSurfaceSpecsExposeSkillAlignedTools() {
        #expect(ToolPolicy.toolSpec(.delete_path).contains("recursive"))
        #expect(ToolPolicy.toolSpec(.move_path).contains("overwrite"))
        #expect(ToolPolicy.toolSpec(.process_start).contains("restart_on_exit"))
        #expect(ToolPolicy.toolSpec(.process_status).contains("include_exited"))
        #expect(ToolPolicy.toolSpec(.process_logs).contains("tail_lines"))
        #expect(ToolPolicy.toolSpec(.process_stop).contains("process_id"))
        #expect(ToolPolicy.toolSpec(.git_commit).contains("allow_empty"))
        #expect(ToolPolicy.toolSpec(.git_push).contains("set_upstream"))
        #expect(ToolPolicy.toolSpec(.pr_create).contains("reviewers"))
        #expect(ToolPolicy.toolSpec(.ci_read).contains("workflow"))
        #expect(ToolPolicy.toolSpec(.ci_trigger).contains("inputs"))
        #expect(ToolPolicy.toolSpec(.session_list).contains("project_id"))
        #expect(ToolPolicy.toolSpec(.agentImportRecord).contains("staging_id"))
        #expect(ToolPolicy.toolSpec(.agentImportRecord).contains("selector"))
        #expect(ToolPolicy.toolSpec(.memory_snapshot).contains("mode"))
        #expect(ToolPolicy.toolSpec(.skills_search).contains("source_filter"))
        #expect(ToolPolicy.toolSpec(.summarize).contains("url?|path?|text"))
        #expect(ToolPolicy.toolSpec(.web_search).contains("grant_id"))
        #expect(ToolPolicy.toolSpec(.browser_read).contains("url"))
        #expect(ToolPolicy.toolSpec(.project_snapshot) == "- project_snapshot {}")
        #expect(ToolPolicy.toolSpec(.deviceUIObserve).contains("target_identifier"))
        #expect(ToolPolicy.toolSpec(.deviceUIObserve).contains("max_results"))
        #expect(ToolPolicy.toolSpec(.deviceUIAct).contains("action"))
        #expect(ToolPolicy.toolSpec(.deviceUIAct).contains("target_identifier"))
        #expect(ToolPolicy.toolSpec(.deviceUIAct).contains("target_index"))
        #expect(ToolPolicy.toolSpec(.deviceUIStep).contains("max_results"))
        #expect(ToolPolicy.toolSpec(.deviceClipboardRead) == "- device.clipboard.read {}")
        #expect(ToolPolicy.toolSpec(.deviceClipboardWrite).contains("text|content|value"))
        #expect(ToolPolicy.toolSpec(.deviceScreenCapture).contains("path"))
        #expect(ToolPolicy.toolSpec(.deviceBrowserControl).contains("action"))
        #expect(ToolPolicy.toolSpec(.deviceBrowserControl).contains("click|type|upload"))
        #expect(ToolPolicy.toolSpec(.deviceBrowserControl).contains("selector"))
        #expect(ToolPolicy.toolSpec(.deviceBrowserControl).contains("field_role"))
        #expect(ToolPolicy.toolSpec(.deviceBrowserControl).contains("secret_item_id"))
        #expect(ToolPolicy.toolSpec(.deviceBrowserControl).contains("secret_name"))
        #expect(ToolPolicy.toolSpec(.deviceAppleScript).contains("source"))
    }

    @Test
    func toolPolicyGroupsAndRiskIncludeNewSurface() {
        let allowed = ToolPolicy.effectiveAllowedTools(
            profileRaw: ToolProfile.minimal.rawValue,
            allowTokens: ["group:runtime", "group:network"],
            denyTokens: []
        )

        #expect(allowed.contains(.session_list))
        #expect(allowed.contains(.session_resume))
        #expect(allowed.contains(.session_compact))
        #expect(allowed.contains(.agentImportRecord))
        #expect(allowed.contains(.memory_snapshot))
        #expect(allowed.contains(.project_snapshot))
        #expect(allowed.contains(.process_start))
        #expect(allowed.contains(.process_status))
        #expect(allowed.contains(.process_logs))
        #expect(allowed.contains(.process_stop))
        #expect(!allowed.contains(.git_push))
        #expect(!allowed.contains(.pr_create))
        #expect(allowed.contains(.skills_search))
        #expect(allowed.contains(.summarize))
        #expect(allowed.contains(.web_search))
        #expect(allowed.contains(.browser_read))
        #expect(!allowed.contains(.deviceUIObserve))
        #expect(!allowed.contains(.deviceUIAct))
        #expect(!allowed.contains(.deviceUIStep))
        #expect(!allowed.contains(.deviceClipboardRead))
        let full = ToolPolicy.effectiveAllowedTools(
            profileRaw: ToolProfile.full.rawValue,
            allowTokens: [],
            denyTokens: []
        )
        #expect(full.contains(.delete_path))
        #expect(full.contains(.move_path))
        #expect(full.contains(.process_start))
        #expect(full.contains(.process_status))
        #expect(full.contains(.process_logs))
        #expect(full.contains(.process_stop))
        #expect(full.contains(.git_commit))
        #expect(full.contains(.git_push))
        #expect(full.contains(.pr_create))
        #expect(full.contains(.ci_read))
        #expect(full.contains(.ci_trigger))
        #expect(!full.contains(.deviceUIObserve))
        #expect(!full.contains(.deviceUIAct))
        #expect(!full.contains(.deviceUIStep))
        #expect(!full.contains(.deviceClipboardRead))
        #expect(!full.contains(.deviceAppleScript))
        let armed = ToolPolicy.effectiveAllowedTools(
            profileRaw: ToolProfile.full.rawValue,
            allowTokens: ["group:device_automation"],
            denyTokens: []
        )
        #expect(armed.contains(.deviceUIObserve))
        #expect(armed.contains(.deviceUIAct))
        #expect(armed.contains(.deviceUIStep))
        #expect(armed.contains(.deviceClipboardRead))
        #expect(armed.contains(.deviceClipboardWrite))
        #expect(armed.contains(.deviceScreenCapture))
        #expect(armed.contains(.deviceBrowserControl))
        #expect(armed.contains(.deviceAppleScript))
        let incompleteStep = ToolPolicy.effectiveAllowedTools(
            profileRaw: ToolProfile.full.rawValue,
            allowTokens: ["device.ui.step"],
            denyTokens: []
        )
        #expect(!incompleteStep.contains(.deviceUIStep))
        let completeStep = ToolPolicy.effectiveAllowedTools(
            profileRaw: ToolProfile.full.rawValue,
            allowTokens: ["device.ui.step", "device.ui.observe", "device.ui.act"],
            denyTokens: []
        )
        #expect(completeStep.contains(.deviceUIStep))
        #expect(ToolPolicy.risk(for: ToolCall(tool: .session_resume, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .agentImportRecord, args: ["staging_id": .string("stage-1")])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .agentImportRecord, args: ["selector": .string("latest_for_project")])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .memory_snapshot, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .skills_search, args: ["query": .string("browser")])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .summarize, args: ["text": .string("hello")])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .web_search, args: ["query": .string("OpenAI")])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .delete_path, args: ["path": .string("Sources/Old.swift")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .move_path, args: ["from": .string("a"), "to": .string("b")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .process_start, args: ["command": .string("npm run dev")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .process_status, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .process_logs, args: ["process_id": .string("web")])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .process_stop, args: ["process_id": .string("web")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .git_commit, args: ["message": .string("ship it")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .git_push, args: [:])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .pr_create, args: ["title": .string("PR")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .ci_read, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .ci_trigger, args: ["workflow": .string("build.yml")])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceUIObserve, args: [:])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceUIAct, args: [:])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceUIStep, args: [:])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceClipboardRead, args: [:])) == .safe)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceScreenCapture, args: [:])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceBrowserControl, args: [:])) == .needsConfirm)
        #expect(ToolPolicy.risk(for: ToolCall(tool: .deviceAppleScript, args: [:])) == .needsConfirm)
    }
}
