import Foundation

extension HubMemoryContextBuilder {
    static func compressDialogueWindowObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }
        let keys = [
            "window_profile",
            "raw_window_floor_pairs",
            "raw_window_ceiling_pairs",
            "raw_window_selected_pairs",
            "eligible_messages",
            "low_signal_dropped_messages",
            "raw_window_source",
            "continuity_floor_satisfied",
            "truncation_after_floor",
            "current_turn_refs",
            "recent_user_intent",
            "recent_assistant_commitments",
            "raw_messages",
            "rolling_dialogue_digest",
            "focused_project_recent_dialogue_recovery",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        let floorPairs = parsedInlineIntValue(parsed, key: "raw_window_floor_pairs") ?? 8
        let floorRawMessages = max(1, floorPairs * 2)

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var supportTrimmed = parsed
        var supportTrimmedFields: [String: Int] = [:]
        trimBlockLines(
            &supportTrimmed,
            key: "current_turn_refs",
            maxLines: 2,
            counterKey: "current_turn_refs_items",
            counts: &supportTrimmedFields
        )
        trimBlockLines(
            &supportTrimmed,
            key: "recent_user_intent",
            maxLines: 2,
            counterKey: "recent_user_intent_items",
            counts: &supportTrimmedFields
        )
        trimBlockLines(
            &supportTrimmed,
            key: "recent_assistant_commitments",
            maxLines: 2,
            counterKey: "recent_assistant_commitments_items",
            counts: &supportTrimmedFields
        )
        dropBlock(
            &supportTrimmed,
            key: "rolling_dialogue_digest",
            counterKey: "rolling_dialogue_digest",
            counts: &supportTrimmedFields
        )
        dropBlock(
            &supportTrimmed,
            key: "focused_project_recent_dialogue_recovery",
            counterKey: "focused_project_recent_dialogue_recovery",
            counts: &supportTrimmedFields
        )
        updateDialogueWindowSummary(
            &supportTrimmed,
            floorPairs: floorPairs,
            markTruncated: !supportTrimmedFields.isEmpty
        )
        candidates.append((
            "drop_supporting_context_before_raw_floor",
            totalDroppedCount(supportTrimmedFields),
            supportTrimmedFields,
            supportTrimmed
        ))

        var floorTrimmed = supportTrimmed
        var floorTrimmedFields = supportTrimmedFields
        trimBlockLinesFromTail(
            &floorTrimmed,
            key: "raw_messages",
            maxLines: floorRawMessages,
            counterKey: "raw_messages_items",
            counts: &floorTrimmedFields
        )
        updateDialogueWindowSummary(
            &floorTrimmed,
            floorPairs: floorPairs,
            markTruncated: !floorTrimmedFields.isEmpty
        )
        candidates.append((
            "keep_recent_raw_floor",
            totalDroppedCount(floorTrimmedFields),
            floorTrimmedFields,
            floorTrimmed
        ))

        var coreFloor = floorTrimmed
        var coreFloorFields = floorTrimmedFields
        keepOnlyBlocks(
            &coreFloor,
            keys: [
                "window_profile",
                "raw_window_floor_pairs",
                "raw_window_ceiling_pairs",
                "raw_window_selected_pairs",
                "eligible_messages",
                "low_signal_dropped_messages",
                "raw_window_source",
                "continuity_floor_satisfied",
                "truncation_after_floor",
                "raw_messages",
            ],
            counts: &coreFloorFields
        )
        updateDialogueWindowSummary(
            &coreFloor,
            floorPairs: floorPairs,
            markTruncated: !coreFloorFields.isEmpty
        )
        candidates.append((
            "keep_core_metadata_and_recent_raw_floor",
            totalDroppedCount(coreFloorFields),
            coreFloorFields,
            coreFloor
        ))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(coreFloor),
            budgetTokens: budgetTokens,
            reason: "clip_core_recent_raw_floor",
            droppedItems: totalDroppedCount(coreFloorFields),
            droppedFields: coreFloorFields
        )
    }

    static func compressPortfolioBriefObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "managed_projects",
            "active_projects",
            "blocked_projects",
            "focus_candidate_project",
            "priority_order",
            "top_blocked_projects",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var droppedFields: [String: Int] = [:]
        let droppedPriority4 = trimBlockLines(&trimmed, key: "priority_order", maxLines: 4, counterKey: "priority_order_items", counts: &droppedFields)
        let droppedBlocked2 = trimBlockLines(&trimmed, key: "top_blocked_projects", maxLines: 2, counterKey: "top_blocked_projects_items", counts: &droppedFields)
        candidates.append(("drop_tail_items", droppedPriority4 + droppedBlocked2, droppedFields, trimmed))

        var tight = parsed
        var tightFields: [String: Int] = [:]
        let droppedPriority2 = trimBlockLines(&tight, key: "priority_order", maxLines: 2, counterKey: "priority_order_items", counts: &tightFields)
        let droppedBlocked1 = trimBlockLines(&tight, key: "top_blocked_projects", maxLines: 1, counterKey: "top_blocked_projects_items", counts: &tightFields)
        candidates.append(("drop_tail_items", droppedPriority2 + droppedBlocked1, tightFields, tight))

        var noBlocked = tight
        var noBlockedFields = tightFields
        dropBlock(&noBlocked, key: "top_blocked_projects", counterKey: "top_blocked_projects", counts: &noBlockedFields)
        candidates.append(("drop_tail_items_and_fields", droppedPriority2 + droppedBlocked1, noBlockedFields, noBlocked))

        var summaryOnly = parsed
        var summaryFields: [String: Int] = [:]
        keepOnlyBlocks(
            &summaryOnly,
            keys: [
                "managed_projects",
                "active_projects",
                "blocked_projects",
                "focus_candidate_project",
            ],
            counts: &summaryFields
        )
        candidates.append(("keep_summary_only", 0, summaryFields, summaryOnly))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(summaryOnly),
            budgetTokens: budgetTokens,
            reason: "clip_summary_only",
            droppedItems: 0,
            droppedFields: summaryFields
        )
    }

    static func compressFocusedProjectAnchorPackObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "focus_source",
            "project",
            "memory_source",
            "runtime_state",
            "goal",
            "done_definition",
            "constraints",
            "approved_decisions",
            "longterm_outline",
            "background_hints",
            "governance",
            "latest_review_note",
            "latest_guidance_injection",
            "pending_ack_guidance",
            "missing_anchor_fields",
            "current_state",
            "next_step",
            "blocker",
            "active_job_id",
            "active_job_goal",
            "active_job_status",
            "active_plan_id",
            "active_plan_status",
            "active_plan_steps",
            "next_pending_steps",
            "attention_steps",
            "active_skill_request_id",
            "active_skill_id",
            "active_skill_status",
            "active_skill_result_summary",
            "recent_relevant_messages",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var trimmedFields: [String: Int] = [:]
        let trimmedItems =
            trimBlockLines(&trimmed, key: "constraints", maxLines: 3, counterKey: "constraints_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "approved_decisions", maxLines: 2, counterKey: "approved_decisions_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "longterm_outline", maxLines: 6, counterKey: "longterm_outline_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "latest_review_note", maxLines: 4, counterKey: "latest_review_note_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "latest_guidance_injection", maxLines: 4, counterKey: "latest_guidance_injection_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "pending_ack_guidance", maxLines: 4, counterKey: "pending_ack_guidance_lines", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "active_plan_steps", maxLines: 3, counterKey: "active_plan_steps_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "next_pending_steps", maxLines: 2, counterKey: "next_pending_steps_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "attention_steps", maxLines: 2, counterKey: "attention_steps_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_relevant_messages", maxLines: 2, counterKey: "recent_relevant_messages_items", counts: &trimmedFields)
        candidates.append(("trim_low_priority_blocks", trimmedItems, trimmedFields, trimmed))

        var reduced = trimmed
        var reducedFields = trimmedFields
        dropBlock(&reduced, key: "background_hints", counterKey: "background_hints", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_request_id", counterKey: "active_skill_request_id", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_id", counterKey: "active_skill_id", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_status", counterKey: "active_skill_status", counts: &reducedFields)
        dropBlock(&reduced, key: "active_skill_result_summary", counterKey: "active_skill_result_summary", counts: &reducedFields)
        dropBlock(&reduced, key: "recent_relevant_messages", counterKey: "recent_relevant_messages", counts: &reducedFields)
        candidates.append(("trim_and_drop_low_priority_fields", trimmedItems, reducedFields, reduced))

        var coreish = reduced
        var coreishFields = reducedFields
        dropBlock(&coreish, key: "latest_guidance_injection", counterKey: "latest_guidance_injection", counts: &coreishFields)
        dropBlock(&coreish, key: "pending_ack_guidance", counterKey: "pending_ack_guidance", counts: &coreishFields)
        dropBlock(&coreish, key: "governance", counterKey: "governance", counts: &coreishFields)
        dropBlock(&coreish, key: "active_plan_steps", counterKey: "active_plan_steps", counts: &coreishFields)
        dropBlock(&coreish, key: "attention_steps", counterKey: "attention_steps", counts: &coreishFields)
        trimBlockLines(&coreish, key: "next_pending_steps", maxLines: 1, counterKey: "next_pending_steps_items", counts: &coreishFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, coreishFields, coreish))

        var core = coreish
        var coreFields = coreishFields
        dropBlock(&core, key: "longterm_outline", counterKey: "longterm_outline", counts: &coreFields)
        dropBlock(&core, key: "latest_review_note", counterKey: "latest_review_note", counts: &coreFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, coreFields, core))

        var coreOnly = parsed
        var coreOnlyFields: [String: Int] = [:]
        keepOnlyBlocks(
            &coreOnly,
            keys: [
                "focus_source",
                "project",
                "memory_source",
                "runtime_state",
                "goal",
                "done_definition",
                "constraints",
                "approved_decisions",
                "missing_anchor_fields",
                "current_state",
                "next_step",
                "blocker",
                "active_job_id",
                "active_job_goal",
                "active_job_status",
                "active_plan_id",
                "active_plan_status",
                "next_pending_steps",
            ],
            counts: &coreOnlyFields
        )
        trimBlockLines(&coreOnly, key: "constraints", maxLines: 2, counterKey: "constraints_items", counts: &coreOnlyFields)
        trimBlockLines(&coreOnly, key: "approved_decisions", maxLines: 1, counterKey: "approved_decisions_items", counts: &coreOnlyFields)
        trimBlockLines(&coreOnly, key: "next_pending_steps", maxLines: 1, counterKey: "next_pending_steps_items", counts: &coreOnlyFields)
        candidates.append(("keep_core_anchor_only", 0, coreOnlyFields, coreOnly))

        var minimalCore = parsed
        var minimalCoreFields: [String: Int] = [:]
        keepOnlyBlocks(
            &minimalCore,
            keys: [
                "project",
                "goal",
                "done_definition",
                "constraints",
                "approved_decisions",
                "current_state",
                "next_step",
                "blocker",
            ],
            counts: &minimalCoreFields
        )
        trimBlockLines(&minimalCore, key: "constraints", maxLines: 1, counterKey: "constraints_items", counts: &minimalCoreFields)
        trimBlockLines(&minimalCore, key: "approved_decisions", maxLines: 1, counterKey: "approved_decisions_items", counts: &minimalCoreFields)
        candidates.append(("keep_minimal_anchor_only", 0, minimalCoreFields, minimalCore))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(minimalCore),
            budgetTokens: budgetTokens,
            reason: "clip_minimal_anchor_only",
            droppedItems: 0,
            droppedFields: minimalCoreFields
        )
    }

    static func compressLongtermOutlineObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "project",
            "goal",
            "done_definition",
            "stable_constraints",
            "strategic_milestones",
            "durable_decisions",
            "background_memory",
            "source_tags",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var trimmedFields: [String: Int] = [:]
        let trimmedItems =
            trimBlockLines(&trimmed, key: "stable_constraints", maxLines: 2, counterKey: "stable_constraints_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "strategic_milestones", maxLines: 2, counterKey: "strategic_milestones_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "durable_decisions", maxLines: 2, counterKey: "durable_decisions_items", counts: &trimmedFields)
        candidates.append(("drop_tail_items", trimmedItems, trimmedFields, trimmed))

        var compact = trimmed
        var compactFields = trimmedFields
        trimBlockLines(&compact, key: "stable_constraints", maxLines: 1, counterKey: "stable_constraints_items", counts: &compactFields)
        trimBlockLines(&compact, key: "strategic_milestones", maxLines: 1, counterKey: "strategic_milestones_items", counts: &compactFields)
        trimBlockLines(&compact, key: "durable_decisions", maxLines: 1, counterKey: "durable_decisions_items", counts: &compactFields)
        dropBlock(&compact, key: "source_tags", counterKey: "source_tags", counts: &compactFields)
        candidates.append(("drop_tail_items_and_fields", trimmedItems, compactFields, compact))

        var noBackground = compact
        var noBackgroundFields = compactFields
        dropBlock(&noBackground, key: "background_memory", counterKey: "background_memory", counts: &noBackgroundFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, noBackgroundFields, noBackground))

        var coreOnly = parsed
        var coreOnlyFields: [String: Int] = [:]
        keepOnlyBlocks(
            &coreOnly,
            keys: [
                "project",
                "goal",
                "done_definition",
                "stable_constraints",
                "strategic_milestones",
            ],
            counts: &coreOnlyFields
        )
        trimBlockLines(&coreOnly, key: "stable_constraints", maxLines: 1, counterKey: "stable_constraints_items", counts: &coreOnlyFields)
        trimBlockLines(&coreOnly, key: "strategic_milestones", maxLines: 1, counterKey: "strategic_milestones_items", counts: &coreOnlyFields)
        candidates.append(("keep_core_longterm_only", 0, coreOnlyFields, coreOnly))

        var minimal = parsed
        var minimalFields: [String: Int] = [:]
        keepOnlyBlocks(
            &minimal,
            keys: ["project", "goal", "done_definition"],
            counts: &minimalFields
        )
        candidates.append(("keep_minimal_longterm_only", 0, minimalFields, minimal))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(minimal),
            budgetTokens: budgetTokens,
            reason: "clip_minimal_longterm_only",
            droppedItems: 0,
            droppedFields: minimalFields
        )
    }

    static func compressDeltaFeedObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let keys = [
            "cursor_from",
            "cursor_to",
            "focus_project",
            "focus_project_id",
            "project_state_hash_before",
            "project_state_hash_after",
            "portfolio_state_hash_before",
            "portfolio_state_hash_after",
            "material_change_flags",
            "user_intent_hint",
            "delta_items",
            "focused_project_delta",
            "workflow_delta",
            "recent_project_actions",
            "recent_events",
            "recent_actions",
        ]
        let parsed = parseKnownBlocks(clean, keys: keys)
        guard !parsed.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        var candidates: [(String, Int, [String: Int], [LabeledBlock])] = []

        var trimmed = parsed
        var trimmedFields: [String: Int] = [:]
        let trimmedItems =
            trimBlockLines(&trimmed, key: "delta_items", maxLines: 4, counterKey: "delta_items", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_project_actions", maxLines: 2, counterKey: "recent_project_actions", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_events", maxLines: 2, counterKey: "recent_events", counts: &trimmedFields) +
            trimBlockLines(&trimmed, key: "recent_actions", maxLines: 2, counterKey: "recent_actions", counts: &trimmedFields)
        candidates.append(("drop_tail_items", trimmedItems, trimmedFields, trimmed))

        var reduced = trimmed
        var reducedFields = trimmedFields
        dropBlock(&reduced, key: "recent_events", counterKey: "recent_events", counts: &reducedFields)
        dropBlock(&reduced, key: "recent_actions", counterKey: "recent_actions", counts: &reducedFields)
        candidates.append(("drop_tail_items_and_fields", trimmedItems, reducedFields, reduced))

        var coreish = reduced
        var coreishFields = reducedFields
        dropBlock(&coreish, key: "recent_project_actions", counterKey: "recent_project_actions", counts: &coreishFields)
        dropBlock(&coreish, key: "focused_project_delta", counterKey: "focused_project_delta", counts: &coreishFields)
        dropBlock(&coreish, key: "workflow_delta", counterKey: "workflow_delta", counts: &coreishFields)
        trimBlockLines(&coreish, key: "delta_items", maxLines: 3, counterKey: "delta_items", counts: &coreishFields)
        candidates.append(("drop_low_priority_fields", trimmedItems, coreishFields, coreish))

        var core = parsed
        var coreFields: [String: Int] = [:]
        keepOnlyBlocks(
            &core,
            keys: [
                "cursor_from",
                "cursor_to",
                "focus_project",
                "focus_project_id",
                "project_state_hash_before",
                "project_state_hash_after",
                "portfolio_state_hash_before",
                "portfolio_state_hash_after",
                "material_change_flags",
                "user_intent_hint",
                "delta_items",
            ],
            counts: &coreFields
        )
        trimBlockLines(&core, key: "delta_items", maxLines: 2, counterKey: "delta_items", counts: &coreFields)
        candidates.append(("keep_core_delta_only", 0, coreFields, core))

        var minimal = parsed
        var minimalFields: [String: Int] = [:]
        keepOnlyBlocks(
            &minimal,
            keys: [
                "cursor_from",
                "cursor_to",
                "focus_project_id",
                "project_state_hash_before",
                "project_state_hash_after",
                "portfolio_state_hash_before",
                "portfolio_state_hash_after",
                "material_change_flags",
                "delta_items",
            ],
            counts: &minimalFields
        )
        trimBlockLines(&minimal, key: "delta_items", maxLines: 1, counterKey: "delta_items", counts: &minimalFields)
        candidates.append(("keep_minimal_delta_only", 0, minimalFields, minimal))

        return firstFittingServingObjectCandidate(
            candidates,
            budgetTokens: budgetTokens
        ) ?? clippedServingObjectFallback(
            renderBlocks(minimal),
            budgetTokens: budgetTokens,
            reason: "clip_minimal_delta_only",
            droppedItems: 0,
            droppedFields: minimalFields
        )
    }

    private static func firstFittingServingObjectCandidate(
        _ candidates: [(String, Int, [String: Int], [LabeledBlock])],
        budgetTokens: Int
    ) -> ServingObjectCompressionResult? {
        for candidate in candidates {
            let text = compressionCandidate(
                reason: candidate.0,
                droppedItems: candidate.1,
                droppedFields: candidate.2,
                payload: renderBlocks(candidate.3)
            )
            if estimateTokens(text) <= budgetTokens {
                return ServingObjectCompressionResult(text: text, truncated: true)
            }
        }
        return nil
    }

    private static func clippedServingObjectFallback(
        _ payload: String,
        budgetTokens: Int,
        reason: String,
        droppedItems: Int,
        droppedFields: [String: Int]
    ) -> ServingObjectCompressionResult {
        let header = compressionHeader(
            reason: reason,
            droppedItems: droppedItems,
            droppedFields: droppedFields
        )
        let available = max(8, budgetTokens - estimateTokens(header) - 1)
        let clipped = clip(payload, budgetTokens: available, preferTail: false)
        let text = compressionCandidate(
            reason: reason,
            droppedItems: droppedItems,
            droppedFields: droppedFields,
            payload: clipped.text
        )
        return ServingObjectCompressionResult(text: text, truncated: true)
    }

    private static func parseKnownBlocks(
        _ text: String,
        keys: [String]
    ) -> [LabeledBlock] {
        let allowed = Set(keys)
        let lines = normalized(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [LabeledBlock] = []
        var current: LabeledBlock?

        func flush() {
            if let current {
                blocks.append(current)
            }
        }

        for line in lines {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                if allowed.contains(key) {
                    flush()
                    let remainder = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    current = LabeledBlock(
                        key: key,
                        valueLines: remainder.isEmpty ? [] : [remainder],
                        inline: !remainder.isEmpty
                    )
                    continue
                }
            }
            if current == nil {
                continue
            }
            current?.inline = false
            current?.valueLines.append(line)
        }

        flush()
        return blocks
    }

    private static func renderBlocks(_ blocks: [LabeledBlock]) -> String {
        normalized(
            blocks.map { $0.render() }.joined(separator: "\n")
        )
    }

    private static func parsedInlineValue(
        _ blocks: [LabeledBlock],
        key: String
    ) -> String? {
        guard let block = blocks.first(where: { $0.key == key }) else { return nil }
        guard block.inline else { return nil }
        let value = block.valueLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func parsedInlineIntValue(
        _ blocks: [LabeledBlock],
        key: String
    ) -> Int? {
        guard let raw = parsedInlineValue(blocks, key: key) else { return nil }
        return Int(raw)
    }

    private static func setInlineBlockValue(
        _ blocks: inout [LabeledBlock],
        key: String,
        value: String
    ) {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else { return }
        if let index = blocks.firstIndex(where: { $0.key == key }) {
            blocks[index].inline = true
            blocks[index].valueLines = [normalizedValue]
            return
        }
        blocks.append(
            LabeledBlock(
                key: key,
                valueLines: [normalizedValue],
                inline: true
            )
        )
    }

    private static func blockLineCount(
        _ blocks: [LabeledBlock],
        key: String
    ) -> Int {
        guard let block = blocks.first(where: { $0.key == key }) else { return 0 }
        return block.inline ? min(block.valueLines.count, 1) : block.valueLines.count
    }

    private static func updateDialogueWindowSummary(
        _ blocks: inout [LabeledBlock],
        floorPairs: Int,
        markTruncated: Bool
    ) {
        let rawMessageCount = blockLineCount(blocks, key: "raw_messages")
        let selectedPairs = Int(ceil(Double(max(0, rawMessageCount)) / 2.0))
        setInlineBlockValue(
            &blocks,
            key: "raw_window_selected_pairs",
            value: String(selectedPairs)
        )
        setInlineBlockValue(
            &blocks,
            key: "eligible_messages",
            value: String(rawMessageCount)
        )
        setInlineBlockValue(
            &blocks,
            key: "continuity_floor_satisfied",
            value: rawMessageCount >= floorPairs * 2 ? "true" : "false"
        )
        if markTruncated {
            setInlineBlockValue(
                &blocks,
                key: "truncation_after_floor",
                value: "true"
            )
        }
    }

    private static func totalDroppedCount(_ counts: [String: Int]) -> Int {
        counts.values.reduce(0, +)
    }

    @discardableResult
    private static func trimBlockLines(
        _ blocks: inout [LabeledBlock],
        key: String,
        maxLines: Int,
        counterKey: String,
        counts: inout [String: Int]
    ) -> Int {
        guard let index = blocks.firstIndex(where: { $0.key == key }) else { return 0 }
        guard !blocks[index].inline else { return 0 }
        let lines = blocks[index].valueLines
        guard lines.count > maxLines else { return 0 }
        let dropped = max(0, lines.count - maxLines)
        blocks[index].valueLines = Array(lines.prefix(maxLines))
        counts[counterKey, default: 0] += dropped
        return dropped
    }

    @discardableResult
    private static func trimBlockLinesFromTail(
        _ blocks: inout [LabeledBlock],
        key: String,
        maxLines: Int,
        counterKey: String,
        counts: inout [String: Int]
    ) -> Int {
        guard let index = blocks.firstIndex(where: { $0.key == key }) else { return 0 }
        guard !blocks[index].inline else { return 0 }
        let lines = blocks[index].valueLines
        guard lines.count > maxLines else { return 0 }
        let dropped = max(0, lines.count - maxLines)
        blocks[index].valueLines = Array(lines.suffix(maxLines))
        counts[counterKey, default: 0] += dropped
        return dropped
    }

    @discardableResult
    private static func trimBlockLines(
        _ blocks: inout [LabeledBlock],
        key: String,
        maxLines: Int,
        counterKey: String
    ) -> Int {
        var counts: [String: Int] = [:]
        return trimBlockLines(&blocks, key: key, maxLines: maxLines, counterKey: counterKey, counts: &counts)
    }

    private static func dropBlock(
        _ blocks: inout [LabeledBlock],
        key: String,
        counterKey: String,
        counts: inout [String: Int]
    ) {
        guard let index = blocks.firstIndex(where: { $0.key == key }) else { return }
        blocks.remove(at: index)
        counts[counterKey, default: 0] += 1
    }

    private static func keepOnlyBlocks(
        _ blocks: inout [LabeledBlock],
        keys: [String],
        counts: inout [String: Int]
    ) {
        let allowed = Set(keys)
        let removed = blocks.filter { !allowed.contains($0.key) }
        for block in removed {
            counts[block.key, default: 0] += 1
        }
        blocks = blocks.filter { allowed.contains($0.key) }
    }

    static func compressConflictSetObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let blocks = splitConflictBlocks(clean)
        guard !blocks.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        for keepCount in stride(from: blocks.count - 1, through: 1, by: -1) {
            let kept = Array(blocks.prefix(keepCount)).joined(separator: "\n")
            let candidate = compressionCandidate(
                reason: "drop_tail_conflicts",
                droppedItems: blocks.count - keepCount,
                droppedFields: [:],
                payload: kept
            )
            if estimateTokens(candidate) <= budgetTokens {
                return ServingObjectCompressionResult(text: candidate, truncated: true)
            }
        }

        let header = compressionHeader(
            reason: "drop_tail_conflicts_and_clip_conflict",
            droppedItems: max(0, blocks.count - 1),
            droppedFields: [:]
        )
        let available = max(8, budgetTokens - estimateTokens(header) - 1)
        let clipped = clip(blocks[0], budgetTokens: available, preferTail: false)
        let candidate = compressionCandidate(
            reason: "drop_tail_conflicts_and_clip_conflict",
            droppedItems: max(0, blocks.count - 1),
            droppedFields: [:],
            payload: clipped.text
        )
        return ServingObjectCompressionResult(
            text: candidate,
            truncated: true || clipped.truncated
        )
    }

    static func compressContextRefsObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        let items = parseContextRefLines(clean)
        guard !items.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        let noFreshnessFields = ["freshness_hint": items.count]
        let noFreshness = items.map {
            $0.render(includeTokenCostHint: true, includeFreshnessHint: false)
        }.joined(separator: "\n")
        let noFreshnessCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: noFreshnessFields,
            payload: noFreshness
        )
        if estimateTokens(noFreshnessCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: noFreshnessCandidate, truncated: true)
        }

        let compactFields = [
            "freshness_hint": items.count,
            "token_cost_hint": items.count,
        ]
        let compactLines = items.map {
            $0.render(includeTokenCostHint: false, includeFreshnessHint: false)
        }
        let compactPayload = compactLines.joined(separator: "\n")
        let compactCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: compactFields,
            payload: compactPayload
        )
        if estimateTokens(compactCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: compactCandidate, truncated: true)
        }

        for keepCount in stride(from: compactLines.count, through: 1, by: -1) {
            let candidate = compressionCandidate(
                reason: "drop_low_priority_fields_and_tail_refs",
                droppedItems: compactLines.count - keepCount,
                droppedFields: [
                    "freshness_hint": keepCount,
                    "token_cost_hint": keepCount,
                ],
                payload: Array(compactLines.prefix(keepCount)).joined(separator: "\n")
            )
            if estimateTokens(candidate) <= budgetTokens {
                return ServingObjectCompressionResult(text: candidate, truncated: true)
            }
        }

        let header = compressionHeader(
            reason: "drop_low_priority_fields_and_clip_ref",
            droppedItems: max(0, compactLines.count - 1),
            droppedFields: compactFields
        )
        let available = max(8, budgetTokens - estimateTokens(header) - 1)
        let clipped = clip(compactLines[0], budgetTokens: available, preferTail: false)
        let candidate = compressionCandidate(
            reason: "drop_low_priority_fields_and_clip_ref",
            droppedItems: max(0, compactLines.count - 1),
            droppedFields: compactFields,
            payload: clipped.text
        )
        return ServingObjectCompressionResult(
            text: candidate,
            truncated: true || clipped.truncated
        )
    }

    static func compressEvidencePackObject(
        _ text: String,
        budgetTokens: Int
    ) -> ServingObjectCompressionResult {
        let clean = normalized(text)
        guard !clean.isEmpty else {
            return ServingObjectCompressionResult(text: "", truncated: false)
        }
        guard budgetTokens > 0 else {
            return ServingObjectCompressionResult(text: "", truncated: true)
        }
        if estimateTokens(clean) <= budgetTokens {
            return ServingObjectCompressionResult(text: clean, truncated: false)
        }

        guard let pack = parseEvidencePackBody(clean), !pack.items.isEmpty else {
            let clipped = clip(clean, budgetTokens: budgetTokens, preferTail: false)
            return ServingObjectCompressionResult(text: clipped.text, truncated: clipped.truncated)
        }

        let dropFreshnessFields = ["freshness": pack.items.count]
        let noFreshnessBody = renderEvidencePackBody(
            pack,
            items: pack.items,
            includeFreshness: false,
            includeExcerpt: true
        )
        let noFreshnessCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: dropFreshnessFields,
            payload: noFreshnessBody
        )
        if estimateTokens(noFreshnessCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: noFreshnessCandidate, truncated: true)
        }

        let compactFields = [
            "freshness": pack.items.count,
            "excerpt": pack.items.count,
        ]
        let compactBody = renderEvidencePackBody(
            pack,
            items: pack.items,
            includeFreshness: false,
            includeExcerpt: false
        )
        let compactCandidate = compressionCandidate(
            reason: "drop_low_priority_fields",
            droppedItems: 0,
            droppedFields: compactFields,
            payload: compactBody
        )
        if estimateTokens(compactCandidate) <= budgetTokens {
            return ServingObjectCompressionResult(text: compactCandidate, truncated: true)
        }

        for keepCount in stride(from: pack.items.count, through: 1, by: -1) {
            let keptItems = Array(pack.items.prefix(keepCount))
            let candidate = compressionCandidate(
                reason: "drop_low_priority_fields_and_tail_evidence",
                droppedItems: pack.items.count - keepCount,
                droppedFields: [
                    "freshness": keepCount,
                    "excerpt": keepCount,
                ],
                payload: renderEvidencePackBody(
                    pack,
                    items: keptItems,
                    includeFreshness: false,
                    includeExcerpt: false
                )
            )
            if estimateTokens(candidate) <= budgetTokens {
                return ServingObjectCompressionResult(text: candidate, truncated: true)
            }
        }

        let compactFirst = pack.items[0].render(includeFreshness: false, includeExcerpt: false)
        let header = compressionHeader(
            reason: "drop_low_priority_fields_and_clip_evidence_item",
            droppedItems: max(0, pack.items.count - 1),
            droppedFields: compactFields
        )
        let skeleton = renderEvidencePackBody(
            pack,
            items: [],
            includeFreshness: false,
            includeExcerpt: false
        )
        let staticBudget = estimateTokens(header) + estimateTokens(skeleton.replacingOccurrences(of: "selected_items:", with: ""))
        let available = max(8, budgetTokens - staticBudget)
        let clipped = clip(compactFirst, budgetTokens: available, preferTail: false)
        let candidate = compressionCandidate(
            reason: "drop_low_priority_fields_and_clip_evidence_item",
            droppedItems: max(0, pack.items.count - 1),
            droppedFields: compactFields,
            payload: renderEvidencePackBody(
                pack,
                items: [
                    EvidencePackItem(
                        refId: "",
                        title: "",
                        sourceScope: "",
                        freshness: "",
                        whyIncluded: "",
                        excerpt: clipped.text
                    )
                ],
                includeFreshness: false,
                includeExcerpt: false,
                overrideFirstRenderedLine: clipped.text
            )
        )
        return ServingObjectCompressionResult(
            text: candidate,
            truncated: true || clipped.truncated
        )
    }

    private static func compressionHeader(
        reason: String,
        droppedItems: Int,
        droppedFields: [String: Int]
    ) -> String {
        """
compression_reason: \(reason)
dropped_items: \(max(0, droppedItems))
dropped_fields: \(droppedFieldsSummary(droppedFields))
"""
    }

    private static func compressionCandidate(
        reason: String,
        droppedItems: Int,
        droppedFields: [String: Int],
        payload: String
    ) -> String {
        let header = compressionHeader(
            reason: reason,
            droppedItems: droppedItems,
            droppedFields: droppedFields
        )
        let normalizedPayload = normalized(payload)
        guard !normalizedPayload.isEmpty else { return header }
        return "\(header)\n\(normalizedPayload)"
    }

    private static func droppedFieldsSummary(_ droppedFields: [String: Int]) -> String {
        let nonZero = droppedFields
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in lhs.key < rhs.key }
        guard !nonZero.isEmpty else { return "0" }
        return nonZero
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static func splitConflictBlocks(_ text: String) -> [String] {
        let lines = normalized(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var blocks: [String] = []
        var current: [String] = []

        for line in lines {
            if line.hasPrefix("- conflict_id:"), !current.isEmpty {
                blocks.append(normalized(current.joined(separator: "\n")))
                current = [line]
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            blocks.append(normalized(current.joined(separator: "\n")))
        }
        return blocks.filter { !$0.isEmpty }
    }

    private static func parseContextRefLines(_ text: String) -> [ContextRefLine] {
        normalized(text)
            .split(separator: "\n")
            .compactMap { parseContextRefLine(String($0)) }
    }

    private static func parseContextRefLine(_ line: String) -> ContextRefLine? {
        guard line.hasPrefix("- ref_id=") else { return nil }
        guard
            let refId = inlineField(line, after: "ref_id=", before: " ref_kind="),
            let refKind = inlineField(line, after: "ref_kind=", before: " title="),
            let title = inlineField(line, after: "title=", before: " source_scope="),
            let sourceScope = inlineField(line, after: "source_scope=", before: " token_cost_hint="),
            let tokenCostHint = inlineField(line, after: "token_cost_hint=", before: " freshness_hint="),
            let freshnessHint = inlineField(line, after: "freshness_hint=", before: nil)
        else {
            return nil
        }
        return ContextRefLine(
            refId: refId,
            refKind: refKind,
            title: title,
            sourceScope: sourceScope,
            tokenCostHint: tokenCostHint,
            freshnessHint: freshnessHint
        )
    }

    private static func parseEvidencePackBody(_ text: String) -> EvidencePackBody? {
        let lines = normalized(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var evidenceGoal = ""
        var items: [EvidencePackItem] = []
        var truncatedItems = 0
        var redactedItems = 0
        var auditRef = ""

        for line in lines {
            if line.hasPrefix("evidence_goal: ") {
                evidenceGoal = String(line.dropFirst("evidence_goal: ".count))
            } else if line.hasPrefix("- ref_id=") {
                if let item = parseEvidencePackItem(line) {
                    items.append(item)
                }
            } else if line.hasPrefix("truncated_items: ") {
                truncatedItems = Int(line.dropFirst("truncated_items: ".count)) ?? 0
            } else if line.hasPrefix("redacted_items: ") {
                redactedItems = Int(line.dropFirst("redacted_items: ".count)) ?? 0
            } else if line.hasPrefix("audit_ref: ") {
                auditRef = String(line.dropFirst("audit_ref: ".count))
            }
        }

        guard !evidenceGoal.isEmpty || !items.isEmpty || !auditRef.isEmpty else { return nil }
        return EvidencePackBody(
            evidenceGoal: evidenceGoal,
            items: items,
            truncatedItems: truncatedItems,
            redactedItems: redactedItems,
            auditRef: auditRef
        )
    }

    private static func parseEvidencePackItem(_ line: String) -> EvidencePackItem? {
        guard line.hasPrefix("- ref_id=") else { return nil }
        guard
            let refId = inlineField(line, after: "ref_id=", before: " title="),
            let title = inlineField(line, after: "title=", before: " source_scope="),
            let sourceScope = inlineField(line, after: "source_scope=", before: " freshness="),
            let freshness = inlineField(line, after: "freshness=", before: " why_included="),
            let whyIncluded = inlineField(line, after: "why_included=", before: " excerpt="),
            let excerpt = inlineField(line, after: "excerpt=", before: nil)
        else {
            return nil
        }
        return EvidencePackItem(
            refId: refId,
            title: title,
            sourceScope: sourceScope,
            freshness: freshness,
            whyIncluded: whyIncluded,
            excerpt: excerpt
        )
    }

    private static func renderEvidencePackBody(
        _ body: EvidencePackBody,
        items: [EvidencePackItem],
        includeFreshness: Bool,
        includeExcerpt: Bool,
        overrideFirstRenderedLine: String? = nil
    ) -> String {
        var lines: [String] = [
            "evidence_goal: \(body.evidenceGoal)",
            "selected_items:",
        ]

        if let overrideFirstRenderedLine {
            lines.append(overrideFirstRenderedLine)
            if items.count > 1 {
                lines.append(
                    contentsOf: items.dropFirst().map {
                        $0.render(includeFreshness: includeFreshness, includeExcerpt: includeExcerpt)
                    }
                )
            }
        } else {
            lines.append(
                contentsOf: items.map {
                    $0.render(includeFreshness: includeFreshness, includeExcerpt: includeExcerpt)
                }
            )
        }

        lines.append("truncated_items: \(body.truncatedItems)")
        lines.append("redacted_items: \(body.redactedItems)")
        lines.append("audit_ref: \(body.auditRef)")
        return normalized(lines.joined(separator: "\n"))
    }

    private static func inlineField(
        _ line: String,
        after startMarker: String,
        before endMarker: String?
    ) -> String? {
        guard let startRange = line.range(of: startMarker) else { return nil }
        let suffix = String(line[startRange.upperBound...])
        if let endMarker {
            guard let endRange = suffix.range(of: endMarker) else { return nil }
            return normalized(String(suffix[..<endRange.lowerBound]))
        }
        return normalized(suffix)
    }

}
