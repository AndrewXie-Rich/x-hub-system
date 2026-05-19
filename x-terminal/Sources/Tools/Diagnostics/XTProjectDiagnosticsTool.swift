import Foundation

enum XTProjectDiagnosticsTool {
    private static let maxInlineOutputChars = 12_000

    static func run(
        tool: ToolName,
        call: ToolCall,
        projectRoot: URL,
        config: AXProjectConfig
    ) throws -> ToolResult {
        let request = requestKind(tool: tool, call: call)
        let ctx = AXProjectContext(root: projectRoot)
        try FileManager.default.createDirectory(at: ctx.diagnosticsDir, withIntermediateDirectories: true)

        let runID = "diag-\(Int64((Date().timeIntervalSince1970 * 1000.0).rounded()))"
        let language = detectLanguage(projectRoot: projectRoot)
        let timeout = max(5.0, min(1800.0, doubleArg(call, "timeout_sec") ?? 300.0))
        let commands = diagnosticsCommands(
            request: request,
            call: call,
            config: config,
            language: language,
            projectRoot: projectRoot
        )

        guard !commands.isEmpty else {
            let summary = baseSummary(
                tool: tool,
                runID: runID,
                projectRoot: projectRoot,
                language: language,
                request: request,
                commandObjects: [],
                diagnostics: [],
                ok: true
            ).merging([
                "reason_code": .string("no_diagnostics_command_available")
            ]) { _, new in new }
            let body = "No diagnostics command is available for language=\(language)."
            try persist(summary: summary, body: body, ctx: ctx, runID: runID)
            return ToolResult(id: call.id, tool: tool, ok: true, output: ToolExecutor.structuredOutput(summary: summary, body: body))
        }

        var commandObjects: [JSONValue] = []
        var diagnostics: [JSONValue] = []
        var bodySections: [String] = []
        var allGreen = true

        for (index, command) in commands.enumerated() {
            let commandID = "\(runID)-cmd\(index + 1)"
            let stdoutURL = ctx.diagnosticsDir.appendingPathComponent("\(commandID).stdout.log")
            let stderrURL = ctx.diagnosticsDir.appendingPathComponent("\(commandID).stderr.log")
            let started = Date()
            let result: ProcessResult
            do {
                result = try run(command: command, cwd: projectRoot, timeout: timeout)
            } catch {
                allGreen = false
                let message = error.localizedDescription
                try XTStoreWriteSupport.writeUTF8Text("", to: stdoutURL)
                try XTStoreWriteSupport.writeUTF8Text(message, to: stderrURL)
                let durationMs = Int(Date().timeIntervalSince(started) * 1000.0)
                commandObjects.append(commandObject(
                    command: command,
                    exitCode: -1,
                    durationMs: durationMs,
                    stdoutURL: stdoutURL,
                    stderrURL: stderrURL,
                    error: message
                ))
                diagnostics.append(.object([
                    "file": .string(""),
                    "line": .number(0),
                    "column": .number(0),
                    "severity": .string("error"),
                    "code": .string("diagnostics_command_failed"),
                    "message": .string(message),
                    "source": .string(command.source),
                ]))
                bodySections.append("\(command.display): failed to launch\n\(message)")
                continue
            }

            if result.exitCode != 0 {
                allGreen = false
            }
            try XTStoreWriteSupport.writeUTF8Text(result.stdout, to: stdoutURL)
            try XTStoreWriteSupport.writeUTF8Text(result.stderr, to: stderrURL)
            let durationMs = Int(Date().timeIntervalSince(started) * 1000.0)
            commandObjects.append(commandObject(
                command: command,
                exitCode: result.exitCode,
                durationMs: durationMs,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                error: nil
            ))

            let combined = result.combined
            diagnostics.append(contentsOf: parseDiagnostics(
                text: combined,
                language: language,
                source: command.source
            ))
            bodySections.append("\(command.display): exit \(result.exitCode)\n\(truncated(combined, limit: maxInlineOutputChars))")
        }

        let errorCount = diagnostics.filter { diagnosticSeverity($0) == "error" }.count
        let warningCount = diagnostics.filter { diagnosticSeverity($0) == "warning" }.count
        let ok = allGreen && errorCount == 0
        var summary = baseSummary(
            tool: tool,
            runID: runID,
            projectRoot: projectRoot,
            language: language,
            request: request,
            commandObjects: commandObjects,
            diagnostics: diagnostics,
            ok: ok
        )
        summary["error_count"] = .number(Double(errorCount))
        summary["warning_count"] = .number(Double(warningCount))
        summary["diagnostic_count"] = .number(Double(diagnostics.count))
        summary["is_green"] = .bool(ok)

        let body = bodySections.joined(separator: "\n\n")
        try persist(summary: summary, body: body, ctx: ctx, runID: runID)
        return ToolResult(id: call.id, tool: tool, ok: ok, output: ToolExecutor.structuredOutput(summary: summary, body: body))
    }

    private struct DiagnosticsCommand {
        var kind: String
        var display: String
        var executable: String
        var arguments: [String]
        var source: String
        var useShell: Bool
    }

    private static func requestKind(tool: ToolName, call: ToolCall) -> String {
        switch tool {
        case .checkRun:
            return "check"
        case .buildRun:
            return "build"
        case .testRun:
            return "test"
        case .lspDiagnostics:
            return "lsp"
        default:
            return stringArg(call, "kind") ?? stringArg(call, "trigger") ?? "auto"
        }
    }

    private static func diagnosticsCommands(
        request: String,
        call: ToolCall,
        config: AXProjectConfig,
        language: String,
        projectRoot: URL
    ) -> [DiagnosticsCommand] {
        if boolArg(call, "use_verify_commands") == true {
            return config.verifyCommands
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map {
                    DiagnosticsCommand(
                        kind: "verify",
                        display: $0,
                        executable: "/bin/zsh",
                        arguments: ["-lc", $0],
                        source: "project-verify-command",
                        useShell: true
                    )
                }
        }

        let normalizedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRequest == "lsp" {
            return fallbackCheckCommands(language: language, projectRoot: projectRoot, source: "lsp-fallback")
        }

        switch normalizedRequest {
        case "check":
            return fallbackCheckCommands(language: language, projectRoot: projectRoot, source: "check")
        case "build":
            return buildCommands(language: language, projectRoot: projectRoot)
        case "test":
            return testCommands(language: language, projectRoot: projectRoot)
        default:
            return fallbackCheckCommands(language: language, projectRoot: projectRoot, source: "auto")
        }
    }

    private static func fallbackCheckCommands(language: String, projectRoot: URL, source: String) -> [DiagnosticsCommand] {
        switch language {
        case "swift":
            return [
                DiagnosticsCommand(kind: "check", display: "swift build", executable: "/usr/bin/env", arguments: ["swift", "build"], source: source, useShell: false)
            ]
        case "rust":
            return [
                DiagnosticsCommand(kind: "check", display: "cargo check", executable: "/usr/bin/env", arguments: ["cargo", "check"], source: source, useShell: false)
            ]
        case "typescript":
            if FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("node_modules/.bin/tsc").path) {
                return [
                    DiagnosticsCommand(kind: "check", display: "node_modules/.bin/tsc --noEmit", executable: projectRoot.appendingPathComponent("node_modules/.bin/tsc").path, arguments: ["--noEmit"], source: source, useShell: false)
                ]
            }
            return [
                DiagnosticsCommand(kind: "check", display: "tsc --noEmit", executable: "/usr/bin/env", arguments: ["tsc", "--noEmit"], source: source, useShell: false)
            ]
        default:
            return []
        }
    }

    private static func buildCommands(language: String, projectRoot: URL) -> [DiagnosticsCommand] {
        switch language {
        case "swift":
            return [DiagnosticsCommand(kind: "build", display: "swift build", executable: "/usr/bin/env", arguments: ["swift", "build"], source: "build", useShell: false)]
        case "rust":
            return [DiagnosticsCommand(kind: "build", display: "cargo build", executable: "/usr/bin/env", arguments: ["cargo", "build"], source: "build", useShell: false)]
        case "typescript":
            return fallbackCheckCommands(language: language, projectRoot: projectRoot, source: "build")
        default:
            return []
        }
    }

    private static func testCommands(language: String, projectRoot: URL) -> [DiagnosticsCommand] {
        switch language {
        case "swift":
            return [DiagnosticsCommand(kind: "test", display: "swift test", executable: "/usr/bin/env", arguments: ["swift", "test"], source: "test", useShell: false)]
        case "rust":
            return [DiagnosticsCommand(kind: "test", display: "cargo test", executable: "/usr/bin/env", arguments: ["cargo", "test"], source: "test", useShell: false)]
        default:
            return []
        }
    }

    private static func run(command: DiagnosticsCommand, cwd: URL, timeout: Double) throws -> ProcessResult {
        try ProcessCapture.run(
            command.executable,
            command.arguments,
            cwd: cwd,
            timeoutSec: timeout
        )
    }

    private static func detectLanguage(projectRoot: URL) -> String {
        let fm = FileManager.default
        if fm.fileExists(atPath: projectRoot.appendingPathComponent("Package.swift").path) {
            return "swift"
        }
        if fm.fileExists(atPath: projectRoot.appendingPathComponent("Cargo.toml").path) {
            return "rust"
        }
        if fm.fileExists(atPath: projectRoot.appendingPathComponent("tsconfig.json").path)
            || fm.fileExists(atPath: projectRoot.appendingPathComponent("package.json").path) {
            return "typescript"
        }
        if fm.fileExists(atPath: projectRoot.appendingPathComponent("pyproject.toml").path) {
            return "python"
        }
        return "unknown"
    }

    private static func parseDiagnostics(text: String, language: String, source: String) -> [JSONValue] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [JSONValue] = []
        for (index, line) in lines.enumerated() {
            if let swift = parseColonDiagnostic(line, source: source) {
                out.append(swift)
                continue
            }
            if language == "typescript", let ts = parseTypeScriptDiagnostic(line, source: source) {
                out.append(ts)
                continue
            }
            if language == "rust", line.trimmingCharacters(in: .whitespaces).hasPrefix("-->") {
                let message = index > 0 ? lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines) : "rust diagnostic"
                out.append(rustDiagnostic(locationLine: line, message: message, source: source))
            }
        }
        return out
    }

    private static func parseColonDiagnostic(_ line: String, source: String) -> JSONValue? {
        let parts = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else { return nil }
        guard let lineNumber = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              let columnNumber = Double(parts[2].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let severityToken = parts[3].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard severityToken == "error" || severityToken == "warning" || severityToken == "note" else {
            return nil
        }
        let message = parts.dropFirst(4).joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        return .object([
            "file": .string(parts[0]),
            "line": .number(lineNumber),
            "column": .number(columnNumber),
            "severity": .string(severityToken == "note" ? "info" : severityToken),
            "code": .string(""),
            "message": .string(message),
            "source": .string(source),
        ])
    }

    private static func parseTypeScriptDiagnostic(_ line: String, source: String) -> JSONValue? {
        guard let open = line.firstIndex(of: "("),
              let close = line[open...].firstIndex(of: ")") else {
            return nil
        }
        let file = String(line[..<open])
        let location = line[line.index(after: open)..<close].split(separator: ",").map(String.init)
        guard location.count == 2,
              let lineNumber = Double(location[0]),
              let columnNumber = Double(location[1]) else {
            return nil
        }
        let tail = line[line.index(after: close)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard tail.hasPrefix(": error") || tail.hasPrefix(": warning") else { return nil }
        let severity = tail.hasPrefix(": error") ? "error" : "warning"
        return .object([
            "file": .string(file),
            "line": .number(lineNumber),
            "column": .number(columnNumber),
            "severity": .string(severity),
            "code": .string("typescript"),
            "message": .string(tail.trimmingCharacters(in: CharacterSet(charactersIn: ": "))),
            "source": .string(source),
        ])
    }

    private static func rustDiagnostic(locationLine: String, message: String, source: String) -> JSONValue {
        let cleaned = locationLine
            .replacingOccurrences(of: "-->", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ":").map(String.init)
        let file = parts.first ?? ""
        let lineNumber = parts.count > 1 ? Double(parts[1]) ?? 0 : 0
        let columnNumber = parts.count > 2 ? Double(parts[2]) ?? 0 : 0
        let severity = message.lowercased().hasPrefix("warning") ? "warning" : "error"
        return .object([
            "file": .string(file),
            "line": .number(lineNumber),
            "column": .number(columnNumber),
            "severity": .string(severity),
            "code": .string("rust"),
            "message": .string(message),
            "source": .string(source),
        ])
    }

    private static func commandObject(
        command: DiagnosticsCommand,
        exitCode: Int32,
        durationMs: Int,
        stdoutURL: URL,
        stderrURL: URL,
        error: String?
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "kind": .string(command.kind),
            "command": .string(command.display),
            "exit_code": .number(Double(exitCode)),
            "duration_ms": .number(Double(durationMs)),
            "stdout_ref": .string(stdoutURL.path),
            "stderr_ref": .string(stderrURL.path),
            "source": .string(command.source),
        ]
        if let error {
            object["error"] = .string(error)
        }
        return .object(object)
    }

    private static func baseSummary(
        tool: ToolName,
        runID: String,
        projectRoot: URL,
        language: String,
        request: String,
        commandObjects: [JSONValue],
        diagnostics: [JSONValue],
        ok: Bool
    ) -> [String: JSONValue] {
        [
            "schema_version": .string("xt.project_diagnostics_result.v1"),
            "tool": .string(tool.rawValue),
            "ok": .bool(ok),
            "run_id": .string(runID),
            "project_root": .string(projectRoot.path),
            "language": .string(language),
            "trigger": .string(request),
            "commands": .array(commandObjects),
            "diagnostics": .array(diagnostics),
            "changed_files_only": .bool(false),
        ]
    }

    private static func persist(
        summary: [String: JSONValue],
        body: String,
        ctx: AXProjectContext,
        runID: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let record: JSONValue = .object([
            "summary": .object(summary),
            "body": .string(body),
        ])
        let data = try encoder.encode(record)
        let runURL = ctx.diagnosticsDir.appendingPathComponent("\(runID).json")
        try XTStoreWriteSupport.writeSnapshotData(data, to: runURL)
        try XTStoreWriteSupport.writeSnapshotData(data, to: ctx.latestDiagnosticsURL)
    }

    private static func stringArg(_ call: ToolCall, _ key: String) -> String? {
        if case .string(let value)? = call.args[key] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func boolArg(_ call: ToolCall, _ key: String) -> Bool? {
        switch call.args[key] {
        case .bool(let value):
            return value
        case .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1", "on"].contains(normalized) { return true }
            if ["false", "no", "0", "off"].contains(normalized) { return false }
            return nil
        default:
            return nil
        }
    }

    private static func doubleArg(_ call: ToolCall, _ key: String) -> Double? {
        switch call.args[key] {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func diagnosticSeverity(_ value: JSONValue) -> String {
        guard case .object(let object) = value,
              case .string(let severity)? = object["severity"] else {
            return ""
        }
        return severity
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text.isEmpty ? "(no output)" : text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "\n... truncated ..."
    }
}
