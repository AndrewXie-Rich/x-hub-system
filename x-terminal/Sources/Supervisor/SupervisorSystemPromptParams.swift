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
    var memorySource: String
}

struct SupervisorSystemPromptParams: Equatable {
    var identity: SupervisorIdentityProfile
    var runtimeInfo: SupervisorSystemPromptRuntimeInfo
    var userTimezone: String
    var userTime: String
    var userMessage: String
    var memoryV1: String
    var promptMode: SupervisorSystemPromptMode
    var extraSystemPrompt: String?
}

enum SupervisorSystemPromptParamsBuilder {
    static func build(
        identity: SupervisorIdentityProfile = .default(),
        preferredSupervisorModelId: String?,
        supervisorModelRouteSummary: String,
        memorySource: String,
        projectCount: Int,
        userMessage: String,
        memoryV1: String,
        promptMode: SupervisorSystemPromptMode = .full,
        extraSystemPrompt: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        hubConnected: Bool,
        hubRemoteConnected: Bool
    ) -> SupervisorSystemPromptParams {
        SupervisorSystemPromptParams(
            identity: identity,
            runtimeInfo: SupervisorSystemPromptRuntimeInfo(
                appName: "X-Terminal",
                host: ProcessInfo.processInfo.hostName,
                os: ProcessInfo.processInfo.operatingSystemVersionString,
                arch: currentArchitecture(),
                hubRoute: hubRouteDescription(hubConnected: hubConnected, hubRemoteConnected: hubRemoteConnected),
                projectCount: projectCount,
                preferredSupervisorModelId: preferredSupervisorModelId,
                supervisorModelRouteSummary: supervisorModelRouteSummary,
                memorySource: memorySource,
            ),
            userTimezone: timeZone.identifier,
            userTime: formattedUserTime(now: now, timeZone: timeZone, locale: locale),
            userMessage: userMessage,
            memoryV1: memoryV1,
            promptMode: promptMode,
            extraSystemPrompt: extraSystemPrompt
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
