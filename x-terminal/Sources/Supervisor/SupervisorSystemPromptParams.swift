import Foundation

enum SupervisorSystemPromptMode: String {
    case full
    case minimal
    case none
}

struct SupervisorSystemPromptRuntimeInfo: Equatable {
    var appName: String
    var host: String
    var os: String
    var arch: String
    var hubRoute: String
    var projectCount: Int
    var preferredSupervisorModelId: String?
    var supervisorModelRouteSummary: String
    var retrievalModelSummary: String?
    var memorySource: String
    var lastRemoteSuccessAt: TimeInterval?
    var lastRemoteFailureAt: TimeInterval?
    var portfolioSnapshotUpdatedAt: TimeInterval?
    var canonicalMemorySyncLastFailureAt: TimeInterval?
}

struct SupervisorSystemPromptParams: Equatable {
    var identity: SupervisorIdentityProfile
    var personalProfile: SupervisorPersonalProfile = .default()
    var personalPolicy: SupervisorPersonalPolicy = .default()
    var workMode: XTSupervisorWorkMode = .defaultMode
    var privacyMode: XTPrivacyMode = .defaultMode
    var personalMemorySummary: String = ""
    var personalFollowUpSummary: String = ""
    var personalReviewSummary: String = ""
    var turnRoutingDecision: SupervisorTurnRoutingDecision? = nil
    var turnContextAssembly: SupervisorTurnContextAssemblyResult? = nil
    var runtimeInfo: SupervisorSystemPromptRuntimeInfo
    var userTimezone: String
    var userTime: String
    var userMessage: String
    var attachmentSummary: String = ""
    var memoryV1: String
    var promptMode: SupervisorSystemPromptMode
    var extraSystemPrompt: String?
    var memoryReadiness: SupervisorMemoryAssemblyReadiness? = nil
}

enum SupervisorSystemPromptParamsBuilder {
    static func build(
        identity: SupervisorIdentityProfile = .default(),
        personalProfile: SupervisorPersonalProfile = .default(),
        personalPolicy: SupervisorPersonalPolicy = .default(),
        workMode: XTSupervisorWorkMode = .defaultMode,
        privacyMode: XTPrivacyMode = .defaultMode,
        personalMemorySummary: String = "",
        personalFollowUpSummary: String = "",
        personalReviewSummary: String = "",
        turnRoutingDecision: SupervisorTurnRoutingDecision? = nil,
        turnContextAssembly: SupervisorTurnContextAssemblyResult? = nil,
        preferredSupervisorModelId: String?,
        supervisorModelRouteSummary: String,
        memorySource: String,
        lastRemoteSuccessAt: TimeInterval? = nil,
        lastRemoteFailureAt: TimeInterval? = nil,
        portfolioSnapshotUpdatedAt: TimeInterval? = nil,
        canonicalMemorySyncLastFailureAt: TimeInterval? = nil,
        projectCount: Int,
        userMessage: String,
        attachmentSummary: String = "",
        memoryV1: String,
        promptMode: SupervisorSystemPromptMode = .full,
        extraSystemPrompt: String? = nil,
        memoryReadiness: SupervisorMemoryAssemblyReadiness? = nil,
        retrievalModelSummary: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        hubConnected: Bool,
        hubRemoteConnected: Bool
    ) -> SupervisorSystemPromptParams {
        SupervisorSystemPromptParams(
            identity: identity,
            personalProfile: personalProfile.normalized(),
            personalPolicy: personalPolicy.normalized(),
            workMode: workMode,
            privacyMode: privacyMode,
            personalMemorySummary: personalMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines),
            personalFollowUpSummary: personalFollowUpSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            personalReviewSummary: personalReviewSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            turnRoutingDecision: turnRoutingDecision,
            turnContextAssembly: turnContextAssembly,
            runtimeInfo: SupervisorSystemPromptRuntimeInfo(
                appName: "X-Terminal",
                host: ProcessInfo.processInfo.hostName,
                os: ProcessInfo.processInfo.operatingSystemVersionString,
                arch: currentArchitecture(),
                hubRoute: hubRouteDescription(hubConnected: hubConnected, hubRemoteConnected: hubRemoteConnected),
                projectCount: projectCount,
                preferredSupervisorModelId: preferredSupervisorModelId,
                supervisorModelRouteSummary: supervisorModelRouteSummary,
                retrievalModelSummary: retrievalModelSummary,
                memorySource: memorySource,
                lastRemoteSuccessAt: lastRemoteSuccessAt,
                lastRemoteFailureAt: lastRemoteFailureAt,
                portfolioSnapshotUpdatedAt: portfolioSnapshotUpdatedAt,
                canonicalMemorySyncLastFailureAt: canonicalMemorySyncLastFailureAt,
            ),
            userTimezone: timeZone.identifier,
            userTime: formattedUserTime(now: now, timeZone: timeZone, locale: locale),
            userMessage: userMessage,
            attachmentSummary: attachmentSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            memoryV1: memoryV1,
            promptMode: promptMode,
            extraSystemPrompt: extraSystemPrompt,
            memoryReadiness: memoryReadiness
        )
    }

    private static func formattedUserTime(now: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: now)
    }

    private static func hubRouteDescription(hubConnected: Bool, hubRemoteConnected: Bool) -> String {
        if hubRemoteConnected {
            return "remote_hub"
        }
        if hubConnected {
            return "local_hub"
        }
        return "hub_disconnected"
    }

    private static func currentArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
