import XCTest
@testable import RELFlowHub

final class OperatorChannelsOnboardingSupportTests: XCTestCase {
    func testTicketStableExternalIdUsesProviderTenantAndExternalUser() {
        let ticket = makeTicket(provider: "Feishu", status: "pending")

        XCTAssertEqual(ticket.stableExternalId, "feishu/tenant_1/user_1")
    }

    func testTicketStableExternalIdUsesUnderscoreWhenTenantIsMissing() {
        var ticket = makeTicket(provider: "slack", status: "pending")
        ticket.externalTenantId = ""

        XCTAssertEqual(ticket.stableExternalId, "slack/_/user_1")
    }

    func testTicketDecodesEffectiveStatusWhenPresent() throws {
        let data = Data(
            """
            {
              "schema_version": "xhub.channel_onboarding_discovery_ticket.v1",
              "ticket_id": "ticket_effective_1",
              "provider": "slack",
              "account_id": "acct_1",
              "external_user_id": "user_1",
              "external_tenant_id": "tenant_1",
              "conversation_id": "conv_1",
              "thread_key": "",
              "ingress_surface": "group",
              "first_message_preview": "status",
              "proposed_scope_type": "project",
              "proposed_scope_id": "project_alpha",
              "recommended_binding_mode": "conversation_binding",
              "status": "approved",
              "effective_status": "revoked",
              "event_count": 2,
              "first_seen_at_ms": 100,
              "last_seen_at_ms": 120,
              "created_at_ms": 100,
              "updated_at_ms": 120,
              "expires_at_ms": 200,
              "last_request_id": "request_1",
              "audit_ref": "audit_1"
            }
            """.utf8
        )

        let ticket = try JSONDecoder().decode(HubOperatorChannelOnboardingTicket.self, from: data)

        XCTAssertEqual(ticket.status, "approved")
        XCTAssertEqual(ticket.effectiveStatus, "revoked")
        XCTAssertEqual(ticket.displayStatus, "revoked")
        XCTAssertFalse(ticket.isOpen)
    }

    func testAutomationStateDecodesDeliveryReadinessAndPendingOutbox() throws {
        let data = Data(
            """
            {
              "schema_version": "xhub.channel_onboarding_automation_state.v1",
              "ticket_id": "ticket_123",
              "first_smoke": {
                "schema_version": "xhub.channel_onboarding_first_smoke_receipt.v1",
                "receipt_id": "receipt_1",
                "ticket_id": "ticket_123",
                "decision_id": "decision_1",
                "provider": "feishu",
                "action_name": "supervisor.status.get",
                "status": "query_executed",
                "route_mode": "project_binding",
                "deny_code": "",
                "detail": "query completed",
                "remediation_hint": "",
                "project_id": "project_alpha",
                "binding_id": "binding_1",
                "ack_outbox_item_id": "outbox_ack",
                "smoke_outbox_item_id": "outbox_smoke",
                "created_at_ms": 100,
                "updated_at_ms": 100,
                "audit_ref": "audit_1"
              },
              "outbox_items": [
                {
                  "schema_version": "xhub.channel_outbox_item.v1",
                  "item_id": "outbox_ack",
                  "provider": "feishu",
                  "item_kind": "onboarding_ack",
                  "status": "pending",
                  "ticket_id": "ticket_123",
                  "decision_id": "decision_1",
                  "receipt_id": "",
                  "attempt_count": 1,
                  "last_error_code": "provider_delivery_not_configured",
                  "last_error_message": "provider_delivery_not_configured",
                  "provider_message_ref": "",
                  "created_at_ms": 101,
                  "updated_at_ms": 101,
                  "delivered_at_ms": 0,
                  "audit_ref": "audit_2"
                }
              ],
              "outbox_pending_count": 1,
              "outbox_delivered_count": 0,
              "delivery_readiness": {
                "provider": "feishu",
                "ready": false,
                "reply_enabled": false,
                "credentials_configured": false,
                "deny_code": "provider_delivery_not_configured",
                "remediation_hint": "Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1, configure HUB_FEISHU_OPERATOR_BOT_APP_ID and HUB_FEISHU_OPERATOR_BOT_APP_SECRET, then retry outbox.",
                "repair_hints": ["Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 first."]
              }
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(HubOperatorChannelOnboardingAutomationState.self, from: data)

        XCTAssertEqual(state.ticketId, "ticket_123")
        XCTAssertEqual(state.firstSmoke?.actionName, "supervisor.status.get")
        XCTAssertEqual(state.outboxItems.count, 1)
        XCTAssertEqual(state.outboxItems.first?.itemKind, "onboarding_ack")
        XCTAssertEqual(state.deliveryReadiness?.provider, "feishu")
        XCTAssertFalse(state.deliveryReadiness?.ready ?? true)
        XCTAssertFalse(state.deliveryReadiness?.replyEnabled ?? true)
        XCTAssertEqual(state.deliveryReadiness?.denyCode, "provider_delivery_not_configured")
        XCTAssertEqual(state.deliveryReadiness?.repairHints, ["Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 first."])
        XCTAssertTrue(state.hasPendingOutbox)
        XCTAssertTrue(state.canRetryPendingReplies)
    }

    func testAutomationStateSkipsRetryWhenOutboxIsFullyDelivered() throws {
        let data = Data(
            """
            {
              "schema_version": "xhub.channel_onboarding_automation_state.v1",
              "ticket_id": "ticket_456",
              "outbox_items": [
                {
                  "schema_version": "xhub.channel_outbox_item.v1",
                  "item_id": "outbox_1",
                  "provider": "slack",
                  "item_kind": "onboarding_ack",
                  "status": "delivered",
                  "ticket_id": "ticket_456",
                  "decision_id": "decision_2",
                  "receipt_id": "",
                  "attempt_count": 2,
                  "last_error_code": "",
                  "last_error_message": "",
                  "provider_message_ref": "171.5.1",
                  "created_at_ms": 200,
                  "updated_at_ms": 201,
                  "delivered_at_ms": 201,
                  "audit_ref": "audit_3"
                }
              ],
              "outbox_pending_count": 0,
              "outbox_delivered_count": 1,
              "delivery_readiness": {
                "provider": "slack",
                "ready": true,
                "reply_enabled": true,
                "credentials_configured": true,
                "deny_code": "",
                "remediation_hint": ""
              }
            }
            """.utf8
        )

        let state = try JSONDecoder().decode(HubOperatorChannelOnboardingAutomationState.self, from: data)

        XCTAssertEqual(state.ticketId, "ticket_456")
        XCTAssertEqual(state.outboxDeliveredCount, 1)
        XCTAssertFalse(state.hasPendingOutbox)
        XCTAssertFalse(state.canRetryPendingReplies)
        XCTAssertTrue(state.deliveryReadiness?.ready ?? false)
    }

    func testDetailResponseDecodesRevocation() throws {
        let data = Data(
            """
            {
              "ok": true,
              "ticket": {
                "schema_version": "xhub.channel_onboarding_discovery_ticket.v1",
                "ticket_id": "ticket_123",
                "provider": "slack",
                "account_id": "acct_1",
                "external_user_id": "user_1",
                "external_tenant_id": "tenant_1",
                "conversation_id": "conv_1",
                "thread_key": "",
                "ingress_surface": "dm",
                "first_message_preview": "status",
                "proposed_scope_type": "project",
                "proposed_scope_id": "project_alpha",
                "recommended_binding_mode": "conversation_binding",
                "status": "approved",
                "effective_status": "revoked",
                "event_count": 1,
                "first_seen_at_ms": 100,
                "last_seen_at_ms": 100,
                "created_at_ms": 100,
                "updated_at_ms": 100,
                "expires_at_ms": 200,
                "last_request_id": "request_1",
                "audit_ref": "audit_1"
              },
              "latest_decision": {
                "schema_version": "xhub.channel_onboarding_approval_decision.v1",
                "decision_id": "decision_1",
                "ticket_id": "ticket_123",
                "decision": "approve",
                "approved_by_hub_user_id": "hub_admin",
                "approved_via": "hub_local_ui",
                "hub_user_id": "hub_user_1",
                "scope_type": "project",
                "scope_id": "project_alpha",
                "binding_mode": "conversation_binding",
                "preferred_device_id": "",
                "allowed_actions": ["supervisor.status.get"],
                "grant_profile": "low_risk_readonly",
                "note": "",
                "created_at_ms": 100,
                "audit_ref": "audit_2"
              },
              "revocation": {
                "schema_version": "xhub.channel_onboarding_auto_bind_revocation.v1",
                "revocation_id": "revoke_1",
                "ticket_id": "ticket_123",
                "receipt_id": "receipt_1",
                "decision_id": "decision_1",
                "status": "revoked",
                "provider": "slack",
                "account_id": "acct_1",
                "external_user_id": "user_1",
                "external_tenant_id": "tenant_1",
                "conversation_id": "conv_1",
                "thread_key": "",
                "hub_user_id": "hub_user_1",
                "scope_type": "project",
                "scope_id": "project_alpha",
                "identity_actor_ref": "xhub.im_identity_binding.v1:slack/tenant_1/user_1",
                "channel_binding_id": "binding_1",
                "revoked_by_hub_user_id": "hub_admin",
                "revoked_via": "hub_local_ui",
                "note": "retired route",
                "created_at_ms": 150,
                "updated_at_ms": 150,
                "audit_ref": "audit_revoke_1"
              }
            }
            """.utf8
        )

        let detail = try JSONDecoder().decode(HubOperatorChannelOnboardingTicketDetail.self, from: data)

        XCTAssertEqual(detail.ticket.displayStatus, "revoked")
        XCTAssertEqual(detail.latestDecision?.decision, "approve")
        XCTAssertEqual(detail.revocation?.status, "revoked")
        XCTAssertEqual(detail.revocation?.revokedByHubUserId, "hub_admin")
    }

    func testProviderSetupGuideForFeishuIncludesEnableAndCredentialChecklist() {
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: "feishu",
            readiness: HubOperatorChannelOnboardingDeliveryReadiness(
                provider: "feishu",
                ready: false,
                replyEnabled: false,
                credentialsConfigured: false,
                denyCode: "provider_delivery_not_configured",
                remediationHint: "Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 and configure bot credentials."
            )
        )

        XCTAssertEqual(guide.provider, "feishu")
        XCTAssertTrue(guide.checklist.contains(where: { $0.key.contains("HUB_FEISHU_OPERATOR_REPLY_ENABLE=1") }))
        XCTAssertTrue(guide.checklist.contains(where: { $0.key.contains("HUB_FEISHU_OPERATOR_BOT_APP_ID") }))
        XCTAssertTrue(guide.checklist.contains(where: { $0.key.contains("HUB_FEISHU_OPERATOR_BOT_APP_SECRET") }))
        XCTAssertTrue(guide.statusSummary.contains("关闭"))
        XCTAssertTrue(guide.checklistText.contains("安全说明"))
    }

    func testProviderSetupGuideForSlackMentionsDedicatedBotToken() {
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: "slack",
            readiness: HubOperatorChannelOnboardingDeliveryReadiness(
                provider: "slack",
                ready: false,
                replyEnabled: true,
                credentialsConfigured: false,
                denyCode: "provider_delivery_not_configured",
                remediationHint: "Configure HUB_SLACK_OPERATOR_BOT_TOKEN."
            )
        )

        XCTAssertEqual(guide.provider, "slack")
        XCTAssertTrue(guide.checklist.contains(where: { $0.key.contains("HUB_SLACK_OPERATOR_BOT_TOKEN") }))
        XCTAssertTrue(guide.summary.contains("专用 bot token"))
        XCTAssertTrue(guide.nextStep.contains("待发送回复"))
    }

    func testProviderSetupGuideIncludesLiveTestRunbookForWhatsAppCloud() {
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: "whatsapp_cloud_api",
            readiness: HubOperatorChannelOnboardingDeliveryReadiness(
                provider: "whatsapp_cloud_api",
                ready: false,
                replyEnabled: true,
                credentialsConfigured: true,
                denyCode: "",
                remediationHint: ""
            )
        )

        XCTAssertTrue(guide.liveTestSteps.contains(where: { $0.contains("/whatsapp/events") }))
        XCTAssertTrue(guide.successSignals.contains(where: { $0.contains("命令入口已就绪") }))
        XCTAssertTrue(guide.failureChecks.contains(where: { $0.contains("APP_SECRET") }))
        XCTAssertTrue(guide.liveTestText.contains("首次真实联调"))
    }

    func testFirstUseFlowMarksRuntimeAttentionWhenFeishuIsNotConfigured() {
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "feishu",
            ready: false,
            replyEnabled: false,
            credentialsConfigured: false,
            denyCode: "provider_delivery_not_configured",
            remediationHint: "Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 and configure bot credentials."
        )
        let guide = HubOperatorChannelProviderSetupGuide.guide(for: "feishu", readiness: readiness)

        let flow = guide.firstUseFlow(readiness: readiness)

        XCTAssertEqual(flow.steps.count, 4)
        XCTAssertEqual(flow.steps[0].state, .attention)
        XCTAssertTrue(flow.steps[0].evidence.contains("HUB_FEISHU_OPERATOR_REPLY_ENABLE=1"))
        XCTAssertEqual(flow.steps[1].state, .pending)
        XCTAssertTrue(flow.nextAction.contains("HUB_FEISHU_OPERATOR_REPLY_ENABLE=1"))
        XCTAssertTrue(guide.setupPackText(flow: flow).contains("首次接入路径"))
    }

    func testFirstUseFlowMarksApprovalAndSmokeCompleteWhenAutomationSucceeded() {
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "slack",
            ready: true,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let guide = HubOperatorChannelProviderSetupGuide.guide(for: "slack", readiness: readiness)
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "slack",
            label: "Slack",
            releaseStage: "wave1",
            runtimeState: "ready",
            deliveryReady: true,
            commandEntryReady: true,
            lastErrorCode: "",
            updatedAtMs: 1710000005000
        )
        let ticket = makeTicket(provider: "slack", status: "approved")
        let decision = makeDecision(ticketId: ticket.ticketId, decision: "approve")
        let automationState = HubOperatorChannelOnboardingAutomationState(
            schemaVersion: "xhub.channel_onboarding_automation_state.v1",
            ticketId: ticket.ticketId,
            firstSmoke: HubOperatorChannelOnboardingFirstSmokeReceipt(
                schemaVersion: "xhub.channel_onboarding_first_smoke_receipt.v1",
                receiptId: "receipt_1",
                ticketId: ticket.ticketId,
                decisionId: decision.decisionId,
                provider: "slack",
                actionName: "supervisor.status.get",
                status: "query_executed",
                routeMode: "project_binding",
                denyCode: "",
                detail: "query_executed",
                remediationHint: "",
                projectId: "project_alpha",
                bindingId: "binding_1",
                ackOutboxItemId: "outbox_ack",
                smokeOutboxItemId: "outbox_smoke",
                createdAtMs: 100,
                updatedAtMs: 100,
                auditRef: "audit_1"
            ),
            outboxItems: [
                HubOperatorChannelOutboxItem(
                    schemaVersion: "xhub.channel_outbox_item.v1",
                    itemId: "outbox_ack",
                    provider: "slack",
                    itemKind: "onboarding_ack",
                    status: "delivered",
                    ticketId: ticket.ticketId,
                    decisionId: decision.decisionId,
                    receiptId: "receipt_1",
                    attemptCount: 1,
                    lastErrorCode: "",
                    lastErrorMessage: "",
                    providerMessageRef: "provider_ref_1",
                    createdAtMs: 101,
                    updatedAtMs: 101,
                    deliveredAtMs: 101,
                    auditRef: "audit_2"
                )
            ],
            outboxPendingCount: 0,
            outboxDeliveredCount: 1,
            deliveryReadiness: readiness
        )

        let flow = guide.firstUseFlow(
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticket: ticket,
            latestDecision: decision,
            automationState: automationState
        )

        XCTAssertTrue(flow.steps.allSatisfy { $0.state == .complete })
        XCTAssertTrue(flow.nextAction.contains("首次接入路径已完成"))
        XCTAssertTrue(flow.runbookText.contains("[完成] 验证 first smoke 和外发回复"))
    }

    func testFirstUseFlowMarksRevokedTicketAsAttention() {
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "slack",
            ready: true,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let guide = HubOperatorChannelProviderSetupGuide.guide(for: "slack", readiness: readiness)
        var ticket = makeTicket(provider: "slack", status: "approved")
        ticket.effectiveStatus = "revoked"
        let decision = makeDecision(ticketId: ticket.ticketId, decision: "approve")

        let flow = guide.firstUseFlow(
            readiness: readiness,
            ticket: ticket,
            latestDecision: decision,
            automationState: nil
        )

        XCTAssertEqual(flow.steps[2].state, .attention)
        XCTAssertTrue(flow.steps[2].evidence.contains("已经被撤销"))
        XCTAssertEqual(flow.steps[3].state, .attention)
    }

    func testRuntimeStatusDecodesCommandEntryReadiness() throws {
        let data = Data(
            """
            {
              "provider": "slack",
              "label": "Slack",
              "release_stage": "wave1",
              "runtime_state": "ready",
              "delivery_ready": true,
              "command_entry_ready": true,
              "last_error_code": "",
              "updated_at_ms": 1710000005000,
              "repair_hints": []
            }
            """.utf8
        )

        let status = try JSONDecoder().decode(HubOperatorChannelProviderRuntimeStatus.self, from: data)

        XCTAssertEqual(status.provider, "slack")
        XCTAssertEqual(status.normalizedRuntimeState, "ready")
        XCTAssertTrue(status.deliveryReady)
        XCTAssertTrue(status.commandEntryReady)
        XCTAssertEqual(status.repairHints, [])
    }

    func testFirstUseFlowUsesRuntimeStatusForConnectorStep() {
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "feishu",
            ready: false,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "feishu",
            label: "Feishu",
            releaseStage: "wave1",
            runtimeState: "ingress_ready",
            deliveryReady: false,
            commandEntryReady: false,
            lastErrorCode: "verification_token_missing",
            updatedAtMs: 1710000005000
        )
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: "feishu",
            readiness: readiness,
            runtimeStatus: runtimeStatus
        )

        let flow = guide.firstUseFlow(readiness: readiness, runtimeStatus: runtimeStatus)

        XCTAssertTrue(guide.checklist.contains(where: { $0.key.contains("HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN") }))
        XCTAssertTrue(guide.statusSummary.contains("入口链路已经连通"))
        XCTAssertEqual(flow.steps[1].state, .attention)
        XCTAssertTrue(flow.steps[1].evidence.contains("HUB_FEISHU_OPERATOR_VERIFICATION_TOKEN"))
        XCTAssertTrue(guide.repairHints.contains(where: { $0.contains("/feishu/events") }))
    }

    func testProviderSetupGuideBuildsRepairHintsForReplaySuspicion() {
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "slack",
            label: "Slack",
            releaseStage: "wave1",
            runtimeState: "degraded",
            deliveryReady: false,
            commandEntryReady: false,
            lastErrorCode: "webhook_replay_detected",
            updatedAtMs: 1710000005000
        )
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: "slack",
            readiness: nil,
            runtimeStatus: runtimeStatus
        )

        XCTAssertTrue(guide.repairHints.contains(where: { $0.contains("重放嫌疑") }))
        XCTAssertTrue(guide.repairHints.contains(where: { $0.contains("重新发送一条新消息") }))
        XCTAssertTrue(guide.checklistText.contains("修复建议"))
    }

    func testProviderSetupGuideBuildsRepairHintsForSlackSignatureFailure() {
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "slack",
            label: "Slack",
            releaseStage: "wave1",
            runtimeState: "degraded",
            deliveryReady: false,
            commandEntryReady: false,
            lastErrorCode: "signature_invalid",
            updatedAtMs: 1710000005000
        )
        let guide = HubOperatorChannelProviderSetupGuide.guide(
            for: "slack",
            readiness: nil,
            runtimeStatus: runtimeStatus
        )

        XCTAssertTrue(guide.repairHints.contains(where: { $0.contains("HUB_SLACK_OPERATOR_SIGNING_SECRET") }))
        XCTAssertTrue(guide.repairHints.contains(where: { $0.contains("/slack/events") }))
    }

    func testOnboardingOverviewMarksReadyProviderWhenRuntimeIsGreenAndNoTicketExists() throws {
        let overview = HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: [
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "slack",
                    ready: true,
                    replyEnabled: true,
                    credentialsConfigured: true,
                    denyCode: "",
                    remediationHint: ""
                )
            ],
            runtimeRows: [
                HubOperatorChannelProviderRuntimeStatus(
                    provider: "slack",
                    label: "Slack",
                    releaseStage: "wave1",
                    runtimeState: "ready",
                    deliveryReady: true,
                    commandEntryReady: true,
                    lastErrorCode: "",
                    updatedAtMs: 1710000005000
                )
            ],
            tickets: []
        )

        let card = try XCTUnwrap(overview.cards.first { $0.provider == "slack" })
        XCTAssertEqual(card.badgeTitle, HubUIStrings.Settings.OperatorChannels.readyBadge)
        XCTAssertEqual(card.badgeStyle, HubOperatorChannelOnboardingOverviewBadgeStyle.ready)
        XCTAssertTrue(card.nextAction.contains("生成隔离工单"))
        XCTAssertEqual(card.primaryAction.kind, .refreshStatus)
        XCTAssertEqual(card.primaryAction.title, HubUIStrings.Settings.OperatorChannels.Onboarding.reloadStatus)
        XCTAssertEqual(card.secondaryAction?.kind, .copySetupPack)
        XCTAssertEqual(overview.readyProviders, 1)
    }

    func testOnboardingOverviewMarksOpenTicketAsAwaitingReview() throws {
        let ticket = makeTicket(provider: "slack", status: "pending")
        let overview = HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: [
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "slack",
                    ready: true,
                    replyEnabled: true,
                    credentialsConfigured: true,
                    denyCode: "",
                    remediationHint: ""
                )
            ],
            runtimeRows: [
                HubOperatorChannelProviderRuntimeStatus(
                    provider: "slack",
                    label: "Slack",
                    releaseStage: "wave1",
                    runtimeState: "ready",
                    deliveryReady: true,
                    commandEntryReady: true,
                    lastErrorCode: "",
                    updatedAtMs: 1710000005000
                )
            ],
            tickets: [ticket]
        )

        let card = try XCTUnwrap(overview.cards.first { $0.provider == "slack" })
        XCTAssertEqual(card.badgeTitle, HubUIStrings.Settings.OperatorChannels.Onboarding.awaitingReviewBadge)
        XCTAssertEqual(card.badgeStyle, HubOperatorChannelOnboardingOverviewBadgeStyle.pending)
        XCTAssertEqual(card.reviewTicket?.ticketId, ticket.ticketId)
        XCTAssertTrue(card.nextAction.contains("等待本地 Hub 管理员审批"))
        XCTAssertEqual(card.primaryAction.kind, .reviewTicket)
        XCTAssertEqual(card.primaryAction.title, HubUIStrings.Settings.OperatorChannels.Onboarding.reviewPendingTicket)
        XCTAssertEqual(card.secondaryAction?.kind, .copySetupPack)
        XCTAssertEqual(overview.pendingTickets, 1)
    }

    func testOnboardingOverviewMarksRequireRealProviderAsPreviewSupportAttention() throws {
        let overview = HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: [
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "whatsapp_cloud_api",
                    ready: true,
                    replyEnabled: true,
                    credentialsConfigured: true,
                    denyCode: "",
                    remediationHint: ""
                )
            ],
            runtimeRows: [
                HubOperatorChannelProviderRuntimeStatus(
                    provider: "whatsapp_cloud_api",
                    label: "WhatsApp Cloud API",
                    releaseStage: "designed",
                    releaseBlocked: true,
                    requireRealEvidence: true,
                    runtimeState: "ready",
                    deliveryReady: true,
                    commandEntryReady: true,
                    lastErrorCode: "",
                    updatedAtMs: 1710000005000,
                    repairHints: ["先完成 require-real evidence，再决定是否继续开放。"]
                )
            ],
            tickets: []
        )

        let card = try XCTUnwrap(overview.cards.first { $0.provider == "whatsapp_cloud_api" })
        XCTAssertEqual(card.badgeTitle, HubUIStrings.Settings.OperatorChannels.Onboarding.previewSupportBadge)
        XCTAssertEqual(card.badgeStyle, HubOperatorChannelOnboardingOverviewBadgeStyle.attention)
        XCTAssertTrue(card.statusSummary.contains("require-real"))
        XCTAssertTrue(card.nextAction.contains("require-real evidence"))
        XCTAssertEqual(card.primaryAction.kind, .copySetupPack)
        XCTAssertEqual(card.secondaryAction?.kind, .refreshStatus)
        XCTAssertEqual(overview.attentionProviders, 1)
    }

    func testOnboardingOverviewUsesCopyAndRefreshActionsWhenProviderNeedsConfig() throws {
        let overview = HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: [
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "feishu",
                    ready: false,
                    replyEnabled: false,
                    credentialsConfigured: false,
                    denyCode: "provider_delivery_not_configured",
                    remediationHint: "Configure bot credentials first."
                )
            ],
            runtimeRows: [],
            tickets: []
        )

        let card = try XCTUnwrap(overview.cards.first { $0.provider == "feishu" })
        XCTAssertEqual(card.badgeStyle, HubOperatorChannelOnboardingOverviewBadgeStyle.attention)
        XCTAssertEqual(card.primaryAction.kind, .copySetupPack)
        XCTAssertEqual(card.primaryAction.title, HubUIStrings.Settings.OperatorChannels.copySetupPack)
        XCTAssertEqual(card.secondaryAction?.kind, .refreshStatus)
        XCTAssertEqual(card.secondaryAction?.title, HubUIStrings.Settings.OperatorChannels.Onboarding.reloadStatus)
    }

    func testOnboardingOverviewUsesViewActionForReadyProviderWithRecentTicket() throws {
        var ticket = makeTicket(provider: "slack", status: "approved")
        ticket.ticketId = "ticket_recent_1"
        ticket.updatedAtMs = 250

        let overview = HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: [
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "slack",
                    ready: true,
                    replyEnabled: true,
                    credentialsConfigured: true,
                    denyCode: "",
                    remediationHint: ""
                )
            ],
            runtimeRows: [
                HubOperatorChannelProviderRuntimeStatus(
                    provider: "slack",
                    label: "Slack",
                    releaseStage: "wave1",
                    runtimeState: "ready",
                    deliveryReady: true,
                    commandEntryReady: true,
                    lastErrorCode: "",
                    updatedAtMs: 1710000005000
                )
            ],
            tickets: [ticket]
        )

        let card = try XCTUnwrap(overview.cards.first { $0.provider == "slack" })
        XCTAssertEqual(card.badgeStyle, HubOperatorChannelOnboardingOverviewBadgeStyle.ready)
        XCTAssertEqual(card.latestTicket?.ticketId, "ticket_recent_1")
        XCTAssertEqual(card.primaryAction.kind, .viewLatestTicket)
        XCTAssertEqual(card.primaryAction.title, HubUIStrings.Settings.OperatorChannels.Onboarding.view)
        XCTAssertEqual(card.secondaryAction?.kind, .refreshStatus)
    }

    func testOnboardingOverviewSortsAttentionBeforePendingAndReady() throws {
        let pendingTicket = makeTicket(provider: "slack", status: "pending")
        let overview = HubOperatorChannelOnboardingOverviewPlanner.build(
            readinessRows: [
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "slack",
                    ready: true,
                    replyEnabled: true,
                    credentialsConfigured: true,
                    denyCode: "",
                    remediationHint: ""
                ),
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "telegram",
                    ready: true,
                    replyEnabled: true,
                    credentialsConfigured: true,
                    denyCode: "",
                    remediationHint: ""
                ),
                HubOperatorChannelOnboardingDeliveryReadiness(
                    provider: "feishu",
                    ready: false,
                    replyEnabled: false,
                    credentialsConfigured: false,
                    denyCode: "provider_delivery_not_configured",
                    remediationHint: "Set HUB_FEISHU_OPERATOR_REPLY_ENABLE=1 and configure bot credentials."
                )
            ],
            runtimeRows: [
                HubOperatorChannelProviderRuntimeStatus(
                    provider: "slack",
                    label: "Slack",
                    releaseStage: "wave1",
                    runtimeState: "ready",
                    deliveryReady: true,
                    commandEntryReady: true,
                    lastErrorCode: "",
                    updatedAtMs: 1710000005000
                ),
                HubOperatorChannelProviderRuntimeStatus(
                    provider: "telegram",
                    label: "Telegram",
                    releaseStage: "wave1",
                    runtimeState: "ready",
                    deliveryReady: true,
                    commandEntryReady: true,
                    lastErrorCode: "",
                    updatedAtMs: 1710000005000
                )
            ],
            tickets: [pendingTicket]
        )

        XCTAssertEqual(overview.cards.map(\.provider), ["feishu", "slack", "whatsapp_cloud_api", "telegram"])
    }

    func testLiveTestEvidenceBuilderProducesPassReportForApprovedSlackTicket() {
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "slack",
            ready: true,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "slack",
            label: "Slack",
            releaseStage: "wave1",
            releaseBlocked: false,
            requireRealEvidence: false,
            endpointVisibility: "relay_only",
            operatorSurface: "thread",
            runtimeState: "ready",
            deliveryReady: true,
            commandEntryReady: true,
            lastErrorCode: "",
            updatedAtMs: 1710000005000
        )
        let ticket = makeTicket(provider: "slack", status: "approved")
        let decision = makeDecision(ticketId: ticket.ticketId, decision: "approve")
        let automationState = HubOperatorChannelOnboardingAutomationState(
            schemaVersion: "xhub.channel_onboarding_automation_state.v1",
            ticketId: ticket.ticketId,
            firstSmoke: HubOperatorChannelOnboardingFirstSmokeReceipt(
                schemaVersion: "xhub.channel_onboarding_first_smoke_receipt.v1",
                receiptId: "receipt_1",
                ticketId: ticket.ticketId,
                decisionId: decision.decisionId,
                provider: "slack",
                actionName: "supervisor.status.get",
                status: "query_executed",
                routeMode: "project_binding",
                denyCode: "",
                detail: "query_executed",
                remediationHint: "",
                projectId: "project_alpha",
                bindingId: "binding_1",
                ackOutboxItemId: "outbox_ack",
                smokeOutboxItemId: "outbox_smoke",
                heartbeatGovernanceSnapshot: HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceSnapshot(
                    projectId: "project_alpha",
                    projectName: "Alpha",
                    statusDigest: "Core loop advancing",
                    latestQualityBand: "usable",
                    latestQualityScore: 74,
                    openAnomalyTypes: ["stale_repeat"],
                    weakReasons: ["evidence_thin"],
                    nextReviewDue: HubOperatorChannelOnboardingFirstSmokeReceipt.HeartbeatGovernanceNextReviewDue(
                        kind: "review_pulse",
                        due: true,
                        atMs: 1710000600000,
                        reasonCodes: ["pulse_due_window"]
                    )
                ),
                createdAtMs: 100,
                updatedAtMs: 101,
                auditRef: "audit_1"
            ),
            outboxItems: [],
            outboxPendingCount: 0,
            outboxDeliveredCount: 2,
            deliveryReadiness: readiness
        )

        let report = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "slack",
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: HubOperatorChannelOnboardingTicketDetail(
                ticket: ticket,
                latestDecision: decision,
                automationState: automationState
            ),
            adminBaseURL: "http://127.0.0.1:50052",
            outputPath: "x-terminal/build/reports/xt_w3_24_s_slack_live_test_evidence.v1.json"
        )

        XCTAssertEqual(report.schemaVersion, "xt_w3_24_operator_channel_live_test_evidence.v1")
        XCTAssertEqual(report.provider, "slack")
        XCTAssertEqual(report.operatorVerdict, "passed")
        XCTAssertEqual(report.derivedStatus, "pass")
        XCTAssertTrue(report.liveTestSuccess)
        XCTAssertEqual(report.providerReleaseContext?.releaseStage, "wave1")
        XCTAssertEqual(report.checks.count, 8)
        XCTAssertTrue(report.checks.allSatisfy { $0.status == "pass" })
        XCTAssertEqual(report.checks[6].name, "heartbeat_governance_visible")
        XCTAssertTrue(report.checks[6].detail.contains("heartbeat_quality=usable"))
        XCTAssertTrue(report.checks[6].detail.contains("next_review=review_pulse"))
        XCTAssertEqual(report.repairHints, [])
        XCTAssertEqual(report.requiredNextStep, "All key operator channel live-test checks passed.")
    }

    func testLiveTestEvidenceBuilderFailsWhenHeartbeatGovernanceVisibilityIsMissing() {
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "slack",
            ready: true,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "slack",
            label: "Slack",
            releaseStage: "wave1",
            releaseBlocked: false,
            requireRealEvidence: false,
            endpointVisibility: "relay_only",
            operatorSurface: "thread",
            runtimeState: "ready",
            deliveryReady: true,
            commandEntryReady: true,
            lastErrorCode: "",
            updatedAtMs: 1710000005000
        )
        let ticket = makeTicket(provider: "slack", status: "approved")
        let decision = makeDecision(ticketId: ticket.ticketId, decision: "approve")
        let automationState = HubOperatorChannelOnboardingAutomationState(
            schemaVersion: "xhub.channel_onboarding_automation_state.v1",
            ticketId: ticket.ticketId,
            firstSmoke: HubOperatorChannelOnboardingFirstSmokeReceipt(
                schemaVersion: "xhub.channel_onboarding_first_smoke_receipt.v1",
                receiptId: "receipt_visibility_missing_1",
                ticketId: ticket.ticketId,
                decisionId: decision.decisionId,
                provider: "slack",
                actionName: "supervisor.status.get",
                status: "query_executed",
                routeMode: "project_binding",
                denyCode: "",
                detail: "query_executed",
                remediationHint: "",
                projectId: "project_alpha",
                bindingId: "binding_1",
                ackOutboxItemId: "outbox_ack",
                smokeOutboxItemId: "outbox_smoke",
                createdAtMs: 100,
                updatedAtMs: 101,
                auditRef: "audit_visibility_missing_1"
            ),
            outboxItems: [],
            outboxPendingCount: 0,
            outboxDeliveredCount: 2,
            deliveryReadiness: readiness
        )

        let report = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "slack",
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: HubOperatorChannelOnboardingTicketDetail(
                ticket: ticket,
                latestDecision: decision,
                automationState: automationState
            )
        )

        XCTAssertEqual(report.derivedStatus, "attention")
        XCTAssertFalse(report.liveTestSuccess)
        XCTAssertEqual(report.checks[5].name, "first_smoke_executed")
        XCTAssertEqual(report.checks[5].status, "pass")
        XCTAssertEqual(report.checks[6].name, "heartbeat_governance_visible")
        XCTAssertEqual(report.checks[6].status, "fail")
        XCTAssertEqual(
            report.requiredNextStep,
            "Re-run or reload first smoke and verify it exported heartbeat governance visibility (quality band / next review)."
        )
    }

    func testLiveTestEvidenceBuilderFailsClosedWhenApprovalAndSmokeAreMissing() {
        let runtimeRepairHint = "Restart the Telegram polling worker with HUB_TELEGRAM_OPERATOR_ENABLE=1, HUB_TELEGRAM_OPERATOR_BOT_TOKEN, and HUB_OPERATOR_CHANNEL_CONNECTOR_TOKEN."
        let readinessRepairHint = "Load the Telegram bot token into the running Hub process and keep reply delivery enabled."
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "telegram",
            ready: false,
            replyEnabled: true,
            credentialsConfigured: false,
            denyCode: "provider_delivery_not_configured",
            remediationHint: "Load bot token.",
            repairHints: [readinessRepairHint]
        )
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "telegram",
            label: "Telegram",
            releaseStage: "wave1",
            runtimeState: "degraded",
            deliveryReady: false,
            commandEntryReady: false,
            lastErrorCode: "bot_token_missing",
            updatedAtMs: 1710000005000,
            repairHints: [runtimeRepairHint]
        )
        let ticket = makeTicket(provider: "telegram", status: "held")

        let report = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "telegram",
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: HubOperatorChannelOnboardingTicketDetail(
                ticket: ticket,
                latestDecision: nil,
                automationState: nil
            )
        )

        XCTAssertEqual(report.operatorVerdict, "partial")
        XCTAssertEqual(report.derivedStatus, "attention")
        XCTAssertFalse(report.liveTestSuccess)
        XCTAssertEqual(report.checks.first?.name, "runtime_command_entry_ready")
        XCTAssertEqual(report.checks.first?.status, "fail")
        XCTAssertEqual(report.checks.first?.remediation, runtimeRepairHint)
        XCTAssertEqual(report.checks[1].remediation, readinessRepairHint)
        XCTAssertEqual(report.checks[2].name, "release_ready_boundary")
        XCTAssertEqual(report.repairHints, [runtimeRepairHint, readinessRepairHint])
        XCTAssertEqual(report.requiredNextStep, runtimeRepairHint)
        XCTAssertEqual(
            HubOperatorChannelLiveTestEvidenceBuilder.defaultFileName(provider: "telegram", ticketId: "ticket_123"),
            "xt_w3_24_s_telegram_ticket_123_live_test_evidence.v1.json"
        )
    }

    func testLiveTestEvidenceBuilderUsesRuntimeRepairHintForReleaseBoundary() {
        let releaseRepairHint = "Keep WhatsApp Cloud API in designed/wired mode until real live evidence clears the release block."
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "whatsapp_cloud_api",
            ready: true,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "whatsapp_cloud_api",
            label: "WhatsApp Cloud",
            releaseStage: "p1",
            releaseBlocked: true,
            requireRealEvidence: true,
            endpointVisibility: "relay_only",
            operatorSurface: "hub_supervisor_facade",
            runtimeState: "ready",
            deliveryReady: true,
            commandEntryReady: true,
            lastErrorCode: "",
            updatedAtMs: 1710000007000,
            repairHints: [releaseRepairHint]
        )
        let ticket = makeTicket(provider: "whatsapp_cloud_api", status: "approved")
        let decision = makeDecision(ticketId: ticket.ticketId, decision: "approve")
        let automationState = HubOperatorChannelOnboardingAutomationState(
            schemaVersion: "xhub.channel_onboarding_automation_state.v1",
            ticketId: ticket.ticketId,
            firstSmoke: HubOperatorChannelOnboardingFirstSmokeReceipt(
                schemaVersion: "xhub.channel_onboarding_first_smoke_receipt.v1",
                receiptId: "receipt_release_1",
                ticketId: ticket.ticketId,
                decisionId: decision.decisionId,
                provider: "whatsapp_cloud_api",
                actionName: "supervisor.status.get",
                status: "query_executed",
                routeMode: "hub_to_xt",
                denyCode: "",
                detail: "query_executed",
                remediationHint: "",
                projectId: "project_alpha",
                bindingId: "binding_1",
                ackOutboxItemId: "outbox_ack",
                smokeOutboxItemId: "outbox_smoke",
                createdAtMs: 100,
                updatedAtMs: 101,
                auditRef: "audit_release_1"
            ),
            outboxItems: [],
            outboxPendingCount: 0,
            outboxDeliveredCount: 1,
            deliveryReadiness: readiness
        )

        let report = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "whatsapp_cloud_api",
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: HubOperatorChannelOnboardingTicketDetail(
                ticket: ticket,
                latestDecision: decision,
                automationState: automationState
            )
        )

        XCTAssertEqual(report.derivedStatus, "attention")
        XCTAssertEqual(report.checks[2].name, "release_ready_boundary")
        XCTAssertEqual(report.checks[2].status, "fail")
        XCTAssertEqual(report.checks[2].remediation, releaseRepairHint)
        XCTAssertEqual(report.requiredNextStep, releaseRepairHint)
        XCTAssertEqual(report.repairHints, [releaseRepairHint])
    }

    func testLiveTestEvidenceBuilderPromotesSignatureMismatchRepairHintIntoNextStep() {
        let signatureRepairHint = "Slack 签名校验失败。检查 HUB_SLACK_OPERATOR_SIGNING_SECRET，确认代理或隧道保留原始请求体和 X-Slack-* 头，不要在到达 /slack/events 前改写 body。"
        let readiness = HubOperatorChannelOnboardingDeliveryReadiness(
            provider: "slack",
            ready: true,
            replyEnabled: true,
            credentialsConfigured: true,
            denyCode: "",
            remediationHint: ""
        )
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "slack",
            label: "Slack",
            releaseStage: "wave1",
            runtimeState: "degraded",
            deliveryReady: false,
            commandEntryReady: false,
            lastErrorCode: "signature_invalid",
            updatedAtMs: 1710000008000,
            repairHints: [signatureRepairHint]
        )
        let ticket = makeTicket(provider: "slack", status: "reviewed")

        let report = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "slack",
            readiness: readiness,
            runtimeStatus: runtimeStatus,
            ticketDetail: HubOperatorChannelOnboardingTicketDetail(
                ticket: ticket,
                latestDecision: nil,
                automationState: nil
            )
        )

        XCTAssertEqual(report.derivedStatus, "attention")
        XCTAssertEqual(report.checks.first?.name, "runtime_command_entry_ready")
        XCTAssertEqual(report.checks.first?.status, "fail")
        XCTAssertEqual(report.checks.first?.remediation, signatureRepairHint)
        XCTAssertEqual(report.repairHints, [signatureRepairHint])
        XCTAssertEqual(report.requiredNextStep, signatureRepairHint)
    }

    func testLiveTestEvidenceBuilderPromotesReplaySuspicionRepairHintFromAutomationDeliveryState() {
        let replayRepairHint = "Hub 因重放嫌疑已 fail-closed。先检查 provider 是否重复投递、代理是否重放旧请求；修复后请在目标会话重新发送一条新消息生成新工单，不要直接复用旧 payload。"
        let runtimeStatus = HubOperatorChannelProviderRuntimeStatus(
            provider: "telegram",
            label: "Telegram",
            releaseStage: "wave1",
            runtimeState: "degraded",
            deliveryReady: false,
            commandEntryReady: true,
            lastErrorCode: "",
            updatedAtMs: 1710000008100
        )
        let ticket = makeTicket(provider: "telegram", status: "held")
        let automationState = HubOperatorChannelOnboardingAutomationState(
            schemaVersion: "xhub.channel_onboarding_automation_state.v1",
            ticketId: ticket.ticketId,
            firstSmoke: nil,
            outboxItems: [
                HubOperatorChannelOutboxItem(
                    schemaVersion: "xhub.channel_outbox_item.v1",
                    itemId: "outbox_replay_1",
                    provider: "telegram",
                    itemKind: "onboarding_ack",
                    status: "pending",
                    ticketId: ticket.ticketId,
                    decisionId: "",
                    receiptId: "",
                    attemptCount: 1,
                    lastErrorCode: "replay_detected",
                    lastErrorMessage: "replay_detected",
                    providerMessageRef: "",
                    createdAtMs: 1710000008100,
                    updatedAtMs: 1710000008101,
                    deliveredAtMs: 0,
                    auditRef: "audit_replay_1"
                ),
            ],
            outboxPendingCount: 1,
            outboxDeliveredCount: 0,
            deliveryReadiness: HubOperatorChannelOnboardingDeliveryReadiness(
                provider: "telegram",
                ready: false,
                replyEnabled: true,
                credentialsConfigured: true,
                denyCode: "replay_detected",
                remediationHint: "",
                repairHints: [replayRepairHint]
            )
        )

        let report = HubOperatorChannelLiveTestEvidenceBuilder.build(
            provider: "telegram",
            readiness: nil,
            runtimeStatus: runtimeStatus,
            ticketDetail: HubOperatorChannelOnboardingTicketDetail(
                ticket: ticket,
                latestDecision: nil,
                automationState: automationState
            )
        )

        XCTAssertEqual(report.derivedStatus, "attention")
        XCTAssertEqual(report.checks[0].name, "runtime_command_entry_ready")
        XCTAssertEqual(report.checks[0].status, "pass")
        XCTAssertEqual(report.checks[1].name, "delivery_ready")
        XCTAssertEqual(report.checks[1].status, "fail")
        XCTAssertEqual(report.checks[1].remediation, replayRepairHint)
        XCTAssertEqual(report.repairHints, [replayRepairHint])
        XCTAssertEqual(report.requiredNextStep, replayRepairHint)
    }

    func testLiveTestEvidencePathEncodesExpectedQueryItems() throws {
        let performedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let path = OperatorChannelsOnboardingHTTPClient.liveTestEvidencePath(
            provider: "Telegram",
            ticketId: "ticket_123",
            verdict: "partial",
            summary: "Telegram onboarding is still blocked.",
            performedAt: performedAt,
            evidenceRefs: ["captures/telegram live 1.png", "captures/telegram live 1.png", "captures/telegram-live-2.png"],
            requiredNextStep: "Load HUB_TELEGRAM_OPERATOR_BOT_TOKEN first."
        )

        let components = try XCTUnwrap(URLComponents(string: "http://127.0.0.1\(path)"))
        XCTAssertEqual(components.path, "/admin/operator-channels/live-test/evidence")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "provider" })?.value,
            "telegram"
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "ticket_id" })?.value,
            "ticket_123"
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "verdict" })?.value,
            "partial"
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "summary" })?.value,
            "Telegram onboarding is still blocked."
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "next_step" })?.value,
            "Load HUB_TELEGRAM_OPERATOR_BOT_TOKEN first."
        )
        XCTAssertEqual(
            components.queryItems?.filter { $0.name == "evidence_ref" }.map(\.value),
            ["captures/telegram live 1.png", "captures/telegram live 1.png", "captures/telegram-live-2.png"]
        )
        XCTAssertNotNil(components.queryItems?.first(where: { $0.name == "performed_at" })?.value)
    }

    func testLiveTestEvidenceFallbackOnlyTriggersForLegacyEndpointMisses() {
        XCTAssertTrue(
            OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(
                for: OperatorChannelsOnboardingHTTPClient.OnboardingError.apiError(code: "not_found", message: "not_found")
            )
        )
        XCTAssertTrue(
            OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(
                for: OperatorChannelsOnboardingHTTPClient.OnboardingError.badResponse
            )
        )
        XCTAssertFalse(
            OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(
                for: OperatorChannelsOnboardingHTTPClient.OnboardingError.apiError(code: "ticket_not_found", message: "missing")
            )
        )
        XCTAssertFalse(
            OperatorChannelsOnboardingHTTPClient.supportsLegacyLiveTestEvidenceFallback(
                for: OperatorChannelsOnboardingHTTPClient.OnboardingError.apiError(code: "provider_required", message: "provider_required")
            )
        )
    }

    private func makeTicket(provider: String, status: String) -> HubOperatorChannelOnboardingTicket {
        HubOperatorChannelOnboardingTicket(
            schemaVersion: "xhub.channel_onboarding_discovery_ticket.v1",
            ticketId: "ticket_123",
            provider: provider,
            accountId: "acct_1",
            externalUserId: "user_1",
            externalTenantId: "tenant_1",
            conversationId: "conv_1",
            threadKey: "",
            ingressSurface: "dm",
            firstMessagePreview: "status",
            proposedScopeType: "project",
            proposedScopeId: "project_alpha",
            recommendedBindingMode: "conversation_binding",
            status: status,
            effectiveStatus: status,
            eventCount: 1,
            firstSeenAtMs: 100,
            lastSeenAtMs: 100,
            createdAtMs: 100,
            updatedAtMs: 100,
            expiresAtMs: 200,
            lastRequestId: "request_1",
            auditRef: "audit_1"
        )
    }

    private func makeDecision(ticketId: String, decision: String) -> HubOperatorChannelOnboardingApprovalDecision {
        HubOperatorChannelOnboardingApprovalDecision(
            schemaVersion: "xhub.channel_onboarding_approval_decision.v1",
            decisionId: "decision_1",
            ticketId: ticketId,
            decision: decision,
            approvedByHubUserId: "hub_admin",
            approvedVia: "hub_local_ui",
            hubUserId: "hub_user_1",
            scopeType: "project",
            scopeId: "project_alpha",
            bindingMode: "conversation_binding",
            preferredDeviceId: "",
            allowedActions: ["supervisor.status.get"],
            grantProfile: "low_risk_readonly",
            note: "",
            createdAtMs: 100,
            auditRef: "audit_2"
        )
    }
}
