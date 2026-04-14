import Foundation

enum AXSkillGovernanceTone: String, Equatable, Sendable {
    case ready
    case warning
    case blocked
    case neutral
}

struct AXSkillGovernanceSurfaceEntry: Identifiable, Equatable, Sendable {
    var skillID: String
    var name: String
    var version: String
    var riskLevel: String
    var packageSHA256: String
    var publisherID: String
    var sourceID: String
    var policyScope: String
    var tone: AXSkillGovernanceTone
    var stateLabel: String
    var intentFamilies: [String]
    var capabilityFamilies: [String]
    var capabilityProfiles: [String]
    var grantFloor: String
    var approvalFloor: String
    var discoverabilityState: String
    var installabilityState: String
    var requestabilityState: String
    var executionReadiness: String
    var whyNotRunnable: String
    var unblockActions: [String]
    var trustRootValue: String
    var pinnedVersionValue: String
    var runnerRequirementValue: String
    var compatibilityStatusValue: String
    var preflightResultValue: String
    var note: String
    var installHint: String

    var id: String { packageSHA256 }
}

extension AXSkillsDoctorSnapshot {
    var governanceSurfaceEntries: [AXSkillGovernanceSurfaceEntry] {
        governanceSurfaceEntries()
    }

    func governanceSurfaceEntries(
        projectId: String? = nil,
        projectName: String? = nil,
        projectRoot: URL? = nil,
        config: AXProjectConfig? = nil,
        hubBaseDir: URL? = nil
    ) -> [AXSkillGovernanceSurfaceEntry] {
        let lifecycleByPackage = Dictionary(
            uniqueKeysWithValues: officialPackageLifecyclePackages.map { ($0.packageSHA256.lowercased(), $0) }
        )

        let resolvedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedProjectRoot = projectRoot
        let resolvedConfig = resolvedProjectRoot.map { config ?? .default(forProjectRoot: $0) }
        let resolvedHubBaseDir = hubBaseDir ?? HubPaths.baseDir()
        let registryItemsBySkillID: [String: SupervisorSkillRegistryItem] = {
            guard !resolvedProjectId.isEmpty else { return [:] }
            let snapshot: SupervisorSkillRegistrySnapshot?
            if let resolvedProjectRoot {
                snapshot = AXSkillsLibrary.preferredSupervisorSkillRegistrySnapshot(
                    projectId: resolvedProjectId,
                    projectName: projectName,
                    projectRoot: resolvedProjectRoot,
                    hubBaseDir: resolvedHubBaseDir
                )
            } else {
                snapshot = AXSkillsLibrary.supervisorSkillRegistrySnapshot(
                    projectId: resolvedProjectId,
                    projectName: projectName,
                    hubBaseDir: resolvedHubBaseDir
                )
            }
            return Dictionary(
                uniqueKeysWithValues: (snapshot?.items ?? []).map {
                    (AXSkillsLibrary.canonicalSupervisorSkillID($0.skillId), $0)
                }
            )
        }()

        return installedSkills
            .map { skill in
                let canonicalSkillId = AXSkillsLibrary.canonicalSupervisorSkillID(skill.skillID)
                let readiness: XTSkillExecutionReadiness? = {
                    guard let resolvedProjectRoot, !resolvedProjectId.isEmpty else { return nil }
                    let baseReadiness = AXSkillsLibrary.skillExecutionReadiness(
                        skillId: canonicalSkillId,
                        projectId: resolvedProjectId,
                        projectName: projectName,
                        projectRoot: resolvedProjectRoot,
                        config: resolvedConfig,
                        registryItem: registryItemsBySkillID[canonicalSkillId],
                        hubBaseDir: resolvedHubBaseDir
                    )
                    return XTSkillCapabilityProfileSupport.effectiveReadinessForRequestScopedGrantOverride(
                        readiness: baseReadiness,
                        registryItem: registryItemsBySkillID[canonicalSkillId]
                    )
                }()
                return AXSkillGovernanceSurfaceEntry(
                    skill: skill,
                    lifecycle: lifecycleByPackage[skill.packageSHA256.lowercased()],
                    readiness: readiness
                )
            }
            .sorted { lhs, rhs in
                let leftTone = governanceTonePriority(lhs.tone)
                let rightTone = governanceTonePriority(rhs.tone)
                if leftTone != rightTone {
                    return leftTone < rightTone
                }

                let leftExecution = governanceExecutionPriority(lhs.executionReadiness)
                let rightExecution = governanceExecutionPriority(rhs.executionReadiness)
                if leftExecution != rightExecution {
                    return leftExecution < rightExecution
                }

                let leftRisk = governanceRiskPriority(lhs.riskLevel)
                let rightRisk = governanceRiskPriority(rhs.riskLevel)
                if leftRisk != rightRisk {
                    return leftRisk > rightRisk
                }

                let leftName = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let rightName = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let nameOrder = leftName.localizedCaseInsensitiveCompare(rightName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.packageSHA256 < rhs.packageSHA256
            }
    }

    private func governanceTonePriority(_ tone: AXSkillGovernanceTone) -> Int {
        switch tone {
        case .blocked:
            return 0
        case .warning:
            return 1
        case .ready:
            return 2
        case .neutral:
            return 3
        }
    }

    private func governanceExecutionPriority(_ raw: String) -> Int {
        switch XTSkillCapabilityProfileSupport.readinessState(from: raw) {
        case .revoked:
            return 0
        case .quarantined:
            return 1
        case .unsupported:
            return 2
        case .policyClamped:
            return 3
        case .runtimeUnavailable:
            return 4
        case .notInstalled:
            return 5
        case .grantRequired:
            return 6
        case .localApprovalRequired:
            return 7
        case .degraded:
            return 8
        case .hubDisconnected:
            return 9
        case .ready:
            return 10
        case .none:
            return 11
        }
    }

    private func governanceRiskPriority(_ riskLevel: String) -> Int {
        switch riskLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical":
            return 4
        case "high":
            return 3
        case "medium":
            return 2
        case "low":
            return 1
        default:
            return 0
        }
    }
}

private extension AXSkillGovernanceSurfaceEntry {
    init(
        skill: AXHubSkillCompatibilityEntry,
        lifecycle: AXOfficialSkillPackageLifecycleEntry?,
        readiness: XTSkillExecutionReadiness?
    ) {
        let compatibility = Self.compatibilitySummary(skill: skill, lifecycle: lifecycle)
        let preflight = Self.preflightSummary(skill: skill, lifecycle: lifecycle)
        let resolvedReadiness = readiness ?? Self.fallbackReadiness(skill: skill, lifecycle: lifecycle)
        let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: resolvedReadiness.executionReadiness)
            ?? XTSkillCapabilityProfileSupport.readinessState(
                from: Self.fallbackReadiness(skill: skill, lifecycle: lifecycle).executionReadiness
            )
            ?? .degraded

        self.init(
            skillID: skill.skillID,
            name: skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? skill.skillID : skill.name,
            version: skill.version,
            riskLevel: skill.riskLevel,
            packageSHA256: skill.packageSHA256,
            publisherID: skill.publisherID,
            sourceID: skill.sourceID,
            policyScope: resolvedReadiness.policyScope,
            tone: Self.tone(
                readiness: readinessState,
                compatibilityTone: compatibility.tone,
                preflightTone: preflight.tone
            ),
            stateLabel: resolvedReadiness.stateLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? preflight.label
                : resolvedReadiness.stateLabel,
            intentFamilies: resolvedReadiness.intentFamilies.isEmpty ? skill.intentFamilies : resolvedReadiness.intentFamilies,
            capabilityFamilies: resolvedReadiness.capabilityFamilies.isEmpty
                ? skill.capabilityFamilies
                : resolvedReadiness.capabilityFamilies,
            capabilityProfiles: resolvedReadiness.capabilityProfiles.isEmpty
                ? skill.capabilityProfiles
                : resolvedReadiness.capabilityProfiles,
            grantFloor: Self.normalizedToken(
                resolvedReadiness.grantFloor,
                fallback: Self.normalizedToken(skill.grantFloor, fallback: XTSkillGrantFloor.none.rawValue)
            ),
            approvalFloor: Self.normalizedToken(
                resolvedReadiness.approvalFloor,
                fallback: Self.normalizedToken(skill.approvalFloor, fallback: XTSkillApprovalFloor.none.rawValue)
            ),
            discoverabilityState: Self.normalizedToken(
                resolvedReadiness.discoverabilityState,
                fallback: "discoverable"
            ),
            installabilityState: Self.normalizedToken(
                resolvedReadiness.installabilityState,
                fallback: preflight.tone == .blocked ? "blocked" : "installable"
            ),
            requestabilityState: Self.requestabilityState(
                readiness: readinessState,
                installabilityState: resolvedReadiness.installabilityState
            ),
            executionReadiness: resolvedReadiness.executionReadiness,
            whyNotRunnable: readinessState == .ready ? "" : Self.normalizedToken(
                resolvedReadiness.reasonCode,
                fallback: preflight.value
            ),
            unblockActions: resolvedReadiness.unblockActions,
            trustRootValue: Self.trustRootValue(skill: skill),
            pinnedVersionValue: Self.pinnedVersionValue(skill: skill),
            runnerRequirementValue: Self.runnerRequirementValue(skill: skill),
            compatibilityStatusValue: compatibility.value,
            preflightResultValue: preflight.value,
            note: Self.note(skill: skill, lifecycle: lifecycle, compatibility: compatibility.value, preflight: preflight.value),
            installHint: skill.installHint.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func trustRootValue(skill: AXHubSkillCompatibilityEntry) -> String {
        let publisher = normalizedToken(skill.publisherID, fallback: "unknown publisher")
        let tier = normalizedToken(skill.trustTier)
        let trustedPublisher = skill.publisherTrusted
            || skill.artifactIntegrity.signature.trustedPublisher
            || skill.signatureVerified

        var parts: [String] = []
        if trustedPublisher {
            if publisher == "xhub.official" {
                parts.append("official trust root: \(publisher)")
            } else {
                parts.append("Hub trusted publisher: \(publisher)")
            }
        } else {
            parts.append("trust root unresolved: \(publisher)")
        }

        if !tier.isEmpty {
            parts.append("tier=\(tier)")
        }

        if skill.signatureVerified {
            parts.append("signature=verified")
        } else if skill.signatureBypassed {
            parts.append("signature=bypassed")
        } else if skill.artifactIntegrity.signature.present {
            parts.append("signature=present")
        }

        return parts.joined(separator: " | ")
    }

    static func pinnedVersionValue(skill: AXHubSkillCompatibilityEntry) -> String {
        let versionToken = normalizedToken(skill.version, fallback: "unknown")
        let base = "\(versionToken) @\(shortSHA(skill.packageSHA256))"

        if !skill.activePinnedScopes.isEmpty {
            return "\(base) | pinned=\(skill.activePinnedScopes.joined(separator: ","))"
        }
        if !skill.inactivePinnedScopes.isEmpty {
            return "\(base) | current build not pinned | other scopes=\(skill.inactivePinnedScopes.joined(separator: ","))"
        }
        return "\(base) | not pinned"
    }

    static func runnerRequirementValue(skill: AXHubSkillCompatibilityEntry) -> String {
        let runtime = skill.entrypointRuntime.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = skill.entrypointCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = skill.entrypointArgs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parts: [String] = []
        if !runtime.isEmpty {
            parts.append("runtime=\(runtime)")
        }
        if !command.isEmpty {
            let preview = ([command] + Array(args.prefix(2))).joined(separator: " ")
            parts.append("cmd=\(preview)")
        }
        if parts.isEmpty {
            return "runner not declared"
        }
        return parts.joined(separator: " | ")
    }

    static func compatibilitySummary(
        skill: AXHubSkillCompatibilityEntry,
        lifecycle: AXOfficialSkillPackageLifecycleEntry?
    ) -> (value: String, tone: AXSkillGovernanceTone) {
        let envelopeState = skill.compatibilityEnvelope.compatibilityState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let lifecycleOverall = lifecycle?.overallState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let runtimeHosts = skill.compatibilityEnvelope.runtimeHosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parts: [String] = []
        switch skill.compatibilityState {
        case .supported:
            if envelopeState == "verified" || envelopeState == "supported" {
                parts.append("supported | verified")
            } else {
                parts.append("supported")
            }
        case .partial:
            parts.append("partial")
        case .unsupported:
            parts.append("unsupported")
        case .unknown:
            parts.append("unknown")
        }

        if !runtimeHosts.isEmpty {
            parts.append("hosts=\(runtimeHosts.joined(separator: ","))")
        }

        if lifecycleOverall == "not_supported" {
            parts.append("lifecycle=not_supported")
            return (parts.joined(separator: " | "), .blocked)
        }

        if skill.compatibilityState == .partial {
            if !skill.mappingAliasesUsed.isEmpty || !skill.defaultsApplied.isEmpty {
                parts.append("alias/default mapping applied")
            } else if envelopeState == "partial" || envelopeState == "unknown" || envelopeState.isEmpty {
                parts.append("awaiting full verify")
            }
            return (parts.joined(separator: " | "), .warning)
        }

        if skill.compatibilityState == .unsupported || envelopeState == "incompatible" {
            return (parts.joined(separator: " | "), .blocked)
        }

        return (parts.joined(separator: " | "), .ready)
    }

    static func preflightSummary(
        skill: AXHubSkillCompatibilityEntry,
        lifecycle: AXOfficialSkillPackageLifecycleEntry?
    ) -> (value: String, tone: AXSkillGovernanceTone, label: String) {
        let packageState = normalizedToken(
            lifecycle?.packageState,
            fallback: normalizedToken(skill.packageState, fallback: "")
        ).lowercased()
        let overallState = normalizedToken(lifecycle?.overallState, fallback: "").lowercased()
        let doctor = skill.qualityEvidenceStatus.doctor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let smoke = skill.qualityEvidenceStatus.smoke.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let envelopeState = skill.compatibilityEnvelope.compatibilityState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if skill.revoked
            || skill.revokeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "revoked"
            || packageState == "revoked" {
            return ("blocked | revoked", .blocked, "revoked")
        }
        if packageState == "quarantined" {
            return ("quarantined", .blocked, "quarantined")
        }
        if skill.requiresGrant && (overallState == "blocked" || overallState == "degraded") {
            return ("grant required before run", .blocked, "grant required")
        }
        if skill.compatibilityState == .unsupported
            || envelopeState == "incompatible"
            || overallState == "not_supported" {
            return ("blocked | incompatible", .blocked, "blocked")
        }
        if doctor == "failed" || smoke == "failed" {
            return ("blocked | doctor or smoke failed", .blocked, "blocked")
        }
        if overallState == "blocked" {
            return ("blocked | package not ready", .blocked, "blocked")
        }
        if overallState == "ready" || packageState == "active" || packageState == "ready" {
            return ("passed", .ready, "ready")
        }
        if skill.requiresGrant {
            return ("grant required before run", .warning, "grant required")
        }
        if doctor == "passed" && smoke == "passed" && skill.compatibilityState == .supported {
            return ("passed", .ready, "ready")
        }
        if doctor == "passed" || smoke == "passed" {
            return ("partial preflight | quality evidence incomplete", .warning, "watch")
        }
        return ("pending preflight evidence", .warning, "watch")
    }

    static func note(
        skill: AXHubSkillCompatibilityEntry,
        lifecycle: AXOfficialSkillPackageLifecycleEntry?,
        compatibility: String,
        preflight: String
    ) -> String {
        var parts: [String] = []

        if skill.requiresGrant {
            parts.append("high-risk capability grant applies")
        }
        if !skill.mappingAliasesUsed.isEmpty {
            parts.append("aliases=\(skill.mappingAliasesUsed.joined(separator: ","))")
        }
        if !skill.defaultsApplied.isEmpty {
            parts.append("defaults=\(skill.defaultsApplied.joined(separator: ","))")
        }

        let doctor = skill.qualityEvidenceStatus.doctor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let smoke = skill.qualityEvidenceStatus.smoke.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if doctor != "passed" || smoke != "passed" {
            parts.append(
                "quality doctor=\(normalizedToken(skill.qualityEvidenceStatus.doctor, fallback: "missing")) " +
                "smoke=\(normalizedToken(skill.qualityEvidenceStatus.smoke, fallback: "missing"))"
            )
        }

        if let lifecycle {
            let overall = lifecycle.overallState.trimmingCharacters(in: .whitespacesAndNewlines)
            let package = lifecycle.packageState.trimmingCharacters(in: .whitespacesAndNewlines)
            if !overall.isEmpty || !package.isEmpty {
                parts.append(
                    "lifecycle=\(normalizedToken(overall, fallback: "unknown"))/" +
                    "\(normalizedToken(package, fallback: "unknown"))"
                )
            }
        }

        if parts.isEmpty {
            return compatibility == preflight ? compatibility : "\(compatibility) | \(preflight)"
        }
        return parts.joined(separator: " | ")
    }

    static func tone(
        readiness: XTSkillExecutionReadinessState?,
        compatibilityTone: AXSkillGovernanceTone,
        preflightTone: AXSkillGovernanceTone
    ) -> AXSkillGovernanceTone {
        switch readiness {
        case .ready:
            return preflightTone == .ready ? compatibilityTone : preflightTone
        case .grantRequired, .localApprovalRequired, .degraded:
            return .warning
        case .policyClamped, .runtimeUnavailable, .hubDisconnected, .quarantined, .revoked, .notInstalled, .unsupported:
            return .blocked
        case nil:
            return preflightTone == .ready ? compatibilityTone : preflightTone
        }
    }

    static func requestabilityState(
        readiness: XTSkillExecutionReadinessState?,
        installabilityState: String
    ) -> String {
        switch readiness {
        case .ready, .grantRequired, .localApprovalRequired, .degraded:
            return "requestable"
        case .notInstalled:
            return normalizedToken(installabilityState).isEmpty ? "not_requestable" : "installable_only"
        case .policyClamped,
             .runtimeUnavailable,
             .hubDisconnected,
             .quarantined,
             .revoked,
             .unsupported,
             nil:
            return "not_requestable"
        }
    }

    static func fallbackReadiness(
        skill: AXHubSkillCompatibilityEntry,
        lifecycle: AXOfficialSkillPackageLifecycleEntry?
    ) -> XTSkillExecutionReadiness {
        let preflight = preflightSummary(skill: skill, lifecycle: lifecycle)
        let capabilityFamilies = skill.capabilityFamilies
        let capabilityProfiles = skill.capabilityProfiles
        let grantFloor = normalizedToken(skill.grantFloor, fallback: XTSkillGrantFloor.none.rawValue)
        let approvalFloor = normalizedToken(skill.approvalFloor, fallback: XTSkillApprovalFloor.none.rawValue)
        let fallbackState: XTSkillExecutionReadinessState = {
            if preflight.label == "revoked" {
                return .revoked
            }
            if preflight.label == "quarantined" {
                return .quarantined
            }
            if preflight.label == "grant required" {
                return .grantRequired
            }
            if preflight.label == "blocked" {
                return .unsupported
            }
            if preflight.label == "watch" {
                return .degraded
            }
            return .ready
        }()

        return XTSkillExecutionReadiness(
            schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
            projectId: "",
            skillId: skill.skillID,
            packageSHA256: skill.packageSHA256,
            publisherID: skill.publisherID,
            policyScope: normalizedToken(skill.activePinnedScopes.first ?? skill.pinnedScopes.first),
            intentFamilies: skill.intentFamilies,
            capabilityFamilies: capabilityFamilies,
            capabilityProfiles: capabilityProfiles,
            discoverabilityState: skill.revoked ? "revoked" : "discoverable",
            installabilityState: fallbackState == .quarantined ? "vetter_blocked" : (fallbackState == .unsupported ? "unsupported" : "installable"),
            pinState: normalizedToken(skill.activePinnedScopes.first ?? skill.pinnedScopes.first, fallback: "unpinned"),
            resolutionState: skill.activePinnedScopes.isEmpty && skill.pinnedScopes.isEmpty ? "missing_package" : "resolved",
            executionReadiness: fallbackState.rawValue,
            runnableNow: fallbackState == .ready,
            denyCode: fallbackState == .ready ? "" : preflight.label.replacingOccurrences(of: " ", with: "_"),
            reasonCode: preflight.value,
            grantFloor: grantFloor,
            approvalFloor: approvalFloor,
            requiredGrantCapabilities: skill.requiresGrant ? skill.capabilitiesRequired : [],
            requiredRuntimeSurfaces: XTSkillCapabilityProfileSupport.requiredRuntimeSurfaces(for: capabilityFamilies),
            stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(fallbackState.rawValue),
            installHint: skill.installHint,
            unblockActions: XTSkillCapabilityProfileSupport.unblockActions(
                for: fallbackState,
                approvalFloor: approvalFloor,
                requiredRuntimeSurfaces: XTSkillCapabilityProfileSupport.requiredRuntimeSurfaces(for: capabilityFamilies)
            ),
            auditRef: "",
            doctorAuditRef: "",
            vetterAuditRef: fallbackState == .quarantined ? "vetter:quarantined" : "",
            resolvedSnapshotId: "",
            grantSnapshotRef: ""
        )
    }

    static func normalizedToken(_ value: String?, fallback: String = "") -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func shortSHA(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "n/a" }
        return String(normalized.prefix(12))
    }
}
