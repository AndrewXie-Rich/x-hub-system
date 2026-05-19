import Foundation

struct XTUnifiedDoctorHubContractProjection: Codable, Equatable, Sendable {
    var schemaVersion: String
    var ok: Bool
    var contractReady: Bool
    var contractObservedAtMs: Int64
    var lastCheckedAtMs: Int64
    var lastFetchOK: Bool
    var fetchErrorCode: String
    var fetchErrorMessage: String
    var sourceOfTruth: String
    var kernel: String
    var shell: String
    var xtRole: String
    var mustReadContractFirst: Bool
    var mustNotRecreateHubAuthorityLocally: Bool
    var mustFailClosedOnMissingGrantOrStaleContract: Bool
    var recommendedContractTTLMS: Int64
    var transportSecretFieldsIncluded: Bool
    var remoteXTRequiresPairing: Bool
    var remoteXTRequiresMTLSForRuntimeChannels: Bool
    var memoryCanonicalWriter: String
    var memoryDurableTruthInXT: Bool
    var skillsAuthority: String
    var skillsLeaseRequired: Bool
    var skillsLeaseSourceEndpoint: String
    var thirdPartyCodeInHubTrustRoot: Bool
    var skillsPackageHashPinRequired: Bool
    var skillsRevocationEpochRequired: Bool
    var remoteEntryNoDomainSupported: Bool
    var remoteEntryRequiresMTLS: Bool
    var modelsXTMustNotSelectPaidProviderDirectly: Bool
    var providerRouteSecretFieldsIncluded: Bool
    var naturalLanguageDirectGrant: Bool
    var auditFallbackPolicy: String

    init(snapshot: HubContractSnapshot, observedAt: Date = Date()) {
        let checkedAtMs = Int64(observedAt.timeIntervalSince1970 * 1000)
        schemaVersion = snapshot.schemaVersion
        ok = snapshot.ok
        contractReady = false
        contractObservedAtMs = snapshot.generatedAtMs ?? checkedAtMs
        lastCheckedAtMs = checkedAtMs
        lastFetchOK = true
        fetchErrorCode = ""
        fetchErrorMessage = ""
        sourceOfTruth = snapshot.hubProduct.sourceOfTruth ?? ""
        kernel = snapshot.hubProduct.kernel ?? ""
        shell = snapshot.hubProduct.shell ?? ""
        xtRole = snapshot.hubProduct.xtRole ?? ""
        mustReadContractFirst = snapshot.xtUpdateRule.mustReadContractFirst ?? false
        mustNotRecreateHubAuthorityLocally = snapshot.xtUpdateRule.mustNotRecreateHubAuthorityLocally ?? false
        mustFailClosedOnMissingGrantOrStaleContract =
            snapshot.xtUpdateRule.mustFailClosedOnMissingGrantOrStaleContract ?? false
        recommendedContractTTLMS = max(0, snapshot.xtUpdateRule.recommendedContractTTLMS ?? 0)
        transportSecretFieldsIncluded = snapshot.transportSecurity.secretFieldsIncluded ?? true
        remoteXTRequiresPairing = snapshot.transportSecurity.remoteXTRequiresPairing ?? false
        remoteXTRequiresMTLSForRuntimeChannels =
            snapshot.transportSecurity.remoteXTRequiresMTLSForRuntimeChannels ?? false
        memoryCanonicalWriter = snapshot.capabilities.memory.canonicalWriter ?? ""
        memoryDurableTruthInXT = snapshot.capabilities.memory.durableTruthInXT ?? true
        skillsAuthority = snapshot.capabilities.skills.authority ?? ""
        skillsLeaseRequired = snapshot.capabilities.skills.leaseRequired ?? false
        skillsLeaseSourceEndpoint = snapshot.capabilities.skills.leaseSourceEndpoint ?? ""
        thirdPartyCodeInHubTrustRoot = snapshot.capabilities.skills.thirdPartyCodeInHubTrustRoot ?? true
        skillsPackageHashPinRequired = snapshot.capabilities.skills.packageHashPinRequired ?? false
        skillsRevocationEpochRequired = snapshot.capabilities.skills.revocationEpochRequired ?? false
        remoteEntryNoDomainSupported = snapshot.capabilities.remoteEntry.supportsNoDomainUsers ?? false
        remoteEntryRequiresMTLS = snapshot.capabilities.remoteEntry.requiresMTLS ?? false
        modelsXTMustNotSelectPaidProviderDirectly =
            snapshot.capabilities.models.xtMustNotSelectPaidProviderDirectly ?? false
        providerRouteSecretFieldsIncluded = snapshot.capabilities.providerRoute.secretFieldsIncluded ?? true
        naturalLanguageDirectGrant = snapshot.capabilities.grants.naturalLanguageDirectGrant ?? true
        auditFallbackPolicy = snapshot.capabilities.audit.fallbackPolicy ?? ""
        contractReady = Self.isReady(
            schemaVersion: schemaVersion,
            ok: ok,
            sourceOfTruth: sourceOfTruth,
            mustReadContractFirst: mustReadContractFirst,
            mustNotRecreateHubAuthorityLocally: mustNotRecreateHubAuthorityLocally,
            mustFailClosedOnMissingGrantOrStaleContract: mustFailClosedOnMissingGrantOrStaleContract,
            transportSecretFieldsIncluded: transportSecretFieldsIncluded,
            remoteXTRequiresPairing: remoteXTRequiresPairing,
            remoteXTRequiresMTLSForRuntimeChannels: remoteXTRequiresMTLSForRuntimeChannels,
            memoryCanonicalWriter: memoryCanonicalWriter,
            memoryDurableTruthInXT: memoryDurableTruthInXT,
            skillsAuthority: skillsAuthority,
            skillsLeaseRequired: skillsLeaseRequired,
            skillsLeaseSourceEndpoint: skillsLeaseSourceEndpoint,
            thirdPartyCodeInHubTrustRoot: thirdPartyCodeInHubTrustRoot,
            skillsPackageHashPinRequired: skillsPackageHashPinRequired,
            skillsRevocationEpochRequired: skillsRevocationEpochRequired,
            remoteEntryNoDomainSupported: remoteEntryNoDomainSupported,
            remoteEntryRequiresMTLS: remoteEntryRequiresMTLS,
            modelsXTMustNotSelectPaidProviderDirectly: modelsXTMustNotSelectPaidProviderDirectly,
            providerRouteSecretFieldsIncluded: providerRouteSecretFieldsIncluded,
            naturalLanguageDirectGrant: naturalLanguageDirectGrant,
            auditFallbackPolicy: auditFallbackPolicy
        )
    }

    static func fetchFailure(
        errorCode: String,
        errorMessage: String,
        observedAt: Date = Date()
    ) -> XTUnifiedDoctorHubContractProjection {
        let checkedAtMs = Int64(observedAt.timeIntervalSince1970 * 1000)
        return XTUnifiedDoctorHubContractProjection(
            schemaVersion: HubContractSnapshot.currentSchemaVersion,
            ok: false,
            contractReady: false,
            contractObservedAtMs: 0,
            lastCheckedAtMs: checkedAtMs,
            lastFetchOK: false,
            fetchErrorCode: errorCode,
            fetchErrorMessage: errorMessage,
            sourceOfTruth: "",
            kernel: "",
            shell: "",
            xtRole: "",
            mustReadContractFirst: false,
            mustNotRecreateHubAuthorityLocally: false,
            mustFailClosedOnMissingGrantOrStaleContract: false,
            recommendedContractTTLMS: 0,
            transportSecretFieldsIncluded: true,
            remoteXTRequiresPairing: false,
            remoteXTRequiresMTLSForRuntimeChannels: false,
            memoryCanonicalWriter: "",
            memoryDurableTruthInXT: true,
            skillsAuthority: "",
            skillsLeaseRequired: false,
            skillsLeaseSourceEndpoint: "",
            thirdPartyCodeInHubTrustRoot: true,
            skillsPackageHashPinRequired: false,
            skillsRevocationEpochRequired: false,
            remoteEntryNoDomainSupported: false,
            remoteEntryRequiresMTLS: false,
            modelsXTMustNotSelectPaidProviderDirectly: false,
            providerRouteSecretFieldsIncluded: true,
            naturalLanguageDirectGrant: true,
            auditFallbackPolicy: ""
        )
    }

    func withFetchFailure(
        errorCode: String,
        errorMessage: String,
        observedAt: Date = Date()
    ) -> XTUnifiedDoctorHubContractProjection {
        var copy = self
        let checkedAtMs = Int64(observedAt.timeIntervalSince1970 * 1000)
        copy.lastCheckedAtMs = checkedAtMs
        copy.lastFetchOK = false
        copy.fetchErrorCode = errorCode
        copy.fetchErrorMessage = errorMessage
        if recommendedContractTTLMS > 0,
           contractObservedAtMs > 0,
           checkedAtMs - contractObservedAtMs > recommendedContractTTLMS {
            copy.contractReady = false
        }
        return copy
    }

    func detailLines() -> [String] {
        var lines = [
            "hub_contract_ready=\(contractReady)",
            "hub_contract_schema_version=\(schemaVersion)",
            "hub_contract_last_fetch_ok=\(lastFetchOK)",
            "hub_contract_source_of_truth=\(sourceOfTruth.isEmpty ? "unknown" : sourceOfTruth)",
            "hub_contract_kernel=\(kernel.isEmpty ? "unknown" : kernel)",
            "hub_contract_shell=\(shell.isEmpty ? "unknown" : shell)",
            "hub_contract_xt_role=\(xtRole.isEmpty ? "unknown" : xtRole)",
            "hub_contract_must_read_first=\(mustReadContractFirst)",
            "hub_contract_no_local_authority_recreation=\(mustNotRecreateHubAuthorityLocally)",
            "hub_contract_fail_closed_on_stale=\(mustFailClosedOnMissingGrantOrStaleContract)",
            "hub_contract_recommended_ttl_ms=\(recommendedContractTTLMS)",
            "hub_contract_transport_secret_fields_included=\(transportSecretFieldsIncluded)",
            "hub_contract_remote_xt_requires_pairing=\(remoteXTRequiresPairing)",
            "hub_contract_remote_xt_requires_mtls_runtime=\(remoteXTRequiresMTLSForRuntimeChannels)",
            "hub_contract_memory_canonical_writer=\(memoryCanonicalWriter.isEmpty ? "unknown" : memoryCanonicalWriter)",
            "hub_contract_memory_durable_truth_in_xt=\(memoryDurableTruthInXT)",
            "hub_contract_skills_authority=\(skillsAuthority.isEmpty ? "unknown" : skillsAuthority)",
            "hub_contract_skills_lease_required=\(skillsLeaseRequired)",
            "hub_contract_skills_lease_source_endpoint=\(skillsLeaseSourceEndpoint.isEmpty ? "unknown" : skillsLeaseSourceEndpoint)",
            "hub_contract_skills_third_party_code_in_hub_trust_root=\(thirdPartyCodeInHubTrustRoot)",
            "hub_contract_skills_package_hash_pin_required=\(skillsPackageHashPinRequired)",
            "hub_contract_skills_revocation_epoch_required=\(skillsRevocationEpochRequired)",
            "hub_contract_remote_entry_no_domain_supported=\(remoteEntryNoDomainSupported)",
            "hub_contract_remote_entry_requires_mtls=\(remoteEntryRequiresMTLS)",
            "hub_contract_models_xt_must_not_select_paid_provider_directly=\(modelsXTMustNotSelectPaidProviderDirectly)",
            "hub_contract_provider_route_secret_fields_included=\(providerRouteSecretFieldsIncluded)",
            "hub_contract_natural_language_direct_grant=\(naturalLanguageDirectGrant)",
            "hub_contract_audit_fallback_policy=\(auditFallbackPolicy.isEmpty ? "unknown" : auditFallbackPolicy)"
        ]
        if !fetchErrorCode.isEmpty {
            lines.append("hub_contract_fetch_error_code=\(fetchErrorCode)")
        }
        if !fetchErrorMessage.isEmpty {
            lines.append("hub_contract_fetch_error_message=\(fetchErrorMessage)")
        }
        return lines
    }

    private init(
        schemaVersion: String,
        ok: Bool,
        contractReady: Bool,
        contractObservedAtMs: Int64,
        lastCheckedAtMs: Int64,
        lastFetchOK: Bool,
        fetchErrorCode: String,
        fetchErrorMessage: String,
        sourceOfTruth: String,
        kernel: String,
        shell: String,
        xtRole: String,
        mustReadContractFirst: Bool,
        mustNotRecreateHubAuthorityLocally: Bool,
        mustFailClosedOnMissingGrantOrStaleContract: Bool,
        recommendedContractTTLMS: Int64,
        transportSecretFieldsIncluded: Bool,
        remoteXTRequiresPairing: Bool,
        remoteXTRequiresMTLSForRuntimeChannels: Bool,
        memoryCanonicalWriter: String,
        memoryDurableTruthInXT: Bool,
        skillsAuthority: String,
        skillsLeaseRequired: Bool,
        skillsLeaseSourceEndpoint: String,
        thirdPartyCodeInHubTrustRoot: Bool,
        skillsPackageHashPinRequired: Bool,
        skillsRevocationEpochRequired: Bool,
        remoteEntryNoDomainSupported: Bool,
        remoteEntryRequiresMTLS: Bool,
        modelsXTMustNotSelectPaidProviderDirectly: Bool,
        providerRouteSecretFieldsIncluded: Bool,
        naturalLanguageDirectGrant: Bool,
        auditFallbackPolicy: String
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.contractReady = contractReady
        self.contractObservedAtMs = contractObservedAtMs
        self.lastCheckedAtMs = lastCheckedAtMs
        self.lastFetchOK = lastFetchOK
        self.fetchErrorCode = fetchErrorCode
        self.fetchErrorMessage = fetchErrorMessage
        self.sourceOfTruth = sourceOfTruth
        self.kernel = kernel
        self.shell = shell
        self.xtRole = xtRole
        self.mustReadContractFirst = mustReadContractFirst
        self.mustNotRecreateHubAuthorityLocally = mustNotRecreateHubAuthorityLocally
        self.mustFailClosedOnMissingGrantOrStaleContract = mustFailClosedOnMissingGrantOrStaleContract
        self.recommendedContractTTLMS = recommendedContractTTLMS
        self.transportSecretFieldsIncluded = transportSecretFieldsIncluded
        self.remoteXTRequiresPairing = remoteXTRequiresPairing
        self.remoteXTRequiresMTLSForRuntimeChannels = remoteXTRequiresMTLSForRuntimeChannels
        self.memoryCanonicalWriter = memoryCanonicalWriter
        self.memoryDurableTruthInXT = memoryDurableTruthInXT
        self.skillsAuthority = skillsAuthority
        self.skillsLeaseRequired = skillsLeaseRequired
        self.skillsLeaseSourceEndpoint = skillsLeaseSourceEndpoint
        self.thirdPartyCodeInHubTrustRoot = thirdPartyCodeInHubTrustRoot
        self.skillsPackageHashPinRequired = skillsPackageHashPinRequired
        self.skillsRevocationEpochRequired = skillsRevocationEpochRequired
        self.remoteEntryNoDomainSupported = remoteEntryNoDomainSupported
        self.remoteEntryRequiresMTLS = remoteEntryRequiresMTLS
        self.modelsXTMustNotSelectPaidProviderDirectly = modelsXTMustNotSelectPaidProviderDirectly
        self.providerRouteSecretFieldsIncluded = providerRouteSecretFieldsIncluded
        self.naturalLanguageDirectGrant = naturalLanguageDirectGrant
        self.auditFallbackPolicy = auditFallbackPolicy
    }

    private static func isReady(
        schemaVersion: String,
        ok: Bool,
        sourceOfTruth: String,
        mustReadContractFirst: Bool,
        mustNotRecreateHubAuthorityLocally: Bool,
        mustFailClosedOnMissingGrantOrStaleContract: Bool,
        transportSecretFieldsIncluded: Bool,
        remoteXTRequiresPairing: Bool,
        remoteXTRequiresMTLSForRuntimeChannels: Bool,
        memoryCanonicalWriter: String,
        memoryDurableTruthInXT: Bool,
        skillsAuthority: String,
        skillsLeaseRequired: Bool,
        skillsLeaseSourceEndpoint: String,
        thirdPartyCodeInHubTrustRoot: Bool,
        skillsPackageHashPinRequired: Bool,
        skillsRevocationEpochRequired: Bool,
        remoteEntryNoDomainSupported: Bool,
        remoteEntryRequiresMTLS: Bool,
        modelsXTMustNotSelectPaidProviderDirectly: Bool,
        providerRouteSecretFieldsIncluded: Bool,
        naturalLanguageDirectGrant: Bool,
        auditFallbackPolicy: String
    ) -> Bool {
        ok
            && schemaVersion == HubContractSnapshot.currentSchemaVersion
            && sourceOfTruth == "hub"
            && mustReadContractFirst
            && mustNotRecreateHubAuthorityLocally
            && mustFailClosedOnMissingGrantOrStaleContract
            && !transportSecretFieldsIncluded
            && remoteXTRequiresPairing
            && remoteXTRequiresMTLSForRuntimeChannels
            && memoryCanonicalWriter == "hub_only"
            && !memoryDurableTruthInXT
            && skillsAuthority == "hub_policy_gate"
            && skillsLeaseRequired
            && skillsLeaseSourceEndpoint == "/skills/preflight"
            && !thirdPartyCodeInHubTrustRoot
            && skillsPackageHashPinRequired
            && skillsRevocationEpochRequired
            && remoteEntryNoDomainSupported
            && remoteEntryRequiresMTLS
            && modelsXTMustNotSelectPaidProviderDirectly
            && !providerRouteSecretFieldsIncluded
            && !naturalLanguageDirectGrant
            && auditFallbackPolicy == "do_not_synthesize_audit_refs"
    }
}
