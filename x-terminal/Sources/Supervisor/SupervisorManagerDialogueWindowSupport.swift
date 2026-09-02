import Foundation

extension SupervisorManager {
    func currentSupervisorRecentRawContextProfile() -> XTSupervisorRecentRawContextProfile {
        let configuredProfile = appModel?.settingsStore.settings.supervisorRecentRawContextProfile
            ?? .defaultProfile
        return currentSupervisorPrivacyMode.effectiveRecentRawContextProfile(configuredProfile)
    }

    func supervisorRecentRawContextCeilingPairs(
        profile: XTSupervisorRecentRawContextProfile,
        availableEligibleMessages: Int
    ) -> Int {
        let availablePairs = max(
            XTSupervisorRecentRawContextProfile.hardFloorPairs,
            Int(ceil(Double(max(0, availableEligibleMessages)) / 2.0))
        )
        if let fixed = profile.windowCeilingPairs {
            return max(XTSupervisorRecentRawContextProfile.hardFloorPairs, fixed)
        }
        return max(XTSupervisorRecentRawContextProfile.hardFloorPairs, min(availablePairs, 40))
    }

    func supervisorDialogueWindowTargetBudgetTokens(
        servingProfile: XTMemoryServingProfile,
        profile _: XTSupervisorRecentRawContextProfile
    ) -> Int {
        switch servingProfile {
        case .m0Heartbeat:
            return 180
        case .m1Execute:
            return 360
        case .m2PlanReview:
            return 520
        case .m3DeepDive, .m4FullScan:
            switch servingProfile {
            case .m3DeepDive:
                return 760
            case .m4FullScan:
                return 1_040
            default:
                return 760
            }
        }
    }

    func focusedSupervisorRecentMessagesDigest(
        _ recent: AXRecentContext,
        limit: Int
    ) -> String {
        let rows = recent.messages
            .suffix(max(0, limit))
            .map { message in
                let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "unknown"
                    : message.role
                let content = sanitizeSupervisorPromptIdentifiers(
                    capped(message.content, maxChars: 180)
                )
                return "- \(role): \(content.isEmpty ? "(empty)" : content)"
            }
        return rows.isEmpty ? "(none)" : rows.joined(separator: "\n")
    }

    func focusedSupervisorDialogueRecoveryDigest(
        selection: SupervisorFocusedProjectSelection?
    ) -> String {
        guard let selection else { return "" }

        let explicitHiddenProjectFocus = selection.source == "explicit_user_mention" &&
            !projectVisibleInCurrentSupervisorJurisdiction(selection.project)
        guard explicitHiddenProjectFocus else { return "" }

        let recentMessages = focusedSupervisorRecentMessagesDigest(
            AXRecentContextStore.load(for: supervisorMemoryContext(for: selection.project)),
            limit: 4
        )
        guard recentMessages != "(none)" else { return "" }

        return """
focus_project=\(selection.project.displayName) (\(selection.project.projectId))
source=project_recent_context
recent_messages:
\(recentMessages)
"""
    }

    func renderSupervisorDialogueWindow(
        messages sourceMessages: [SupervisorMessage],
        userMessage: String,
        servingProfile: XTMemoryServingProfile,
        rawContextProfile: XTSupervisorRecentRawContextProfile,
        turnRoutingDecision: SupervisorTurnRoutingDecision,
        focusedProjectSelection: SupervisorFocusedProjectSelection?
    ) async -> SupervisorDialogueWindowSelection {
        let profile = rawContextProfile
        let floorPairs = XTSupervisorRecentRawContextProfile.hardFloorPairs
        let remoteContinuity = await HubIPCClient.requestSupervisorRemoteContinuity()
        let continuitySourceSelection: SupervisorDialogueContinuitySourceSelection
        if remoteContinuity.ok {
            continuitySourceSelection = SupervisorDialogueContinuitySourceResolver.resolve(
                localMessages: sourceMessages,
                remoteWorkingEntries: remoteContinuity.workingEntries
            )
        } else {
            continuitySourceSelection = SupervisorDialogueContinuitySourceSelection(
                messages: sourceMessages,
                source: "xt_cache"
            )
        }
        let continuityMessages = continuitySourceSelection.messages
        let eligibleAvailableMessages = continuityMessages.reduce(into: 0) { partial, message in
            if message.role == .user || message.role == .assistant {
                partial += 1
            }
        }
        let ceilingPairs = supervisorRecentRawContextCeilingPairs(
            profile: profile,
            availableEligibleMessages: eligibleAvailableMessages
        )
        let targetEligibleMessages = max(floorPairs * 2, ceilingPairs * 2)

        var collected: [SupervisorMessage] = []
        var eligibleSelectedMessages = 0
        var lowSignalDroppedMessages = 0
        var lowSignalDropSampleLines: [String] = []
        var oldestIncludedIndex: Int?
        for index in continuityMessages.indices.reversed() {
            let message = continuityMessages[index]
            if message.role == .user || message.role == .assistant {
                let continuityDecision = SupervisorDialogueContinuityFilter.classify(message)
                if continuityDecision.isLowSignal {
                    lowSignalDroppedMessages += 1
                    if lowSignalDropSampleLines.count < 3 {
                        let preview = sanitizeSupervisorPromptIdentifiers(
                            capped(firstNonEmptyLine(in: message.content), maxChars: 60)
                        )
                        let renderedPreview = preview.isEmpty ? "(empty)" : preview
                        lowSignalDropSampleLines.append(
                            "role=\(message.role.rawValue) reason=\(continuityDecision.reasonCode) text=\(renderedPreview)"
                        )
                    }
                    continue
                }
                eligibleSelectedMessages += 1
            }
            collected.append(message)
            oldestIncludedIndex = index
            if eligibleSelectedMessages >= targetEligibleMessages {
                break
            }
        }
        collected.reverse()

        let olderMessages: [SupervisorMessage]
        if let oldestIncludedIndex, oldestIncludedIndex > continuityMessages.startIndex {
            olderMessages = Array(continuityMessages[..<oldestIncludedIndex])
        } else {
            olderMessages = []
        }

        let rollingDigest = sanitizeSupervisorPromptIdentifiers(
            SupervisorDialogueRollingDigestBuilder.build(
                olderMessages: olderMessages,
                turnMode: turnRoutingDecision.mode.rawValue,
                focusedProjectName: focusedProjectSelection?.project.displayName,
                focusedProjectId: focusedProjectSelection?.project.projectId
            )
        )
        let rollingDigestPresent = supervisorAssemblyHasMeaningfulContent(rollingDigest)

        let selectedPairs = Int(ceil(Double(max(0, eligibleSelectedMessages)) / 2.0))
        let continuityFloorSatisfied = eligibleSelectedMessages >= floorPairs * 2
        let currentTurnRefs = [
            "turn_mode=\(turnRoutingDecision.mode.rawValue)",
            "focused_project=\(focusedProjectSelection?.project.displayName ?? "(none)")",
            "focused_project_id=\(focusedProjectSelection?.project.projectId ?? "(none)")"
        ].joined(separator: "\n- ")
        let recentUserIntentLines = orderedUniqueSupervisorRefs(
            [userMessage] + collected.reversed().compactMap { message in
                guard message.role == .user else { return nil }
                return firstNonEmptyLine(in: message.content)
            }
        )
        let recentAssistantCommitments = orderedUniqueSupervisorRefs(
            collected.reversed().compactMap { message in
                guard message.role == .assistant else { return nil }
                return firstNonEmptyLine(in: message.content)
            }
        )
        let targetBudgetTokens = supervisorDialogueWindowTargetBudgetTokens(
            servingProfile: servingProfile,
            profile: profile
        )
        let focusedProjectDialogueRecovery = focusedSupervisorDialogueRecoveryDigest(
            selection: focusedProjectSelection
        )
        let supervisorSelfObservationBlock = renderSupervisorSelfObservationPromptBlock(
            messages: collected
        )

        let preferredLineCap: Int
        switch servingProfile {
        case .m3DeepDive, .m4FullScan:
            preferredLineCap = 220
        case .m2PlanReview:
            preferredLineCap = 180
        default:
            preferredLineCap = 150
        }

        let supportedLineCaps = stride(
            from: preferredLineCap,
            through: 96,
            by: -18
        ).map { $0 } + [96]

        var bestText = ""
        var usedReducedCap = false

        for lineCap in supportedLineCaps {
            let recentUserIntentBlock = recentUserIntentLines.prefix(3).map {
                "- \(sanitizeSupervisorPromptIdentifiers(capped($0, maxChars: 140)))"
            }
            let recentAssistantCommitmentBlock = recentAssistantCommitments.prefix(3).map {
                "- \(sanitizeSupervisorPromptIdentifiers(capped($0, maxChars: 140)))"
            }
            let renderedMessages = collected.map { message in
                let content = sanitizeSupervisorPromptIdentifiers(
                    capped(message.content, maxChars: lineCap)
                )
                return "- \(message.role.rawValue): \(content.isEmpty ? "(empty)" : content)"
            }
            let rollingDigestSection = rollingDigestPresent
                ? """
rolling_dialogue_digest:
\(rollingDigest)
"""
                : ""
            let focusedProjectDialogueRecoverySection = focusedProjectDialogueRecovery.isEmpty
                ? ""
                : """
focused_project_recent_dialogue_recovery:
\(focusedProjectDialogueRecovery)
"""

            let candidate = """
window_profile: \(profile.rawValue)
raw_window_floor_pairs: \(floorPairs)
raw_window_ceiling_pairs: \(ceilingPairs)
raw_window_selected_pairs: \(selectedPairs)
eligible_messages: \(eligibleSelectedMessages)
low_signal_dropped_messages: \(lowSignalDroppedMessages)
raw_window_source: \(continuitySourceSelection.source)
continuity_floor_satisfied: \(continuityFloorSatisfied ? "true" : "false")
truncation_after_floor: false
current_turn_refs:
- \(currentTurnRefs)
recent_user_intent:
\(recentUserIntentBlock.isEmpty ? "- (none)" : recentUserIntentBlock.joined(separator: "\n"))
recent_assistant_commitments:
\(recentAssistantCommitmentBlock.isEmpty ? "- (none)" : recentAssistantCommitmentBlock.joined(separator: "\n"))
supervisor_self_observation:
\(supervisorSelfObservationBlock)
raw_messages:
\(renderedMessages.isEmpty ? "- (none)" : renderedMessages.joined(separator: "\n"))
\(rollingDigestSection.isEmpty ? "" : "\n\(rollingDigestSection)")
\(focusedProjectDialogueRecoverySection.isEmpty ? "" : "\n\(focusedProjectDialogueRecoverySection)")
"""
            bestText = candidate
            if TokenEstimator.estimateTokens(candidate) <= targetBudgetTokens {
                usedReducedCap = lineCap < preferredLineCap
                break
            }
            usedReducedCap = true
        }

        let continuityRemoteLine: String
        if remoteContinuity.ok {
            continuityRemoteLine = "remote_continuity=ok cache_hit=\(remoteContinuity.cacheHit ? "true" : "false") working_entries=\(remoteContinuity.workingEntries.count) assembled_source=\(continuitySourceSelection.source)"
        } else {
            continuityRemoteLine = "remote_continuity=fallback reason=\(remoteContinuity.reasonCode ?? "unknown") assembled_source=\(continuitySourceSelection.source)"
        }
        var continuityTraceLines = [
            continuityRemoteLine,
            "selection raw_profile=\(profile.rawValue) available_eligible=\(eligibleAvailableMessages) selected_eligible=\(eligibleSelectedMessages) selected_pairs=\(selectedPairs) floor_pairs=\(floorPairs) ceiling_pairs=\(ceilingPairs)"
        ]
        if rollingDigestPresent {
            continuityTraceLines.append("rolling_digest=present older_messages=\(olderMessages.count)")
        }
        if lowSignalDroppedMessages > 0 {
            continuityTraceLines.append("low_signal_drop=\(lowSignalDroppedMessages)")
        }
        if !focusedProjectDialogueRecovery.isEmpty {
            continuityTraceLines.append("focused_project_dialogue_recovery=project_recent_context")
        }
        if usedReducedCap {
            continuityTraceLines.append("truncated_after_floor=true")
        }

        return SupervisorDialogueWindowSelection(
            text: bestText,
            profile: profile,
            floorPairs: floorPairs,
            ceilingPairs: profile.windowCeilingPairs,
            selectedPairs: selectedPairs,
            eligibleMessages: eligibleSelectedMessages,
            lowSignalDroppedMessages: lowSignalDroppedMessages,
            source: continuitySourceSelection.source,
            rollingDigestPresent: rollingDigestPresent,
            continuityFloorSatisfied: continuityFloorSatisfied,
            truncationAfterFloor: usedReducedCap,
            continuityTraceLines: continuityTraceLines,
            lowSignalDropSampleLines: lowSignalDropSampleLines
        )
    }
}
