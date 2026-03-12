import Foundation

@MainActor
final class FunASRSidecarHealthMonitor {
    typealias ProbeHandler = (FunASRSidecarConfig) async -> VoiceSidecarHealthSnapshot

    private let probeHandler: ProbeHandler

    init(probeHandler: ProbeHandler? = nil) {
        self.probeHandler = probeHandler ?? Self.defaultProbe(config:)
    }

    func probe(config: FunASRSidecarConfig) async -> VoiceSidecarHealthSnapshot {
        await probeHandler(config)
    }

    private static func defaultProbe(
        config: FunASRSidecarConfig
    ) async -> VoiceSidecarHealthSnapshot {
        guard config.enabled else {
            return .disabled(config: config)
        }

        guard let webSocketURL = URL(string: config.webSocketURL),
              let scheme = webSocketURL.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme),
              isLocalHost(webSocketURL.host) else {
            return VoiceSidecarHealthSnapshot(
                engine: "funasr",
                transport: config.transport,
                endpoint: config.webSocketURL,
                status: .unreachable,
                vadReady: false,
                wakeReady: false,
                partialReady: false,
                lastError: "funasr_remote_sidecar_not_allowed"
            )
        }

        let healthURLText = config.healthcheckURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !healthURLText.isEmpty else {
            return VoiceSidecarHealthSnapshot(
                engine: "funasr",
                transport: config.transport,
                endpoint: config.webSocketURL,
                status: .degraded,
                vadReady: false,
                wakeReady: false,
                partialReady: config.partialsEnabled,
                lastError: "funasr_healthcheck_not_configured"
            )
        }

        guard let healthURL = URL(string: healthURLText),
              isLocalHost(healthURL.host) else {
            return VoiceSidecarHealthSnapshot(
                engine: "funasr",
                transport: config.transport,
                endpoint: config.webSocketURL,
                status: .unreachable,
                vadReady: false,
                wakeReady: false,
                partialReady: false,
                lastError: "funasr_remote_sidecar_not_allowed"
            )
        }

        do {
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 1.0
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(statusCode) else {
                return VoiceSidecarHealthSnapshot(
                    engine: "funasr",
                    transport: config.transport,
                    endpoint: config.webSocketURL,
                    status: .unreachable,
                    vadReady: false,
                    wakeReady: false,
                    partialReady: false,
                    lastError: "funasr_healthcheck_http_\(statusCode)"
                )
            }

            return VoiceSidecarHealthSnapshot(
                engine: "funasr",
                transport: config.transport,
                endpoint: config.webSocketURL,
                status: .ready,
                vadReady: true,
                wakeReady: config.wakeEnabled,
                partialReady: config.partialsEnabled,
                lastError: nil
            )
        } catch {
            return VoiceSidecarHealthSnapshot(
                engine: "funasr",
                transport: config.transport,
                endpoint: config.webSocketURL,
                status: .unreachable,
                vadReady: false,
                wakeReady: false,
                partialReady: false,
                lastError: error.localizedDescription
            )
        }
    }

    private static func isLocalHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
