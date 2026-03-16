import Foundation

struct GitHubToolRunSummary: Equatable, Sendable {
    var output: String
    var structuredSummary: [String: JSONValue]
}

enum GitHubTool {
    typealias RunOverride = @Sendable (_ args: [String], _ cwd: URL, _ timeoutSec: Double) throws -> ProcessResult
    typealias ExecutableLookupOverride = @Sendable (_ candidates: [String]) -> String?

    private static let testingOverrideLock = NSLock()
    private static var runOverrideForTesting: RunOverride?
    private static var executableLookupOverrideForTesting: ExecutableLookupOverride?

    private struct Environment: Equatable, Sendable {
        var executablePath: String?
        var repoNameWithOwner: String?
        var repoURL: String?
    }

    private struct RunListEntry: Decodable {
        var displayTitle: String?
        var workflowName: String?
        var status: String?
        var conclusion: String?
        var headBranch: String?
        var headSha: String?
        var url: String?
        var createdAt: String?
        var updatedAt: String?
    }

    private struct RepoView: Decodable {
        var nameWithOwner: String?
        var url: String?
    }

    private struct Failure: LocalizedError, Equatable, Sendable {
        var reasonCode: String
        var failureStage: String
        var detail: String
        var diagnostic: String?
        var provider: String = "github"

        var errorDescription: String? { detail }

        func runSummary(tool: ToolName) -> GitHubToolRunSummary {
            var summary: [String: JSONValue] = [
                "tool": .string(tool.rawValue),
                "ok": .bool(false),
                "provider": .string(provider),
                "reason_code": .string(reasonCode),
                "failure_stage": .string(failureStage),
                "preflight_checked": .bool(true),
            ]
            if let diagnostic, !diagnostic.isEmpty {
                summary["diagnostic"] = .string(diagnostic)
            }
            return GitHubToolRunSummary(
                output: renderedBody(),
                structuredSummary: summary
            )
        }

        private func renderedBody() -> String {
            let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDiagnostic = diagnostic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedDiagnostic.isEmpty else { return trimmedDetail }
            guard trimmedDiagnostic != trimmedDetail else { return trimmedDetail }
            if trimmedDetail.isEmpty { return trimmedDiagnostic }
            return trimmedDetail + "\n" + trimmedDiagnostic
        }
    }

    private static func withTestingOverrideLock<T>(_ body: () -> T) -> T {
        testingOverrideLock.lock()
        defer { testingOverrideLock.unlock() }
        return body()
    }

    static func prCreate(
        root: URL,
        title: String?,
        body: String?,
        base: String?,
        head: String?,
        draft: Bool,
        fill: Bool,
        labels: [String],
        reviewers: [String]
    ) throws -> GitHubToolRunSummary {
        var args = ["pr", "create"]
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fill {
            args.append("--fill")
        } else {
            guard !trimmedTitle.isEmpty else {
                throw NSError(domain: "xterminal", code: 400, userInfo: [NSLocalizedDescriptionKey: "pr_create requires title unless fill=true"])
            }
            args += ["--title", trimmedTitle]
        }
        if !trimmedBody.isEmpty {
            args += ["--body", trimmedBody]
        } else if !fill {
            args += ["--body", ""]
        }
        if let base = base?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
            args += ["--base", base]
        }
        if let head = head?.trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            args += ["--head", head]
        }
        if draft {
            args.append("--draft")
        }
        for label in labels where !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--label", label]
        }
        for reviewer in reviewers where !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--reviewer", reviewer]
        }

        let environment: Environment
        switch preflight(root: root) {
        case .success(let resolved):
            environment = resolved
        case .failure(let failure):
            return failure.runSummary(tool: .pr_create)
        }

        let result = try runGH(args, environment: environment, cwd: root, timeoutSec: 60.0)
        let combined = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = firstURL(in: combined)
        var summary: [String: JSONValue] = [
            "tool": .string(ToolName.pr_create.rawValue),
            "ok": .bool(result.exitCode == 0),
            "provider": .string("github"),
            "title": .string(trimmedTitle),
            "draft": .bool(draft),
            "fill": .bool(fill),
            "labels": .array(labels.map(JSONValue.string)),
            "reviewers": .array(reviewers.map(JSONValue.string)),
            "preflight_checked": .bool(true),
        ]
        if let base = base?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
            summary["base"] = .string(base)
        }
        if let head = head?.trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty {
            summary["head"] = .string(head)
        }
        if let repoNameWithOwner = environment.repoNameWithOwner, !repoNameWithOwner.isEmpty {
            summary["repo"] = .string(repoNameWithOwner)
        }
        if let repoURL = environment.repoURL, !repoURL.isEmpty {
            summary["repo_url"] = .string(repoURL)
        }
        if let url {
            summary["url"] = .string(url)
        }
        return GitHubToolRunSummary(output: combined, structuredSummary: summary)
    }

    static func ciRead(
        root: URL,
        workflow: String?,
        branch: String?,
        commit: String?,
        limit: Int
    ) throws -> GitHubToolRunSummary {
        var args = [
            "run", "list",
            "--limit", String(max(1, min(20, limit))),
            "--json", "displayTitle,workflowName,status,conclusion,headBranch,headSha,url,createdAt,updatedAt",
        ]
        if let workflow = workflow?.trimmingCharacters(in: .whitespacesAndNewlines), !workflow.isEmpty {
            args += ["--workflow", workflow]
        }
        if let branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            args += ["--branch", branch]
        }
        if let commit = commit?.trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty {
            args += ["--commit", commit]
        }

        let environment: Environment
        switch preflight(root: root) {
        case .success(let resolved):
            environment = resolved
        case .failure(let failure):
            return failure.runSummary(tool: .ci_read)
        }

        let result = try runGH(args, environment: environment, cwd: root, timeoutSec: 30.0)
        let combined = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = (combined.data(using: .utf8))
            .flatMap { try? JSONDecoder().decode([RunListEntry].self, from: $0) } ?? []
        let runs: [JSONValue] = entries.map { entry in
            .object([
                "display_title": entry.displayTitle.map(JSONValue.string) ?? .null,
                "workflow_name": entry.workflowName.map(JSONValue.string) ?? .null,
                "status": entry.status.map(JSONValue.string) ?? .null,
                "conclusion": entry.conclusion.map(JSONValue.string) ?? .null,
                "head_branch": entry.headBranch.map(JSONValue.string) ?? .null,
                "head_sha": entry.headSha.map(JSONValue.string) ?? .null,
                "url": entry.url.map(JSONValue.string) ?? .null,
                "created_at": entry.createdAt.map(JSONValue.string) ?? .null,
                "updated_at": entry.updatedAt.map(JSONValue.string) ?? .null,
            ])
        }
        let lines = entries.prefix(10).map { entry in
            let title = (entry.displayTitle ?? entry.workflowName ?? "(unknown)").trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (entry.status ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
            let conclusion = (entry.conclusion ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = (entry.headBranch ?? "-").trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(title) | status=\(status) | conclusion=\(conclusion) | branch=\(branch)"
        }
        var summary: [String: JSONValue] = [
            "tool": .string(ToolName.ci_read.rawValue),
            "ok": .bool(result.exitCode == 0),
            "provider": .string("github"),
            "runs_count": .number(Double(entries.count)),
            "runs": .array(runs),
            "preflight_checked": .bool(true),
        ]
        if let workflow = workflow?.trimmingCharacters(in: .whitespacesAndNewlines), !workflow.isEmpty {
            summary["workflow"] = .string(workflow)
        }
        if let branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            summary["branch"] = .string(branch)
        }
        if let commit = commit?.trimmingCharacters(in: .whitespacesAndNewlines), !commit.isEmpty {
            summary["commit"] = .string(commit)
        }
        if let repoNameWithOwner = environment.repoNameWithOwner, !repoNameWithOwner.isEmpty {
            summary["repo"] = .string(repoNameWithOwner)
        }
        if let repoURL = environment.repoURL, !repoURL.isEmpty {
            summary["repo_url"] = .string(repoURL)
        }
        let body = lines.isEmpty ? (combined.isEmpty ? "(no ci runs)" : combined) : lines.joined(separator: "\n")
        return GitHubToolRunSummary(output: body, structuredSummary: summary)
    }

    static func ciTrigger(
        root: URL,
        workflow: String,
        ref: String?,
        inputs: [String: JSONValue]
    ) throws -> GitHubToolRunSummary {
        let trimmedWorkflow = workflow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWorkflow.isEmpty else {
            throw NSError(domain: "xterminal", code: 400, userInfo: [NSLocalizedDescriptionKey: "ci_trigger requires workflow"])
        }
        var args = ["workflow", "run", trimmedWorkflow]
        if let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            args += ["--ref", ref]
        }
        for key in inputs.keys.sorted() {
            guard let rendered = renderScalar(inputs[key]) else { continue }
            args += ["-f", "\(key)=\(rendered)"]
        }

        let environment: Environment
        switch preflight(root: root) {
        case .success(let resolved):
            environment = resolved
        case .failure(let failure):
            return failure.runSummary(tool: .ci_trigger)
        }

        let result = try runGH(args, environment: environment, cwd: root, timeoutSec: 30.0)
        let combined = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        var summary: [String: JSONValue] = [
            "tool": .string(ToolName.ci_trigger.rawValue),
            "ok": .bool(result.exitCode == 0),
            "provider": .string("github"),
            "workflow": .string(trimmedWorkflow),
            "inputs": .object(inputs),
            "preflight_checked": .bool(true),
        ]
        if let ref = ref?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            summary["ref"] = .string(ref)
        }
        if let repoNameWithOwner = environment.repoNameWithOwner, !repoNameWithOwner.isEmpty {
            summary["repo"] = .string(repoNameWithOwner)
        }
        if let repoURL = environment.repoURL, !repoURL.isEmpty {
            summary["repo_url"] = .string(repoURL)
        }
        return GitHubToolRunSummary(output: combined, structuredSummary: summary)
    }

    static func installRunOverrideForTesting(_ override: RunOverride?) {
        withTestingOverrideLock {
            runOverrideForTesting = override
        }
    }

    static func resetRunOverrideForTesting() {
        withTestingOverrideLock {
            runOverrideForTesting = nil
        }
    }

    static func installExecutableLookupOverrideForTesting(_ override: ExecutableLookupOverride?) {
        withTestingOverrideLock {
            executableLookupOverrideForTesting = override
        }
    }

    static func resetExecutableLookupOverrideForTesting() {
        withTestingOverrideLock {
            executableLookupOverrideForTesting = nil
        }
    }

    private static func preflight(root: URL) -> Result<Environment, Failure> {
        guard GitTool.isGitRepo(root: root) else {
            return .failure(Failure(
                reasonCode: "not_git_repository",
                failureStage: "workspace",
                detail: "Current folder is not a git repository.",
                diagnostic: nil
            ))
        }

        let usingRunOverride = hasRunOverrideForTesting()
        let executablePath: String?
        if usingRunOverride {
            executablePath = nil
        } else {
            executablePath = findExecutable(["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"])
        }

        if !usingRunOverride, executablePath == nil {
            return .failure(Failure(
                reasonCode: "github_cli_missing",
                failureStage: "cli",
                detail: "GitHub CLI (`gh`) is not installed on this machine.",
                diagnostic: nil
            ))
        }

        do {
            let auth = try runGHExecutable(
                executablePath,
                args: ["auth", "status"],
                cwd: root,
                timeoutSec: 10.0
            )
            guard auth.exitCode == 0 else {
                return .failure(Failure(
                    reasonCode: "github_auth_missing",
                    failureStage: "auth",
                    detail: "GitHub CLI is installed but not authenticated for this machine.",
                    diagnostic: normalizedDiagnostic(auth.combined)
                ))
            }

            let repoView = try runGHExecutable(
                executablePath,
                args: ["repo", "view", "--json", "nameWithOwner,url"],
                cwd: root,
                timeoutSec: 15.0
            )
            guard repoView.exitCode == 0 else {
                return .failure(Failure(
                    reasonCode: "github_repo_context_unavailable",
                    failureStage: "repo",
                    detail: "XT could not resolve a GitHub repository from the current folder.",
                    diagnostic: normalizedDiagnostic(repoView.combined)
                ))
            }

            let decoded = decodeRepoView(from: repoView.combined)
            return .success(Environment(
                executablePath: executablePath,
                repoNameWithOwner: decoded?.nameWithOwner?.trimmingCharacters(in: .whitespacesAndNewlines),
                repoURL: decoded?.url?.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        } catch {
            return .failure(Failure(
                reasonCode: "github_cli_execution_failed",
                failureStage: "cli",
                detail: "GitHub CLI could not be started from this project.",
                diagnostic: normalizedDiagnostic(error.localizedDescription)
            ))
        }
    }

    private static func runGH(
        _ args: [String],
        environment: Environment,
        cwd: URL,
        timeoutSec: Double
    ) throws -> ProcessResult {
        try runGHExecutable(environment.executablePath, args: args, cwd: cwd, timeoutSec: timeoutSec)
    }

    private static func runGHExecutable(
        _ executablePath: String?,
        args: [String],
        cwd: URL,
        timeoutSec: Double
    ) throws -> ProcessResult {
        if let override = withTestingOverrideLock({ runOverrideForTesting }) {
            return try override(args, cwd, timeoutSec)
        }
        guard let executablePath else {
            throw NSError(domain: "xterminal", code: 404, userInfo: [NSLocalizedDescriptionKey: "GitHub CLI `gh` is not installed"])
        }
        return try ProcessCapture.run(executablePath, args, cwd: cwd, timeoutSec: timeoutSec)
    }

    private static func findExecutable(_ candidates: [String]) -> String? {
        if let override = withTestingOverrideLock({ executableLookupOverrideForTesting }) {
            return override(candidates)
        }
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    private static func hasRunOverrideForTesting() -> Bool {
        withTestingOverrideLock { runOverrideForTesting != nil }
    }

    private static func decodeRepoView(from text: String) -> RepoView? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RepoView.self, from: data)
    }

    private static func firstURL(in text: String) -> String? {
        let pattern = #"https?://\S+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let urlRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedDiagnostic(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func renderScalar(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number(let number):
            if number.rounded() == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        default:
            return nil
        }
    }
}
