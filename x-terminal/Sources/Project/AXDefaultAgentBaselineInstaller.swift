import Foundation

enum AXAgentBaselineInstallScope: Equatable, Sendable {
    case global
    case project(projectId: String, projectName: String?)

    var hubScope: String {
        switch self {
        case .global:
            return "global"
        case .project:
            return "project"
        }
    }

    var projectId: String? {
        switch self {
        case .global:
            return nil
        case .project(let projectId, _):
            let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var displayLabel: String {
        switch self {
        case .global:
            return "Global"
        case .project(_, let projectName):
            let trimmed = (projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Current Project"
            }
            return "Project: \(trimmed)"
        }
    }

    var noteTag: String {
        switch self {
        case .global:
            return "xt_default_agent_baseline:global"
        case .project(let projectId, _):
            let suffix = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            return "xt_default_agent_baseline:project:\(suffix)"
        }
    }
}

struct AXSkillCanonicalCapabilitySemantics: Equatable, Sendable {
    var intentFamilies: [String]
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]
    var grantFloor: String
    var approvalFloor: String
}

struct AXDefaultAgentBaselineBundle: Equatable, Sendable, Identifiable {
    var bundleID: String
    var displayName: String
    var summary: String
    var skillIDs: [String]
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]

    var id: String { bundleID }
}

struct AXDefaultAgentBaselineInstallableCandidate: Equatable, Sendable, Identifiable {
    var skillID: String
    var displayName: String
    var version: String
    var sourceID: String
    var packageSHA256: String
    var installHint: String
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]

    var id: String { "\(skillID)::\(packageSHA256)" }
}

struct AXDefaultAgentBaselineMissingPackage: Equatable, Sendable, Identifiable {
    var skillID: String
    var displayName: String
    var installHint: String
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]

    var id: String { skillID }
}

struct AXDefaultAgentBaselineBundlePlan: Equatable, Sendable, Identifiable {
    var bundle: AXDefaultAgentBaselineBundle
    var resolvedSkillIDs: [String]
    var installableCandidates: [AXDefaultAgentBaselineInstallableCandidate]
    var missingPackageSkills: [AXDefaultAgentBaselineMissingPackage]
    var targetCapabilityFamilies: [String]
    var targetCapabilityProfiles: [String]
    var availableCapabilityProfiles: [String]
    var deltaCapabilityProfiles: [String]
    var residualBlockedProfiles: [XTProjectEffectiveSkillBlockedProfile]

    var id: String { bundle.bundleID }
    var bundleID: String { bundle.bundleID }
    var displayName: String { bundle.displayName }
    var summary: String { bundle.summary }
    var ready: Bool { missingPackageSkills.isEmpty }
}

struct AXDefaultAgentBaselineInstallPlan: Equatable, Sendable {
    var scope: AXAgentBaselineInstallScope
    var totalBaselineCount: Int
    var alreadyResolvedSkillIDs: [String]
    var installableCandidates: [AXDefaultAgentBaselineInstallableCandidate]
    var missingPackageSkills: [AXDefaultAgentBaselineMissingPackage]
    var bundles: [AXDefaultAgentBaselineBundlePlan]
    var targetCapabilityProfiles: [String]
    var availableCapabilityProfiles: [String]
    var deltaCapabilityProfiles: [String]
    var residualBlockedProfiles: [XTProjectEffectiveSkillBlockedProfile]
}

enum AXDefaultAgentBaselineInstaller {
    static func makePlan(
        scope: AXAgentBaselineInstallScope,
        baseline: [AXDefaultAgentBaselineSkill],
        bundles: [AXDefaultAgentBaselineBundle],
        resolvedSkills: [HubIPCClient.ResolvedSkillEntry],
        searchResultsBySkillID: [String: [HubIPCClient.SkillCatalogEntry]],
        currentProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot? = nil
    ) -> AXDefaultAgentBaselineInstallPlan {
        let normalizedBaselineByID = Dictionary(
            uniqueKeysWithValues: baseline.map { item in
                (
                    normalizedSkillID(item.skillID),
                    AXDefaultAgentBaselineSkill(
                        skillID: item.skillID.trimmingCharacters(in: .whitespacesAndNewlines),
                        displayName: item.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        summary: item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }
        )

        let resolvedBySkillID = Dictionary(
            resolvedSkills.map { entry in
                (
                    normalizedSkillID(entry.skill.skillID),
                    entry
                )
            },
            uniquingKeysWith: { first, _ in first }
        )

        var alreadyResolved: [String] = []
        var installable: [AXDefaultAgentBaselineInstallableCandidate] = []
        var missingPackages: [AXDefaultAgentBaselineMissingPackage] = []
        var installableBySkillID: [String: AXDefaultAgentBaselineInstallableCandidate] = [:]
        var missingBySkillID: [String: AXDefaultAgentBaselineMissingPackage] = [:]
        var semanticsBySkillID: [String: AXSkillCanonicalCapabilitySemantics] = [:]

        for baselineSkill in baseline {
            let skillID = baselineSkill.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedID = normalizedSkillID(skillID)
            let searchResults = searchResultsForSkill(skillID: skillID, searchResultsBySkillID: searchResultsBySkillID)

            if let resolved = resolvedBySkillID[normalizedID] {
                alreadyResolved.append(skillID)
                semanticsBySkillID[normalizedID] = semantics(
                    skillID: skillID,
                    capabilitiesRequired: resolved.skill.capabilitiesRequired
                )
                continue
            }

            if let candidate = selectInstallableCandidate(skillID: skillID, searchResults: searchResults) {
                installable.append(candidate)
                installableBySkillID[normalizedID] = candidate
                semanticsBySkillID[normalizedID] = AXSkillCanonicalCapabilitySemantics(
                    intentFamilies: [],
                    capabilityFamilies: candidate.capabilityFamilies,
                    capabilityProfiles: candidate.capabilityProfiles,
                    grantFloor: XTSkillCapabilityProfileSupport.grantFloor(
                        for: candidate.capabilityFamilies,
                        requiresGrant: false,
                        riskLevel: ""
                    ),
                    approvalFloor: XTSkillCapabilityProfileSupport.approvalFloor(for: candidate.capabilityFamilies)
                )
                continue
            }

            let fallbackSemantics = semantics(
                skillID: skillID,
                capabilitiesRequired: bestCapabilitiesHint(searchResults: searchResults)
            )
            let fallbackHint = selectFallbackInstallHint(
                displayName: baselineSkill.displayName,
                baselineSummary: baselineSkill.summary,
                searchResults: searchResults
            )
            let missing = AXDefaultAgentBaselineMissingPackage(
                skillID: skillID,
                displayName: baselineSkill.displayName,
                installHint: fallbackHint,
                capabilityFamilies: fallbackSemantics.capabilityFamilies,
                capabilityProfiles: fallbackSemantics.capabilityProfiles
            )
            missingPackages.append(missing)
            missingBySkillID[normalizedID] = missing
            semanticsBySkillID[normalizedID] = fallbackSemantics
        }

        let bundlePlans = normalizedBundles(
            bundles,
            baselineSkillsByID: normalizedBaselineByID,
            semanticsBySkillID: semanticsBySkillID
        )
        .map { bundle in
            let normalizedSkillIDs = bundle.skillIDs.map(normalizedSkillID)
            let bundleResolved = normalizedSkillIDs.compactMap { resolvedBySkillID[$0]?.skill.skillID }
            let bundleInstallable = normalizedSkillIDs.compactMap { installableBySkillID[$0] }
            let bundleMissing = normalizedSkillIDs.compactMap { missingBySkillID[$0] }

            let skillFamilies = normalizedSkillIDs.flatMap {
                semanticsBySkillID[$0]?.capabilityFamilies ?? []
            }
            let skillProfiles = normalizedSkillIDs.flatMap {
                semanticsBySkillID[$0]?.capabilityProfiles ?? []
            }

            let targetFamilies = XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(
                bundle.capabilityFamilies + skillFamilies
            )
            let targetProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
                bundle.capabilityProfiles + skillProfiles
            )
            let availableProfiles = availableProfiles(
                resolvedSkillIDs: normalizedSkillIDs,
                resolvedBySkillID: resolvedBySkillID,
                installableBySkillID: installableBySkillID,
                semanticsBySkillID: semanticsBySkillID
            )
            let deltaProfiles = deltaProfiles(
                availableProfiles: availableProfiles,
                currentProfileSnapshot: currentProfileSnapshot
            )
            let residualBlocked = residualBlockedProfiles(
                targetProfiles: targetProfiles,
                availableProfiles: availableProfiles,
                currentProfileSnapshot: currentProfileSnapshot
            )

            return AXDefaultAgentBaselineBundlePlan(
                bundle: bundle,
                resolvedSkillIDs: bundleResolved.sorted(),
                installableCandidates: sortCandidates(bundleInstallable),
                missingPackageSkills: bundleMissing.sorted { lhs, rhs in
                    lhs.skillID.localizedStandardCompare(rhs.skillID) == .orderedAscending
                },
                targetCapabilityFamilies: targetFamilies,
                targetCapabilityProfiles: targetProfiles,
                availableCapabilityProfiles: availableProfiles,
                deltaCapabilityProfiles: deltaProfiles,
                residualBlockedProfiles: residualBlocked
            )
        }

        let allTargetProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
            bundlePlans.flatMap { $0.targetCapabilityProfiles }
        )
        let allAvailableProfiles = XTSkillCapabilityProfileSupport.orderedProfiles(
            bundlePlans.flatMap { $0.availableCapabilityProfiles }
        )
        let allDeltaProfiles = deltaProfiles(
            availableProfiles: allAvailableProfiles,
            currentProfileSnapshot: currentProfileSnapshot
        )
        let allResidualBlocked = residualBlockedProfiles(
            targetProfiles: allTargetProfiles,
            availableProfiles: allAvailableProfiles,
            currentProfileSnapshot: currentProfileSnapshot
        )

        return AXDefaultAgentBaselineInstallPlan(
            scope: scope,
            totalBaselineCount: baseline.count,
            alreadyResolvedSkillIDs: alreadyResolved.sorted(),
            installableCandidates: sortCandidates(installable),
            missingPackageSkills: missingPackages.sorted { lhs, rhs in
                lhs.skillID.localizedStandardCompare(rhs.skillID) == .orderedAscending
            },
            bundles: bundlePlans,
            targetCapabilityProfiles: allTargetProfiles,
            availableCapabilityProfiles: allAvailableProfiles,
            deltaCapabilityProfiles: allDeltaProfiles,
            residualBlockedProfiles: allResidualBlocked
        )
    }

    static func previewLines(
        plan: AXDefaultAgentBaselineInstallPlan,
        currentProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot?
    ) -> [String] {
        var lines: [String] = []
        if let currentProfileSnapshot {
            let currentActive = activeProfiles(from: currentProfileSnapshot)
            lines.append(
                currentActive.isEmpty
                    ? "Current active profiles: none"
                    : "Current active profiles: \(currentActive.joined(separator: ", "))"
            )
        } else {
            lines.append("Current active profiles: unavailable outside a project snapshot")
        }

        if !plan.targetCapabilityProfiles.isEmpty {
            lines.append("Bundle target profiles: \(plan.targetCapabilityProfiles.joined(separator: ", "))")
        }
        lines.append(
            plan.deltaCapabilityProfiles.isEmpty
                ? "Profile delta after install: none"
                : "Profile delta after install: \(plan.deltaCapabilityProfiles.joined(separator: ", "))"
        )

        if !plan.residualBlockedProfiles.isEmpty {
            let blocked = plan.residualBlockedProfiles.map(blockedProfileSummary).joined(separator: ", ")
            lines.append("Residual blocked profiles: \(blocked)")
        } else if currentProfileSnapshot != nil {
            lines.append("Residual blocked profiles: none")
        }

        for bundle in plan.bundles {
            let targetProfiles = bundle.targetCapabilityProfiles.isEmpty
                ? "none"
                : bundle.targetCapabilityProfiles.joined(separator: ", ")
            var parts: [String] = ["\(bundle.displayName) [\(bundle.bundleID)]", "profiles=\(targetProfiles)"]
            if !bundle.deltaCapabilityProfiles.isEmpty {
                parts.append("delta=\(bundle.deltaCapabilityProfiles.joined(separator: ", "))")
            }
            if !bundle.missingPackageSkills.isEmpty {
                parts.append("missing_pkg=\(bundle.missingPackageSkills.count)")
            } else if bundle.ready {
                parts.append("ready_to_pin")
            }
            lines.append(parts.joined(separator: " | "))
        }

        if !plan.missingPackageSkills.isEmpty {
            lines.append("Missing uploadable packages:")
            for item in plan.missingPackageSkills {
                let profiles = item.capabilityProfiles.isEmpty ? "" : " [\(item.capabilityProfiles.joined(separator: ", "))]"
                lines.append("- \(item.skillID)\(profiles): \(item.installHint)")
            }
        }

        return lines
    }

    private static func normalizedBundles(
        _ bundles: [AXDefaultAgentBaselineBundle],
        baselineSkillsByID: [String: AXDefaultAgentBaselineSkill],
        semanticsBySkillID: [String: AXSkillCanonicalCapabilitySemantics]
    ) -> [AXDefaultAgentBaselineBundle] {
        let baselineSkillIDs = Set(baselineSkillsByID.keys)
        var normalized: [AXDefaultAgentBaselineBundle] = bundles.compactMap { bundle in
            let skillIDs = XTSkillCapabilityProfileSupport.normalizedStrings(bundle.skillIDs)
                .filter { baselineSkillIDs.contains($0) }
            guard !skillIDs.isEmpty else { return nil }
            return AXDefaultAgentBaselineBundle(
                bundleID: bundle.bundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: bundle.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                summary: bundle.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                skillIDs: skillIDs,
                capabilityFamilies: XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(bundle.capabilityFamilies),
                capabilityProfiles: XTSkillCapabilityProfileSupport.orderedProfiles(bundle.capabilityProfiles)
            )
        }

        let coveredSkillIDs = Set(normalized.flatMap(\.skillIDs))
        let uncoveredSkillIDs = baselineSkillIDs.subtracting(coveredSkillIDs)
        if !uncoveredSkillIDs.isEmpty {
            let orderedSkillIDs = uncoveredSkillIDs.sorted()
            let families = XTSkillCapabilityProfileSupport.orderedCapabilityFamilies(
                orderedSkillIDs.flatMap { semanticsBySkillID[$0]?.capabilityFamilies ?? [] }
            )
            let profiles = XTSkillCapabilityProfileSupport.orderedProfiles(
                orderedSkillIDs.flatMap { semanticsBySkillID[$0]?.capabilityProfiles ?? [] }
            )
            normalized.append(
                AXDefaultAgentBaselineBundle(
                    bundleID: "baseline-misc",
                    displayName: "Baseline Misc",
                    summary: "Fallback bundle for baseline skills not yet assigned to a named product bundle.",
                    skillIDs: orderedSkillIDs,
                    capabilityFamilies: families,
                    capabilityProfiles: profiles
                )
            )
        }

        return normalized.sorted { lhs, rhs in
            lhs.bundleID.localizedStandardCompare(rhs.bundleID) == .orderedAscending
        }
    }

    private static func availableProfiles(
        resolvedSkillIDs: [String],
        resolvedBySkillID: [String: HubIPCClient.ResolvedSkillEntry],
        installableBySkillID: [String: AXDefaultAgentBaselineInstallableCandidate],
        semanticsBySkillID: [String: AXSkillCanonicalCapabilitySemantics]
    ) -> [String] {
        var profiles: [String] = []
        for skillID in resolvedSkillIDs {
            if resolvedBySkillID[skillID] != nil {
                profiles.append(contentsOf: semanticsBySkillID[skillID]?.capabilityProfiles ?? [])
            }
            if installableBySkillID[skillID] != nil {
                profiles.append(contentsOf: semanticsBySkillID[skillID]?.capabilityProfiles ?? [])
            }
        }
        return XTSkillCapabilityProfileSupport.orderedProfiles(profiles)
    }

    private static func deltaProfiles(
        availableProfiles: [String],
        currentProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot?
    ) -> [String] {
        guard let currentProfileSnapshot else {
            return XTSkillCapabilityProfileSupport.orderedProfiles(availableProfiles)
        }
        let currentActive = Set(activeProfiles(from: currentProfileSnapshot))
        return XTSkillCapabilityProfileSupport.orderedProfiles(
            availableProfiles.filter { !currentActive.contains($0) }
        )
    }

    private static func residualBlockedProfiles(
        targetProfiles: [String],
        availableProfiles: [String],
        currentProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot?
    ) -> [XTProjectEffectiveSkillBlockedProfile] {
        let targetSet = Set(XTSkillCapabilityProfileSupport.normalizedStrings(targetProfiles))
        let availableSet = Set(XTSkillCapabilityProfileSupport.normalizedStrings(availableProfiles))
        var blockedByProfile: [String: XTProjectEffectiveSkillBlockedProfile] = [:]

        if let currentProfileSnapshot {
            for blocked in currentProfileSnapshot.blockedProfiles {
                let profileID = blocked.profileID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard targetSet.contains(profileID) else { continue }
                if availableSet.contains(profileID) && installGapReasonCode(blocked.reasonCode, state: blocked.state) {
                    continue
                }
                blockedByProfile[profileID] = blocked
            }
        }

        for profileID in targetSet where !availableSet.contains(profileID) && blockedByProfile[profileID] == nil {
            blockedByProfile[profileID] = synthesizedNotInstalledBlock(
                profileID: profileID,
                currentProfileSnapshot: currentProfileSnapshot
            )
        }

        return XTSkillCapabilityProfileSupport.orderedProfiles(Array(blockedByProfile.keys))
            .compactMap { blockedByProfile[$0] }
    }

    private static func synthesizedNotInstalledBlock(
        profileID: String,
        currentProfileSnapshot: XTProjectEffectiveSkillProfileSnapshot?
    ) -> XTProjectEffectiveSkillBlockedProfile {
        let installableProfiles = Set(
            XTSkillCapabilityProfileSupport.normalizedStrings(
                currentProfileSnapshot?.installableProfiles ?? []
            )
        )
        let installable = installableProfiles.contains(profileID)
        return XTProjectEffectiveSkillBlockedProfile(
            profileID: profileID,
            reasonCode: installable ? "profile_not_resolved" : "profile_not_installable",
            state: XTSkillExecutionReadinessState.notInstalled.rawValue,
            source: installable ? "hub_skill_registry" : "hub_catalog",
            unblockActions: XTSkillCapabilityProfileSupport.unblockActions(
                for: .notInstalled,
                approvalFloor: XTSkillApprovalFloor.none.rawValue,
                requiredRuntimeSurfaces: []
            )
        )
    }

    private static func activeProfiles(
        from snapshot: XTProjectEffectiveSkillProfileSnapshot
    ) -> [String] {
        XTSkillCapabilityProfileSupport.orderedProfiles(
            snapshot.runnableNowProfiles
                + snapshot.requestableProfiles
                + snapshot.grantRequiredProfiles
                + snapshot.approvalRequiredProfiles
        )
    }

    private static func blockedProfileSummary(_ blocked: XTProjectEffectiveSkillBlockedProfile) -> String {
        let reason = blocked.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if reason.isEmpty {
            return blocked.profileID
        }
        return "\(blocked.profileID)=\(reason)"
    }

    private static func semantics(
        skillID: String,
        capabilitiesRequired: [String]
    ) -> AXSkillCanonicalCapabilitySemantics {
        AXSkillsLibrary.canonicalCapabilitySemantics(
            skillId: skillID,
            capabilitiesRequired: capabilitiesRequired
        )
    }

    private static func searchResultsForSkill(
        skillID: String,
        searchResultsBySkillID: [String: [HubIPCClient.SkillCatalogEntry]]
    ) -> [HubIPCClient.SkillCatalogEntry] {
        let normalizedID = normalizedSkillID(skillID)
        return searchResultsBySkillID[skillID]
            ?? searchResultsBySkillID[normalizedID]
            ?? []
    }

    private static func selectInstallableCandidate(
        skillID: String,
        searchResults: [HubIPCClient.SkillCatalogEntry]
    ) -> AXDefaultAgentBaselineInstallableCandidate? {
        let normalizedID = normalizedSkillID(skillID)
        let exactMatches = searchResults.filter { result in
            normalizedSkillID(result.skillID) == normalizedID
                && !result.packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let uploaded = exactMatches.sorted { lhs, rhs in
            let lhsOfficial = normalizedPublisherID(lhs.publisherID) == "xhub.official"
            let rhsOfficial = normalizedPublisherID(rhs.publisherID) == "xhub.official"
            if lhsOfficial != rhsOfficial {
                return lhsOfficial && !rhsOfficial
            }
            let versionOrder = lhs.version.compare(rhs.version, options: String.CompareOptions.numeric)
            if versionOrder != .orderedSame {
                return versionOrder == .orderedDescending
            }
            let sourceOrder = lhs.sourceID.localizedStandardCompare(rhs.sourceID)
            if sourceOrder != .orderedSame {
                return sourceOrder == .orderedAscending
            }
            return lhs.packageSHA256.localizedStandardCompare(rhs.packageSHA256) == .orderedAscending
        }.first

        guard let uploaded else { return nil }

        let displayName = uploaded.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            ? skillID
            : uploaded.name
        let semantics = AXSkillsLibrary.canonicalCapabilitySemantics(
            skillId: uploaded.skillID,
            capabilitiesRequired: uploaded.capabilitiesRequired
        )
        return AXDefaultAgentBaselineInstallableCandidate(
            skillID: uploaded.skillID,
            displayName: displayName,
            version: uploaded.version,
            sourceID: uploaded.sourceID,
            packageSHA256: uploaded.packageSHA256,
            installHint: uploaded.installHint,
            capabilityFamilies: semantics.capabilityFamilies,
            capabilityProfiles: semantics.capabilityProfiles
        )
    }

    private static func selectFallbackInstallHint(
        displayName: String,
        baselineSummary: String,
        searchResults: [HubIPCClient.SkillCatalogEntry]
    ) -> String {
        if let firstHint = searchResults
            .map(\.installHint)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return firstHint
        }

        let summary = baselineSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            return summary
        }
        return "\(displayName) is recommended for the default Agent baseline, but Hub has no uploadable package yet."
    }

    private static func bestCapabilitiesHint(
        searchResults: [HubIPCClient.SkillCatalogEntry]
    ) -> [String] {
        searchResults.first(where: {
            !$0.capabilitiesRequired.isEmpty
        })?.capabilitiesRequired ?? []
    }

    private static func normalizedSkillID(_ value: String) -> String {
        AXSkillsLibrary.canonicalSupervisorSkillID(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedPublisherID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func installGapReasonCode(_ reasonCode: String, state: String) -> Bool {
        let normalizedReason = reasonCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedState = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedState == XTSkillExecutionReadinessState.notInstalled.rawValue
            || normalizedReason == "profile_not_resolved"
            || normalizedReason == "profile_not_installable"
    }

    private static func sortCandidates(
        _ candidates: [AXDefaultAgentBaselineInstallableCandidate]
    ) -> [AXDefaultAgentBaselineInstallableCandidate] {
        candidates.sorted { lhs, rhs in
            lhs.skillID.localizedStandardCompare(rhs.skillID) == .orderedAscending
        }
    }
}
