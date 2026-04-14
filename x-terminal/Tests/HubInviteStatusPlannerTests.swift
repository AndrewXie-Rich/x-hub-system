import Testing
@testable import XTerminal

struct HubInviteStatusPlannerTests {
    @Test
    func buildsLoadedInvitePresentation() throws {
        let presentation = try #require(
            HubInviteStatusPlanner.build(
                inviteAlias: "ops-main",
                internetHost: "hub.tailnet.example",
                pairingPort: 50054,
                grpcPort: 50053,
                inviteToken: "axhub_invite_test_123",
                hubInstanceID: "hub_deadbeefcafefeed00",
                connected: false,
                linking: false,
                failureCode: ""
            )
        )

        #expect(presentation.state == .inProgress)
        #expect(presentation.title == "官方邀请已载入")
        #expect(presentation.nextAction.contains("一键连接"))
        #expect(presentation.facts.contains("Hub alias：ops-main"))
        #expect(presentation.facts.contains("邀请令牌：已载入"))
    }

    @Test
    func buildsMissingInviteTokenFailurePresentation() throws {
        let presentation = try #require(
            HubInviteStatusPlanner.build(
                inviteAlias: "",
                internetHost: "hub.tailnet.example",
                pairingPort: 50054,
                grpcPort: 50053,
                inviteToken: "",
                hubInstanceID: "",
                connected: false,
                linking: false,
                failureCode: "invite_token_required"
            )
        )

        #expect(presentation.state == .diagnosticRequired)
        #expect(presentation.title == "这次外网配对缺少邀请令牌")
        #expect(presentation.nextAction.contains("重新打开 Hub 发出的邀请链接"))
    }

    @Test
    func buildsInvalidInviteTokenFailurePresentation() throws {
        let presentation = try #require(
            HubInviteStatusPlanner.build(
                inviteAlias: "ops-main",
                internetHost: "hub.tailnet.example",
                pairingPort: 50054,
                grpcPort: 50053,
                inviteToken: "axhub_invite_old",
                hubInstanceID: "",
                connected: false,
                linking: false,
                failureCode: "invite_token_invalid"
            )
        )

        #expect(presentation.state == .diagnosticRequired)
        #expect(presentation.title == "邀请令牌已失效或不匹配")
        #expect(presentation.summary.contains("invite_token_invalid"))
        #expect(presentation.nextAction.contains("轮换邀请令牌"))
    }
}
