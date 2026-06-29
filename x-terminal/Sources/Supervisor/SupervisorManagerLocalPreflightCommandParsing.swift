import Foundation

extension SupervisorManager {
    func shouldRunDoctorCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/doctor" || token == "doctor" || token == "supervisor doctor" {
            return true
        }
        if text.contains("doctor 预检") || text.contains("doctor体检") || text.contains("发布前体检") || text.contains("运行 doctor") {
            return true
        }
        return false
    }

    func shouldRetryCanonicalMemorySyncCommand(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let token = trimmed.lowercased()
        let exactCommands = [
            "/canonical sync retry",
            "canonical sync retry",
            "/canonical memory retry",
            "canonical memory retry",
            "/memory sync retry",
            "memory sync retry",
            "retry canonical sync",
            "retry canonical memory",
            "replay canonical memory"
        ]
        if exactCommands.contains(token) {
            return true
        }

        let hasRetry = containsAny(token, ["retry", "replay", "resync"]) ||
            containsAny(trimmed, ["重试", "重推", "重同步", "重新同步", "补推", "补同步"])
        guard hasRetry else { return false }

        let hasCanonical = token.contains("canonical")
        let hasMemory = token.contains("memory") || trimmed.contains("记忆")
        let hasSync = token.contains("sync") || token.contains("resync") || trimmed.contains("同步")
        let hasSupervisorScope = containsAny(token, ["supervisor", "hub", "project", "portfolio"]) ||
            containsAny(trimmed, ["主管", "项目", "组合", "portfolio", "hub", "supervisor"])

        if hasCanonical && (hasSync || hasMemory) {
            return true
        }
        if hasMemory && hasSync && hasSupervisorScope {
            return true
        }
        return false
    }

    func shouldRunSecretsDryRunCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/secrets dry-run" || token == "secrets dry-run" {
            return true
        }
        if token.contains("secrets") && token.contains("dry") {
            return true
        }
        if text.contains("secrets 预检") || text.contains("密钥预检") || text.contains("dry-run") {
            return true
        }
        return false
    }

    func shouldExportXTReadyIncidentEventsCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/xt-ready incidents export" || token == "xt-ready incidents export" {
            return true
        }
        if token == "/xt-ready incidents" || token == "xt-ready incidents" {
            return true
        }
        if token.contains("xt-ready") && token.contains("incident") && token.contains("export") {
            return true
        }
        if text.contains("导出") && text.contains("incident") && text.contains("证据") {
            return true
        }
        return false
    }

    func shouldShowXTReadyIncidentEventsStatusCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/xt-ready incidents status" || token == "xt-ready incidents status" {
            return true
        }
        if token == "/xt-ready status" || token == "xt-ready status" {
            return true
        }
        if token.contains("xt-ready") && token.contains("incident") && token.contains("status") {
            return true
        }
        if text.contains("incident") && text.contains("导出状态") {
            return true
        }
        return false
    }

    func shouldInjectXTReadyIncidentsCommand(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token == "/xt-ready incidents inject" || token == "xt-ready incidents inject" {
            return true
        }
        if token.hasPrefix("/xt-ready incidents inject ") || token.hasPrefix("xt-ready incidents inject ") {
            return true
        }
        if token.contains("xt-ready") && token.contains("incident") && token.contains("inject") {
            return true
        }
        return false
    }
}
