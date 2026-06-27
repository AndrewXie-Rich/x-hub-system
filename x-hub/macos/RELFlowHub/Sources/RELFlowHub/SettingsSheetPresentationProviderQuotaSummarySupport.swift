import Foundation
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
private var providerQuotaOperationsImportIssueCount: Int {
        providerKeySnapshot.importSources.filter { source in
            source.state != "ready" || source.lastErrorCount > 0
        }.count
    }

    var providerQuotaOperationsSummaryText: String {
        let derived = providerKeyDerivedSnapshot
        if derived.totalAccounts == 0
            && providerKeySnapshot.importSources.isEmpty
            && derived.keyPools.isEmpty {
            return "这里管理 provider key、共享额度池、导入源、CLIProxy OAuth 和各类配额台账。按需展开，避免切页时卡住。"
        }

        var parts: [String] = []
        if derived.totalAccounts > 0 {
            parts.append("\(derived.readyAccounts)/\(derived.totalAccounts) 个 key 就绪")
        }
        if quotaPoolCount > 0 {
            parts.append("\(quotaPoolCount) 个额度池")
        }
        if !derived.keyPools.isEmpty {
            parts.append("\(derived.keyPools.count) 个物理池")
        }
        if providerQuotaOperationsImportIssueCount > 0 {
            parts.append("\(providerQuotaOperationsImportIssueCount) 个导入源异常")
        }
        if derived.blockedAccounts > 0 {
            parts.append("\(derived.blockedAccounts) 个 key 阻塞")
        }
        return parts.joined(separator: " · ")
    }

    var providerQuotaOperationsBadgeText: String {
        let derived = providerKeyDerivedSnapshot
        if !remoteQuotaErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "异常"
        }
        if derived.totalAccounts == 0
            && providerKeySnapshot.importSources.isEmpty
            && derived.keyPools.isEmpty {
            return "未配置"
        }
        if derived.blockedAccounts > 0 || providerQuotaOperationsImportIssueCount > 0 {
            return "需处理"
        }
        if derived.readyAccounts > 0 {
            return "\(derived.readyAccounts) 就绪"
        }
        return "按需展开"
    }

    var providerQuotaOperationsTint: Color {
        let derived = providerKeyDerivedSnapshot
        if !remoteQuotaErrorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }
        if derived.blockedAccounts > 0 || providerQuotaOperationsImportIssueCount > 0 {
            return .orange
        }
        if derived.readyAccounts > 0 || quotaPoolCount > 0 {
            return .blue
        }
        return .secondary
    }
}
