import Testing
@testable import XTerminal

struct FirstPairTroubleshootRoutingTests {
    @Test
    func firstPairApprovalTimeoutMapsToPairingRepairIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "pairing_approval_timeout") == .pairingRepairRequired)
    }

    @Test
    func firstPairOwnerAuthFailuresMapToPairingRepairIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "pairing_owner_auth_cancelled") == .pairingRepairRequired)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "pairing_owner_auth_failed") == .pairingRepairRequired)
    }

    @Test
    func stalePairingFailuresMapToPairingRepairIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "hub_instance_mismatch") == .pairingRepairRequired)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "pairing_profile_epoch_stale") == .pairingRepairRequired)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "route_pack_outdated") == .pairingRepairRequired)
    }

    @Test
    func localNetworkDiscoveryFailuresMapToPermissionDeniedIssue() {
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "local_network_permission_required") == .permissionDenied)
        #expect(UITroubleshootKnowledgeBase.issue(forFailureCode: "local_network_discovery_blocked") == .permissionDenied)
    }

    @Test
    func firstPairRepairContextUsesApprovalSpecificCopy() {
        let timeoutContext = AppModel.automaticFirstPairRepairContext(for: "pairing_approval_timeout")
        #expect(timeoutContext.title == "在 Hub 上批准这次首次配对")
        #expect(timeoutContext.detail.contains("等待本机 owner 批准时超时"))

        let cancelledContext = AppModel.automaticFirstPairRepairContext(for: "pairing_owner_auth_cancelled")
        #expect(cancelledContext.title == "回到 Hub 重新确认首次配对")
        #expect(cancelledContext.detail.contains("本机 owner 验证被取消"))

        let failedContext = AppModel.automaticFirstPairRepairContext(for: "pairing_owner_auth_failed")
        #expect(failedContext.title == "先修复 Hub 本机验证再配对")
        #expect(failedContext.detail.contains("无法完成本机 owner 验证"))
    }

    @Test
    func stalePairingRepairContextUsesSpecificCopy() {
        let mismatchContext = AppModel.automaticFirstPairRepairContext(for: "hub_instance_mismatch")
        #expect(mismatchContext.title == "清掉旧 Hub 档案后重新配对")
        #expect(mismatchContext.detail.contains("不是同一台主机"))

        let epochContext = AppModel.automaticFirstPairRepairContext(for: "pairing_profile_epoch_stale")
        #expect(epochContext.title == "刷新最新配对档案后再重连")
        #expect(epochContext.detail.contains("旧 profile"))

        let routePackContext = AppModel.automaticFirstPairRepairContext(for: "route_pack_outdated")
        #expect(routePackContext.title == "重新导入最新远端入口")
        #expect(routePackContext.detail.contains("旧的 host / port / token 材料"))
    }

    @Test
    func localNetworkRepairContextUsesSpecificCopy() {
        let context = AppModel.automaticFirstPairRepairContext(for: "local_network_discovery_blocked")

        #expect(context.title == "先允许 XT 访问本地网络")
        #expect(context.detail.contains("loopback Hub"))
        #expect(context.detail.contains("client isolation"))
    }

    @Test
    func sameLanRepairContextExplainsSameSSIDIsNotEnoughForPrivateLanHost() {
        let context = AppModel.automaticFirstPairRepairContext(
            for: "first_pair_requires_same_lan",
            internetHost: "17.81.11.116"
        )

        #expect(context.title == "回到同一 Wi-Fi 完成首次配对")
        #expect(context.detail.contains("同一个 Wi-Fi 名称"))
        #expect(context.detail.contains("client isolation"))
        #expect(context.detail.contains("17.81.11.116"))
    }
}
