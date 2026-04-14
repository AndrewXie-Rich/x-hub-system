import Foundation
import Darwin
import AppKit
import LocalAuthentication
import Combine
import SwiftUI
import RELFlowHubCore

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

// If a Process is still running when it deinitializes, Foundation throws an ObjC exception which
// aborts the entire app. We keep a small bounded set of "leaked" processes as a last resort to
// prevent startup crashes if we fail to terminate within our timeouts.
@MainActor private var runCaptureLeakedProcs: [Process] = []
@MainActor private func leakRunningCaptureProcess(_ p: Process) {
    runCaptureLeakedProcs.append(p)
    if runCaptureLeakedProcs.count > 8 {
        runCaptureLeakedProcs.removeFirst(runCaptureLeakedProcs.count - 8)
    }
}

@MainActor
private func runCapture(_ exe: String, _ args: [String], env: [String: String] = [:], timeoutSec: Double = 1.2) -> (code: Int32, out: String, err: String) {
    ProcessCaptureSupport.runCapture(
        exe,
        args,
        env: env,
        timeoutSec: timeoutSec
    )
}

private let suppressedHubNotificationDedupePrefixes = [
    "x_terminal_supervisor_heartbeat",
    "x_terminal_supervisor_memory_follow_up_",
    "x_terminal_supervisor_incident_",
    "x_terminal_supervisor_lane_health_",
    "x_terminal_project_action_",
    "x_terminal_operator_channel_xt_command_",
    "x_terminal_hub_connector_ingress_",
]

private func shouldRetainHubNotification(_ notification: HubNotification) -> Bool {
    let dedupeKey = (notification.dedupeKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !dedupeKey.isEmpty,
       suppressedHubNotificationDedupePrefixes.contains(where: { dedupeKey.hasPrefix($0) }) {
        return false
    }
    if hubNotificationUsesTerminalDeepLink(notification) {
        return false
    }
    return true
}

private let genericLocalProviderImportProbeScript = """
import importlib.util
import sys

ready = []
errors = []

if all(importlib.util.find_spec(name) is not None for name in ("mlx_lm", "mlx", "numpy")):
    ready.append("mlx")
else:
    errors.append("mlx:missing_module")

try:
    import transformers  # type: ignore
    import torch  # type: ignore
    from PIL import Image  # type: ignore
    _ = Image
    ready.append("transformers")
    ready.append("mlx_vlm")
except Exception as exc:
    errors.append(f"transformers:{type(exc).__name__}:{exc}")

print("ready=" + ",".join(ready))
if not ready and errors:
    print("errors=" + " | ".join(errors[:2]))
sys.exit(0 if ready else 1)
"""

private let mlxImportProbeScript = """
import importlib.util
import sys

if all(importlib.util.find_spec(name) is not None for name in ("mlx_lm", "mlx", "numpy")):
    print("ready=mlx")
    sys.exit(0)

print("errors=mlx:missing_module")
sys.exit(1)
"""

private let transformersImportProbeScript = """
import sys

try:
    import transformers  # type: ignore
    import torch  # type: ignore
    from PIL import Image  # type: ignore
    _ = Image
    print("ready=transformers,mlx_vlm")
    sys.exit(0)
except Exception as exc:
    print(f"errors=transformers:{type(exc).__name__}:{exc}")
    sys.exit(1)
"""

private func providerImportProbeScript(for preferredProviderID: String?) -> String {
    switch preferredProviderID?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() {
    case "mlx":
        return mlxImportProbeScript
    case "transformers", "mlx_vlm":
        return transformersImportProbeScript
    default:
        return genericLocalProviderImportProbeScript
    }
}

private func hubRuntimeProbeEnv() -> [String: String] {
    [
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_DATASETS_OFFLINE": "1",
        "TOKENIZERS_PARALLELISM": "false",
    ]
}

private func pythonSnippetArgs(baseArgs: [String], code: String) -> [String] {
    baseArgs.first == "python3" ? ["python3", "-c", code] : ["-c", code]
}

private func normalizeLocalRuntimePythonPath(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    guard expanded.hasPrefix("/") else { return expanded }
    return URL(fileURLWithPath: expanded).standardizedFileURL.path
}

private func localRuntimePythonPathLooksRunnable(_ path: String) -> Bool {
    let normalized = normalizeLocalRuntimePythonPath(path)
    guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return false
    }
    if normalized.contains("/.lmstudio/extensions/backends/vendor/") {
        return true
    }
    if FileManager.default.isExecutableFile(atPath: normalized) {
        return true
    }
    guard FileManager.default.fileExists(atPath: normalized) else {
        return false
    }
    let filename = URL(fileURLWithPath: normalized).lastPathComponent.lowercased()
    guard filename == "env" || filename == "python" || filename.hasPrefix("python") else {
        return false
    }

    // Sandboxed builds can occasionally report false negatives for executability on
    // inherited LM Studio vendor runtimes even though Process can still launch them.
    return false
}

private func isUnsafeLocalRuntimePythonPath(_ path: String) -> Bool {
    let normalized = normalizeLocalRuntimePythonPath(path).lowercased()
    guard !normalized.isEmpty else { return false }
    if normalized == "/usr/bin/python3" || normalized == "/usr/bin/python" {
        return true
    }
    return normalized.contains("/applications/xcode.app/contents/developer/")
        || normalized.contains("/library/developer/commandlinetools/")
}

private func readyProvidersFromProbeOutput(_ output: String) -> [String] {
    let lines = output.split(whereSeparator: \.isNewline).map(String.init)
    guard let readyLine = lines.first(where: { $0.hasPrefix("ready=") }) else { return [] }
    return readyLine
        .dropFirst("ready=".count)
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func prependingPythonPathEntries(
    _ entries: [String],
    to environment: [String: String]
) -> [String: String] {
    guard !entries.isEmpty else { return environment }
    var updated = environment
    let existing = (updated["PYTHONPATH"] ?? "")
        .split(separator: ":")
        .map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var ordered: [String] = []
    var seen = Set<String>()

    for entry in entries + existing {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let normalized = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            .standardizedFileURL
            .path
        guard seen.insert(normalized).inserted else { continue }
        ordered.append(normalized)
    }

    updated["PYTHONPATH"] = ordered.joined(separator: ":")
    return updated
}

private func managedOfflinePythonPathEntries(baseDir: URL? = nil) -> [String] {
    let resolvedBase = baseDir ?? SharedPaths.ensureHubDirectory()
    let offlineRoots: [URL] = [
        SharedPaths.realHomeDirectory()
            .appendingPathComponent(SharedPaths.legacyRuntimeDirectoryName, isDirectory: true)
            .appendingPathComponent("py_deps", isDirectory: true),
        resolvedBase.appendingPathComponent("py_deps", isDirectory: true),
    ]

    for root in offlineRoots {
        let marker = root.appendingPathComponent("USE_PYTHONPATH")
        let site = root.appendingPathComponent("site-packages", isDirectory: true)
        guard FileManager.default.fileExists(atPath: marker.path),
              FileManager.default.directoryExists(atPath: site.path) else {
            continue
        }
        return [site.path]
    }
    return []
}

private func prependingManagedOfflinePythonPathEntries(
    baseDir: URL? = nil,
    to environment: [String: String]
) -> [String: String] {
    prependingPythonPathEntries(
        managedOfflinePythonPathEntries(baseDir: baseDir),
        to: environment
    )
}

private typealias LocalPythonProbeResult = LocalPythonRuntimeCandidateStatus

private final class LocalPythonProbeCacheEntry: NSObject {
    let result: LocalPythonProbeResult?
    let cachedAt: TimeInterval

    init(result: LocalPythonProbeResult?, cachedAt: TimeInterval) {
        self.result = result
        self.cachedAt = cachedAt
    }
}

private enum LocalPythonProbeCache {
    nonisolated(unsafe) private static let cache = NSCache<NSString, LocalPythonProbeCacheEntry>()
    private static let cacheTTLSeconds: TimeInterval = 20.0

    @MainActor
    static func cachedResult(
        forPath path: String,
        preferredProviderID: String? = nil
    ) -> (hit: Bool, result: LocalPythonProbeResult?) {
        let key = cacheKey(path: path, preferredProviderID: preferredProviderID)
        let now = Date().timeIntervalSince1970
        guard let entry = cache.object(forKey: key),
              now - entry.cachedAt <= cacheTTLSeconds else {
            return (false, nil)
        }
        return (true, entry.result)
    }

    @MainActor
    static func store(
        _ result: LocalPythonProbeResult?,
        forPath path: String,
        preferredProviderID: String? = nil
    ) {
        let key = cacheKey(path: path, preferredProviderID: preferredProviderID)
        guard let result else {
            cache.removeObject(forKey: key)
            return
        }
        cache.setObject(
            LocalPythonProbeCacheEntry(
                result: result,
                cachedAt: Date().timeIntervalSince1970
            ),
            forKey: key
        )
    }

    @MainActor
    static func clear() {
        cache.removeAllObjects()
    }

    @MainActor
    private static func cacheKey(
        path: String,
        preferredProviderID: String?
    ) -> NSString {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath: String
        if trimmedPath.contains("/") {
            normalizedPath = URL(fileURLWithPath: (trimmedPath as NSString).expandingTildeInPath)
                .standardizedFileURL
                .path
        } else {
            normalizedPath = trimmedPath
        }
        let providerID = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return "\(normalizedPath)|\(providerID)" as NSString
    }
}

private struct ResolvedLocalRuntimePythonLaunch {
    var executable: String
    var snippetArgumentsPrefix: [String]
    var environment: [String: String]
    var baseDirPath: String
    var resolvedPythonPath: String
}

private func scorePythonProbe(version: String, readyProviders: [String], preferredProviderID: String? = nil) -> Int {
    var score = 0
    let preferredProvider = preferredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if !preferredProvider.isEmpty, readyProviders.contains(preferredProvider) {
        score += 8
    }
    if readyProviders.contains("transformers") {
        score += 6
    }
    if readyProviders.contains("mlx") {
        score += 4
    }
    if version.hasPrefix("3.11") {
        score += 2
    } else if version.hasPrefix("3.") {
        score += 1
    }
    return score
}

@MainActor
private func runLocalPythonVersionProbe(_ path: String) -> (code: Int32, out: String, err: String) {
    let args = ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"]
    var lastResult = runCapture(path, args, timeoutSec: 1.2)
    let lastOutput = { (result: (code: Int32, out: String, err: String)) in
        (result.out.isEmpty ? result.err : result.out).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if lastResult.code == 0, !lastOutput(lastResult).contains("xcrun") {
        return lastResult
    }

    // Freshly-written wrappers can transiently miss the first probe under load.
    usleep(80_000)
    lastResult = runCapture(path, args, timeoutSec: 1.2)
    return lastResult
}

@MainActor
private func probeLocalPython(_ path: String, preferredProviderID: String? = nil) -> LocalPythonProbeResult? {
    let normalized = (path as NSString).expandingTildeInPath
    let cached = LocalPythonProbeCache.cachedResult(
        forPath: normalized,
        preferredProviderID: preferredProviderID
    )
    if cached.hit {
        return cached.result
    }
    guard localRuntimePythonPathLooksRunnable(normalized) else {
        LocalPythonProbeCache.store(nil, forPath: normalized, preferredProviderID: preferredProviderID)
        return nil
    }
    guard !isUnsafeLocalRuntimePythonPath(normalized) else {
        LocalPythonProbeCache.store(nil, forPath: normalized, preferredProviderID: preferredProviderID)
        return nil
    }

    let versionResult = runLocalPythonVersionProbe(normalized)
    let versionOutput = (versionResult.out.isEmpty ? versionResult.err : versionResult.out)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard versionResult.code == 0, !versionOutput.contains("xcrun") else {
        LocalPythonProbeCache.store(nil, forPath: normalized, preferredProviderID: preferredProviderID)
        return nil
    }

    let probeArgs = ["-c", providerImportProbeScript(for: preferredProviderID)]
    let baseEnvironment = hubRuntimeProbeEnv()
    var bestReadyProviders: [String] = []
    var bestPythonPathEntries: [String] = []
    var bestScore = Int.min

    let supplementalEntries = LocalPythonRuntimeDiscovery.supplementalPythonPathEntries(
        forPythonPath: normalized
    )
    let offlineEntries = managedOfflinePythonPathEntries()
    var probeEnvironments: [([String: String], [String])] = []
    var seenProbeSignatures: Set<String> = []

    func appendProbeEnvironment(_ entries: [String]) {
        let environment = prependingPythonPathEntries(entries, to: baseEnvironment)
        let signature = environment["PYTHONPATH"] ?? ""
        guard seenProbeSignatures.insert(signature).inserted else { return }
        probeEnvironments.append((environment, entries))
    }

    appendProbeEnvironment([])
    appendProbeEnvironment(supplementalEntries)
    appendProbeEnvironment(offlineEntries)
    appendProbeEnvironment(offlineEntries + supplementalEntries)

    for (environment, pythonPathEntries) in probeEnvironments {
        let probeResult = runCapture(
            normalized,
            probeArgs,
            env: environment,
            timeoutSec: 4.0
        )
        let readyProviders = readyProvidersFromProbeOutput(probeResult.out)
        let score = scorePythonProbe(
            version: versionOutput,
            readyProviders: readyProviders,
            preferredProviderID: preferredProviderID
        )
        if score > bestScore {
            bestScore = score
            bestReadyProviders = readyProviders
            bestPythonPathEntries = pythonPathEntries
        }
    }

    let result = LocalPythonProbeResult(
        path: normalized,
        version: versionOutput,
        readyProviders: bestReadyProviders,
        score: bestScore,
        environmentPythonPathEntries: bestPythonPathEntries
    )
    LocalPythonProbeCache.store(result, forPath: normalized, preferredProviderID: preferredProviderID)
    return result
}

@MainActor
var hubAuditDatabaseURLProvider: @Sendable () -> URL = {
    SharedPaths.ensureHubDirectory()
        .appendingPathComponent("hub_grpc", isDirectory: true)
        .appendingPathComponent("hub.sqlite3")
}

@MainActor
func appendSupervisorProjectActionAuditToHubDB(_ payload: IPCSupervisorProjectActionAuditPayload) -> Bool {
    let eventId = payload.eventId.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectId = payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectName = payload.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionEventType = payload.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
    let severity = payload.severity.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionTitle = payload.actionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let actionSummary = payload.actionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    let whyItMatters = payload.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
    let nextAction = payload.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
    let deliveryChannel = payload.deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines)
    let deliveryStatus = payload.deliveryStatus.trimmingCharacters(in: .whitespacesAndNewlines)
    let auditRef = payload.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !eventId.isEmpty,
          !projectId.isEmpty,
          !projectName.isEmpty,
          !actionEventType.isEmpty,
          !severity.isEmpty,
          !actionTitle.isEmpty,
          !actionSummary.isEmpty,
          !whyItMatters.isEmpty,
          !nextAction.isEmpty,
          !deliveryChannel.isEmpty,
          !deliveryStatus.isEmpty,
          !auditRef.isEmpty else {
        return false
    }

    let dbURL = hubAuditDatabaseURLProvider()
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        return false
    }

    let occurredAtMs = max(0, payload.occurredAtMs)
    let createdAtMs = occurredAtMs > 0 ? occurredAtMs : Int64(Date().timeIntervalSince1970 * 1000.0)
    let storedEventType = "supervisor.project_action.\(actionEventType)"
    let source = payload.source?.trimmingCharacters(in: .whitespacesAndNewlines)
    let jurisdictionRole = payload.jurisdictionRole?.trimmingCharacters(in: .whitespacesAndNewlines)
    let grantedScope = payload.grantedScope?.trimmingCharacters(in: .whitespacesAndNewlines)

    let ext: [String: Any] = [
        "event_id": eventId,
        "project_id": projectId,
        "project_name": projectName,
        "event_type": actionEventType,
        "severity": severity,
        "action_title": actionTitle,
        "action_summary": actionSummary,
        "why_it_matters": whyItMatters,
        "next_action": nextAction,
        "occurred_at_ms": occurredAtMs,
        "delivery_channel": deliveryChannel,
        "delivery_status": deliveryStatus,
        "jurisdiction_role": jurisdictionRole ?? "",
        "granted_scope": grantedScope ?? "",
        "audit_ref": auditRef,
        "audit_event_type": "supervisor.project_action.delivery",
        "source": source ?? "x_terminal_supervisor",
    ]
    guard JSONSerialization.isValidJSONObject(ext),
          let extData = try? JSONSerialization.data(withJSONObject: ext, options: []),
          let extJSON = String(data: extData, encoding: .utf8) else {
        return false
    }

    func sqlQuoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "''"))'"
    }
    func sqlNullable(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "NULL" }
        return sqlQuoted(text)
    }

    let sql = """
PRAGMA busy_timeout=1500;
INSERT OR IGNORE INTO audit_events(
  event_id, event_type, created_at_ms, severity,
  device_id, user_id, app_id, project_id, session_id,
  request_id, capability, model_id,
  prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate,
  network_allowed, ok, error_code, error_message, duration_ms, ext_json
) VALUES (
  \(sqlQuoted("supervisor_project_action_\(auditRef.lowercased())")), \(sqlQuoted(storedEventType)), \(createdAtMs), \(sqlQuoted(severity)),
  'x_terminal', 'x_terminal', 'x_terminal', \(sqlQuoted(projectId)),
  NULL, \(sqlQuoted(eventId)),
  'supervisor_project_action_feed', NULL,
  NULL, NULL, NULL, NULL,
  NULL, 1, NULL, NULL,
  NULL, \(sqlQuoted(extJSON))
);
"""

    let result = runCapture("/usr/bin/sqlite3", [dbURL.path, sql], timeoutSec: 1.5)
    return result.code == 0
}

@MainActor
private func waitForProcessExit(_ p: Process, timeoutSec: Double) -> Bool {
    ProcessWaitSupport.waitForExit(p, timeoutSec: timeoutSec)
}

struct HubResolvedRoutingBinding: Equatable {
    var taskType: String
    var taskLabel: String
    var effectiveModelId: String
    var source: String
    var hubDefaultModelId: String
    var deviceOverrideModelId: String
}

enum HubStoreNotificationCopy {
    static func pairingApprovedTitle() -> String {
        HubUIStrings.Notifications.Delivery.pairingApprovedTitle
    }

    static func pairingApprovedBody(subject: String) -> String {
        HubUIStrings.Notifications.Delivery.pairingApprovedBody(subject: subject)
    }

    static func pairingApproveFailedTitle() -> String {
        HubUIStrings.Notifications.Delivery.pairingApproveFailedTitle
    }

    static func pairingDeniedTitle() -> String {
        HubUIStrings.Notifications.Delivery.pairingDeniedTitle
    }

    static func pairingDeniedBody(subject: String) -> String {
        HubUIStrings.Notifications.Delivery.pairingDeniedBody(subject: subject)
    }

    static func pairingDenyFailedTitle() -> String {
        HubUIStrings.Notifications.Delivery.pairingDenyFailedTitle
    }

    static func operatorChannelReviewTitle(for decision: HubOperatorChannelOnboardingDecisionKind) -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelReviewTitle(for: decision)
    }

    static func operatorChannelReviewBody(provider: String, conversationId: String, status: String) -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelReviewBody(
            provider: provider,
            conversationId: conversationId,
            status: status
        )
    }

    static func operatorChannelRetryCompleteTitle() -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelRetryCompleteTitle
    }

    static func operatorChannelRetryCompleteBody(
        ticketId: String,
        deliveredCount: Int,
        pendingCount: Int
    ) -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelRetryCompleteBody(
            ticketId: ticketId,
            deliveredCount: deliveredCount,
            pendingCount: pendingCount
        )
    }

    static func operatorChannelReviewFailedTitle() -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelReviewFailedTitle
    }

    static func operatorChannelRevokedTitle() -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelRevokedTitle
    }

    static func operatorChannelRevokedBody(provider: String, conversationId: String, status: String) -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelRevokedBody(
            provider: provider,
            conversationId: conversationId,
            status: status
        )
    }

    static func operatorChannelRevokeFailedTitle() -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelRevokeFailedTitle
    }

    static func operatorChannelStatusLabel(_ status: String) -> String {
        HubUIStrings.Notifications.Delivery.operatorChannelStatusLabel(status)
    }
}

private enum HubPairingOwnerAuthenticationError: LocalizedError {
    case unavailable(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This Mac cannot verify the local Hub owner right now."
                : trimmed
        case .cancelled:
            return "Local owner approval was cancelled. The pairing request stays pending."
        case .failed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "Local owner authentication failed. The pairing request stays pending."
                : trimmed
        }
    }

    static func from(_ error: Error) -> HubPairingOwnerAuthenticationError {
        if let authError = error as? HubPairingOwnerAuthenticationError {
            return authError
        }
        if let laError = error as? LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return .cancelled
            case .biometryNotAvailable, .passcodeNotSet, .biometryLockout:
                return .unavailable(laError.localizedDescription)
            default:
                return .failed(laError.localizedDescription)
            }
        }
        return .failed((error as NSError).localizedDescription)
    }
}

func hubNormalizedPairedDeviceCapabilityFocusKey(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    let normalized = trimmed
        .lowercased()
        .replacingOccurrences(of: "-", with: ".")
        .replacingOccurrences(of: "_", with: ".")
        .replacingOccurrences(of: " ", with: "")

    switch normalized {
    case "web.fetch", "网页抓取":
        return "web.fetch"
    case "ai.generate.paid", "付费ai":
        return "ai.generate.paid"
    case "ai.generate.local", "本地ai":
        return "ai.generate.local"
    default:
        return nil
    }
}

func hubPairedDeviceCapabilityFocusTitle(_ capabilityKey: String?) -> String? {
    switch hubNormalizedPairedDeviceCapabilityFocusKey(capabilityKey) {
    case "web.fetch":
        return HubUIStrings.MainPanel.PairingScope.webFetch
    case "ai.generate.paid":
        return HubUIStrings.MainPanel.PairingScope.paidAI
    case "ai.generate.local":
        return HubUIStrings.MainPanel.PairingScope.localAI
    default:
        return nil
    }
}

enum HubSettingsNavigationTarget: Equatable {
    case pairedDevices(deviceID: String?, capabilityKey: String?)
}

enum ModelTrialCategory: Equatable {
    case running
    case success
    case quota
    case rateLimit
    case auth
    case config
    case network
    case runtime
    case unsupported
    case timeout
    case failed
}

struct ModelTrialStatus: Equatable {
    enum State: Equatable {
        case running
        case success
        case failure
    }

    var state: State
    var category: ModelTrialCategory
    var summary: String
    var detail: String
    var updatedAt: TimeInterval

    var isRunning: Bool {
        state == .running
    }
}

func hubClassifyModelTrialFailure(_ message: String) -> ModelTrialCategory {
    let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return .failed }

    if normalized.contains("quota")
        || normalized.contains("insufficient quota")
        || normalized.contains("insufficient_quota")
        || normalized.contains("usage limit")
        || normalized.contains("you've hit your usage limit")
        || normalized.contains("rate limit resets")
        || normalized.contains("resets on")
        || normalized.contains("upgrade to plus")
        || normalized.contains("额度")
        || normalized.contains("余额")
        || normalized.contains("billing")
        || normalized.contains("credit balance") {
        return .quota
    }
    if normalized.contains("rate limit")
        || normalized.contains("too many requests")
        || normalized.contains("rpm limit")
        || normalized.contains("tpm limit")
        || normalized.contains("requests per min")
        || normalized.contains("限流") {
        return .rateLimit
    }
    if normalized.contains("api key")
        || normalized.contains("x-api-key")
        || normalized.contains("unauthorized")
        || normalized.contains("authentication")
        || normalized.contains("forbidden")
        || normalized.contains("401")
        || normalized.contains("403") {
        return .auth
    }
    if normalized.contains("base url")
        || normalized.contains("model id")
        || normalized.contains("model_not_found")
        || normalized.contains("remote_model_not_found")
        || normalized.contains("bad_req_id")
        || normalized.contains("bad_json")
        || normalized.contains("invalid response")
        || normalized.contains("挂到可执行面")
        || normalized.contains("load 再试")
        || normalized.contains("配置")
        || normalized.contains("未设置")
        || normalized.contains("缺少模型") {
        return .config
    }
    if normalized.contains("timeout")
        || normalized.contains("timed out")
        || normalized.contains("超时") {
        return .timeout
    }
    if normalized.contains("network")
        || normalized.contains("fetch_failed")
        || normalized.contains("cannot connect")
        || normalized.contains("could not connect")
        || normalized.contains("connection")
        || normalized.contains("offline")
        || normalized.contains("dns")
        || normalized.contains("socket") {
        return .network
    }
    if normalized.contains("unsupported")
        || normalized.contains("不支持") {
        return .unsupported
    }
    if normalized.contains("runtime")
        || normalized.contains("provider")
        || normalized.contains("python")
        || normalized.contains("quick bench")
        || normalized.contains("运行时")
        || normalized.contains("warmup")
        || normalized.contains("text-generate") {
        return .runtime
    }
    return .failed
}

private enum LocalModelTrialPath {
    case textGenerate
    case quickBench(taskKind: String, fixtureProfile: String)
}

private let modelTrialPrompt = "Reply with exactly HUB_OK. No extra words."

@MainActor
final class HubStore: ObservableObject {
    static let shared = HubStore()
    private static let localModelHealthAutoScanScheduleKey = "relflowhub_local_model_health_auto_scan_schedule_v1"
    private static let remoteKeyHealthAutoScanScheduleKey = "relflowhub_remote_key_health_auto_scan_schedule_v1"

    var pairingApprovalAuthenticationOverride: ((HubPairingRequest, HubPairingApprovalDraft) async throws -> Void)? = nil
    var pairingApprovalSubmitOverride: ((HubPairingRequest, HubPairingApprovalDraft, [String]) async throws -> String?)? = nil

    @Published private(set) var notifications: [HubNotification] = []
    @Published private(set) var pairingApprovalInFlightRequestIDs: Set<String> = []
    @Published private(set) var latestPairingApprovalOutcome: HubPairingApprovalOutcomeSnapshot? = nil
    @Published var settingsNavigationTarget: HubSettingsNavigationTarget? = nil
    @Published var notificationInspectorTarget: HubNotification? = nil
    @Published var ipcStatus: String = HubUIStrings.Menu.IPC.starting
    @Published var ipcPath: String = ""

    // Optional: launcher path for FA Tracker (either a .app bundle or a .command script).
    @Published var faTrackerLauncherPath: String = UserDefaults.standard.string(forKey: "relflowhub_fatracker_launcher_path") ?? "" {
        didSet {
            UserDefaults.standard.set(faTrackerLauncherPath, forKey: "relflowhub_fatracker_launcher_path")
        }
    }

    // Preferred: open FA Tracker by bundle id (works well for DMG-installed apps; avoids file permissions).
    @Published var faTrackerBundleId: String = UserDefaults.standard.string(forKey: "relflowhub_fatracker_bundle_id") ?? "FAtracker" {
        didSet {
            UserDefaults.standard.set(faTrackerBundleId, forKey: "relflowhub_fatracker_bundle_id")
        }
    }

    private let faTrackerLauncherBookmarkKey = "relflowhub_fatracker_launcher_bookmark"

    @Published var floatingMode: FloatingMode = .orb {
        didSet {
            UserDefaults.standard.set(floatingMode.rawValue, forKey: "relflowhub_floating_mode")
        }
    }

    @Published var suppressFloatingContent: Bool = false

    @Published var meetingUrgentMinutes: Int = 5 {
        didSet {
            let v = max(1, min(30, meetingUrgentMinutes))
            if v != meetingUrgentMinutes { meetingUrgentMinutes = v }
            UserDefaults.standard.set(v, forKey: "relflowhub_meeting_urgent_minutes")
        }
    }

    @Published var showModelsDrawer: Bool = false {
        didSet {
            UserDefaults.standard.set(showModelsDrawer, forKey: "relflowhub_show_models_drawer")
        }
    }
    @Published var calendarStatus: String = HubUIStrings.Menu.calendarMigrated
    @Published private(set) var meetings: [HubMeeting] = []
    @Published private(set) var specialDaysToday: [String] = []

    // Meeting reminders (Card/orb) should stop once the user has opened the meeting.
    // We persist "dismissed until endAt" so both Card and Inbox behave consistently.
    @Published private var dismissedMeetingsUntilByKey: [String: Double] = [:]

    private let dismissedMeetingsKey = "relflowhub_dismissed_meetings_v1"

    // -------------------- AI runtime (local provider worker) --------------------
    @Published var aiRuntimeAutoStart: Bool = UserDefaults.standard.bool(forKey: "relflowhub_ai_runtime_autostart") {
        didSet {
            UserDefaults.standard.set(aiRuntimeAutoStart, forKey: "relflowhub_ai_runtime_autostart")
        }
    }
    @Published var aiRuntimePython: String = UserDefaults.standard.string(forKey: "relflowhub_ai_runtime_python") ?? "" {
        didSet {
            UserDefaults.standard.set(aiRuntimePython, forKey: "relflowhub_ai_runtime_python")
            LocalPythonProbeCache.clear()
        }
    }
    var localPythonCandidatePathsOverride: [String]? = nil {
        didSet {
            autoDetectedPythonCachePathByKey = [:]
            autoDetectedPythonCacheAtByKey = [:]
            pythonCandidateStatusCacheByKey = [:]
            pythonCandidateStatusCacheAtByKey = [:]
            LocalPythonProbeCache.clear()
        }
    }
    private var autoDetectedPythonCachePathByKey: [String: String] = [:]
    private var autoDetectedPythonCacheAtByKey: [String: TimeInterval] = [:]
    private var pythonCandidateStatusCacheByKey: [String: [LocalPythonRuntimeCandidateStatus]] = [:]
    private var pythonCandidateStatusCacheAtByKey: [String: TimeInterval] = [:]
    @Published private(set) var aiRuntimeStatusSnapshot: AIRuntimeStatus? = AIRuntimeStatusStorage.load()
    @Published private(set) var aiRuntimeStatusText: String = HubUIStrings.Settings.Advanced.Runtime.statusUnknown
    @Published private(set) var aiRuntimeLastError: String = ""
    @Published private(set) var aiRuntimeLastTestText: String = ""
    @Published private(set) var modelTrialStatusByKey: [String: ModelTrialStatus] = [:]
    @Published private(set) var localModelHealthSnapshot: LocalModelHealthSnapshot = LocalModelHealthStorage.load()
    @Published private(set) var localModelHealthScanningModelIDs: Set<String> = []
    @Published private(set) var localModelHealthScanInFlight: Bool = false
    @Published private(set) var localModelHealthAutoScanSchedule: ModelHealthAutoScanSchedule = HubStore.loadModelHealthAutoScanSchedule(
        key: HubStore.localModelHealthAutoScanScheduleKey
    )
    @Published private(set) var remoteKeyHealthSnapshot: RemoteKeyHealthSnapshot = RemoteKeyHealthStorage.load()
    @Published private(set) var remoteKeyHealthScanningKeyReferences: Set<String> = []
    @Published private(set) var remoteKeyHealthScanInFlight: Bool = false
    @Published private(set) var remoteKeyHealthAutoScanSchedule: ModelHealthAutoScanSchedule = HubStore.loadModelHealthAutoScanSchedule(
        key: HubStore.remoteKeyHealthAutoScanScheduleKey
    )
    @Published private(set) var aiRuntimeProviderSummaryText: String = ""
    @Published private(set) var aiRuntimeDoctorSummaryText: String = ""
    @Published private(set) var aiRuntimeInstallHintsText: String = ""
    @Published private(set) var aiRuntimePythonCandidatesText: String = ""
    @Published private(set) var aiRuntimeProviderHelpTextByProvider: [String: String] = [:]

    @Published private(set) var routingSettings: RoutingSettings = RoutingSettings()
    private var localModelHealthAutoScanTimer: Timer? = nil
    private var remoteKeyHealthAutoScanTimer: Timer? = nil
    private var modelHealthAutoScanCancellables: Set<AnyCancellable> = []

    // Legacy alias kept in sync for existing UI flows that still bind to a task -> model map.
    @Published private(set) var routingPreferredModelIdByTask: [String: String] = [:]

    @Published var calendarRemindMinutes: Int = 10 {
        didSet {
            let m = max(1, min(180, calendarRemindMinutes))
            if m != calendarRemindMinutes { calendarRemindMinutes = m }
            UserDefaults.standard.set(m, forKey: "relflowhub_calendar_remind_minutes")
        }
    }

    private var server: UnixSocketServer?
    private var fileIPC: FileIPC?

    // -------------------- Integrations (counts-only) --------------------
    @Published var integrationFATrackerEnabled: Bool = UserDefaults.standard.object(forKey: "relflowhub_integration_fatracker_enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(integrationFATrackerEnabled, forKey: "relflowhub_integration_fatracker_enabled")
            if !integrationFATrackerEnabled {
                removeNotificationsBySource("FAtracker")
            }
        }
    }
    @Published var integrationMailEnabled: Bool = UserDefaults.standard.bool(forKey: "relflowhub_integration_mail_enabled") {
        didSet {
            UserDefaults.standard.set(integrationMailEnabled, forKey: "relflowhub_integration_mail_enabled")
            if integrationMailEnabled {
                NSApp.activate(ignoringOtherApps: true)
                if !DockBadgeReader.ensureAccessibilityTrusted(prompt: true) {
                    // On newer macOS builds, the prompt may not surface reliably; open the page.
                    SystemSettingsLinks.openAccessibilityPrivacy()
                }
                // Pull counts immediately so users see something right away.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.pollDockBadgeIntegrations()
                }
            } else {
                removeNotificationByDedupeKey("mail_unread")
            }
            updateIntegrationsPolling()
            updateIntegrationsPresence()
        }
    }
    @Published var integrationMessagesEnabled: Bool = UserDefaults.standard.bool(forKey: "relflowhub_integration_messages_enabled") {
        didSet {
            UserDefaults.standard.set(integrationMessagesEnabled, forKey: "relflowhub_integration_messages_enabled")
            if integrationMessagesEnabled {
                NSApp.activate(ignoringOtherApps: true)
                if !DockBadgeReader.ensureAccessibilityTrusted(prompt: true) {
                    SystemSettingsLinks.openAccessibilityPrivacy()
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.pollDockBadgeIntegrations()
                }
            } else {
                removeNotificationByDedupeKey("messages_unread")
            }
            updateIntegrationsPolling()
            updateIntegrationsPresence()
        }
    }
    @Published var integrationSlackEnabled: Bool = UserDefaults.standard.bool(forKey: "relflowhub_integration_slack_enabled") {
        didSet {
            UserDefaults.standard.set(integrationSlackEnabled, forKey: "relflowhub_integration_slack_enabled")
            if integrationSlackEnabled {
                NSApp.activate(ignoringOtherApps: true)
                if !DockBadgeReader.ensureAccessibilityTrusted(prompt: true) {
                    SystemSettingsLinks.openAccessibilityPrivacy()
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.pollDockBadgeIntegrations()
                }
            } else {
                removeNotificationByDedupeKey("slack_updates")
            }
            updateIntegrationsPolling()
            updateIntegrationsPresence()
        }
    }

    @Published private(set) var integrationsStatusText: String = ""
    @Published private(set) var integrationsDebugText: String = ""
    @Published private(set) var pendingNetworkRequests: [HubNetworkRequest] = []
    @Published private(set) var networkPolicySnapshot: HubNetworkPolicyList = HubNetworkPolicyStorage.load()
    @Published private(set) var pendingPairingRequests: [HubPairingRequest] = []
    @Published private(set) var pendingOperatorChannelOnboardingTickets: [HubOperatorChannelOnboardingTicket] = []
    @Published private(set) var recentOperatorChannelOnboardingTickets: [HubOperatorChannelOnboardingTicket] = []

    private var integrationsPollTimer: Timer?
    private var integrationsPresenceTimer: Timer?

    private var lastClientTouchById: [String: Double] = [:]
    // When an external agent pushes counts-only notifications (mail/messages/slack), we
    // temporarily disable the built-in polling for that key to avoid fighting updates.
    private var externalCountsUpdateAtByKey: [String: Double] = [:]
    private var demoSatellitesTimer: Timer?
    private var demoSatellitesEndAt: Double = 0

    private var persistNotificationsTimer: Timer?

    private var aiRuntimeProcess: Process?
    private var aiRuntimeLogHandle: FileHandle?
    private var aiRuntimeMonitorTimer: Timer?
    private var networkRequestsTimer: Timer?
    private var pairingRequestsTimer: Timer?
    private var operatorChannelOnboardingTimer: Timer?
    private var alwaysOnKeepaliveTimer: Timer?
    private var aiRuntimeLastLaunchAt: Double = 0
    private var aiRuntimeStopRequestedAt: Double = 0
    private var aiRuntimeNextStartAttemptAt: Double = 0
    private var aiRuntimeFailCount: Int = 0
    // If a teammate upgrades the DMG while an older runtime process is still running,
    // the UI can start sending new commands (e.g. `bench`) that the old script does not
    // recognize, resulting in `unknown_action`. Restart once per app run when we detect
    // a runtime version mismatch.
    private var didForceRestartRuntimeForVersionMismatch: Bool = false
    let bridge = BridgeSupport.shared
    let grpc = HubGRPCServerSupport.shared
    let models = ModelStore.shared
    let clients = ClientStore.shared

    private static let defaultAlwaysOnSeconds: Int = 8 * 60 * 60

    private static func loadModelHealthAutoScanSchedule(key: String) -> ModelHealthAutoScanSchedule {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ModelHealthAutoScanSchedule.self, from: data) else {
            return ModelHealthAutoScanSchedule(mode: .disabled)
        }
        return decoded.normalized()
    }

    private func saveModelHealthAutoScanSchedule(_ schedule: ModelHealthAutoScanSchedule, key: String) {
        guard let data = try? JSONEncoder().encode(schedule.normalized()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    init(startServices: Bool = true) {
        HubDiagnostics.log("HubStore.init pid=\(getpid()) appPath=\(Bundle.main.bundleURL.path)")
        // Hub-side calendar access is retired; clear any old opt-in so launch never prompts.
        UserDefaults.standard.set(false, forKey: "relflowhub_integration_calendar_enabled")
        if UserDefaults.standard.object(forKey: "relflowhub_integration_mail_enabled") == nil {
            integrationMailEnabled = false
        }
        if UserDefaults.standard.object(forKey: "relflowhub_integration_messages_enabled") == nil {
            integrationMessagesEnabled = false
        }
        if UserDefaults.standard.object(forKey: "relflowhub_integration_slack_enabled") == nil {
            integrationSlackEnabled = false
        }

        // For DMG installs we want a good out-of-box experience: the runtime should come up
        // automatically once the user loads a model.
        if UserDefaults.standard.object(forKey: "relflowhub_ai_runtime_autostart") == nil {
            aiRuntimeAutoStart = true
        }

        loadNotificationsFromDisk()

        if let s = UserDefaults.standard.string(forKey: "relflowhub_floating_mode"),
           let m = FloatingMode(rawValue: s) {
            floatingMode = m
        }

        let um = UserDefaults.standard.integer(forKey: "relflowhub_meeting_urgent_minutes")
        if um > 0 { meetingUrgentMinutes = max(1, min(30, um)) }

        showModelsDrawer = UserDefaults.standard.bool(forKey: "relflowhub_show_models_drawer")

        let m = UserDefaults.standard.integer(forKey: "relflowhub_calendar_remind_minutes")
        if m > 0 { calendarRemindMinutes = m }
        if startServices {
            startIPC()
            startNetworkRequestsPolling()
            startPairingRequestsPolling()
            startOperatorChannelOnboardingPolling()
            startAlwaysOnKeepalive()
            setupNotificationsAuthorizationState()
            refreshCalendarStatusOnly()
        }

        loadDismissedMeetings()

        if aiRuntimePython.isEmpty {
            // Keep launch non-blocking. Full python/provider probing is expensive and can
            // starve first-window creation if we do it during HubStore initialization.
            aiRuntimePython = defaultPythonPath()
        }
        if startServices {
            startAIRuntimeMonitoring()
        }

        loadRoutingSettings()

        // Counts-only integrations (Mail/Messages/Slack) are driven by Dock badges.
        if startServices {
            updateIntegrationsPolling()
            updateIntegrationsPresence()
            configureModelHealthAutoScanMonitoring()
        }

        // Ensure derived state is correct after restoring notifications.
        sort()
        updateSummary()
    }

    private func hubBaseDirURL() -> URL {
        // Keep consistent with FileIPC's base directory choice.
        let group = SharedPaths.appGroupDirectory()
        let container = SharedPaths.containerDataDirectory()?.appendingPathComponent("RELFlowHub", isDirectory: true)
        return group ?? container ?? SharedPaths.ensureHubDirectory()
    }

    func refreshIntegrationsNow() {
        updateIntegrationsPolling()
        pollDockBadgeIntegrations()
        updateIntegrationsPresence()
    }

    private func updateIntegrationsPresence() {
        let any = integrationMailEnabled || integrationMessagesEnabled || integrationSlackEnabled
        if !any {
            integrationsPresenceTimer?.invalidate()
            integrationsPresenceTimer = nil
            removeIntegrationPresenceFiles()
            return
        }

        if integrationsPresenceTimer == nil {
            // Keep integration satellites alive under the 12s TTL.
            integrationsPresenceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.writeIntegrationPresenceFiles()
                }
            }
        }
        writeIntegrationPresenceFiles()
    }

    private func removeIntegrationPresenceFiles() {
        let dir = ClientStorage.dir()
        let ids = ["sys_calendar", "sys_mail", "sys_messages", "sys_slack"]
        for id in ids {
            let url = dir.appendingPathComponent("\(id).json")
            try? FileManager.default.removeItem(at: url)
        }
        clients.refresh()
    }

    private func writeIntegrationPresenceFiles() {
        let now = Date().timeIntervalSince1970
        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func upsert(id: String, name: String, enabled: Bool) {
            let url = dir.appendingPathComponent("\(id).json")
            guard enabled else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            let hb = HubClientHeartbeat(appId: id, appName: name, activity: .idle, aiEnabled: false, updatedAt: now)
            if let data = try? JSONEncoder().encode(hb) {
                try? data.write(to: url, options: .atomic)
            }
        }

        upsert(id: "sys_calendar", name: "Calendar", enabled: false)
        upsert(id: "sys_mail", name: "Mail", enabled: integrationMailEnabled)
        upsert(id: "sys_messages", name: "Messages", enabled: integrationMessagesEnabled)
        upsert(id: "sys_slack", name: "Slack", enabled: integrationSlackEnabled)

        // Pull immediately so the floating orb reflects it quickly.
        clients.refresh()
    }

    private func updateIntegrationsPolling() {
        let any = integrationMailEnabled || integrationMessagesEnabled || integrationSlackEnabled
        if !any {
            integrationsPollTimer?.invalidate()
            integrationsPollTimer = nil
            integrationsStatusText = HubUIStrings.Settings.Doctor.legacyCountsOff
            return
        }

        if integrationsPollTimer == nil {
            // Keep it light; this is counts-only.
            integrationsPollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.pollDockBadgeIntegrations()
                }
            }
        }
        pollDockBadgeIntegrations()
    }

    private func pollDockBadgeIntegrations() {
        let now = Date().timeIntervalSince1970
        func hasRecentExternalUpdate(_ key: String) -> Bool {
            guard let t = externalCountsUpdateAtByKey[key] else { return false }
            return (now - t) < 90.0
        }

        let trusted = DockBadgeReader.ensureAccessibilityTrusted(prompt: false)
        if !trusted {
            integrationsStatusText = HubUIStrings.Settings.Doctor.legacyCountsAccessibilityRequired
            let bid = Bundle.main.bundleIdentifier ?? "(unknown)"
            let appPath = Bundle.main.bundleURL.path
            var dbg: [String] = [
                HubUIStrings.Settings.Doctor.legacyDebugAXTrusted(false),
                HubUIStrings.Settings.Doctor.legacyDebugBundleID(bid),
                HubUIStrings.Settings.Doctor.legacyDebugAppPath(appPath),
                HubUIStrings.Settings.Doctor.legacyCountsAccessibilityHint,
            ]
            if integrationMailEnabled { dbg.append(HubUIStrings.Settings.Doctor.legacyDebugSkipped(app: "Mail")) }
            if integrationMessagesEnabled { dbg.append(HubUIStrings.Settings.Doctor.legacyDebugSkipped(app: "Messages")) }
            if integrationSlackEnabled { dbg.append(HubUIStrings.Settings.Doctor.legacyDebugSkipped(app: "Slack")) }
            integrationsDebugText = dbg.joined(separator: "\n")
            return
        }

        // Prefer Dock badge counts (best for Slack). If the Dock AX tree is inaccessible
        // on this OS build, fall back to AppleScript for Mail/Messages (counts-only).
        func resolvedCounts(bundleId: String, preferAppleScript: Bool) -> (ok: Bool, count: Int, debug: String) {
            let dock = DockBadgeReader.badgeCountForBundleId(bundleId)
            if dock.debug.hasPrefix("dock_item_not_found") {
                if preferAppleScript {
                    if bundleId == "com.apple.mail" {
                        let r = AppleScriptCountsReader.mailUnreadCount()
                        if r.ok { return (true, r.count, "fallback:\(r.debug)") }
                        return (dock.ok, dock.count, "dock=\(dock.debug) applescript=\(r.debug)")
                    }
                    if bundleId == "com.apple.MobileSMS" {
                        let r = AppleScriptCountsReader.messagesUnreadCount()
                        if r.ok { return (true, r.count, "fallback:\(r.debug)") }
                        return (dock.ok, dock.count, "dock=\(dock.debug) applescript=\(r.debug)")
                    }
                }
            }
            return (dock.ok, dock.count, dock.debug)
        }

        let mail: (ok: Bool, count: Int, debug: String)? = {
            guard integrationMailEnabled else { return nil }
            // If a Dock agent is feeding us counts, don't fight it.
            if hasRecentExternalUpdate("mail_unread") {
                return nil
            }
            return resolvedCounts(bundleId: "com.apple.mail", preferAppleScript: true)
        }()

        // Messages: if Dock AX traversal is unavailable, fall back to external counts feeds.
        // AppleScript support for Messages is inconsistent across OS versions.
        let msgDock = integrationMessagesEnabled ? DockBadgeReader.badgeCountForBundleId("com.apple.MobileSMS") : nil
        let msg: (ok: Bool, count: Int, debug: String)? = {
            guard let msgDock else { return nil }
            if hasRecentExternalUpdate("messages_unread") { return nil }
            if msgDock.debug.contains("dockChildren=0") {
                return nil
            }
            // If Dock traversal works, use it; avoids extra Automation prompts.
            return (msgDock.ok, msgDock.count, msgDock.debug)
        }()
        // In macOS 26, sandboxed apps may not be able to enumerate the Dock AX tree
        // (dockChildren=0). In that case, Slack should be powered by an external Dock agent.
        let slackDock = integrationSlackEnabled ? DockBadgeReader.badgeCountForBundleId("com.tinyspeck.slackmacgap") : nil
        let slack: (ok: Bool, count: Int, debug: String)? = {
            guard let slackDock else { return nil }
            if hasRecentExternalUpdate("slack_updates") { return nil }
            if slackDock.debug.contains("dockChildren=0") {
                return nil
            }
            return (slackDock.ok, slackDock.count, slackDock.debug)
        }()

        var debugParts: [String] = [HubUIStrings.Settings.Doctor.legacyDebugAXTrusted(true)]
        if integrationMailEnabled {
            if let mail {
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugDetail(app: "Mail", detail: mail.debug))
            } else if hasRecentExternalUpdate("mail_unread") {
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugUseDockAgent(app: "Mail"))
            } else {
                // Shouldn't happen, but keep it explicit.
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugUnknown(app: "Mail"))
            }
        }
        if integrationMessagesEnabled {
            if let msg {
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugDetail(app: "Messages", detail: msg.debug))
            } else {
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugUseDockAgent(app: "Messages"))
            }
        }
        if integrationSlackEnabled {
            if let slack {
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugDetail(app: "Slack", detail: slack.debug))
            } else {
                debugParts.append(HubUIStrings.Settings.Doctor.legacyDebugUseDockAgent(app: "Slack"))
            }
        }
        integrationsDebugText = debugParts.joined(separator: "\n")

        var parts: [String] = []
        if let mail { parts.append(HubUIStrings.Settings.Doctor.legacyCountsItem(app: "Mail", count: mail.count)) }
        if let msg { parts.append(HubUIStrings.Settings.Doctor.legacyCountsItem(app: "Messages", count: msg.count)) }
        if let slack { parts.append(HubUIStrings.Settings.Doctor.legacyCountsItem(app: "Slack", count: slack.count)) }
        integrationsStatusText = HubUIStrings.Settings.Doctor.legacyCountsSummary(parts)

        if let mail { upsertCountsOnlyNotification(source: "Mail", bundleId: "com.apple.mail", count: mail.count, dedupeKey: "mail_unread") }
        if let msg { upsertCountsOnlyNotification(source: "Messages", bundleId: "com.apple.MobileSMS", count: msg.count, dedupeKey: "messages_unread") }
        if let slack { upsertCountsOnlyNotification(source: "Slack", bundleId: "com.tinyspeck.slackmacgap", count: slack.count, dedupeKey: "slack_updates") }
    }

    private func lastSeenCountKey(_ dedupeKey: String) -> String {
        "relflowhub_seen_count_\(dedupeKey)"
    }

    private func setLastSeenCount(_ n: Int, dedupeKey: String) {
        UserDefaults.standard.set(max(0, n), forKey: lastSeenCountKey(dedupeKey))
    }

    private func getLastSeenCount(dedupeKey: String) -> Int {
        max(0, UserDefaults.standard.integer(forKey: lastSeenCountKey(dedupeKey)))
    }

    func upsertCountsOnlyNotification(source: String, bundleId: String, count: Int, dedupeKey: String) {
        let c = max(0, count)

        // If cleared, remove any existing sticky notification.
        if c == 0 {
            removeNotificationByDedupeKey(dedupeKey)
            // Keep last-seen in sync so a future increase triggers correctly.
            setLastSeenCount(0, dedupeKey: dedupeKey)
            return
        }

        // If the user read items inside the app, badge may decrease; ensure the
        // baseline doesn't get stuck at a higher value.
        let seen = min(getLastSeenCount(dedupeKey: dedupeKey), c)
        setLastSeenCount(seen, dedupeKey: dedupeKey)

        let shouldRemind = c > seen

        // Preserve createdAt unless the count increased (so the card/inbox doesn't "refresh" constantly).
        let existing = notifications.first(where: { $0.dedupeKey == dedupeKey })
        let prevCount = existing.flatMap { firstInt(in: $0.body) } ?? existing.flatMap { firstInt(in: $0.title) } ?? 0
        let createdAt: Double = (existing == nil || c > prevCount) ? Date().timeIntervalSince1970 : (existing?.createdAt ?? Date().timeIntervalSince1970)

        let n = HubNotification(
            id: existing?.id ?? UUID().uuidString,
            source: source,
            title: source,
            body: "\(c) unread",
            createdAt: createdAt,
            dedupeKey: dedupeKey,
            actionURL: "relflowhub://openapp?bundle_id=\(bundleId)",
            snoozedUntil: existing?.snoozedUntil,
            unread: shouldRemind
        )

        // IMPORTANT: do not call push(n) here.
        // push() has a special handling branch for counts-only dedupe keys that calls
        // upsertCountsOnlyNotification(), which would recurse and crash the app when
        // an external agent pushes counts-only notifications.
        if let idx = notifications.firstIndex(where: { $0.dedupeKey == dedupeKey }) {
            notifications[idx] = n
        } else {
            notifications.append(n)
        }
        updateSummary()
        sort()
        schedulePersistNotifications()
    }

    private func firstInt(in s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func removeNotificationByDedupeKey(_ key: String) {
        guard !key.isEmpty else { return }
        if let idx = notifications.firstIndex(where: { $0.dedupeKey == key }) {
            notifications.remove(at: idx)
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func removeNotification(dedupeKey: String?, id: String?) {
        let normalizedDedupeKey = dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedDedupeKey.isEmpty || !normalizedID.isEmpty else { return }

        let removedIDs = notifications
            .filter { notification in
                if !normalizedID.isEmpty, notification.id == normalizedID {
                    return true
                }
                if !normalizedDedupeKey.isEmpty, notification.dedupeKey == normalizedDedupeKey {
                    return true
                }
                return false
            }
            .map(\.id)

        guard !removedIDs.isEmpty else { return }
        notifications.removeAll { removedIDs.contains($0.id) }
        if let inspector = notificationInspectorTarget,
           removedIDs.contains(inspector.id) {
            notificationInspectorTarget = nil
        }
        updateSummary()
        sort()
        schedulePersistNotifications()
    }

    private func removeNotificationsBySource(_ source: String) {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if src.isEmpty { return }
        let before = notifications.count
        notifications.removeAll(where: { $0.source == src })
        if notifications.count != before {
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    private func loadDismissedMeetings() {
        guard let data = UserDefaults.standard.data(forKey: dismissedMeetingsKey) else {
            dismissedMeetingsUntilByKey = [:]
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: Double] = [:]
            for (k, v) in obj {
                if let d = v as? Double {
                    out[k] = d
                } else if let n = v as? NSNumber {
                    out[k] = n.doubleValue
                }
            }
            dismissedMeetingsUntilByKey = out
        } else {
            dismissedMeetingsUntilByKey = [:]
        }
        pruneDismissedMeetings(now: Date().timeIntervalSince1970)
    }

    private func saveDismissedMeetings() {
        // Keep it small: only store future entries.
        let now = Date().timeIntervalSince1970
        pruneDismissedMeetings(now: now)
        let obj: [String: Any] = dismissedMeetingsUntilByKey
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
            UserDefaults.standard.set(data, forKey: dismissedMeetingsKey)
        }
    }

    private func pruneDismissedMeetings(now: Double) {
        if dismissedMeetingsUntilByKey.isEmpty { return }
        // Allow a small grace period after end.
        let cutoff = now - 60.0
        let trimmed = dismissedMeetingsUntilByKey.filter { _, until in
            until > cutoff
        }
        if trimmed.count != dismissedMeetingsUntilByKey.count {
            dismissedMeetingsUntilByKey = trimmed
        }
    }

    private func meetingDismissKey(_ m: HubMeeting) -> String {
        // Include startAt so dismissing one occurrence does not hide future recurring events.
        "\(m.id)|\(Int(m.startAt))"
    }

    func isMeetingDismissed(_ m: HubMeeting, now: Double = Date().timeIntervalSince1970) -> Bool {
        let until = dismissedMeetingsUntilByKey[meetingDismissKey(m)] ?? 0
        return until > now
    }

    func openMeeting(_ m: HubMeeting) {
        // Mark as dismissed first so card/orb stop reminding immediately even if the app switch takes time.
        if !m.id.isEmpty {
            dismissedMeetingsUntilByKey[meetingDismissKey(m)] = m.endAt
            saveDismissedMeetings()
        }
        if let s = m.joinURL, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        } else {
            // If we can't open a join link, show main UI so user can see details.
            NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
        }
    }

    func dismissedMeetingsCount(now: Double = Date().timeIntervalSince1970) -> Int {
        pruneDismissedMeetings(now: now)
        return dismissedMeetingsUntilByKey.count
    }

    func clearDismissedMeetings() {
        dismissedMeetingsUntilByKey = [:]
        UserDefaults.standard.removeObject(forKey: dismissedMeetingsKey)
    }

    func loadRoutingSettings() {
        applyRoutingSettings(RoutingSettingsStorage.load(), persist: false)
    }

    func saveRoutingSettings(_ settings: RoutingSettings) {
        applyRoutingSettings(settings, persist: true)
    }

    func setRoutingPreferredModel(taskType: String, modelId: String?, deviceId: String? = nil) {
        var updated = routingSettings
        updated.setModelId(modelId, for: taskType, deviceId: deviceId)
        saveRoutingSettings(updated)
    }

    func hubDefaultRoutingModelId(taskType: String) -> String {
        routingPreferredModelIdByTask[normalizedRoutingToken(taskType)] ?? ""
    }

    func deviceRoutingModelId(taskType: String, deviceId: String) -> String {
        let normalizedDeviceId = normalizedRoutingToken(deviceId)
        let normalizedTaskType = normalizedRoutingToken(taskType)
        guard !normalizedDeviceId.isEmpty, !normalizedTaskType.isEmpty else { return "" }
        return routingSettings.devicePreferredModelIdByTaskKind[normalizedDeviceId]?[normalizedTaskType] ?? ""
    }

    func resolvedRoutingBinding(taskType: String, deviceId: String? = nil) -> HubResolvedRoutingBinding {
        let normalizedTaskType = normalizedRoutingToken(taskType)
        let resolved = routingSettings.resolvedModelId(taskKind: normalizedTaskType, deviceId: deviceId)
        return HubResolvedRoutingBinding(
            taskType: normalizedTaskType,
            taskLabel: routingTaskLabel(normalizedTaskType),
            effectiveModelId: resolved.modelId,
            source: resolved.source,
            hubDefaultModelId: hubDefaultRoutingModelId(taskType: normalizedTaskType),
            deviceOverrideModelId: deviceRoutingModelId(taskType: normalizedTaskType, deviceId: deviceId ?? "")
        )
    }

    func hubDefaultLocalTaskSummary(forModelId modelId: String, taskKinds: [String]) -> String {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModelId.isEmpty else { return "" }
        let labels = LocalTaskRoutingCatalog
            .supportedTaskKinds(in: taskKinds)
            .filter { hubDefaultRoutingModelId(taskType: $0) == normalizedModelId }
            .map { LocalTaskRoutingCatalog.shortTitle(for: $0) }
        return labels.joined(separator: ", ")
    }

    func routingSourceLabel(_ rawSource: String) -> String {
        switch normalizedRoutingToken(rawSource) {
        case "request_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.requestOverride
        case "device_override":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.deviceOverride
        case "hub_default":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.hubDefault
        case "auto_selected":
            return HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected
        default:
            return rawSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected
                : rawSource
        }
    }

    func refreshNetworkRequests() {
        let list = HubNetworkRequestStorage.load()
        pendingNetworkRequests = list.requests.sorted { a, b in
            a.createdAt > b.createdAt
        }
    }

    func refreshPairingRequests() {
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Avoid piling up requests when the control plane is temporarily down (e.g. gRPC server not started yet).
            if self.pairingPollInFlight { return }
            self.pairingPollInFlight = true
            defer { self.pairingPollInFlight = false }

            do {
                let reqs = try await PairingHTTPClient.listPending(adminToken: adminToken, grpcPort: grpcPort)
                self.pendingPairingRequests = reqs.sorted { a, b in
                    a.createdAtMs > b.createdAtMs
                }
            } catch {
                // Silent failure: pairing server may not be running yet.
                self.pendingPairingRequests = []
            }
        }
    }

    func refreshOperatorChannelOnboardingTickets() {
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.operatorChannelOnboardingPollInFlight { return }
            self.operatorChannelOnboardingPollInFlight = true
            defer { self.operatorChannelOnboardingPollInFlight = false }

            do {
                let tickets = try await OperatorChannelsOnboardingHTTPClient.listTickets(
                    adminToken: adminToken,
                    grpcPort: grpcPort
                )
                self.pendingOperatorChannelOnboardingTickets = tickets
                    .filter { $0.isOpen }
                    .sorted { lhs, rhs in
                        if lhs.displayStatus != rhs.displayStatus {
                            return lhs.displayStatus == "pending"
                        }
                        return lhs.updatedAtMs > rhs.updatedAtMs
                    }
                self.recentOperatorChannelOnboardingTickets = tickets
                    .filter { !$0.isOpen }
                    .sorted { lhs, rhs in
                        lhs.updatedAtMs > rhs.updatedAtMs
                    }
            } catch {
                self.pendingOperatorChannelOnboardingTickets = []
                self.recentOperatorChannelOnboardingTickets = []
            }
        }
    }

    enum NetworkDecision {
        case queued
        case autoApproved(Int)
        case denied(String)
    }

    func reloadNetworkPolicySnapshot() {
        networkPolicySnapshot = HubNetworkPolicyStorage.load()
    }

    private static func matchingNetworkPolicy(
        appId: String,
        projectId: String,
        policies: [HubNetworkPolicyRule]
    ) -> HubNetworkPolicyRule? {
        let normalizedAppID = HubNetworkPolicyStorage.canonicalAppId(appId)
        let normalizedProjectID = projectId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func score(_ rule: HubNetworkPolicyRule) -> Int {
            let ruleAppID = HubNetworkPolicyStorage.canonicalAppId(rule.appId)
            let ruleProjectID = rule.projectId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let appMatches = ruleAppID == "*" || ruleAppID == normalizedAppID
            let projectMatches = ruleProjectID == "*" || ruleProjectID == normalizedProjectID
            if !appMatches || !projectMatches { return -1 }

            var total = 0
            if ruleAppID == normalizedAppID { total += 2 }
            if ruleProjectID == normalizedProjectID { total += 1 }
            return total
        }

        var bestRule: HubNetworkPolicyRule?
        var bestScore = -1
        for rule in policies {
            let currentScore = score(rule)
            if currentScore > bestScore {
                bestScore = currentScore
                bestRule = rule
            }
        }
        return bestRule
    }

    func handleNetworkRequest(_ req: HubNetworkRequest) -> NetworkDecision {
        let appId = Self.policyAppId(for: req)
        let projectId = Self.policyProjectId(for: req)

        if let rule = Self.matchingNetworkPolicy(
            appId: appId,
            projectId: projectId,
            policies: networkPolicySnapshot.policies
        ) {
            switch rule.mode {
            case .deny:
                return .denied("denied_by_policy")
            case .autoApprove:
                let requested = max(10, req.requestedSeconds ?? 900)
                let maxSecs = max(10, rule.maxSeconds ?? requested)
                let secs = min(requested, maxSecs)
                grantNetwork(seconds: secs, openBridge: true)
                return .autoApproved(secs)
            case .alwaysOn:
                // Always-on means "keep networking available" rather than "cap a single request".
                //
                // - If maxSeconds is set: treat it as the desired enable window.
                // - If maxSeconds is unset: default to a long window so clients don't have to keep re-requesting.
                let requested = max(10, req.requestedSeconds ?? 900)
                let desired = max(10, rule.maxSeconds ?? max(requested, Self.defaultAlwaysOnSeconds))
                grantNetwork(seconds: desired, openBridge: true)
                return .autoApproved(desired)
            case .manual:
                _ = HubNetworkRequestStorage.add(req)
                refreshNetworkRequests()
                return .queued
            }
        }

        if let seconds = Self.defaultAutoApproveSeconds(for: req, appId: appId) {
            grantNetwork(seconds: seconds, openBridge: true)
            return .autoApproved(seconds)
        }

        _ = HubNetworkRequestStorage.add(req)
        refreshNetworkRequests()
        return .queued
    }

    func appendSupervisorIncidentAudit(_ payload: IPCSupervisorIncidentAuditPayload) -> Bool {
        let eventType = payload.eventType.trimmingCharacters(in: .whitespacesAndNewlines)
        let incidentCode = payload.incidentCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let denyCode = payload.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let auditRef = payload.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let laneId = payload.laneId.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskId = payload.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        let incidentId = payload.incidentId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !eventType.isEmpty,
              eventType.hasPrefix("supervisor.incident."),
              eventType.hasSuffix(".handled"),
              !incidentCode.isEmpty,
              !denyCode.isEmpty,
              !auditRef.isEmpty,
              !laneId.isEmpty else {
            return false
        }

        let dbURL = hubAuditDatabaseURLProvider()
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return false
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let detectedAtMs = max(0, payload.detectedAtMs)
        let handledAtMs = max(0, payload.handledAtMs ?? detectedAtMs)
        let createdAtMs = max(0, handledAtMs > 0 ? handledAtMs : nowMs)
        let durationMs: Int64? = {
            if let explicit = payload.takeoverLatencyMs, explicit >= 0 {
                return explicit
            }
            if handledAtMs >= detectedAtMs {
                return handledAtMs - detectedAtMs
            }
            return nil
        }()

        let eventIdSeed = auditRef.lowercased()
        let eventId = "supervisor_incident_\(eventIdSeed)"
        let projectId = payload.projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = payload.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = payload.proposedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = payload.status.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = payload.source?.trimmingCharacters(in: .whitespacesAndNewlines)

        let ext: [String: Any] = [
            "incident_id": incidentId,
            "lane_id": laneId,
            "task_id": taskId,
            "project_id": projectId ?? "",
            "incident_code": incidentCode,
            "event_type": eventType,
            "deny_code": denyCode,
            "proposed_action": action,
            "severity": payload.severity.trimmingCharacters(in: .whitespacesAndNewlines),
            "category": payload.category.trimmingCharacters(in: .whitespacesAndNewlines),
            "detected_at_ms": detectedAtMs,
            "handled_at_ms": handledAtMs,
            "takeover_latency_ms": durationMs ?? NSNull(),
            "audit_ref": auditRef,
            "audit_event_type": "supervisor.incident.handled",
            "detail": detail ?? "",
            "status": status,
            "source": source ?? "x_terminal_supervisor",
        ]
        guard JSONSerialization.isValidJSONObject(ext),
              let extData = try? JSONSerialization.data(withJSONObject: ext, options: []),
              let extJSON = String(data: extData, encoding: .utf8) else {
            return false
        }

        func sqlQuoted(_ text: String) -> String {
            "'\(text.replacingOccurrences(of: "'", with: "''"))'"
        }
        func sqlNullable(_ text: String?) -> String {
            guard let text, !text.isEmpty else { return "NULL" }
            return sqlQuoted(text)
        }

        let sql = """
PRAGMA busy_timeout=1500;
INSERT OR IGNORE INTO audit_events(
  event_id, event_type, created_at_ms, severity,
  device_id, user_id, app_id, project_id, session_id,
  request_id, capability, model_id,
  prompt_tokens, completion_tokens, total_tokens, cost_usd_estimate,
  network_allowed, ok, error_code, error_message, duration_ms, ext_json
) VALUES (
  \(sqlQuoted(eventId)), \(sqlQuoted(eventType)), \(createdAtMs), \(sqlQuoted(payload.severity.trimmingCharacters(in: .whitespacesAndNewlines))),
  'x_terminal', 'x_terminal', 'x_terminal', \(sqlNullable(projectId)),
  NULL, \(sqlQuoted(incidentId.isEmpty ? auditRef : incidentId)),
  NULL, NULL,
  NULL, NULL, NULL, NULL,
  NULL, 1, \(sqlQuoted(denyCode)), \(sqlQuoted((detail?.isEmpty == false ? detail! : denyCode))),
  \(durationMs != nil ? String(durationMs!) : "NULL"), \(sqlQuoted(extJSON))
);
"""

        let result = runCapture("/usr/bin/sqlite3", [dbURL.path, sql], timeoutSec: 1.5)
        return result.code == 0
    }

    func appendSupervisorProjectActionAudit(_ payload: IPCSupervisorProjectActionAuditPayload) -> Bool {
        appendSupervisorProjectActionAuditToHubDB(payload)
    }

    func approveNetworkRequest(_ req: HubNetworkRequest, seconds: Int) {
        grantNetwork(seconds: seconds, openBridge: true)
        _ = HubNetworkRequestStorage.remove(id: req.id)
        refreshNetworkRequests()
    }

    func dismissNetworkRequest(_ req: HubNetworkRequest) {
        _ = HubNetworkRequestStorage.remove(id: req.id)
        refreshNetworkRequests()
    }

    func setNetworkPolicy(appId: String, projectId: String, mode: HubNetworkPolicyMode, maxSeconds: Int?) {
        networkPolicySnapshot = HubNetworkPolicyStorage.upsert(
            appId: appId,
            projectId: projectId,
            mode: mode,
            maxSeconds: maxSeconds
        )
    }

    func setNetworkPolicy(for req: HubNetworkRequest, mode: HubNetworkPolicyMode, maxSeconds: Int?) {
        let appId = Self.policyAppId(for: req)
        let projectId = Self.policyProjectId(for: req)
        setNetworkPolicy(appId: appId, projectId: projectId, mode: mode, maxSeconds: maxSeconds)
    }

    func currentNetworkPolicy(for req: HubNetworkRequest) -> HubNetworkPolicyRule? {
        let appId = Self.policyAppId(for: req)
        let projectId = Self.policyProjectId(for: req)
        return Self.matchingNetworkPolicy(
            appId: appId,
            projectId: projectId,
            policies: networkPolicySnapshot.policies
        )
    }

    func clearNetworkPolicy(for req: HubNetworkRequest) {
        guard let rule = currentNetworkPolicy(for: req) else { return }
        networkPolicySnapshot = HubNetworkPolicyStorage.remove(id: rule.id)
    }

    func approveNetworkRequestUsingCurrentDefault(_ req: HubNetworkRequest) {
        let appId = Self.policyAppId(for: req)
        if let seconds = Self.defaultAutoApproveSeconds(for: req, appId: appId) {
            approveNetworkRequest(req, seconds: seconds)
        } else {
            dismissNetworkRequest(req)
        }
    }

    func approveNetworkRequestAsAlwaysOn(_ req: HubNetworkRequest) {
        setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: nil)
        let requested = max(10, req.requestedSeconds ?? 900)
        let desired = max(requested, Self.defaultAlwaysOnSeconds)
        approveNetworkRequest(req, seconds: desired)
    }

    func approveNetworkRequestAsAutoApprove(_ req: HubNetworkRequest) {
        let requested = max(10, req.requestedSeconds ?? 900)
        setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: requested)
        approveNetworkRequest(req, seconds: requested)
    }

    private func startNetworkRequestsPolling() {
        refreshNetworkRequests()
        networkRequestsTimer?.invalidate()
        networkRequestsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNetworkRequests()
            }
        }
    }

    private var pairingPollInFlight: Bool = false
    private var operatorChannelOnboardingPollInFlight: Bool = false

    private func startPairingRequestsPolling() {
        refreshPairingRequests()
        pairingRequestsTimer?.invalidate()
        pairingRequestsTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPairingRequests()
            }
        }
    }

    private func startOperatorChannelOnboardingPolling() {
        refreshOperatorChannelOnboardingTickets()
        operatorChannelOnboardingTimer?.invalidate()
        operatorChannelOnboardingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshOperatorChannelOnboardingTickets()
            }
        }
    }

    func approvePairingRequest(_ req: HubPairingRequest, approval: HubPairingApprovalDraft? = nil) {
        let id = req.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard !pairingApprovalInFlightRequestIDs.contains(id) else { return }
        let draft = approval ?? HubPairingApprovalDraft.recommended(for: req)
        pairingApprovalInFlightRequestIDs.insert(id)
        Task { @MainActor in
            defer {
                pairingApprovalInFlightRequestIDs.remove(id)
            }
            do {
                let approvedDeviceID = try await approvePairingRequestAfterOwnerAuthentication(req, approval: draft)
                recordPairingApprovalOutcome(
                    .approved,
                    request: req,
                    deviceTitle: draft.normalizedDeviceName,
                    deviceID: approvedDeviceID,
                    detail: draft.approvedOutcomeDetailText
                )
                dismissPendingPairingNotification(req.pairingRequestId)
                refreshPairingRequests()
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingApprovedTitle(),
                    body: HubStoreNotificationCopy.pairingApprovedBody(subject: draft.normalizedDeviceName),
                    dedupeKey: nil,
                    actionURL: Self.pairedDevicesSettingsActionURL(deviceID: approvedDeviceID)
                ))
            } catch {
                recordPairingApprovalOutcome(
                    pairingApprovalOutcomeKind(for: error),
                    request: req,
                    deviceTitle: draft.normalizedDeviceName,
                    detail: (error as NSError).localizedDescription
                )
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingApproveFailedTitle(),
                    body: (error as NSError).localizedDescription,
                    dedupeKey: nil
                ))
            }
        }
    }

    func approvePairingRequestRecommended(_ req: HubPairingRequest) {
        approvePairingRequest(req, approval: .recommended(for: req))
    }

    func denyPairingRequest(_ req: HubPairingRequest, reason: String? = nil) {
        let id = req.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor in
            do {
                try await PairingHTTPClient.deny(pairingRequestId: id, reason: reason, adminToken: adminToken, grpcPort: grpcPort)
                recordPairingApprovalOutcome(
                    .denied,
                    request: req,
                    detail: reason
                )
                dismissPendingPairingNotification(req.pairingRequestId)
                refreshPairingRequests()
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingDeniedTitle(),
                    body: HubStoreNotificationCopy.pairingDeniedBody(subject: req.deviceName.isEmpty ? id : req.deviceName),
                    dedupeKey: nil
                ))
            } catch {
                recordPairingApprovalOutcome(
                    .denyFailed,
                    request: req,
                    detail: (error as NSError).localizedDescription
                )
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingDenyFailedTitle(),
                    body: (error as NSError).localizedDescription,
                    dedupeKey: nil
                ))
            }
        }
    }

    // Convenience: approve/deny directly from an inbox notification (dedupeKey includes pairing id).
    func approvePairingRequestId(_ pairingRequestId: String) {
        let id = pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        guard !pairingApprovalInFlightRequestIDs.contains(id) else { return }
        if let req = pendingPairingRequests.first(where: { $0.pairingRequestId == id }) {
            approvePairingRequest(req)
            return
        }
        pairingApprovalInFlightRequestIDs.insert(id)
        Task { @MainActor in
            defer {
                pairingApprovalInFlightRequestIDs.remove(id)
            }
            do {
                let fallbackReq = HubPairingRequest(
                    pairingRequestId: id,
                    requestId: id,
                    status: "pending",
                    appId: "paired-terminal",
                    claimedDeviceId: "",
                    userId: "",
                    deviceName: "",
                    peerIp: "",
                    createdAtMs: 0,
                    decidedAtMs: 0,
                    denyReason: "",
                    requestedScopes: []
                )
                let fallbackApproval = HubPairingApprovalDraft.recommended(for: fallbackReq)
                let approvedDeviceID = try await approvePairingRequestAfterOwnerAuthentication(
                    fallbackReq,
                    approval: fallbackApproval
                )
                recordPairingApprovalOutcome(
                    .approved,
                    request: fallbackReq,
                    deviceTitle: id,
                    deviceID: approvedDeviceID,
                    detail: fallbackApproval.approvedOutcomeDetailText
                )
                dismissPendingPairingNotification(id)
                refreshPairingRequests()
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingApprovedTitle(),
                    body: HubStoreNotificationCopy.pairingApprovedBody(subject: id),
                    dedupeKey: nil,
                    actionURL: Self.pairedDevicesSettingsActionURL(deviceID: approvedDeviceID)
                ))
            } catch {
                recordPairingApprovalOutcome(
                    pairingApprovalOutcomeKind(for: error),
                    request: fallbackReqForOutcome(id),
                    deviceTitle: id,
                    detail: (error as NSError).localizedDescription
                )
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingApproveFailedTitle(),
                    body: (error as NSError).localizedDescription,
                    dedupeKey: nil
                ))
            }
        }
    }

    func isPairingApprovalInFlight(_ req: HubPairingRequest) -> Bool {
        pairingApprovalInFlightRequestIDs.contains(
            req.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func approvePairingRequestAfterOwnerAuthentication(
        _ req: HubPairingRequest,
        approval: HubPairingApprovalDraft
    ) async throws -> String? {
        try await authenticateLocalOwnerForPairingApproval(req, approval: approval)
        let requestedScopes = req.requestedScopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let caps = approval.effectiveCapabilities(requestedScopes: requestedScopes)
        if let override = pairingApprovalSubmitOverride {
            return try await override(req, approval, caps)
        }
        return try await PairingHTTPClient.approve(
            pairingRequestId: req.pairingRequestId,
            approval: approval,
            capabilities: caps,
            allowedCidrs: nil,
            adminToken: grpc.localAdminToken(),
            grpcPort: grpc.port
        )
    }

    private func authenticateLocalOwnerForPairingApproval(
        _ req: HubPairingRequest,
        approval: HubPairingApprovalDraft
    ) async throws {
        if let override = pairingApprovalAuthenticationOverride {
            do {
                try await override(req, approval)
            } catch {
                throw HubPairingOwnerAuthenticationError.from(error)
            }
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        let reason = pairingApprovalAuthenticationReason(req, approval: approval)
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw HubPairingOwnerAuthenticationError.unavailable(
                authError?.localizedDescription ?? "Local owner authentication is not available on this Mac."
            )
        }

        do {
            let approved: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
            if !approved {
                throw HubPairingOwnerAuthenticationError.cancelled
            }
        } catch {
            throw HubPairingOwnerAuthenticationError.from(error)
        }
    }

    private func pairingApprovalAuthenticationReason(
        _ req: HubPairingRequest,
        approval: HubPairingApprovalDraft
    ) -> String {
        Self.pairingApprovalAuthenticationReasonForDisplay(req, approval: approval)
    }

    static func pairingApprovalAuthenticationReasonForDisplay(
        _ req: HubPairingRequest,
        approval: HubPairingApprovalDraft
    ) -> String {
        HubGRPCClientEntry.normalizedStrings([
            approval.deviceName,
            req.deviceName,
            req.claimedDeviceId,
            req.appId,
        ]).first.map { "Approve first pairing for \($0)" } ?? "Approve first pairing for Paired Device"
    }

    private func pairingApprovalOutcomeKind(for error: Error) -> HubPairingApprovalOutcomeKind {
        if let authError = error as? HubPairingOwnerAuthenticationError {
            switch authError {
            case .cancelled:
                return .ownerAuthenticationCancelled
            case .failed, .unavailable:
                return .ownerAuthenticationFailed
            }
        }
        return .approvalFailed
    }

    private func recordPairingApprovalOutcome(
        _ kind: HubPairingApprovalOutcomeKind,
        request: HubPairingRequest,
        deviceTitle: String? = nil,
        deviceID: String? = nil,
        detail: String? = nil
    ) {
        let normalizedDeviceTitle = HubGRPCClientEntry.normalizedStrings([
            deviceTitle ?? "",
            request.deviceName,
            request.claimedDeviceId,
            request.appId,
            request.pairingRequestId,
            "Paired Device",
        ]).first ?? "Paired Device"
        let normalizedDeviceID = deviceID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        latestPairingApprovalOutcome = HubPairingApprovalOutcomeSnapshot(
            requestID: request.pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceTitle: normalizedDeviceTitle,
            deviceID: normalizedDeviceID?.isEmpty == true ? nil : normalizedDeviceID,
            kind: kind,
            detailText: normalizedDetail?.isEmpty == true ? nil : normalizedDetail,
            occurredAt: Date().timeIntervalSince1970
        )
    }

    private func fallbackReqForOutcome(_ pairingRequestId: String) -> HubPairingRequest {
        HubPairingRequest(
            pairingRequestId: pairingRequestId,
            requestId: pairingRequestId,
            status: "pending",
            appId: "paired-terminal",
            claimedDeviceId: "",
            userId: "",
            deviceName: "",
            peerIp: "",
            createdAtMs: 0,
            decidedAtMs: 0,
            denyReason: "",
            requestedScopes: []
        )
    }

    private func dismissPendingPairingNotification(_ pairingRequestId: String) {
        let normalizedID = pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { return }
        let originalCount = notifications.count
        notifications.removeAll { notification in
            let key = (notification.dedupeKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return key == "pairing_request:\(normalizedID)"
        }
        guard notifications.count != originalCount else { return }
        updateSummary()
        schedulePersistNotifications()
    }

    func denyPairingRequestId(_ pairingRequestId: String, reason: String? = nil) {
        let id = pairingRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let req = pendingPairingRequests.first(where: { $0.pairingRequestId == id }) {
            denyPairingRequest(req, reason: reason)
            return
        }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        Task { @MainActor in
            do {
                try await PairingHTTPClient.deny(pairingRequestId: id, reason: reason, adminToken: adminToken, grpcPort: grpcPort)
                recordPairingApprovalOutcome(
                    .denied,
                    request: fallbackReqForOutcome(id),
                    deviceTitle: id,
                    detail: reason
                )
                dismissPendingPairingNotification(id)
                refreshPairingRequests()
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingDeniedTitle(),
                    body: HubStoreNotificationCopy.pairingDeniedBody(subject: id),
                    dedupeKey: nil
                ))
            } catch {
                recordPairingApprovalOutcome(
                    .denyFailed,
                    request: fallbackReqForOutcome(id),
                    deviceTitle: id,
                    detail: (error as NSError).localizedDescription
                )
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.pairingDenyFailedTitle(),
                    body: (error as NSError).localizedDescription,
                    dedupeKey: nil
                ))
            }
        }
    }

    func submitOperatorChannelOnboardingReview(
        _ ticket: HubOperatorChannelOnboardingTicket,
        decision: HubOperatorChannelOnboardingDecisionKind,
        draft: HubOperatorChannelOnboardingReviewDraft
    ) async throws -> HubOperatorChannelOnboardingReviewResult {
        let ticketId = ticket.ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticketId.isEmpty else {
            throw OperatorChannelsOnboardingHTTPClient.OnboardingError.apiError(
                code: "ticket_id_missing",
                message: HubUIStrings.Settings.OperatorChannels.Onboarding.ticketIDMissing
            )
        }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        let result = try await OperatorChannelsOnboardingHTTPClient.reviewTicket(
            ticketId: ticketId,
            decision: decision,
            draft: draft,
            adminToken: adminToken,
            grpcPort: grpcPort
        )
        refreshOperatorChannelOnboardingTickets()
        let title = HubStoreNotificationCopy.operatorChannelReviewTitle(for: decision)
        let body = HubStoreNotificationCopy.operatorChannelReviewBody(
            provider: result.ticket.provider,
            conversationId: result.ticket.conversationId,
            status: result.ticket.displayStatus
        )
        push(.make(source: "Hub", title: title, body: body, dedupeKey: nil))
        return result
    }

    func retryOperatorChannelOnboardingOutbox(
        ticketId: String,
        adminUserId: String
    ) async throws -> HubOperatorChannelOnboardingOutboxRetryResult {
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTicketId.isEmpty else {
            throw OperatorChannelsOnboardingHTTPClient.OnboardingError.apiError(
                code: "ticket_id_missing",
                message: HubUIStrings.Settings.OperatorChannels.Onboarding.ticketIDMissing
            )
        }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        let result = try await OperatorChannelsOnboardingHTTPClient.retryOutbox(
            ticketId: normalizedTicketId,
            userId: adminUserId,
            adminToken: adminToken,
            grpcPort: grpcPort
        )
        refreshOperatorChannelOnboardingTickets()
        push(.make(
            source: "Hub",
            title: HubStoreNotificationCopy.operatorChannelRetryCompleteTitle(),
            body: HubStoreNotificationCopy.operatorChannelRetryCompleteBody(
                ticketId: normalizedTicketId,
                deliveredCount: result.deliveredCount,
                pendingCount: result.pendingCount
            ),
            dedupeKey: nil
        ))
        return result
    }

    func revokeOperatorChannelOnboardingTicket(
        ticketId: String,
        adminUserId: String,
        note: String
    ) async throws -> HubOperatorChannelOnboardingRevokeResult {
        let normalizedTicketId = ticketId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTicketId.isEmpty else {
            throw OperatorChannelsOnboardingHTTPClient.OnboardingError.apiError(
                code: "ticket_id_missing",
                message: HubUIStrings.Settings.OperatorChannels.Onboarding.ticketIDMissing
            )
        }
        let adminToken = grpc.localAdminToken()
        let grpcPort = grpc.port
        let result = try await OperatorChannelsOnboardingHTTPClient.revokeTicket(
            ticketId: normalizedTicketId,
            userId: adminUserId,
            note: note,
            adminToken: adminToken,
            grpcPort: grpcPort
        )
        refreshOperatorChannelOnboardingTickets()
        push(.make(
            source: "Hub",
            title: HubStoreNotificationCopy.operatorChannelRevokedTitle(),
            body: HubStoreNotificationCopy.operatorChannelRevokedBody(
                provider: result.ticket.provider,
                conversationId: result.ticket.conversationId,
                status: result.ticket.displayStatus
            ),
            dedupeKey: nil
        ))
        return result
    }

    func reviewOperatorChannelOnboardingTicket(
        _ ticket: HubOperatorChannelOnboardingTicket,
        decision: HubOperatorChannelOnboardingDecisionKind,
        draft: HubOperatorChannelOnboardingReviewDraft
    ) {
        Task { @MainActor in
            do {
                _ = try await submitOperatorChannelOnboardingReview(
                    ticket,
                    decision: decision,
                    draft: draft
                )
            } catch {
                push(.make(
                    source: "Hub",
                    title: HubStoreNotificationCopy.operatorChannelReviewFailedTitle(),
                    body: (error as NSError).localizedDescription,
                    dedupeKey: nil
                ))
            }
        }
    }

    private func startAlwaysOnKeepalive() {
        alwaysOnKeepaliveTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickAlwaysOnKeepalive()
            }
        }
        t.tolerance = 4.0
        alwaysOnKeepaliveTimer = t
        tickAlwaysOnKeepalive()
    }

    private func tickAlwaysOnKeepalive() {
        let rules = networkPolicySnapshot.policies.filter { $0.mode == .alwaysOn }
        guard !rules.isEmpty else { return }

        // Do not auto-launch the Bridge app. Only keep it enabled if it's already running.
        let st = bridge.statusSnapshot()
        guard st.alive else { return }

        // Since Bridge is global, use the "most permissive" always-on window to minimize renew churn.
        let desired = rules
            .map { r in max(10, r.maxSeconds ?? Self.defaultAlwaysOnSeconds) }
            .max() ?? Self.defaultAlwaysOnSeconds

        let now = Date().timeIntervalSince1970
        let remaining = st.enabledUntil - now

        // Renew early enough so short windows don't accidentally expire under app-nap / timer delays.
        let baseThreshold = Double(max(30, min(15 * 60, desired / 6)))
        let threshold = min(baseThreshold, Double(desired) * 0.5)

        if remaining <= threshold {
            bridge.enable(seconds: desired)
        }
    }

    private func grantNetwork(seconds: Int, openBridge: Bool) {
        if openBridge {
            bridge.restore(seconds: seconds)
            bridge.openBridgeApp()
            return
        }
        bridge.enable(seconds: seconds)
    }

    nonisolated static func policyAppId(for req: HubNetworkRequest) -> String {
        let s = (req.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = HubNetworkPolicyStorage.canonicalAppId(s)
        return canonical.isEmpty ? "unknown" : canonical
    }

    nonisolated static func policyProjectId(for req: HubNetworkRequest) -> String {
        let source = (req.source ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let displayName = (req.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPath = (req.rootPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if source == "x_terminal",
           !displayName.isEmpty,
           isTransientXTerminalSupervisorWorkspace(rootPath) {
            return displayName
        }
        if let pid = req.projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !pid.isEmpty {
            return pid
        }
        if !displayName.isEmpty {
            return displayName
        }
        if !rootPath.isEmpty {
            let name = URL(fileURLWithPath: rootPath).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "unknown"
    }

    nonisolated static func defaultAutoApproveSeconds(for req: HubNetworkRequest, appId: String) -> Int? {
        guard HubNetworkPolicyStorage.canonicalAppId(appId) == "x_terminal" else {
            return nil
        }
        return max(10, req.requestedSeconds ?? 900)
    }

    nonisolated private static func isTransientXTerminalSupervisorWorkspace(_ rootPath: String) -> Bool {
        guard !rootPath.isEmpty else { return false }
        let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path.lowercased()
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path.lowercased()
        guard normalizedRoot.hasPrefix(tempRoot) else { return false }
        let leaf = URL(fileURLWithPath: normalizedRoot).lastPathComponent.lowercased()
        return leaf.hasPrefix("xt-supervisor-call-")
    }

    private func notificationsPersistURL() -> URL {
        SharedPaths.ensureHubDirectory().appendingPathComponent("notifications.json")
    }

    private func loadNotificationsFromDisk() {
        let url = notificationsPersistURL()
        guard let data = try? Data(contentsOf: url) else { return }
        guard let arr = try? JSONDecoder().decode([HubNotification].self, from: data) else { return }

        // Keep the file bounded: only retain a small, recent window.
        // (Today-new radars remain visible even if read; older items can be dropped.)
        let now = Date().timeIntervalSince1970
        let keepAfter = now - (4 * 24 * 60 * 60) // last 4 days
        let trimmed = arr
            .filter { $0.createdAt >= keepAfter }
            .filter { shouldRetainHubNotification($0) }
            .sorted { $0.createdAt > $1.createdAt }
        notifications = Array(trimmed.prefix(200))
    }

    private func schedulePersistNotifications() {
        // Coalesce frequent updates (mark read, snooze, etc) into a single write.
        persistNotificationsTimer?.invalidate()
        persistNotificationsTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.persistNotificationsNow()
            }
        }
    }

    private func persistNotificationsNow() {
        let url = notificationsPersistURL()
        let sorted = notifications.sorted { $0.createdAt > $1.createdAt }
        let capped = Array(sorted.prefix(200))
        if let data = try? JSONEncoder().encode(capped) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private func aiRuntimeScriptNamesInPreferenceOrder() -> [String] {
        ["relflowhub_local_runtime.py", "relflowhub_mlx_runtime.py"]
    }

    private func isAIRuntimeCommandLine(_ commandLine: String) -> Bool {
        let normalized = commandLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return false
        }
        return aiRuntimeScriptNamesInPreferenceOrder().contains { normalized.contains($0.lowercased()) }
    }

    private func bundledAIRuntimeServiceRootURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }
        let candidate = resourceURL.appendingPathComponent("python_service", isDirectory: true)
        guard FileManager.default.directoryExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private func preferredAIRuntimeScriptURL(in directory: URL) -> URL? {
        for scriptName in aiRuntimeScriptNamesInPreferenceOrder() {
            let candidate = directory.appendingPathComponent(scriptName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func runtimeVersionFromScript(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else {
            return nil
        }
        let pat = "RUNTIME_VERSION\\s*=\\s*\"([^\"]+)\""
        guard let re = try? NSRegularExpression(pattern: pat, options: []) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let m = re.firstMatch(in: source, options: [], range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: source) else { return nil }
        return String(source[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveAIRuntimeScriptURL() -> URL? {
        // Prefer the bundled python_service tree for app builds.
        if let root = bundledAIRuntimeServiceRootURL(),
           let bundled = preferredAIRuntimeScriptURL(in: root) {
            return bundled
        }

        // Backward-compatible fallback for older app bundles that shipped a flat script.
        if let bundled = Bundle.main.url(forResource: "relflowhub_local_runtime", withExtension: "py") {
            return bundled
        }
        if let bundled = Bundle.main.url(forResource: "relflowhub_mlx_runtime", withExtension: "py") {
            return bundled
        }

        // Dev build fallback (repo layout; no Resources bundling).
        let p = defaultRuntimeScriptPath()
        if !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            return URL(fileURLWithPath: p)
        }

        return nil
    }

    private func resolveAIRuntimeServiceRootURL() -> URL? {
        if let bundled = bundledAIRuntimeServiceRootURL() {
            return bundled
        }
        let p = defaultRuntimePythonServicePath()
        if !p.isEmpty, FileManager.default.directoryExists(atPath: p) {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        guard let scriptURL = resolveAIRuntimeScriptURL() else {
            return nil
        }
        let dir = scriptURL.deletingLastPathComponent()
        return dir.lastPathComponent == "python_service" ? dir : nil
    }

    func localRuntimeCommandLaunchConfig(preferredProviderID: String? = nil) -> LocalRuntimeCommandLaunchConfig? {
        let base = SharedPaths.ensureHubDirectory()
        let installedServiceRoot = base
            .appendingPathComponent("ai_runtime", isDirectory: true)
            .appendingPathComponent("python_service", isDirectory: true)
        let scriptURL = preferredAIRuntimeScriptURL(in: installedServiceRoot) ?? resolveAIRuntimeScriptURL()
        let normalizedPreferredProviderID = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let pythonLaunch = resolvedLocalRuntimePythonLaunch(
            base: base,
            preferredProviderID: preferredProviderID
        ) ?? (normalizedPreferredProviderID.isEmpty
            ? nil
            : resolvedLocalRuntimePythonLaunch(base: base, preferredProviderID: nil))
        guard let scriptURL, let pythonLaunch else {
            return nil
        }

        return LocalRuntimeCommandLaunchConfig(
            executable: pythonLaunch.executable,
            argumentsPrefix: pythonLaunch.snippetArgumentsPrefix + [scriptURL.path],
            environment: pythonLaunch.environment,
            baseDirPath: pythonLaunch.baseDirPath
        )
    }

    func canResolveLocalRuntimeCommandLaunchConfig(preferredProviderID: String? = nil) -> Bool {
        guard resolveAIRuntimeScriptURL() != nil else {
            return false
        }
        return localRuntimePythonProbeLaunchConfig(preferredProviderID: preferredProviderID) != nil
    }

    func localRuntimePythonProbeLaunchConfig(preferredProviderID: String? = nil) -> LocalRuntimePythonProbeLaunchConfig? {
        let base = SharedPaths.ensureHubDirectory()
        let normalizedPreferredProviderID = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        var resolvedPythonPath = knownReadyRuntimeSourcePythonPath(
            preferredProviderID: normalizedPreferredProviderID
        ) ?? activeRuntimeSourcePythonPath(
            preferredProviderID: normalizedPreferredProviderID
        )
        if (resolvedPythonPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedPythonPath = preferredPythonPath(
                current: currentRuntimePythonPath(),
                preferredProviderID: normalizedPreferredProviderID
            ) ?? lightweightResolvedLocalRuntimePythonPath(
                preferredProviderID: preferredProviderID
            )
        }
        if (resolvedPythonPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !normalizedPreferredProviderID.isEmpty {
            resolvedPythonPath = activeRuntimeSourcePythonPath(preferredProviderID: nil)
                ?? lightweightResolvedLocalRuntimePythonPath(preferredProviderID: nil)
        }
        guard let resolvedPythonPath,
              !resolvedPythonPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let executable: String
        let argumentsPrefix: [String]
        let normalized: String
        if resolvedPythonPath.contains("/") {
            normalized = URL(fileURLWithPath: (resolvedPythonPath as NSString).expandingTildeInPath)
                .standardizedFileURL
                .path
        } else {
            normalized = resolvedPythonPath
        }

        if (normalized as NSString).lastPathComponent == "env" {
            executable = normalized
            argumentsPrefix = ["python3"]
        } else if normalized.contains("/") {
            executable = normalized
            argumentsPrefix = []
        } else {
            executable = "/usr/bin/env"
            argumentsPrefix = [normalized]
        }

        var environment = hubRuntimeProbeEnv()
        if let probe = probeLocalPython(normalized, preferredProviderID: preferredProviderID) {
            environment = prependingPythonPathEntries(
                probe.environmentPythonPathEntries,
                to: environment
            )
        }
        environment = prependingManagedOfflinePythonPathEntries(
            baseDir: base,
            to: environment
        )

        return LocalRuntimePythonProbeLaunchConfig(
            executable: executable,
            argumentsPrefix: argumentsPrefix,
            environment: environment,
            resolvedPythonPath: normalized
        )
    }

    func preferredLocalProviderPythonPath(preferredProviderID: String? = nil) -> String? {
        localRuntimePythonProbeLaunchConfig(preferredProviderID: preferredProviderID)?.resolvedPythonPath
    }

    private func runtimeStatusSnapshots() -> [AIRuntimeStatus] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            candidates.append(url)
        }

        if let group = SharedPaths.appGroupDirectory() {
            append(group.appendingPathComponent(AIRuntimeStatusStorage.fileName))
        }
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent(AIRuntimeStatusStorage.fileName))
        }
        let shouldAddGuessedHome = SharedPaths.sandboxHomeDirectory()
            .path
            .contains("/Library/Containers/")
        if shouldAddGuessedHome, let guessedHome = SharedPaths.guessedRealUserHomeDirectory() {
            append(
                guessedHome
                    .appendingPathComponent(SharedPaths.preferredRuntimeDirectoryName, isDirectory: true)
                    .appendingPathComponent(AIRuntimeStatusStorage.fileName)
            )
            append(
                guessedHome
                    .appendingPathComponent(SharedPaths.legacyRuntimeDirectoryName, isDirectory: true)
                    .appendingPathComponent(AIRuntimeStatusStorage.fileName)
            )
        }

        var snapshots: [AIRuntimeStatus] = []
        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            let path = standardized.path
            do {
                let data = try Data(contentsOf: standardized)
                let status = try JSONDecoder().decode(AIRuntimeStatus.self, from: data)
                let providerSummary = status.providers.keys.sorted().map { providerID in
                    let state = status.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
                        ? "ready"
                        : (status.providerStatus(providerID)?.reasonCode ?? "down")
                    return "\(providerID)=\(state)"
                }.joined(separator: ",")
                appendAIRuntimeLogLine(
                    "Runtime status snapshot loaded: path=\(path) updated_at=\(status.updatedAt) providers=\(providerSummary.isEmpty ? "(none)" : providerSummary)"
                )
                snapshots.append(status)
            } catch {
                let nsError = error as NSError
                appendAIRuntimeLogLine(
                    "Runtime status snapshot skipped: path=\(path) error=\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
                )
            }
        }
        return snapshots
    }

    private func knownReadyRuntimeSourcePythonPath(preferredProviderID: String?) -> String? {
        let normalizedPreferredProviderID = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let snapshots = runtimeStatusSnapshots()
        guard !snapshots.isEmpty else {
            return nil
        }

        if !normalizedPreferredProviderID.isEmpty {
            let sorted = snapshots.sorted { lhs, rhs in
                let lhsUpdatedAt = lhs.providerStatus(normalizedPreferredProviderID)?.updatedAt ?? lhs.updatedAt
                let rhsUpdatedAt = rhs.providerStatus(normalizedPreferredProviderID)?.updatedAt ?? rhs.updatedAt
                return lhsUpdatedAt > rhsUpdatedAt
            }
            for snapshot in sorted {
                if let path = activeRuntimeSourcePythonPath(
                    providerID: normalizedPreferredProviderID,
                    runtimeStatus: snapshot
                ) {
                    return path
                }
            }
        }

        let preferredOrder = ["transformers", "mlx", "mlx_vlm", "llama.cpp"]
        let sortedSnapshots = snapshots.sorted { $0.updatedAt > $1.updatedAt }
        for providerID in preferredOrder {
            for snapshot in sortedSnapshots {
                if let path = activeRuntimeSourcePythonPath(providerID: providerID, runtimeStatus: snapshot) {
                    return path
                }
            }
        }
        for snapshot in sortedSnapshots {
            for providerID in snapshot.providers.keys.sorted() {
                if let path = activeRuntimeSourcePythonPath(providerID: providerID, runtimeStatus: snapshot) {
                    return path
                }
            }
        }
        return nil
    }

    private func activeRuntimeSourcePythonPath(
        preferredProviderID: String?,
        runtimeStatus: AIRuntimeStatus? = AIRuntimeStatusStorage.load()
    ) -> String? {
        guard let runtimeStatus,
              runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return nil
        }

        let normalizedPreferredProviderID = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if !normalizedPreferredProviderID.isEmpty {
            return activeRuntimeSourcePythonPath(
                providerID: normalizedPreferredProviderID,
                runtimeStatus: runtimeStatus
            )
        }

        let preferredOrder = ["transformers", "mlx", "mlx_vlm", "llama.cpp"]
        for providerID in preferredOrder {
            if let path = activeRuntimeSourcePythonPath(providerID: providerID, runtimeStatus: runtimeStatus) {
                return path
            }
        }
        for providerID in runtimeStatus.providers.keys.sorted() {
            if let path = activeRuntimeSourcePythonPath(providerID: providerID, runtimeStatus: runtimeStatus) {
                return path
            }
        }
        return nil
    }

    private func activeRuntimeSourcePythonPath(
        providerID: String,
        runtimeStatus: AIRuntimeStatus
    ) -> String? {
        let normalizedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProviderID.isEmpty else {
            appendAIRuntimeLogLine("Known-ready runtime source rejected: provider=(empty)")
            return nil
        }
        guard runtimeStatus.isProviderReady(normalizedProviderID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL),
              let providerStatus = runtimeStatus.providerStatus(normalizedProviderID) else {
            let reason = runtimeStatus.providerStatus(normalizedProviderID)?.reasonCode ?? "missing_provider_status"
            appendAIRuntimeLogLine(
                "Known-ready runtime source rejected: provider=\(normalizedProviderID) reason=\(reason) runtime_alive=\(runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ? "1" : "0")"
            )
            return nil
        }

        let runtimeSourcePath = providerStatus.runtimeSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runtimeSourcePath.isEmpty else {
            appendAIRuntimeLogLine(
                "Known-ready runtime source rejected: provider=\(normalizedProviderID) reason=empty_runtime_source_path"
            )
            return nil
        }

        let normalizedRuntimeSourcePath = normalizeLocalRuntimePythonPath(runtimeSourcePath)
        let executableName = URL(fileURLWithPath: normalizedRuntimeSourcePath).lastPathComponent.lowercased()
        guard executableName == "env"
                || executableName == "python"
                || executableName.hasPrefix("python") else {
            appendAIRuntimeLogLine(
                "Known-ready runtime source rejected: provider=\(normalizedProviderID) reason=unsupported_executable path=\(normalizedRuntimeSourcePath)"
            )
            return nil
        }
        guard localRuntimePythonPathLooksRunnable(normalizedRuntimeSourcePath) else {
            appendAIRuntimeLogLine(
                "Known-ready runtime source rejected: provider=\(normalizedProviderID) reason=not_runnable path=\(normalizedRuntimeSourcePath)"
            )
            return nil
        }
        appendAIRuntimeLogLine(
            "Known-ready runtime source accepted: provider=\(normalizedProviderID) path=\(normalizedRuntimeSourcePath)"
        )
        return normalizedRuntimeSourcePath
    }

    private func resolvedLocalRuntimePythonLaunch(
        base: URL,
        preferredProviderID: String? = nil
    ) -> ResolvedLocalRuntimePythonLaunch? {
        var py = aiRuntimePython.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferred = preferredPythonPath(current: py, preferredProviderID: preferredProviderID), preferred != py {
            py = preferred
            let currentStored = aiRuntimePython.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerToken = preferredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if providerToken.isEmpty || currentStored.isEmpty {
                aiRuntimePython = preferred
            }
        }

        let executable: String
        let snippetArgumentsPrefix: [String]
        let resolvedPythonPath: String
        if py.isEmpty {
            let fallback = defaultPythonPath()
            executable = fallback
            if (fallback as NSString).lastPathComponent == "env" {
                snippetArgumentsPrefix = ["python3"]
                resolvedPythonPath = "python3"
            } else {
                snippetArgumentsPrefix = []
                resolvedPythonPath = fallback
            }
        } else if py.contains("/") {
            let normalized = (py as NSString).expandingTildeInPath
            guard !FileManager.default.directoryExists(atPath: normalized) else {
                return nil
            }
            guard FileManager.default.isExecutableFile(atPath: normalized) else {
                return nil
            }
            executable = normalized
            if (normalized as NSString).lastPathComponent == "env" {
                snippetArgumentsPrefix = ["python3"]
                resolvedPythonPath = "python3"
            } else {
                snippetArgumentsPrefix = []
                resolvedPythonPath = normalized
            }
        } else {
            executable = "/usr/bin/env"
            snippetArgumentsPrefix = [py]
            resolvedPythonPath = py
        }

        var env = ProcessInfo.processInfo.environment
        env["REL_FLOW_HUB_BASE_DIR"] = base.path
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HUB_OFFLINE"] = "1"
        env["TRANSFORMERS_OFFLINE"] = "1"
        env["HF_DATASETS_OFFLINE"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        if let probe = probeLocalPython(resolvedPythonPath, preferredProviderID: preferredProviderID) {
            env = prependingPythonPathEntries(
                probe.environmentPythonPathEntries,
                to: env
            )
        }

        let offlineRoots: [URL] = [
            SharedPaths.realHomeDirectory()
                .appendingPathComponent("RELFlowHub", isDirectory: true)
                .appendingPathComponent("py_deps", isDirectory: true),
            base.appendingPathComponent("py_deps", isDirectory: true),
        ]
        for root in offlineRoots {
            let marker = root.appendingPathComponent("USE_PYTHONPATH")
            let site = root.appendingPathComponent("site-packages", isDirectory: true)
            guard FileManager.default.fileExists(atPath: marker.path),
                  FileManager.default.directoryExists(atPath: site.path) else {
                continue
            }
            let previous = env["PYTHONPATH"] ?? ""
            env["PYTHONPATH"] = site.path + (previous.isEmpty ? "" : ":" + previous)
            break
        }

        return ResolvedLocalRuntimePythonLaunch(
            executable: executable,
            snippetArgumentsPrefix: snippetArgumentsPrefix,
            environment: env,
            baseDirPath: base.path,
            resolvedPythonPath: resolvedPythonPath
        )
    }

    private func installAIRuntimeServiceRoot(from sourceRoot: URL, to destinationRoot: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationRoot.path) {
            try? fm.removeItem(at: destinationRoot)
        }
        try fm.copyItem(at: sourceRoot, to: destinationRoot)
    }



    func connectedAppSources() -> [String] {
        // Prefer client heartbeats; fallback to notification sources.
        let now = Date().timeIntervalSince1970
        let live = clients.liveClients(now: now)
        if !live.isEmpty {
            return live.map { $0.appName }.sorted()
        }
        let srcs = Set(notifications.map { $0.source }.filter { !$0.isEmpty && $0 != "Hub" })
        return srcs.sorted()
    }

    func previewItems() -> [HubNotification] {
        let now = Date().timeIntervalSince1970
        return notifications
            .filter { $0.unread && ($0.snoozedUntil ?? 0) <= now }
            .filter { hubNotificationPresentation(for: $0).group != .background }
            .prefix(5)
            .map { $0 }
    }

    func topAlert(now: Date = Date()) -> TopAlert {
        // 1) Meeting urgency: 30m (soon), 10m (hot), 5m (urgent). Urgent is configurable.
        if let m = meetings.first(where: { $0.isMeeting && !$0.id.isEmpty && !isMeetingDismissed($0, now: now.timeIntervalSince1970) }) {
            let nowTs = now.timeIntervalSince1970
            let urgentMin = max(1, meetingUrgentMinutes)
            let outerMin = max(urgentMin, calendarRemindMinutes)
            let hotMin = min(10, outerMin)

            let th = urgentMin * 60
            let hot = hotMin * 60
            let warn = outerMin * 60
            // "Urgent" window begins th seconds before start, and continues until meeting ends
            // (unless the user already opened it).
            if nowTs < m.endAt {
                let dt = Int(m.startDate.timeIntervalSince(now))
                if dt <= th {
                    if m.isMeeting || (m.joinURL ?? "").isEmpty == false {
                        return TopAlert(kind: .meetingUrgent, count: 1, urgentSecondsToMeeting: max(0, dt), urgentWindowSeconds: th)
                    }
                    // Non-meeting calendar event -> treat as a task.
                    return TopAlert(kind: .task, count: 1, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
                }

                // "Meeting hot" window: within ~10 minutes (orange), before it becomes urgent.
                if dt > 0, hotMin > urgentMin {
                    let dtSec = Double(dt)
                    let minsCeil = Int(ceil(dtSec / 60.0))
                    if minsCeil <= hotMin {
                        return TopAlert(kind: .meetingHot, count: 1, urgentSecondsToMeeting: dt, urgentWindowSeconds: hot)
                    }
                }

                // "Meeting soon" window: give a noticeable cue (amber) before it becomes urgent.
                if dt > 0 {
                    // Use minute-granularity so events that are "10m 30s" away still count as 10 minutes.
                    let dtSec = Double(dt)
                    let minsCeil = Int(ceil(dtSec / 60.0))
                    if minsCeil <= outerMin {
                        return TopAlert(kind: .meetingSoon, count: 1, urgentSecondsToMeeting: dt, urgentWindowSeconds: warn)
                    }
                }
            }
        }

        let tnow = now.timeIntervalSince1970
        let unread = notifications.filter { $0.unread && ($0.snoozedUntil ?? 0) <= tnow }
        let radar = unread.filter { isFATrackerRadarNotification($0) }
        if !radar.isEmpty {
            return TopAlert(kind: .radar, count: radar.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }
        let msgs = unread.filter { $0.source == "Messages" }
        if !msgs.isEmpty {
            return TopAlert(kind: .message, count: msgs.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }
        let mails = unread.filter { $0.source == "Mail" }
        if !mails.isEmpty {
            return TopAlert(kind: .mail, count: mails.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }
        let slacks = unread.filter { $0.source == "Slack" }
        if !slacks.isEmpty {
            return TopAlert(kind: .slack, count: slacks.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }

        // Today non-meeting events: show as task (blue).
        // (Priority is lower than radar/messages/mail.)
        let cal = Calendar.current
        let today = now
        if meetings.contains(where: { !$0.isMeeting && $0.startDate > now && cal.isDate($0.startDate, inSameDayAs: today) }) {
            let n = meetings.filter { !$0.isMeeting && $0.startDate > now && cal.isDate($0.startDate, inSameDayAs: today) }.count
            return TopAlert(kind: .task, count: n, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }

        // 5) Today tasks due: treat other unread items as tasks for now.
        let others = unread.filter {
            !["FAtracker", "Messages", "Mail", "Slack"].contains($0.source)
                && hubNotificationPresentation(for: $0).group != .background
        }
        if !others.isEmpty {
            return TopAlert(kind: .task, count: others.count, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
        }

        return TopAlert(kind: .idle, count: 0, urgentSecondsToMeeting: nil, urgentWindowSeconds: nil)
    }

    // -------------------- AI runtime (local provider worker) --------------------
    func startAIRuntimeMonitoring() {
        aiRuntimeMonitorTimer?.invalidate()
        aiRuntimeMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAIRuntimeStatus()
                self?.autoStartAIRuntimeIfNeeded()
            }
        }
        refreshAIRuntimeStatus()
        autoStartAIRuntimeIfNeeded()
    }

    private func refreshAIRuntimeStatus() {
        let st = AIRuntimeStatusStorage.load()
        aiRuntimeStatusSnapshot = st
        if let s = st {
            let alive = s.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) || (findRunningAIRuntimePid(status: st) != nil)
            let heartbeatAlive = s.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            let readyProviders = s.readyProviderIDs(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            aiRuntimeProviderSummaryText = s.providerOperatorSummary(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            aiRuntimeDoctorSummaryText = s.providerDoctorText(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            var v = HubUIStrings.Settings.Advanced.Runtime.staleKeyword
            if alive {
                if readyProviders.isEmpty {
                    v = HubUIStrings.Settings.Advanced.Runtime.runningNoProviderReady
                } else {
                    v = HubUIStrings.Settings.Advanced.Runtime.runningProviders(readyProviders.joined(separator: ", "))
                }
            }
            if heartbeatAlive {
                let expected = bundledRuntimeVersion()
                // Treat missing runtimeVersion as mismatch (older scripts didn't write it).
                if let exp = expected {
                    if (s.runtimeVersion ?? "") != exp {
                        v = HubUIStrings.Settings.Advanced.Runtime.runningRefreshNeeded
                    } else {
                        didForceRestartRuntimeForVersionMismatch = false
                    }
                } else {
                    didForceRestartRuntimeForVersionMismatch = false
                }
            } else if alive {
                // Runtime can be alive but the heartbeat stale during long inference; avoid spurious "stale".
                v = HubUIStrings.Settings.Advanced.Runtime.runningHeartbeatStale
            } else {
                didForceRestartRuntimeForVersionMismatch = false
            }
            aiRuntimeStatusText = HubUIStrings.Settings.Advanced.Runtime.statusLine(status: v, pid: s.pid)

            // Only reset backoff when the runtime is truly alive.
            if heartbeatAlive && !readyProviders.isEmpty {
                aiRuntimeFailCount = 0
                aiRuntimeNextStartAttemptAt = 0
            }

            // Surface actionable guidance only when no local provider is actually ready.
            if alive && readyProviders.isEmpty {
                let base = unavailableProvidersHelp(status: s)
                let doctorLead = s.providerDoctorText(ttl: AIRuntimeStatus.recommendedHeartbeatTTL).trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = doctorLead.isEmpty ? "" : doctorLead + "\n\n"
                let msg = prefix + base
                if !msg.isEmpty {
                    // Don't overwrite unrelated errors (e.g. python path selection).
                    if aiRuntimeLastError.isEmpty
                        || HubUIStrings.Settings.Advanced.Runtime.matchesAvailabilityHint(aiRuntimeLastError) {
                        aiRuntimeLastError = msg
                    }
                }
            } else if !readyProviders.isEmpty {
                // Clear stale availability hints once any provider is usable.
                if HubUIStrings.Settings.Advanced.Runtime.matchesAvailabilityHint(aiRuntimeLastError) {
                    aiRuntimeLastError = ""
                }
            }
        } else {
            didForceRestartRuntimeForVersionMismatch = false
            aiRuntimeStatusText = HubUIStrings.Settings.Advanced.Runtime.statusNotRunning
            aiRuntimeProviderSummaryText = HubUIStrings.Settings.Advanced.Runtime.providerSummaryNotRunning
            aiRuntimeDoctorSummaryText = HubUIStrings.Settings.Advanced.Runtime.doctorNotStarted
            aiRuntimeInstallHintsText = ""
            aiRuntimeStatusSnapshot = nil
        }
    }

    private func mlxUnavailableHelp(importError: String) -> String {
        HubUIStrings.Settings.Advanced.Runtime.mlxUnavailableHelp(importError: importError)
    }

    private func findRunningAIRuntimePid(status: AIRuntimeStatus?) -> Int32? {
        // Fast-path: runtime we launched in this process.
        if let p = aiRuntimeProcess, p.isRunning {
            return p.processIdentifier
        }

        // Next: verify the pid from the last heartbeat (even if stale).
        if let st = status, st.pid > 1 {
            let ps = runCapture("/bin/ps", ["-p", String(st.pid), "-o", "command="], timeoutSec: 0.6)
            let txt = (ps.out.isEmpty ? ps.err : ps.out).lowercased()
            if ps.code == 0, isAIRuntimeCommandLine(txt) {
                return Int32(st.pid)
            }
        }

        // Fallback: scan all processes (rare path; used when heartbeat is missing).
        let ps = runCapture("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSec: 1.0)
        let raw = (ps.out.isEmpty ? ps.err : ps.out)
        if raw.isEmpty { return nil }
        for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count < 2 { continue }
            guard let pidNum = Int32(parts[0]), pidNum > 1 else { continue }
            let cmd = String(parts[1]).lowercased()
            if !isAIRuntimeCommandLine(cmd) { continue }
            return pidNum
        }
        return nil
    }

    private func bundledRuntimeVersion() -> String? {
        // Keep version checks aligned with the legacy runtime loop that currently writes
        // ai_runtime_status.json, even when the launch entrypoint is relflowhub_local_runtime.py.
        if let root = bundledAIRuntimeServiceRootURL() {
            let legacy = root.appendingPathComponent("relflowhub_mlx_runtime.py")
            if FileManager.default.fileExists(atPath: legacy.path),
               let version = runtimeVersionFromScript(at: legacy) {
                return version
            }
            if let entry = preferredAIRuntimeScriptURL(in: root),
               let version = runtimeVersionFromScript(at: entry) {
                return version
            }
        }
        if let flatLegacy = Bundle.main.url(forResource: "relflowhub_mlx_runtime", withExtension: "py"),
           let version = runtimeVersionFromScript(at: flatLegacy) {
            return version
        }
        if let resolved = resolveAIRuntimeScriptURL() {
            return runtimeVersionFromScript(at: resolved)
        }
        return nil
    }

    private func autoStartAIRuntimeIfNeeded() {
        if !aiRuntimeAutoStart {
            return
        }
        let hasPendingRequests = pendingAIRuntimeRequests()
        // If already alive, do nothing *unless* the running runtime is an older version.
        let st = AIRuntimeStatusStorage.load()
        if let st, st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) {
            let expected = bundledRuntimeVersion()
            if let exp = expected, (st.runtimeVersion ?? "") != exp {
                if !didForceRestartRuntimeForVersionMismatch {
                    didForceRestartRuntimeForVersionMismatch = true
                    appendAIRuntimeLogLine("Detected runtime version mismatch (running=\(st.runtimeVersion ?? "") expected=\(exp)); restarting")
                    stopAIRuntime()
                    // Start immediately (ignore backoff) because the runtime was already healthy.
                    startAIRuntime()
                }
            }
            return
        }
        let now = Date().timeIntervalSince1970
        if now < aiRuntimeNextStartAttemptAt && !hasPendingRequests {
            return
        }
        // If a runtime process is already running (even with a stale heartbeat), do not auto-start another.
        // This prevents spurious "lock busy" errors during long inference.
        if findRunningAIRuntimePid(status: st) != nil {
            return
        }
        // Backoff on repeated failures. Minimum delay avoids spamming TCC prompts.
        let exp = Double(min(6, max(0, aiRuntimeFailCount)))
        let delay = hasPendingRequests ? 0.0 : min(300.0, 15.0 * pow(2.0, exp))
        aiRuntimeNextStartAttemptAt = now + delay
        startAIRuntime()
    }

    func ensureAIRuntimeRunningIfNeeded() {
        autoStartAIRuntimeIfNeeded()
    }

    private func pendingAIRuntimeRequests(baseDir: URL) -> Bool {
        let reqDir = baseDir.appendingPathComponent("ai_requests", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: reqDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return entries.contains { url in
            let name = url.lastPathComponent
            return name.hasPrefix("req_") && name.hasSuffix(".json")
        }
    }

    private func pendingAIRuntimeRequests() -> Bool {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL?) {
            guard let url else { return }
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            candidates.append(url)
        }

        append(SharedPaths.appGroupDirectory())
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base)
        }

        for candidate in candidates {
            if pendingAIRuntimeRequests(baseDir: candidate) {
                return true
            }
        }
        return false
    }

    func startAIRuntime() {
        aiRuntimeLastError = ""
        aiRuntimeStopRequestedAt = 0

        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        if LocalProviderPackRegistry.syncAutoManagedPacks(baseDir: base) {
            appendAIRuntimeLogLine("Updated provider pack registry for local helper bridge.")
        }

        // If a previous Hub instance left the runtime running, stop it first so we don't
        // end up with multiple runtimes racing on the same file IPC directories.
        if let st = AIRuntimeStatusStorage.load(), st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) {
            stopAIRuntime()
        }

        // Keep logging useful even when we fail early (e.g. lock busy).
        let logURL = base.appendingPathComponent("ai_runtime.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        do {
            if aiRuntimeLogHandle == nil {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                aiRuntimeLogHandle = handle
            } else {
                try aiRuntimeLogHandle?.seekToEnd()
            }
        } catch {
            // Non-fatal; continue without log.
            aiRuntimeLogHandle = nil
        }

        appendAIRuntimeLogLine("==== start attempt ==== (autoStart=\(aiRuntimeAutoStart)) (base=\(base.path))")

        // Do not start a second copy if we already launched one.
        if let p = aiRuntimeProcess, p.isRunning {
            return
        }

        // Preflight: if the runtime lock is held, avoid starting a process that will
        // immediately exit with code 0 (and cause an auto-start loop).
        if isAIRuntimeLockBusy(baseDir: base) {
            let lockURL = base.appendingPathComponent("ai_runtime.lock")
            // Treat as "already running". Users can click Stop to force a restart.
            appendAIRuntimeLogLine("Preflight: lock busy (runtime already running) (\(lockURL.path))")
            refreshAIRuntimeStatus()
            return
        }

        let resolved = resolveAIRuntimeScriptURL()
        let serviceRoot = resolveAIRuntimeServiceRootURL()
        let scriptURL: URL? = resolved.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard let scriptURL else {
            aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.packagedRuntimeScriptMissing
            aiRuntimeFailCount += 1
            return
        }

        // Copy the runtime into App Group so the sandboxed child process can read the full
        // python_service tree (provider registry, legacy runtime fallback, etc).
        let rtDir = base.appendingPathComponent("ai_runtime", isDirectory: true)
        try? FileManager.default.createDirectory(at: rtDir, withIntermediateDirectories: true)
        let rtScript: URL
        do {
            if let serviceRoot, FileManager.default.directoryExists(atPath: serviceRoot.path) {
                let destinationRoot = rtDir.appendingPathComponent("python_service", isDirectory: true)
                if serviceRoot.path != destinationRoot.path {
                    try installAIRuntimeServiceRoot(from: serviceRoot, to: destinationRoot)
                    appendAIRuntimeLogLine("Copied runtime service root to base: \(destinationRoot.path)")
                }
                guard let installed = preferredAIRuntimeScriptURL(in: destinationRoot) else {
                    throw NSError(
                        domain: "relflowhub",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.installedRuntimeScriptsMissing
                        ]
                    )
                }
                rtScript = installed
            } else {
                rtScript = rtDir.appendingPathComponent(scriptURL.lastPathComponent)
                if scriptURL.path != rtScript.path {
                    if FileManager.default.fileExists(atPath: rtScript.path) {
                        try? FileManager.default.removeItem(at: rtScript)
                    }
                    try FileManager.default.copyItem(at: scriptURL, to: rtScript)
                    appendAIRuntimeLogLine("Copied runtime script to base: \(rtScript.path)")
                }
            }
        } catch {
            aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.installRuntimeToBaseFailed(error.localizedDescription)
            aiRuntimeFailCount += 1
            return
        }

        let p = Process()
        var py = aiRuntimePython.trimmingCharacters(in: .whitespacesAndNewlines)
        let bootstrapProviderID = runtimeBootstrapPreferredProviderID()
        let knownReadyPythonPath = knownReadyRuntimeSourcePythonPath(preferredProviderID: bootstrapProviderID)
        let preferredPythonSelection = preferredPythonPath(
            current: py,
            preferredProviderID: bootstrapProviderID
        )
        let exe: String
        var args: [String] = []

        appendAIRuntimeLogLine(
            "Runtime python selection: configured=\(py.isEmpty ? "(auto)" : py) provider=\(bootstrapProviderID ?? "(none)") known_ready=\(knownReadyPythonPath ?? "(none)") preferred=\(preferredPythonSelection ?? "(none)")"
        )

        // Prefer a python that can actually satisfy the available local providers. If the stored
        // path still points at an old default interpreter, auto-promote to a better local venv.
        if let preferred = preferredPythonSelection, preferred != py {
            py = preferred
            aiRuntimePython = preferred
        }
        if py.isEmpty {
            // Fall back to a reasonable python. If the fallback is /usr/bin/env, we must
            // pass "python3" explicitly; otherwise env will try to execute the script.
            exe = defaultPythonPath()
            if (exe as NSString).lastPathComponent == "env" {
                args = ["python3", rtScript.path]
            } else {
                args = [rtScript.path]
            }
        } else if py.contains("/") {
            // Absolute path: must be an executable file, not a directory like site-packages.
            let norm = (py as NSString).expandingTildeInPath
            if FileManager.default.directoryExists(atPath: norm) {
                aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.pythonPathDirectory
                aiRuntimeFailCount += 1
                return
            }
            if !localRuntimePythonPathLooksRunnable(norm) {
                aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.pythonPathNotExecutable
                aiRuntimeFailCount += 1
                return
            }
            exe = norm
            if (norm as NSString).lastPathComponent == "env" {
                args = ["python3", rtScript.path]
            } else {
                args = [rtScript.path]
            }
        } else {
            // Treat as "python3" style: run through env.
            exe = "/usr/bin/env"
            args = [py, rtScript.path]
        }

        // Preflight: reject xcrun stub python which cannot run inside App Sandbox.
        do {
            let probeArgs = args.first == "python3"
                ? ["python3", "-c", "import sys; print(sys.executable); print(sys.version)"]
                : ["-c", "import sys; print(sys.executable); print(sys.version)"]
            let test = runCapture(exe, probeArgs, timeoutSec: 1.2)
            let testOutputLines = (test.out.isEmpty ? test.err : test.out)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            let resolvedPython = testOutputLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if test.out.contains("xcrun")
                || test.err.contains("xcrun")
                || isUnsafeLocalRuntimePythonPath(resolvedPython) {
                aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.pythonPathXcrunStub
                aiRuntimeFailCount += 1
                return
            }
        }

        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["REL_FLOW_HUB_BASE_DIR"] = base.path
        env["PYTHONUNBUFFERED"] = "1"
        for (key, value) in hubRuntimeProbeEnv() {
            env[key] = value
        }
        let launchPythonPath = args.first == "python3"
            ? ""
            : normalizeLocalRuntimePythonPath(py.isEmpty ? exe : py)
        if !launchPythonPath.isEmpty,
           let probe = probeLocalPython(launchPythonPath, preferredProviderID: bootstrapProviderID) {
            env = prependingPythonPathEntries(
                probe.environmentPythonPathEntries,
                to: env
            )
        }

        // Offline deps: optionally add Hub-local site-packages to PYTHONPATH.
        //
        // Problem (macOS 26): some machines block dlopen() of native extensions from the app container
        // ("library load disallowed by system policy"). If the user already installed deps into a
        // real python site-packages, we should NOT force PYTHONPATH to the container.
        //
        // Rule:
        // - Prefer system/user site-packages (no PYTHONPATH)
        // - Only use offline PYTHONPATH if explicitly opted-in AND required

        // 1) Preflight import WITHOUT offline PYTHONPATH.
        // If any local provider runtime already works, ignore any offline marker.
        let probeArgs = pythonSnippetArgs(
            baseArgs: args,
            code: providerImportProbeScript(for: bootstrapProviderID)
        )
        do {
            let t = runCapture(exe, probeArgs, env: env, timeoutSec: 6.0)
            if t.code == 0 {
                // No-op: system/user deps already work.
            } else {
                // 2) Try offline deps (PYTHONPATH) only if explicitly enabled via marker.
                let offlineRoots: [URL] = [
                    // Prefer real home dir because Hub has an entitlement exception for ~/RELFlowHub.
                    SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent("py_deps", isDirectory: true),
                    // Legacy location: under the Hub base dir (often the container for sandbox builds).
                    base.appendingPathComponent("py_deps", isDirectory: true),
                ]

                for root in offlineRoots {
                    let marker = root.appendingPathComponent("USE_PYTHONPATH")
                    let site = root.appendingPathComponent("site-packages", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: marker.path) { continue }
                    if !FileManager.default.directoryExists(atPath: site.path) { continue }

                    var env2 = env
                    let prev = env2["PYTHONPATH"] ?? ""
                    env2["PYTHONPATH"] = site.path + (prev.isEmpty ? "" : ":" + prev)

                    let t2 = runCapture(exe, probeArgs, env: env2, timeoutSec: 6.0)
                    if t2.code == 0 {
                        env = env2
                        break
                    }
                    let err = (t2.err + "\n" + t2.out)
                    if err.contains("library load disallowed by system policy") || err.contains("not valid for use in process") {
                        aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.offlineDepsBlocked
                        aiRuntimeFailCount += 1
                        return
                    }
                }
            }
        }
        p.environment = env

        appendAIRuntimeLogLine(
            HubUIStrings.Settings.Advanced.Runtime.runtimeLaunchLog(
                executable: exe,
                arguments: args.joined(separator: " "),
                scriptPath: scriptURL.path,
                runtimeScriptPath: rtScript.path,
                basePath: base.path
            )
        )
        if let h = aiRuntimeLogHandle {
            p.standardOutput = h
            p.standardError = h
        }

        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }

                // Avoid clobbering a newer runtime if we restarted quickly.
                if let cur = self.aiRuntimeProcess, cur !== proc {
                    self.appendAIRuntimeLogLine(
                        HubUIStrings.Settings.Advanced.Runtime.runtimeExitIgnored(
                            pid: proc.processIdentifier,
                            code: proc.terminationStatus
                        )
                    )
                    return
                }

                let now = Date().timeIntervalSince1970
                self.aiRuntimeProcess = nil
                let stopRequestedAt = self.aiRuntimeStopRequestedAt
                let stopRequestedRecently = stopRequestedAt > 0 && (now - stopRequestedAt) < 5.0

                // Surface quick failures (including lock-busy exit=0).
                if !stopRequestedRecently {
                    let launchedAt = self.aiRuntimeLastLaunchAt
                    let elapsed = launchedAt > 0 ? max(0, now - launchedAt) : 0
                    if proc.terminationStatus != 0 {
                        if self.aiRuntimeLastError.isEmpty {
                            self.aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.runtimeExited(code: proc.terminationStatus)
                        }
                        self.aiRuntimeFailCount += 1
                    } else if elapsed > 0 && elapsed < 2.0 {
                        if self.aiRuntimeLastError.isEmpty {
                            self.aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.runtimeExitedLockBusy
                        }
                        self.aiRuntimeFailCount += 1
                    }
                }
                self.appendAIRuntimeLogLine(
                    HubUIStrings.Settings.Advanced.Runtime.runtimeExitLog(code: proc.terminationStatus)
                )
            }
        }

        do {
            aiRuntimeLastLaunchAt = Date().timeIntervalSince1970
            try p.run()
            aiRuntimeProcess = p
            refreshAIRuntimeStatus()
        } catch {
            aiRuntimeLastError = HubUIStrings.Settings.Advanced.Runtime.runtimeStartFailed(error.localizedDescription)
            aiRuntimeFailCount += 1
        }
    }

    private func autoManagedPythonPathCandidates() -> Set<String> {
        var paths = Set(LocalPythonRuntimeDiscovery.builtinCandidates)
        paths.formUnion(LocalPythonRuntimeDiscovery.lmStudioVendorCandidatePaths())
        paths.formUnion(LocalPythonRuntimeDiscovery.hubManagedRuntimeCandidatePaths())
        paths.insert("/usr/bin/env")
        return Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    private func preferredPythonPath(current: String, preferredProviderID: String? = nil) -> String? {
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrent = trimmedCurrent.contains("/")
            ? URL(fileURLWithPath: (trimmedCurrent as NSString).expandingTildeInPath).standardizedFileURL.path
            : trimmedCurrent
        let normalizedPreferredProviderID = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let best = knownReadyRuntimeSourcePythonPath(preferredProviderID: preferredProviderID)
            ?? autoDetectPython(preferredProviderID: preferredProviderID)

        guard !normalizedCurrent.isEmpty else {
            return best
        }
        guard let best, best != normalizedCurrent else {
            return normalizedCurrent
        }
        if normalizedCurrent == "/usr/bin/env" {
            return best
        }

        let bestProbe = probeLocalPython(best, preferredProviderID: preferredProviderID)
        if !normalizedPreferredProviderID.isEmpty,
           let bestProbe,
           bestProbe.supports(providerID: normalizedPreferredProviderID) {
            guard let currentProbe = probeLocalPython(normalizedCurrent, preferredProviderID: preferredProviderID) else {
                return best
            }
            if !currentProbe.supports(providerID: normalizedPreferredProviderID) {
                return best
            }
        }

        let currentLooksAutoManaged = !normalizedCurrent.contains("/")
            || autoManagedPythonPathCandidates().contains(normalizedCurrent)
        guard currentLooksAutoManaged else {
            return normalizedCurrent
        }

        guard let bestProbe else {
            return normalizedCurrent
        }
        guard let currentProbe = probeLocalPython(normalizedCurrent, preferredProviderID: preferredProviderID) else {
            return best
        }
        return bestProbe.score > currentProbe.score ? best : normalizedCurrent
    }

    private func autoDetectPython(preferredProviderID: String? = nil) -> String? {
        let cacheKey = (preferredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "").isEmpty
            ? "default"
            : (preferredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "default")
        let now = Date().timeIntervalSince1970
        if let cachedAt = autoDetectedPythonCacheAtByKey[cacheKey],
           now - cachedAt <= 8.0 {
            let cached = (autoDetectedPythonCachePathByKey[cacheKey] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cached.isEmpty ? nil : cached
        }

        let candidates = discoveredLocalPythonCandidatePaths()
        var bestAny: String? = nil
        var bestProbe: LocalPythonProbeResult? = nil
        for candidate in candidates {
            guard let probe = probeLocalPython(candidate, preferredProviderID: preferredProviderID) else { continue }
            if bestAny == nil {
                bestAny = probe.path
            }
            if let currentBest = bestProbe {
                if probe.score > currentBest.score {
                    bestProbe = probe
                }
            } else {
                bestProbe = probe
            }
        }
        let resolved = bestProbe?.score ?? Int.min > 0 ? bestProbe?.path : bestAny
        if let resolved, !resolved.isEmpty {
            autoDetectedPythonCachePathByKey[cacheKey] = resolved
            autoDetectedPythonCacheAtByKey[cacheKey] = now
        } else {
            autoDetectedPythonCachePathByKey.removeValue(forKey: cacheKey)
            autoDetectedPythonCacheAtByKey.removeValue(forKey: cacheKey)
        }
        return resolved
    }

    private func localPythonCandidateStatuses(preferredProviderID: String? = nil) -> [LocalPythonRuntimeCandidateStatus] {
        let cacheKey = (preferredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "").isEmpty
            ? "default"
            : (preferredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "default")
        let now = Date().timeIntervalSince1970
        if let cachedAt = pythonCandidateStatusCacheAtByKey[cacheKey],
           now - cachedAt <= 8.0 {
            return pythonCandidateStatusCacheByKey[cacheKey] ?? []
        }

        let rows = discoveredLocalPythonCandidatePaths()
            .compactMap { probeLocalPython($0, preferredProviderID: preferredProviderID) }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.version != $1.version {
                    return $0.version > $1.version
                }
                return $0.path < $1.path
            }

        pythonCandidateStatusCacheByKey[cacheKey] = rows
        pythonCandidateStatusCacheAtByKey[cacheKey] = now
        return rows
    }

    private func discoveredLocalPythonCandidatePaths() -> [String] {
        if let override = localPythonCandidatePathsOverride {
            return override
        }
        return LocalPythonRuntimeDiscovery.candidatePaths()
    }

    private func currentRuntimePythonPath() -> String {
        let configured = aiRuntimePython.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.contains("/") {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        return configured.isEmpty ? defaultPythonPath() : configured
    }

    func runtimeBootstrapPreferredProviderID(
        catalog: ModelCatalogSnapshot = ModelCatalogStorage.load()
    ) -> String? {
        let localProviders = Set(
            catalog.models.compactMap { entry -> String? in
                guard !entry.modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: entry)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return providerID.isEmpty ? nil : providerID
            }
        )
        guard !localProviders.isEmpty else {
            return nil
        }

        let priority = ["transformers", "mlx", "mlx_vlm", "llama.cpp"]
        if let prioritized = priority.first(where: { localProviders.contains($0) }) {
            return prioritized
        }
        return localProviders.sorted().first
    }

    private func pythonCacheKey(preferredProviderID: String? = nil) -> String {
        let normalized = preferredProviderID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized.isEmpty ? "default" : normalized
    }

    private func cachedAutoDetectedPythonPath(preferredProviderID: String? = nil) -> String? {
        let cacheKey = pythonCacheKey(preferredProviderID: preferredProviderID)
        let cached = (autoDetectedPythonCachePathByKey[cacheKey] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cached.isEmpty ? nil : cached
    }

    private func lightweightResolvedLocalRuntimePythonPath(preferredProviderID: String? = nil) -> String {
        let current = currentRuntimePythonPath()
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentLooksAutoManaged = normalizedCurrent.isEmpty
            || !normalizedCurrent.contains("/")
            || autoManagedPythonPathCandidates().contains(normalizedCurrent)
        guard currentLooksAutoManaged else {
            return current
        }
        if let cached = cachedAutoDetectedPythonPath(preferredProviderID: preferredProviderID) {
            return cached
        }
        return autoDetectPython(preferredProviderID: preferredProviderID) ?? current
    }

    private func currentResolvedRuntimePythonPath() -> String {
        localRuntimePythonProbeLaunchConfig(preferredProviderID: nil)?.resolvedPythonPath
            ?? currentRuntimePythonPath()
    }

    private func runtimeRecoveryAction(
        for providerID: String,
        runtimeStatus: AIRuntimeStatus? = nil
    ) -> LocalRuntimeProviderRecoveryAction {
        let normalizedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProvider.isEmpty else {
            return .none
        }
        let status = runtimeStatus ?? AIRuntimeStatusStorage.load()
        let runtimeAlive = (status?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false) || (findRunningAIRuntimePid(status: status) != nil)
        let providerReady = status?.isProviderReady(normalizedProvider, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
        let currentPythonPath = currentResolvedRuntimePythonPath()
        let targetPythonPath = preferredLocalProviderPythonPath(preferredProviderID: normalizedProvider) ?? currentPythonPath
        let targetProbe = probeLocalPython(targetPythonPath, preferredProviderID: normalizedProvider)
        let targetSupportsProvider = targetProbe?.supports(providerID: normalizedProvider) ?? false
        return LocalRuntimeProviderRecoveryPlanner.plan(
            runtimeAlive: runtimeAlive,
            providerReady: providerReady,
            currentPythonPath: currentPythonPath,
            targetPythonPath: targetPythonPath,
            targetSupportsProvider: targetSupportsProvider
        )
    }

    func canAutoRecoverRuntime(for providerID: String, runtimeStatus: AIRuntimeStatus? = nil) -> Bool {
        runtimeRecoveryAction(for: providerID, runtimeStatus: runtimeStatus) != .none
    }

    func ensureRuntimeReady(for providerID: String, waitUpToSec: Double = 12.0) async -> Bool {
        let normalizedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProvider.isEmpty else {
            return false
        }

        let base = SharedPaths.ensureHubDirectory()
        let providerPackUpdated = LocalProviderPackRegistry.syncAutoManagedPacks(baseDir: base)
        if providerPackUpdated, normalizedProvider == "transformers" {
            appendAIRuntimeLogLine("Restarting runtime after local helper pack update for provider \(normalizedProvider)")
            if AIRuntimeStatusStorage.load()?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) == true {
                stopAIRuntime()
            }
            startAIRuntime()
            let restartDeadline = Date().addingTimeInterval(max(1.0, waitUpToSec))
            while Date() < restartDeadline {
                try? await Task.sleep(nanoseconds: 300_000_000)
                refreshAIRuntimeStatus()
                if AIRuntimeStatusStorage.load()?.isProviderReady(normalizedProvider, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) == true {
                    return true
                }
            }
            refreshAIRuntimeStatus()
        }

        let action = runtimeRecoveryAction(for: normalizedProvider, runtimeStatus: AIRuntimeStatusStorage.load())
        switch action {
        case .none:
            return AIRuntimeStatusStorage.load()?.isProviderReady(normalizedProvider, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
        case .start(let targetPythonPath):
            appendAIRuntimeLogLine("Auto-starting runtime for provider \(normalizedProvider) with python \(targetPythonPath)")
            aiRuntimePython = targetPythonPath
            startAIRuntime()
        case .restart(let targetPythonPath):
            appendAIRuntimeLogLine("Restarting runtime for provider \(normalizedProvider) with python \(targetPythonPath)")
            aiRuntimePython = targetPythonPath
            stopAIRuntime()
            startAIRuntime()
        }

        let deadline = Date().addingTimeInterval(max(1.0, waitUpToSec))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
            refreshAIRuntimeStatus()
            if AIRuntimeStatusStorage.load()?.isProviderReady(normalizedProvider, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) == true {
                return true
            }
        }
        refreshAIRuntimeStatus()
        return AIRuntimeStatusStorage.load()?.isProviderReady(normalizedProvider, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false
    }

    private func refreshAIRuntimeGuidance(status: AIRuntimeStatus?) {
        let selectedPythonPath = currentResolvedRuntimePythonPath()
        aiRuntimePythonCandidatesText = LocalRuntimeProviderGuidance.pythonCandidatesSummary(
            selectedPythonPath: selectedPythonPath,
            preferredProviderPaths: [
                "mlx": preferredLocalProviderPythonPath(preferredProviderID: "mlx") ?? "",
                "mlx_vlm": preferredLocalProviderPythonPath(preferredProviderID: "mlx_vlm") ?? "",
                "transformers": preferredLocalProviderPythonPath(preferredProviderID: "transformers") ?? "",
            ],
            candidates: localPythonCandidateStatuses()
        )

        guard let status else {
            aiRuntimeInstallHintsText = ""
            aiRuntimeProviderHelpTextByProvider = [:]
            return
        }

        var perProvider: [String: String] = [:]
        var lines: [String] = []
        for diagnosis in status.providerDiagnoses(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) where diagnosis.state == .down {
            let providerID = diagnosis.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !providerID.isEmpty else { continue }
            let providerStatus = status.providerStatus(providerID)
            let hint: String
            if providerID == "mlx" {
                hint = mlxUnavailableHelp(importError: diagnosis.importError)
            } else {
                hint = LocalRuntimeProviderGuidance.providerHint(
                    providerID: providerID,
                    reasonCode: diagnosis.reasonCode,
                    importError: diagnosis.importError,
                    runtimeResolutionState: providerStatus?.runtimeResolutionState ?? diagnosis.runtimeResolutionState,
                    runtimeSource: providerStatus?.runtimeSource ?? diagnosis.runtimeSource,
                    runtimeSourcePath: providerStatus?.runtimeSourcePath ?? diagnosis.runtimeSourcePath,
                    runtimeReasonCode: providerStatus?.runtimeReasonCode ?? diagnosis.runtimeReasonCode,
                    runtimeHint: providerStatus?.runtimeHint ?? "",
                    fallbackUsed: providerStatus?.fallbackUsed ?? diagnosis.fallbackUsed,
                    selectedPythonPath: selectedPythonPath,
                    preferredPythonPath: preferredLocalProviderPythonPath(preferredProviderID: providerID),
                    candidates: localPythonCandidateStatuses(preferredProviderID: providerID)
                )
            }
            let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            perProvider[providerID] = normalized
            lines.append("[\(providerID)] \(normalized)")
        }
        aiRuntimeProviderHelpTextByProvider = perProvider
        aiRuntimeInstallHintsText = lines.joined(separator: "\n\n")
    }

    private func unavailableProvidersHelp(status: AIRuntimeStatus) -> String {
        let hints = status.providerDiagnoses(ttl: AIRuntimeStatus.recommendedHeartbeatTTL)
            .filter { $0.state == .down }
            .compactMap { diagnosis -> String? in
                let providerID = diagnosis.provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let hint = aiRuntimeProviderHelpTextByProvider[providerID] ?? ""
                let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalized.isEmpty ? nil : normalized
            }
        return hints.joined(separator: "\n\n")
    }

    struct AIRuntimeUnlockResult {
        var lockPath: String
        var command: String
        var holderPids: [Int32]
        var killedPids: [Int32]
        var skippedPids: [Int32]
        var lockReleased: Bool
        var detail: String
    }

    private func runtimeBaseDirForAIRuntime() -> URL {
        SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
    }

    private func resolvedLsofPath() -> String? {
        let fm = FileManager.default
        let candidates = ["/usr/sbin/lsof", "/usr/bin/lsof"]
        for p in candidates where fm.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }

    func aiRuntimeLockBusyNow() -> Bool {
        isAIRuntimeLockBusy(baseDir: runtimeBaseDirForAIRuntime())
    }

    func aiRuntimeLockKillCommandHint(pids: [Int32] = []) -> String {
        let base = runtimeBaseDirForAIRuntime()
        let lockPath = base.appendingPathComponent("ai_runtime.lock").path
        let lsofCmd = resolvedLsofPath() ?? "lsof"
        let uniq = Array(Set(pids.filter { $0 > 1 })).sorted()
        if !uniq.isEmpty {
            let pidList = uniq.map(String.init).joined(separator: " ")
            return "kill -9 \(pidList)"
        }
        // Runnable snippet for Terminal copy/paste that resolves holders at execution time.
        return "pids=$(\(lsofCmd) -t \"\(lockPath)\" 2>/dev/null); [ -n \"$pids\" ] && kill -9 $pids"
    }

    private func aiRuntimePsKillCommandHint(pids: [Int32] = []) -> String {
        let uniq = Array(Set(pids.filter { $0 > 1 })).sorted()
        if !uniq.isEmpty {
            let pidList = uniq.map(String.init).joined(separator: " ")
            return "kill -9 \(pidList)"
        }
        return "pids=$(ps ax -o pid=,command= | awk '/relflowhub_(local|mlx)_runtime.py/ && $0 !~ /awk/ {print $1}'); [ -n \"$pids\" ] && kill -9 $pids"
    }

    private func parsePidList(_ text: String) -> [Int32] {
        let raw = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen = Set<Int32>()
        var out: [Int32] = []
        for s in raw {
            guard let pid = Int32(s), pid > 1 else { continue }
            if seen.contains(pid) { continue }
            seen.insert(pid)
            out.append(pid)
        }
        return out
    }

    private func collectRuntimePidsFromStatusAndPS() -> [Int32] {
        var out: [Int32] = []
        var seen = Set<Int32>()

        if let st = AIRuntimeStatusStorage.load() {
            let pid = Int32(st.pid)
            if pid > 1 {
                // Guard against stale/reused pids from old heartbeat files.
                let cmd = runtimeCommandLineForPid(pid).lowercased()
                let ageSec = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
                let heartbeatRecent = ageSec < 90.0
                let psBlocked =
                    cmd.isEmpty ||
                    cmd.contains("operation not permitted") ||
                    cmd.contains("permission denied")
                if isAIRuntimeCommandLine(cmd) ||
                    (heartbeatRecent && psBlocked && alivePid(pid_t(pid))) {
                    seen.insert(pid)
                    out.append(pid)
                }
            }
        }

        let ps = runCapture("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSec: 1.0)
        let raw = (ps.out.isEmpty ? ps.err : ps.out)
        if raw.isEmpty {
            return out
        }
        for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count < 2 { continue }
            guard let pid = Int32(parts[0]), pid > 1 else { continue }
            let cmd = String(parts[1]).lowercased()
            if !isAIRuntimeCommandLine(cmd) { continue }
            if seen.contains(pid) { continue }
            seen.insert(pid)
            out.append(pid)
        }

        return out
    }

    private func runtimeCommandLineForPid(_ pid: Int32) -> String {
        let ps = runCapture("/bin/ps", ["-p", String(pid), "-o", "command="], timeoutSec: 0.8)
        let txt = (ps.out.isEmpty ? ps.err : ps.out).trimmingCharacters(in: .whitespacesAndNewlines)
        return txt
    }

    private func alivePid(_ pid: pid_t) -> Bool {
        if pid <= 1 { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    func forceUnlockAIRuntimeLockByLsof(allowNonRuntimeHolders: Bool = false) -> AIRuntimeUnlockResult {
        let base = runtimeBaseDirForAIRuntime()
        let lockPath = base.appendingPathComponent("ai_runtime.lock").path
        var result = AIRuntimeUnlockResult(
            lockPath: lockPath,
            command: aiRuntimeLockKillCommandHint(),
            holderPids: [],
            killedPids: [],
            skippedPids: [],
            lockReleased: false,
            detail: ""
        )

        if !isAIRuntimeLockBusy(baseDir: base) {
            result.lockReleased = true
            result.detail = HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockAlreadyReleased
            return result
        }

        guard let lsofExe = resolvedLsofPath() else {
            result.detail = HubUIStrings.Settings.Diagnostics.FixNow.lsofNotFound
            return result
        }
        let lsofCandidates = [lsofExe]
        var lsofOut = ""
        var lsofErr = ""
        var lsofCode: Int32 = 127
        for exe in lsofCandidates {
            let r = runCapture(exe, ["-t", lockPath], timeoutSec: 1.4)
            lsofOut = r.out
            lsofErr = r.err
            lsofCode = r.code
            let pids = parsePidList(r.out)
            if !pids.isEmpty || r.code == 0 {
                result.holderPids = pids
                break
            }
        }

        let lsofTail = [lsofOut, lsofErr].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let lsofTailLower = lsofTail.lowercased()
        let lsofBlocked =
            lsofTailLower.contains("operation not permitted") ||
            lsofTailLower.contains("can't get pid byte count")

        if result.holderPids.isEmpty {
            let fallbackPids = collectRuntimePidsFromStatusAndPS()
            if !fallbackPids.isEmpty {
                result.holderPids = fallbackPids
                result.command = aiRuntimePsKillCommandHint(pids: fallbackPids)
                if lsofBlocked {
                    result.detail = HubUIStrings.Settings.Diagnostics.FixNow.lsofSandboxFallback
                }
            } else if lsofCode != 0 {
                if lsofBlocked {
                    result.command = aiRuntimePsKillCommandHint()
                    result.detail = HubUIStrings.Settings.Diagnostics.FixNow.lsofSandboxNoPid
                } else {
                    result.detail = lsofTail.isEmpty
                        ? HubUIStrings.Settings.Diagnostics.FixNow.lsofFailed(code: lsofCode)
                        : HubUIStrings.Settings.Diagnostics.FixNow.lsofFailed(detail: lsofTail)
                }
                return result
            }
        }

        if result.command.isEmpty || (result.command.contains("lsof") && !result.holderPids.isEmpty) {
            result.command = aiRuntimeLockKillCommandHint(pids: result.holderPids)
        }
        if result.holderPids.isEmpty {
            result.lockReleased = !isAIRuntimeLockBusy(baseDir: base)
            if result.lockReleased {
                result.detail = HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockReleased
            } else {
                if result.detail.isEmpty {
                    result.detail = HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockBusyNoPid
                }
            }
            return result
        }

        for pidNum in result.holderPids {
            let pid = pid_t(pidNum)
            if pid <= 1 || pid == getpid() {
                result.skippedPids.append(pidNum)
                continue
            }

            let cmd = runtimeCommandLineForPid(pidNum).lowercased()
            // Safety by default: only auto-kill known Hub runtime holders.
            if !allowNonRuntimeHolders && !isAIRuntimeCommandLine(cmd) {
                result.skippedPids.append(pidNum)
                continue
            }

            kill(pid, SIGTERM)
            for _ in 0..<12 {
                if !alivePid(pid) { break }
                usleep(50_000)
            }
            if alivePid(pid) {
                kill(pid, SIGKILL)
                for _ in 0..<10 {
                    if !alivePid(pid) { break }
                    usleep(50_000)
                }
            }
            if alivePid(pid) {
                result.detail = HubUIStrings.Settings.Diagnostics.FixNow.unableToKillLockHolder(pid: pidNum)
            } else {
                result.killedPids.append(pidNum)
            }
        }

        for _ in 0..<18 {
            if !isAIRuntimeLockBusy(baseDir: base) { break }
            usleep(50_000)
        }
        result.lockReleased = !isAIRuntimeLockBusy(baseDir: base)

        if result.lockReleased {
            if result.killedPids.isEmpty {
                result.detail = HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockReleased
            } else {
                let pids = result.killedPids.map(String.init).joined(separator: ",")
                result.detail = HubUIStrings.Settings.Diagnostics.FixNow.runtimeLockReleasedKilled(pids)
            }
            return result
        }

        var parts: [String] = []
        if !result.killedPids.isEmpty {
            parts.append(
                HubUIStrings.Settings.Diagnostics.FixNow.killedProcesses(
                    result.killedPids.map(String.init).joined(separator: ",")
                )
            )
        }
        if !result.skippedPids.isEmpty {
            parts.append(
                HubUIStrings.Settings.Diagnostics.FixNow.skippedProcesses(
                    result.skippedPids.map(String.init).joined(separator: ",")
                )
            )
        }
        parts.append(HubUIStrings.Settings.Diagnostics.FixNow.lockStillBusyFlag)
        if !result.detail.isEmpty {
            parts.append(result.detail)
        }
        result.detail = HubUIStrings.Settings.Diagnostics.FixNow.lockCleanupSummary(parts)
        return result
    }

    private func isAIRuntimeLockBusy(baseDir: URL) -> Bool {
        // The python runtime uses a flock() lock at: <base>/ai_runtime.lock.
        // If that lock is held, starting a new runtime will immediately exit (code 0),
        // which is confusing for users. Preflight here and surface a human error.
        let lockURL = baseDir.appendingPathComponent("ai_runtime.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        if fd < 0 {
            return false
        }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            _ = flock(fd, LOCK_UN)
            return false
        }
        if errno == EWOULDBLOCK || errno == EAGAIN {
            return true
        }
        return false
    }

    func stopAIRuntime() {
        aiRuntimeLastError = ""
        aiRuntimeStopRequestedAt = Date().timeIntervalSince1970

        // Ask the runtime to stop via a file marker first. This works even when OS signals
        // are restricted (App Sandbox), and also handles runtimes that survived an app relaunch.
        let base = runtimeBaseDirForAIRuntime()
        do {
            let stopURL = base.appendingPathComponent("ai_runtime_stop.json")
            let obj: [String: Any] = [
                "req_id": UUID().uuidString,
                "requested_at": Date().timeIntervalSince1970,
                "hub_pid": Int(getpid()),
            ]
            let data = try JSONSerialization.data(withJSONObject: obj, options: [])
            try data.write(to: stopURL, options: .atomic)
        } catch {
            // Best-effort.
        }

        // Give the runtime a brief moment to observe the marker and release the lock.
        for _ in 0..<12 {
            if !isAIRuntimeLockBusy(baseDir: base) {
                break
            }
            usleep(50_000)
        }

        // Best-effort: terminate by pid from the runtime heartbeat as well.
        // This cleans up runtimes started by older Hub instances.
        if let st = AIRuntimeStatusStorage.load() {
            let pid = pid_t(st.pid)
            if pid > 1 {
                // Avoid killing an unrelated process if the pid was reused.
                // Prefer verifying the command line contains our script name.
                let ps = runCapture("/bin/ps", ["-p", String(pid), "-o", "command="], timeoutSec: 0.8)
                let psText = (ps.out.isEmpty ? ps.err : ps.out).lowercased()
                let looksLikeRuntime = ps.code == 0 && isAIRuntimeCommandLine(psText)
                let statusAgeSec = max(0.0, Date().timeIntervalSince1970 - st.updatedAt)
                let statusRecent = statusAgeSec < 10 * 60 // 10 minutes

                if looksLikeRuntime || (ps.code != 0 && statusRecent) {
                    kill(pid, SIGTERM)
                    // If it doesn't exit quickly, force-kill to avoid lock-busy loops.
                    var stillAlive = false
                    for _ in 0..<8 {
                        usleep(50_000)
                        if kill(pid, 0) == 0 {
                            stillAlive = true
                            continue
                        }
                        stillAlive = false
                        break
                    }
                    if stillAlive {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }

        // If the heartbeat is stale (or missing), the lock can still be held by a lingering
        // runtime process. As a safety net, kill any known relflowhub runtime processes we can find.
        do {
            let ps = runCapture("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSec: 1.0)
            let raw = (ps.out.isEmpty ? ps.err : ps.out)
            if !raw.isEmpty {
                for row in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                    let line = row.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty { continue }
                    let parts = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
                    if parts.count < 2 { continue }
                    guard let pidNum = Int32(parts[0]), pidNum > 1 else { continue }
                    let cmd = String(parts[1]).lowercased()
                    if !isAIRuntimeCommandLine(cmd) { continue }
                    let pid = pid_t(pidNum)
                    kill(pid, SIGTERM)
                    var stillAlive = false
                    for _ in 0..<8 {
                        usleep(50_000)
                        if kill(pid, 0) == 0 {
                            stillAlive = true
                            continue
                        }
                        stillAlive = false
                        break
                    }
                    if stillAlive {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }

        if let p = aiRuntimeProcess {
            if p.isRunning {
                let pid = pid_t(p.processIdentifier)
                p.terminate()
                _ = waitForProcessExit(p, timeoutSec: 0.9)
                if p.isRunning, pid > 1 {
                    kill(pid, SIGKILL)
                    _ = waitForProcessExit(p, timeoutSec: 0.9)
                }
            }
            if p.isRunning {
                // Keep it alive so we don't crash on Process deinit; surface an error below.
                leakRunningCaptureProcess(p)
                aiRuntimeProcess = p
            } else {
                aiRuntimeProcess = nil
            }
        }
        try? aiRuntimeLogHandle?.close()
        aiRuntimeLogHandle = nil

        // If we're still locked after all stop attempts, surface actionable guidance.
        if isAIRuntimeLockBusy(baseDir: base) {
            let lockURL = base.appendingPathComponent("ai_runtime.lock")
            let pidHint = (AIRuntimeStatusStorage.load()?.pid ?? 0)
            aiRuntimeLastError = HubUIStrings.Settings.Diagnostics.FixNow.stopRequestedButLockBusy(
                lockPath: lockURL.path,
                command: aiRuntimeLockKillCommandHint(),
                pidHint: pidHint
            )
        }

        refreshAIRuntimeStatus()
    }

    func openAIRuntimeLog() {
        let base = SharedPaths.ensureHubDirectory()
        let logURL = base.appendingPathComponent("ai_runtime.log")
        NSWorkspace.shared.open(logURL)
    }

    func axConstitutionURL() -> URL {
        SharedPaths.ensureHubDirectory()
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("ax_constitution.json")
    }

    func openAXConstitutionFile() {
        let url = axConstitutionURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            // The runtime creates the default file on first start; open the folder so users can inspect/edit.
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    func recentAIRuntimeAuditLines(limit: Int = 16) -> [String] {
        let n = max(1, min(80, limit))
        let base = SharedPaths.ensureHubDirectory()
        let p = base.appendingPathComponent("mlx_runtime_audit.log")
        guard let data = try? Data(contentsOf: p), let s = String(data: data, encoding: .utf8) else {
            return []
        }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
        let ai = lines.filter { $0.contains("\tai_request\t") }
        return Array(ai.suffix(n))
    }

    func testAIRuntimeGenerate() {
        aiRuntimeLastTestText = ""

        // Fast preflight checks.
        if !(AIRuntimeStatusStorage.load()?.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) ?? false) {
            aiRuntimeLastTestText = HubUIStrings.Settings.Advanced.Runtime.testNotRunning
            return
        }
        let loaded = ModelStore.shared.snapshot.models.filter { $0.state == .loaded }
        if loaded.isEmpty {
            aiRuntimeLastTestText = HubUIStrings.Settings.Advanced.Runtime.testNoLoadedModels
            return
        }

        let base = SharedPaths.ensureHubDirectory()
        let reqDir = base.appendingPathComponent("ai_requests", isDirectory: true)
        let respDir = base.appendingPathComponent("ai_responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let reqURL = reqDir.appendingPathComponent("req_\(reqId).json")
        let respURL = respDir.appendingPathComponent("resp_\(reqId).jsonl")

        let obj: [String: Any] = [
            "type": "generate",
            "req_id": reqId,
            "app_id": "hub_ui",
            "task_type": "assist",
            "prompt": "Say hello in one short sentence. Output ONLY the sentence.",
            "max_tokens": 64,
            "temperature": 0.2,
            "top_p": 0.95,
            "created_at": Date().timeIntervalSince1970,
            "auto_load": false,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            aiRuntimeLastTestText = HubUIStrings.Settings.Advanced.Runtime.testEncodeRequestFailed
            return
        }
        do {
            try data.write(to: reqURL, options: .atomic)
        } catch {
            aiRuntimeLastTestText = HubUIStrings.Settings.Advanced.Runtime.testWriteRequestFailed(error.localizedDescription)
            return
        }

        // Poll response asynchronously to keep UI responsive.
        Task { @MainActor in
            let finalText: String = await Task.detached(priority: .userInitiated) {
                let deadline = Date().addingTimeInterval(12)
                var pos: UInt64 = 0
                var buf = ""
                var done: (ok: Bool, reason: String)? = nil

                while Date() < deadline {
                    if let fh = try? FileHandle(forReadingFrom: respURL) {
                        defer { try? fh.close() }
                        do {
                            try fh.seek(toOffset: pos)
                            let chunk = try fh.readToEnd() ?? Data()
                            pos += UInt64(chunk.count)
                            if !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) {
                                for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
                                    guard let ld = String(line).data(using: .utf8) else { continue }
                                    guard let o = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
                                    guard String(describing: o["req_id"] ?? "") == reqId else { continue }
                                    let typ = String(describing: o["type"] ?? "")
                                    if typ == "delta" {
                                        buf += String(describing: o["text"] ?? "")
                                    } else if typ == "done" {
                                        let ok = (o["ok"] as? Bool) ?? false
                                        let reason = String(describing: o["reason"] ?? "")
                                        done = (ok: ok, reason: reason)
                                    }
                                }
                            }
                        } catch {
                            // Ignore read races.
                        }
                    }

                    if done != nil { break }
                    try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
                }

                if let d = done {
                    if d.ok {
                        let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t.isEmpty
                            ? HubUIStrings.Settings.Advanced.Runtime.testSuccessEmpty
                            : HubUIStrings.Settings.Advanced.Runtime.testSuccess(String(t.prefix(120)))
                    }
                    return HubUIStrings.Settings.Advanced.Runtime.testFailure(d.reason)
                }
                return HubUIStrings.Settings.Advanced.Runtime.testTimeout
            }.value

            self.aiRuntimeLastTestText = finalText
        }
    }

    func localModelTrialStatus(for modelId: String) -> ModelTrialStatus? {
        modelTrialStatusByKey[localModelTrialKey(modelId)]
    }

    func localModelHealth(for modelId: String) -> LocalModelHealthRecord? {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return localModelHealthSnapshot.records.first { record in
            record.modelId == normalized
        }
    }

    func isLocalModelHealthScanInProgress(for modelId: String) -> Bool {
        let normalized = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return localModelHealthScanningModelIDs.contains(normalized)
    }

    func updateLocalModelHealthAutoScanSchedule(_ schedule: ModelHealthAutoScanSchedule) {
        let normalized = schedule.normalized()
        guard normalized != localModelHealthAutoScanSchedule else { return }
        localModelHealthAutoScanSchedule = normalized
        saveModelHealthAutoScanSchedule(normalized, key: Self.localModelHealthAutoScanScheduleKey)
        refreshLocalModelHealthAutoScanTimer()
    }

    func preflightAllLocalModelHealth() {
        requestLocalModelHealthScan(limitingTo: nil, mode: .preflightOnly, updatesTrialStatus: false)
    }

    func preflightLocalModelHealth(for modelIds: [String]) {
        let normalized = Set(
            modelIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalized.isEmpty else { return }
        requestLocalModelHealthScan(limitingTo: normalized, mode: .preflightOnly, updatesTrialStatus: false)
    }

    func scanAllLocalModelHealth() {
        requestLocalModelHealthScan(limitingTo: nil, mode: .full, updatesTrialStatus: true)
    }

    func scanLocalModelHealth(for modelIds: [String]) {
        let normalized = Set(
            modelIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalized.isEmpty else { return }
        requestLocalModelHealthScan(limitingTo: normalized, mode: .full, updatesTrialStatus: true)
    }

    func remoteModelTrialStatus(for modelId: String) -> ModelTrialStatus? {
        modelTrialStatusByKey[remoteModelTrialKey(modelId)]
    }

    func remoteKeyHealth(for keyReference: String) -> RemoteKeyHealthRecord? {
        let normalized = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return remoteKeyHealthSnapshot.records.first { record in
            record.keyReference == normalized
        }
    }

    func isRemoteKeyHealthScanInProgress(for keyReference: String) -> Bool {
        let normalized = keyReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return remoteKeyHealthScanningKeyReferences.contains(normalized)
    }

    func updateRemoteKeyHealthAutoScanSchedule(_ schedule: ModelHealthAutoScanSchedule) {
        let normalized = schedule.normalized()
        guard normalized != remoteKeyHealthAutoScanSchedule else { return }
        remoteKeyHealthAutoScanSchedule = normalized
        saveModelHealthAutoScanSchedule(normalized, key: Self.remoteKeyHealthAutoScanScheduleKey)
        refreshRemoteKeyHealthAutoScanTimer()
    }

    func scanAllRemoteKeyHealth() {
        requestRemoteKeyHealthScan(limitingTo: nil)
    }

    func scanRemoteKeyHealth(for keyReferences: [String]) {
        let normalized = Set(
            keyReferences
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalized.isEmpty else { return }
        requestRemoteKeyHealthScan(limitingTo: normalized)
    }

    func testLocalModelConnectivity(_ model: HubModel) {
        let key = localModelTrialKey(model.id)
        modelTrialStatusByKey[key] = ModelTrialStatus(
            state: .running,
            category: .running,
            summary: HubUIStrings.Models.Trial.running,
            detail: "",
            updatedAt: Date().timeIntervalSince1970
        )

        Task { @MainActor in
            let startedAt = Date().timeIntervalSince1970
            do {
                let detail = try await runLocalModelTrial(model)
                let duration = HubUIStrings.Models.Trial.duration(Date().timeIntervalSince1970 - startedAt)
                modelTrialStatusByKey[key] = ModelTrialStatus(
                    state: .success,
                    category: .success,
                    summary: HubUIStrings.Models.Trial.success,
                    detail: HubUIStrings.Models.Trial.detailSummary([duration, detail]),
                    updatedAt: Date().timeIntervalSince1970
                )
            } catch {
                let duration = HubUIStrings.Models.Trial.duration(Date().timeIntervalSince1970 - startedAt)
                let failureMessage = error.localizedDescription
                modelTrialStatusByKey[key] = ModelTrialStatus(
                    state: .failure,
                    category: hubClassifyModelTrialFailure(failureMessage),
                    summary: HubUIStrings.Models.Trial.failed,
                    detail: HubUIStrings.Models.Trial.detailSummary([duration, failureMessage]),
                    updatedAt: Date().timeIntervalSince1970
                )
            }
        }
    }

    private func requestLocalModelHealthScan(
        limitingTo modelIDs: Set<String>?,
        mode: LocalModelHealthScanMode,
        updatesTrialStatus: Bool
    ) {
        guard !localModelHealthScanInFlight else { return }

        let models = ModelStore.shared.snapshot.models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
        let filteredModels = models
            .filter { model in
                guard let modelIDs else { return true }
                return modelIDs.contains(model.id)
            }
        let validModelIDs = Set(models.map(\.id))

        guard !filteredModels.isEmpty else {
            let pruned = LocalModelHealthSnapshot(
                records: localModelHealthSnapshot.records.filter { validModelIDs.contains($0.modelId) },
                updatedAt: Date().timeIntervalSince1970
            )
            localModelHealthSnapshot = pruned
            LocalModelHealthStorage.save(pruned)
            refreshLocalModelHealthAutoScanTimer()
            return
        }

        localModelHealthScanInFlight = true
        localModelHealthScanningModelIDs = Set(filteredModels.map(\.id))

        Task { @MainActor in
            var recordsByModelID = Dictionary(
                uniqueKeysWithValues: localModelHealthSnapshot.records.map { ($0.modelId, $0) }
            )
            let orderedModels = orderedLocalModelHealthScanModels(filteredModels)
            let scanJobs = LocalModelHealthScanPlanner.jobs(
                for: orderedModels,
                requestedMode: mode,
                explicitlyLimited: modelIDs != nil,
                healthByModelID: recordsByModelID,
                preferredModelIDByTask: routingPreferredModelIdByTask,
                requestedTrialStatusUpdates: updatesTrialStatus
            )
            let runtimeScriptAvailable = resolveAIRuntimeScriptURL() != nil
            let readinessSession = LocalLibraryRuntimeReadinessSession { [weak self] providerID in
                guard let self else {
                    return LocalLibraryRuntimeProviderProbe(
                        launchConfigAvailable: false,
                        probeLaunchConfig: nil,
                        pythonPath: nil
                    )
                }
                let probeLaunchConfig = runtimeScriptAvailable
                    ? self.localRuntimePythonProbeLaunchConfig(preferredProviderID: providerID)
                    : nil
                return LocalLibraryRuntimeProviderProbe(
                    launchConfigAvailable: runtimeScriptAvailable && probeLaunchConfig != nil,
                    probeLaunchConfig: probeLaunchConfig,
                    pythonPath: probeLaunchConfig?.resolvedPythonPath
                )
            }

            for job in scanJobs {
                let model = job.model
                let key = localModelTrialKey(model.id)
                if job.updatesTrialStatus {
                    modelTrialStatusByKey[key] = ModelTrialStatus(
                        state: .running,
                        category: .running,
                        summary: HubUIStrings.Models.Trial.running,
                        detail: "",
                        updatedAt: Date().timeIntervalSince1970
                    )
                }

                let startedAt = Date().timeIntervalSince1970
                let record = await LocalModelHealthScanner.scan(
                    model: model,
                    mode: job.mode,
                    previous: recordsByModelID[model.id],
                    readinessResolver: { scanModel in
                        readinessSession.readiness(for: scanModel)
                    },
                    trialRunner: { scanModel in
                        try await self.runLocalModelTrial(scanModel)
                    }
                )
                recordsByModelID[model.id] = record
                localModelHealthScanningModelIDs.remove(model.id)

                if job.updatesTrialStatus {
                    let duration = HubUIStrings.Models.Trial.duration(Date().timeIntervalSince1970 - startedAt)
                    if record.state == .healthy {
                        modelTrialStatusByKey[key] = ModelTrialStatus(
                            state: .success,
                            category: .success,
                            summary: HubUIStrings.Models.Trial.success,
                            detail: HubUIStrings.Models.Trial.detailSummary([duration, record.detail]),
                            updatedAt: Date().timeIntervalSince1970
                        )
                    } else {
                        modelTrialStatusByKey[key] = ModelTrialStatus(
                            state: .failure,
                            category: localModelTrialCategory(for: record),
                            summary: HubUIStrings.Models.Trial.failed,
                            detail: HubUIStrings.Models.Trial.detailSummary([duration, record.detail]),
                            updatedAt: Date().timeIntervalSince1970
                        )
                    }
                }

                let snapshot = LocalModelHealthSnapshot(
                    records: filteredLocalModelHealthRecords(recordsByModelID, validModelIDs: validModelIDs),
                    updatedAt: Date().timeIntervalSince1970
                )
                localModelHealthSnapshot = snapshot
                LocalModelHealthStorage.save(snapshot)
            }

            localModelHealthScanInFlight = false
            localModelHealthScanningModelIDs = []
            let finalSnapshot = LocalModelHealthSnapshot(
                records: filteredLocalModelHealthRecords(recordsByModelID, validModelIDs: validModelIDs),
                updatedAt: Date().timeIntervalSince1970
            )
            localModelHealthSnapshot = finalSnapshot
            LocalModelHealthStorage.save(finalSnapshot)
            refreshLocalModelHealthAutoScanTimer()
        }
    }

    private func requestRemoteKeyHealthScan(limitingTo keyReferences: Set<String>?) {
        guard !remoteKeyHealthScanInFlight else { return }

        let models = RemoteModelStorage.load().models
        let groups = RemoteKeyHealthScanner.groups(from: models, limitingTo: keyReferences)
        let validKeys = Set(
            models
                .map { RemoteModelStorage.keyReference(for: $0) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )

        guard !groups.isEmpty else {
            let pruned = RemoteKeyHealthSnapshot(
                records: remoteKeyHealthSnapshot.records.filter { validKeys.contains($0.keyReference) },
                updatedAt: Date().timeIntervalSince1970
            )
            remoteKeyHealthSnapshot = pruned
            RemoteKeyHealthStorage.save(pruned)
            refreshRemoteKeyHealthAutoScanTimer()
            return
        }

        remoteKeyHealthScanInFlight = true
        remoteKeyHealthScanningKeyReferences = Set(groups.map(\.keyReference))

        Task { @MainActor in
            var recordsByKey = Dictionary(
                uniqueKeysWithValues: remoteKeyHealthSnapshot.records.map { ($0.keyReference, $0) }
            )

            for group in groups {
                let scanned = await RemoteKeyHealthScanner.scan(
                    group: group,
                    previous: recordsByKey[group.keyReference]
                )
                recordsByKey[group.keyReference] = scanned
                remoteKeyHealthScanningKeyReferences.remove(group.keyReference)

                let snapshot = RemoteKeyHealthSnapshot(
                    records: filteredRemoteKeyHealthRecords(recordsByKey, validKeys: validKeys),
                    updatedAt: Date().timeIntervalSince1970
                )
                remoteKeyHealthSnapshot = snapshot
                RemoteKeyHealthStorage.save(snapshot)
            }

            remoteKeyHealthScanInFlight = false
            remoteKeyHealthScanningKeyReferences = []
            let finalSnapshot = RemoteKeyHealthSnapshot(
                records: filteredRemoteKeyHealthRecords(recordsByKey, validKeys: validKeys),
                updatedAt: Date().timeIntervalSince1970
            )
            remoteKeyHealthSnapshot = finalSnapshot
            RemoteKeyHealthStorage.save(finalSnapshot)
            refreshRemoteKeyHealthAutoScanTimer()
        }
    }

    private func orderedLocalModelHealthScanModels(_ models: [HubModel]) -> [HubModel] {
        let healthByModelID = Dictionary(
            uniqueKeysWithValues: localModelHealthSnapshot.records.map { ($0.modelId, $0) }
        )

        return models.sorted { lhs, rhs in
            let lhsHealth = healthByModelID[lhs.id]
            let rhsHealth = healthByModelID[rhs.id]
            let lhsPriority = LocalModelHealthSupport.sortPriority(for: lhsHealth)
            let rhsPriority = LocalModelHealthSupport.sortPriority(for: rhsHealth)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            let lhsState = stateRank(lhs.state)
            let rhsState = stateRank(rhs.state)
            if lhsState != rhsState {
                return lhsState < rhsState
            }

            let lhsRecency = LocalModelHealthSupport.recency(for: lhsHealth)
            let rhsRecency = LocalModelHealthSupport.recency(for: rhsHealth)
            if lhsRecency != rhsRecency {
                return lhsRecency > rhsRecency
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func filteredLocalModelHealthRecords(
        _ recordsByModelID: [String: LocalModelHealthRecord],
        validModelIDs: Set<String>
    ) -> [LocalModelHealthRecord] {
        recordsByModelID.values
            .filter { validModelIDs.contains($0.modelId) }
            .sorted { lhs, rhs in
                let lhsPriority = LocalModelHealthSupport.sortPriority(for: lhs)
                let rhsPriority = LocalModelHealthSupport.sortPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                let lhsRecency = LocalModelHealthSupport.recency(for: lhs)
                let rhsRecency = LocalModelHealthSupport.recency(for: rhs)
                if lhsRecency != rhsRecency {
                    return lhsRecency > rhsRecency
                }
                return lhs.modelId.localizedCaseInsensitiveCompare(rhs.modelId) == .orderedAscending
            }
    }

    private func localModelTrialCategory(for record: LocalModelHealthRecord) -> ModelTrialCategory {
        switch LocalModelHealthSupport.effectiveState(for: record) ?? record.state {
        case .healthy:
            return .success
        case .degraded, .unknownStale:
            return .failed
        case .blockedReadiness:
            return .config
        case .blockedRuntime:
            return .runtime
        }
    }

    private func stateRank(_ state: HubModelState) -> Int {
        switch state {
        case .loaded:
            return 0
        case .sleeping:
            return 1
        case .available:
            return 2
        }
    }

    private func filteredRemoteKeyHealthRecords(
        _ recordsByKey: [String: RemoteKeyHealthRecord],
        validKeys: Set<String>
    ) -> [RemoteKeyHealthRecord] {
        recordsByKey.values
            .filter { validKeys.contains($0.keyReference) }
            .sorted { lhs, rhs in
                let lhsPriority = RemoteKeyHealthSupport.sortPriority(for: lhs)
                let rhsPriority = RemoteKeyHealthSupport.sortPriority(for: rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                let lhsRecency = RemoteKeyHealthSupport.recency(for: lhs)
                let rhsRecency = RemoteKeyHealthSupport.recency(for: rhs)
                if lhsRecency != rhsRecency {
                    return lhsRecency > rhsRecency
                }
                return lhs.keyReference.localizedCaseInsensitiveCompare(rhs.keyReference) == .orderedAscending
            }
    }

    private func configureModelHealthAutoScanMonitoring() {
        guard modelHealthAutoScanCancellables.isEmpty else {
            refreshLocalModelHealthAutoScanTimer()
            refreshRemoteKeyHealthAutoScanTimer()
            return
        }

        ModelStore.shared.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLocalModelHealthAutoScanTimer()
            }
            .store(in: &modelHealthAutoScanCancellables)

        NotificationCenter.default.publisher(for: .relflowhubRemoteModelsChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshRemoteKeyHealthAutoScanTimer()
            }
            .store(in: &modelHealthAutoScanCancellables)

        refreshLocalModelHealthAutoScanTimer()
        refreshRemoteKeyHealthAutoScanTimer()
    }

    private func refreshLocalModelHealthAutoScanTimer(now: TimeInterval = Date().timeIntervalSince1970) {
        localModelHealthAutoScanTimer?.invalidate()
        localModelHealthAutoScanTimer = nil

        guard let dueAt = nextLocalModelHealthAutoScanDueAt(now: now) else { return }
        let delay = max(1.0, dueAt - now)
        localModelHealthAutoScanTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runDueLocalModelHealthAutoScan()
            }
        }
    }

    private func refreshRemoteKeyHealthAutoScanTimer(now: TimeInterval = Date().timeIntervalSince1970) {
        remoteKeyHealthAutoScanTimer?.invalidate()
        remoteKeyHealthAutoScanTimer = nil

        guard let dueAt = nextRemoteKeyHealthAutoScanDueAt(now: now) else { return }
        let delay = max(1.0, dueAt - now)
        remoteKeyHealthAutoScanTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runDueRemoteKeyHealthAutoScan()
            }
        }
    }

    private func nextLocalModelHealthAutoScanDueAt(now: TimeInterval) -> TimeInterval? {
        guard localModelHealthAutoScanSchedule.isEnabled else { return nil }
        let models = ModelStore.shared.snapshot.models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
        guard !models.isEmpty else { return nil }

        let healthByModelID = Dictionary(
            uniqueKeysWithValues: localModelHealthSnapshot.records.map { ($0.modelId, $0) }
        )

        return models.compactMap { model in
            localModelHealthAutoScanSchedule.nextDueAt(
                lastCheckedAt: healthByModelID[model.id]?.lastCheckedAt,
                now: now
            )
        }
        .min()
    }

    private func nextRemoteKeyHealthAutoScanDueAt(now: TimeInterval) -> TimeInterval? {
        guard remoteKeyHealthAutoScanSchedule.isEnabled else { return nil }
        let groups = RemoteKeyHealthScanner.groups(from: RemoteModelStorage.load().models)
        guard !groups.isEmpty else { return nil }

        let healthByKey = Dictionary(
            uniqueKeysWithValues: remoteKeyHealthSnapshot.records.map { ($0.keyReference, $0) }
        )

        return groups.compactMap { group in
            remoteKeyHealthAutoScanSchedule.nextDueAt(
                lastCheckedAt: healthByKey[group.keyReference]?.lastCheckedAt,
                now: now
            )
        }
        .min()
    }

    private func dueLocalModelHealthModelIDs(now: TimeInterval) -> Set<String> {
        guard localModelHealthAutoScanSchedule.isEnabled else { return [] }
        let models = ModelStore.shared.snapshot.models
            .filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }
        guard !models.isEmpty else { return [] }

        let healthByModelID = Dictionary(
            uniqueKeysWithValues: localModelHealthSnapshot.records.map { ($0.modelId, $0) }
        )

        return Set(
            models.compactMap { model in
                return localModelHealthAutoScanSchedule.isDue(
                    lastCheckedAt: healthByModelID[model.id]?.lastCheckedAt,
                    now: now
                ) ? model.id : nil
            }
        )
    }

    private func dueRemoteKeyHealthReferences(now: TimeInterval) -> Set<String> {
        guard remoteKeyHealthAutoScanSchedule.isEnabled else { return [] }
        let groups = RemoteKeyHealthScanner.groups(from: RemoteModelStorage.load().models)
        guard !groups.isEmpty else { return [] }

        let healthByKey = Dictionary(
            uniqueKeysWithValues: remoteKeyHealthSnapshot.records.map { ($0.keyReference, $0) }
        )

        return Set(
            groups.compactMap { group in
                return remoteKeyHealthAutoScanSchedule.isDue(
                    lastCheckedAt: healthByKey[group.keyReference]?.lastCheckedAt,
                    now: now
                ) ? group.keyReference : nil
            }
        )
    }

    private func runDueLocalModelHealthAutoScan() {
        let now = Date().timeIntervalSince1970
        let modelIDs = dueLocalModelHealthModelIDs(now: now)
        guard !modelIDs.isEmpty, !localModelHealthScanInFlight else {
            refreshLocalModelHealthAutoScanTimer(now: now)
            return
        }
        requestLocalModelHealthScan(
            limitingTo: modelIDs,
            mode: .preflightOnly,
            updatesTrialStatus: false
        )
    }

    private func runDueRemoteKeyHealthAutoScan() {
        let now = Date().timeIntervalSince1970
        let keyReferences = dueRemoteKeyHealthReferences(now: now)
        guard !keyReferences.isEmpty, !remoteKeyHealthScanInFlight else {
            refreshRemoteKeyHealthAutoScanTimer(now: now)
            return
        }
        requestRemoteKeyHealthScan(limitingTo: keyReferences)
    }

    func testRemoteModelConnectivity(_ entry: RemoteModelEntry) {
        let key = remoteModelTrialKey(entry.id)
        modelTrialStatusByKey[key] = ModelTrialStatus(
            state: .running,
            category: .running,
            summary: HubUIStrings.Models.Trial.running,
            detail: "",
            updatedAt: Date().timeIntervalSince1970
        )

        Task { @MainActor in
            let startedAt = Date().timeIntervalSince1970
            do {
                let result = await RemoteModelTrialRunner.generate(
                    modelId: entry.id,
                    allowDisabledModelLookup: !entry.enabled,
                    prompt: modelTrialPrompt,
                    timeoutSec: 20.0
                )
                guard result.ok else {
                    let detail = humanizedRemoteModelTrialError(status: result.status, error: result.error)
                    throw NSError(domain: "relflowhub", code: 21, userInfo: [NSLocalizedDescriptionKey: detail])
                }
                let response = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let responseSummary = response.isEmpty
                    ? HubUIStrings.Models.Trial.emptyResponse
                    : "\(HubUIStrings.Models.Trial.responsePrefix) \(String(response.prefix(80)))"
                let duration = HubUIStrings.Models.Trial.duration(Date().timeIntervalSince1970 - startedAt)
                modelTrialStatusByKey[key] = ModelTrialStatus(
                    state: .success,
                    category: .success,
                    summary: HubUIStrings.Models.Trial.success,
                    detail: HubUIStrings.Models.Trial.detailSummary([duration, responseSummary]),
                    updatedAt: Date().timeIntervalSince1970
                )
            } catch {
                let duration = HubUIStrings.Models.Trial.duration(Date().timeIntervalSince1970 - startedAt)
                let failureMessage = error.localizedDescription
                modelTrialStatusByKey[key] = ModelTrialStatus(
                    state: .failure,
                    category: hubClassifyModelTrialFailure(failureMessage),
                    summary: HubUIStrings.Models.Trial.failed,
                    detail: HubUIStrings.Models.Trial.detailSummary([duration, failureMessage]),
                    updatedAt: Date().timeIntervalSince1970
                )
            }
        }
    }

    // -------------------- Hub AI (file IPC) --------------------
    private func preferredModelIdForTask(_ taskType: String) -> String {
        resolvedRoutingBinding(taskType: taskType).effectiveModelId
    }

    private func applyRoutingSettings(_ settings: RoutingSettings, persist: Bool) {
        routingSettings = settings
        routingPreferredModelIdByTask = settings.preferredModelIdByTask
        if persist {
            RoutingSettingsStorage.save(settings)
        }
    }

    private func normalizedRoutingToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func routingTaskLabel(_ taskType: String) -> String {
        if let descriptor = LocalTaskRoutingCatalog.descriptor(for: taskType) {
            return descriptor.title
        }
        let normalized = normalizedRoutingToken(taskType)
        guard !normalized.isEmpty else { return HubUIStrings.Settings.GRPC.EditDeviceSheet.autoSelected }
        return normalized
            .split(separator: "_")
            .map { token in
                let text = String(token)
                guard let first = text.first else { return "" }
                return String(first).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Send a single text-generate request to the local runtime via file IPC.
    ///
    /// This is used by Hub-side features (Routing Preview, Today New summaries, etc).
    func aiGenerate(
        prompt: String,
        taskType: String,
        preferredModelIDOverride: String? = nil,
        requiredProviderID: String? = nil,
        requiredModelID: String? = nil,
        maxTokens: Int = 768,
        temperature: Double = 0.2,
        topP: Double = 0.95,
        autoLoad: Bool = true,
        timeoutSec: Double = 25
    ) async throws -> String {
        let normalizedRequiredModelID = requiredModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localTextModels = ModelStore.shared.snapshot.models.filter { model in
            let path = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return false }
            guard model.taskKinds.contains("text_generate") else { return false }
            if !normalizedRequiredModelID.isEmpty {
                return model.id == normalizedRequiredModelID
            }
            return true
        }
        if localTextModels.isEmpty {
            throw NSError(
                domain: "relflowhub",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.noLocalTextGenerateModels]
            )
        }

        let preferredOverride = preferredModelIDOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preferred = preferredOverride.isEmpty ? preferredModelIdForTask(taskType) : preferredOverride
        let targetModel = localTextModels.first(where: { $0.id == preferred }) ?? localTextModels.first
        let providerID = {
            let explicit = requiredProviderID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if !explicit.isEmpty {
                return explicit
            }
            if let targetModel {
                return LocalModelRuntimeActionPlanner.providerID(for: targetModel)
            }
            return "mlx"
        }()
        var status = AIRuntimeStatusStorage.load()
        if autoLoad || aiRuntimeAutoStart {
            if status?.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) != true {
                let recoveryWindow = min(12.0, max(4.0, timeoutSec * 0.4))
                _ = await ensureRuntimeReady(for: providerID, waitUpToSec: recoveryWindow)
                status = AIRuntimeStatusStorage.load()
            }
        }

        // Preflight.
        guard let st = status, st.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            throw NSError(
                domain: "relflowhub",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.generateNotStarted]
            )
        }
        if !st.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) {
            let doctor = st.providerDoctorText(ttl: AIRuntimeStatus.recommendedHeartbeatTTL).trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = (st.providerStatus(providerID)?.importError?.isEmpty == false)
                ? (st.providerStatus(providerID)?.importError ?? "")
                : ((st.importError?.isEmpty == false) ? (st.importError ?? "") : HubUIStrings.Settings.Advanced.Runtime.mlxProviderUnavailable)
            let msg = doctor.isEmpty ? fallback : doctor
            throw NSError(
                domain: "relflowhub",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.generateNotReady(msg)]
            )
        }

        let base = SharedPaths.ensureHubDirectory()
        let reqDir = base.appendingPathComponent("ai_requests", isDirectory: true)
        let respDir = base.appendingPathComponent("ai_responses", isDirectory: true)
        try? FileManager.default.createDirectory(at: reqDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: respDir, withIntermediateDirectories: true)

        let reqId = UUID().uuidString
        let reqURL = reqDir.appendingPathComponent("req_\(reqId).json")
        let respURL = respDir.appendingPathComponent("resp_\(reqId).jsonl")

        let obj: [String: Any] = [
            "type": "generate",
            "req_id": reqId,
            "app_id": "hub_ui",
            "task_type": taskType,
            "preferred_model_id": preferred,
            "prompt": prompt,
            "max_tokens": max(1, min(8192, maxTokens)),
            "temperature": temperature,
            "top_p": topP,
            "created_at": Date().timeIntervalSince1970,
            "auto_load": autoLoad,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            throw NSError(
                domain: "relflowhub",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.encodeGenerateRequestFailed]
            )
        }
        do {
            try data.write(to: reqURL, options: .atomic)
        } catch {
            throw NSError(
                domain: "relflowhub",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.writeGenerateRequestFailed(error.localizedDescription)]
            )
        }

        let finalText: String = try await Task.detached(priority: .userInitiated) {
            let deadline = Date().addingTimeInterval(timeoutSec)
            var pos: UInt64 = 0
            var buf = ""
            var done: (ok: Bool, reason: String)? = nil

            while Date() < deadline {
                if let fh = try? FileHandle(forReadingFrom: respURL) {
                    defer { try? fh.close() }
                    do {
                        try fh.seek(toOffset: pos)
                        let chunk = try fh.readToEnd() ?? Data()
                        pos += UInt64(chunk.count)
                        if !chunk.isEmpty, let s = String(data: chunk, encoding: .utf8) {
                            for line in s.split(separator: "\n", omittingEmptySubsequences: true) {
                                guard let ld = String(line).data(using: .utf8) else { continue }
                                guard let o = try? JSONSerialization.jsonObject(with: ld) as? [String: Any] else { continue }
                                guard String(describing: o["req_id"] ?? "") == reqId else { continue }
                                let typ = String(describing: o["type"] ?? "")
                                if typ == "delta" {
                                    buf += String(describing: o["text"] ?? "")
                                } else if typ == "done" {
                                    let ok = (o["ok"] as? Bool) ?? false
                                    let reason = String(describing: o["reason"] ?? "")
                                    done = (ok: ok, reason: reason)
                                }
                            }
                        }
                    } catch {
                        // Ignore read races.
                    }
                }

                if done != nil { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }

            if let d = done {
                if d.ok {
                    return buf.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                throw NSError(domain: "relflowhub", code: 6, userInfo: [NSLocalizedDescriptionKey: d.reason])
            }
            throw NSError(
                domain: "relflowhub",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.generateTimeout]
            )
        }.value

        return finalText
    }

    private func localModelTrialKey(_ modelId: String) -> String {
        "local::\(modelId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func remoteModelTrialKey(_ modelId: String) -> String {
        "remote::\(modelId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private func runLocalModelTrial(_ model: HubModel) async throws -> String {
        guard let trialPath = localModelTrialPath(for: model) else {
            throw NSError(
                domain: "relflowhub",
                code: 30,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Models.Review.Bench.noRegisteredTasks]
            )
        }

        switch trialPath {
        case .textGenerate:
            let response = try await aiGenerate(
                prompt: modelTrialPrompt,
                taskType: "text_generate",
                preferredModelIDOverride: model.id,
                requiredProviderID: LocalModelRuntimeActionPlanner.providerID(for: model),
                requiredModelID: model.id,
                maxTokens: 24,
                temperature: 0.0,
                topP: 1.0,
                autoLoad: true,
                timeoutSec: 35
            )
            let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty {
                return HubUIStrings.Models.Trial.emptyResponse
            }
            return "\(HubUIStrings.Models.Trial.responsePrefix) \(String(normalized.prefix(80)))"
        case .quickBench(let taskKind, let fixtureProfile):
            return try await runQuickBenchTrial(model: model, taskKind: taskKind, fixtureProfile: fixtureProfile)
        }
    }

    private func localModelTrialPath(for model: HubModel) -> LocalModelTrialPath? {
        guard (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        if model.taskKinds.contains("text_generate") {
            return .textGenerate
        }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard let taskKind = ModelStore.shared.availableBenchTaskDescriptors(for: model).first?.taskKind,
              let fixtureProfile = LocalBenchFixtureCatalog.defaultFixtureID(for: taskKind, providerID: providerID) else {
            return nil
        }
        return .quickBench(taskKind: taskKind, fixtureProfile: fixtureProfile)
    }

    private func runQuickBenchTrial(
        model: HubModel,
        taskKind: String,
        fixtureProfile: String
    ) async throws -> String {
        let startedAt = Date().timeIntervalSince1970
        ModelStore.shared.runBench(
            modelId: model.id,
            taskKind: taskKind,
            fixtureProfile: fixtureProfile
        )
        let result = try await waitForLocalBenchTrialResult(
            modelId: model.id,
            requestedAfter: startedAt,
            timeoutSec: 65.0
        )
        if !result.ok {
            throw NSError(domain: "relflowhub", code: 31, userInfo: [NSLocalizedDescriptionKey: result.msg])
        }
        let taskTitle = LocalTaskRoutingCatalog.title(for: taskKind)
        return HubUIStrings.Models.Trial.detailSummary([
            HubUIStrings.Models.Trial.usingQuickBench,
            taskTitle,
            result.msg,
        ])
    }

    private func waitForLocalBenchTrialResult(
        modelId: String,
        requestedAfter: TimeInterval,
        timeoutSec: Double
    ) async throws -> ModelCommandResult {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if let result = ModelStore.shared.lastResultByModelId[modelId],
               result.action == "bench",
               result.finishedAt >= requestedAfter,
               ModelStore.shared.pendingAction(for: modelId) != "bench" {
                return result
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        throw NSError(
            domain: "relflowhub",
            code: 32,
            userInfo: [NSLocalizedDescriptionKey: HubUIStrings.Settings.Advanced.Runtime.generateTimeout]
        )
    }

    private func humanizedRemoteModelTrialError(status: Int, error: String) -> String {
        let normalizedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        if status > 0 {
            return RemoteProviderClient.userFacingHTTPError(status: status, body: normalizedError)
        }
        if !normalizedError.isEmpty {
            return RemoteProviderClient.humanizedBridgeFailureReason(normalizedError)
        }
        return HubUIStrings.Settings.Networking.BridgeIPC.invalidResponse
    }

    // -------------------- Today New (FA) batch summarization --------------------
    private struct FASummaryItem {
        let radarId: Int
        let title: String
    }

    private func parseFATrackerProjectName(_ n: HubNotification) -> String? {
        guard n.source == "FAtracker" else { return nil }
        let lines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if let first = lines.first {
            let s = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return nil
    }

    private func parseFATrackerRadarIds(_ n: HubNotification) -> [Int] {
        guard n.source == "FAtracker" else { return [] }
        if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
            let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let radarsRaw = items.first(where: { $0.name == "radars" })?.value ?? ""
            let ids = radarsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if !ids.isEmpty { return ids }
        }

        // Fallback: only look at the 2nd line (plain id list).
        let lines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if lines.count >= 2 {
            return lines[1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return []
    }

    private func parseFATrackerRadarTitles(_ n: HubNotification) -> [Int: String] {
        // Expected agent body format:
        //   <projectName>\n
        //   <id, id, id>\n
        //   \n
        //   <id> - <title>\n
        guard n.source == "FAtracker" else { return [:] }
        let lines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        if lines.count < 3 { return [:] }

        var out: [Int: String] = [:]
        for i in 2..<lines.count {
            let ln = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if ln.isEmpty { continue }

            // Extract leading number.
            var digits = ""
            var idx = ln.startIndex
            while idx < ln.endIndex {
                let ch = ln[idx]
                if ch.isNumber {
                    digits.append(ch)
                    idx = ln.index(after: idx)
                    continue
                }
                break
            }
            guard let rid = Int(digits), rid > 0 else { continue }

            var rest = String(ln[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if rest.hasPrefix("-") || rest.hasPrefix("—") || rest.hasPrefix(":") {
                rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let ttl = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ttl.isEmpty {
                out[rid] = ttl
            }
        }
        return out
    }

    func summarizeTodayNewFA(projectNameFilter: String? = nil) async throws -> String {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
        let now = Date().timeIntervalSince1970
        let active = notifications.filter { ($0.snoozedUntil ?? 0) <= now }
        let todayFA = active.filter { isFATrackerRadarNotification($0) && $0.createdAt >= todayStart }
        if todayFA.isEmpty {
            throw NSError(
                domain: "relflowhub",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.MainPanel.FASummary.noNewRadarToday]
            )
        }

        // Group by project name.
        var itemsByProject: [String: [FASummaryItem]] = [:]
        for n in todayFA {
            let proj = (parseFATrackerProjectName(n) ?? "(Unknown Project)").trimmingCharacters(in: .whitespacesAndNewlines)
            if let f = projectNameFilter, !f.isEmpty, proj != f { continue }
            let ids = parseFATrackerRadarIds(n)
            let titles = parseFATrackerRadarTitles(n)
            var arr = itemsByProject[proj] ?? []
            for rid in ids {
                let ttl = titles[rid] ?? ""
                arr.append(FASummaryItem(radarId: rid, title: ttl))
            }
            // De-dup by radar id.
            var seen: Set<Int> = []
            arr = arr.filter { seen.insert($0.radarId).inserted }
            itemsByProject[proj] = arr
        }

        if itemsByProject.isEmpty {
            throw NSError(
                domain: "relflowhub",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: HubUIStrings.MainPanel.FASummary.noMatchingProjectRadar]
            )
        }

        let projects = itemsByProject.keys.sorted()
        var input = ""
        for p in projects {
            let arr = itemsByProject[p] ?? []
            input += "Project: \(p) (\(arr.count))\n"
            for it in arr.prefix(18) {
                if it.title.isEmpty {
                    input += "- \(it.radarId)\n"
                } else {
                    input += "- \(it.radarId): \(it.title)\n"
                }
            }
            if arr.count > 18 {
                input += "- … (+\(arr.count - 18) more)\n"
            }
            input += "\n"
        }

        let prompt = HubUIStrings.MainPanel.FASummary.dailyRadarPrompt(input)

        return try await aiGenerate(prompt: prompt, taskType: "summarize", maxTokens: 900, temperature: 0.2, autoLoad: true, timeoutSec: 35)
    }

    private func appendAIRuntimeLogLine(_ line: String) {
        guard let h = aiRuntimeLogHandle else {
            return
        }
        let ts = ISO8601DateFormatter().string(from: Date())
        let s = "[\(ts)] \(line)\n"
        guard let data = s.data(using: .utf8) else {
            return
        }
        do {
            try h.write(contentsOf: data)
        } catch {
            // Ignore.
        }
    }

    private func defaultRuntimePythonServicePath() -> String {
        // Dev build heuristic: .../REL Flow Hub/build/RELFlowHub.app -> .../REL Flow Hub/python_service/
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("python_service", isDirectory: true)
            if FileManager.default.directoryExists(atPath: candidate.path),
               preferredAIRuntimeScriptURL(in: candidate) != nil {
                return candidate.path
            }
            dir.deleteLastPathComponent()
        }

        let sourceTreeCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("python-runtime", isDirectory: true)
            .appendingPathComponent("python_service", isDirectory: true)
        if FileManager.default.directoryExists(atPath: sourceTreeCandidate.path),
           preferredAIRuntimeScriptURL(in: sourceTreeCandidate) != nil {
            return sourceTreeCandidate.path
        }

        return ""
    }

    private func defaultRuntimeScriptPath() -> String {
        let root = defaultRuntimePythonServicePath()
        guard !root.isEmpty else {
            return ""
        }
        guard let scriptURL = preferredAIRuntimeScriptURL(in: URL(fileURLWithPath: root, isDirectory: true)) else {
            return ""
        }
        return scriptURL.path
    }

    private func defaultPythonPath() -> String {
        // Prefer the Hub-managed wrapper first. It lets packaged builds reuse the
        // container-local runtime bridge even when UserDefaults drift back to a framework
        // interpreter between launches.
        for path in LocalPythonRuntimeDiscovery.hubManagedRuntimeCandidatePaths() {
            return path
        }

        // Prefer a real python binary. `/usr/bin/python3` and `env python3` can be a
        // CommandLineTools stub that shells out to xcrun, which fails under App Sandbox.
        let cands = [
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        for p in cands {
            if FileManager.default.fileExists(atPath: p) {
                return p
            }
        }
        // Fallback (may be a stub on some systems).
        return "/usr/bin/env"
    }

    func startIPC() {
        HubDiagnostics.log("startIPC pid=\(getpid()) sandbox=\(SharedPaths.isSandboxedProcess())")
        // In App Sandbox, external tools cannot reliably connect to AF_UNIX sockets.
        // Use file-based IPC dropbox + heartbeat.
        if SharedPaths.isSandboxedProcess() {
            let f = FileIPC(store: self)
            self.fileIPC = f
            do {
                try f.start()
                ipcStatus = HubUIStrings.Menu.IPC.fileMode
                ipcPath = f.ipcPathText()
                HubDiagnostics.log("startIPC ok mode=file path=\(ipcPath)")
            } catch {
                ipcStatus = HubUIStrings.Menu.IPC.fileFailed(String(describing: error))
                ipcPath = f.ipcPathText()
                HubDiagnostics.log("startIPC failed mode=file err=\(error)")
            }
            return
        }

        let srv = UnixSocketServer(store: self)
        self.server = srv
        do {
            try srv.start()
            ipcStatus = HubUIStrings.Menu.IPC.socketMode
            ipcPath = SharedPaths.ipcSocketPath()
            HubDiagnostics.log("startIPC ok mode=socket path=\(ipcPath)")
        } catch {
            ipcStatus = HubUIStrings.Menu.IPC.socketFailed(String(describing: error))
            ipcPath = SharedPaths.ipcSocketPath()
            HubDiagnostics.log("startIPC failed mode=socket err=\(error)")
        }
    }

    func startDemoSatellites(count: Int = 6, seconds: Int = 120) {
        stopDemoSatellites(removeFiles: true)

        let n = max(1, min(6, count))
        let endAt = Date().addingTimeInterval(Double(max(10, min(600, seconds)))).timeIntervalSince1970
        demoSatellitesEndAt = endAt

        // Global stop marker: if multiple Hub instances are running, a single stop should
        // disable demo writers across all instances.
        let stopMarker = ClientStorage.dir().appendingPathComponent(".demo_satellites_stop")
        try? FileManager.default.removeItem(at: stopMarker)

        writeDemoSatellites(count: n)
        demoSatellitesTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                // Respect global stop marker.
                let stopMarker = ClientStorage.dir().appendingPathComponent(".demo_satellites_stop")
                if FileManager.default.fileExists(atPath: stopMarker.path) {
                    self.stopDemoSatellites(removeFiles: true)
                    return
                }

                if Date().timeIntervalSince1970 >= self.demoSatellitesEndAt {
                    self.stopDemoSatellites(removeFiles: true)
                    return
                }
                self.writeDemoSatellites(count: n)
            }
        }
    }

    private func writeDemoSatellites(count: Int) {
        let n = max(1, min(6, count))
        let now = Date().timeIntervalSince1970
        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for i in 1...n {
            let id = "demoapp\(i)"
            let hb = HubClientHeartbeat(
                appId: id,
                appName: "Demo App \(i)",
                activity: (i % 3 == 0) ? .idle : .active,
                aiEnabled: (i % 2 == 0),
                modelMemoryBytes: Int64(1_200_000_000 + i * 350_000_000),
                updatedAt: now
            )
            let path = dir.appendingPathComponent("\(id).json")
            if let data = try? JSONEncoder().encode(hb) {
                try? data.write(to: path, options: .atomic)
            }
        }

        clients.refresh()
    }

    func stopDemoSatellites(removeFiles: Bool = true) {
        demoSatellitesTimer?.invalidate()
        demoSatellitesTimer = nil
        demoSatellitesEndAt = 0

        guard removeFiles else { return }
        let dir = ClientStorage.dir()

        // Write stop marker first so any other Hub instances stop refreshing demo files.
        let stopMarker = dir.appendingPathComponent(".demo_satellites_stop")
        try? Data("stop".utf8).write(to: stopMarker, options: .atomic)

        // Remove all demoapp*.json files (be robust to older runs).
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in files {
                let name = url.lastPathComponent
                if name.hasPrefix("demoapp") && name.hasSuffix(".json") {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        clients.refresh()
    }

    func push(_ n: HubNotification) {
        // Allow users to disable noisy sources without uninstalling any agent.
        if !integrationFATrackerEnabled, n.source == "FAtracker" {
            return
        }
        if !integrationMailEnabled, n.source == "Mail" {
            return
        }
        if !integrationMessagesEnabled, n.source == "Messages" {
            return
        }
        if !integrationSlackEnabled, n.source == "Slack" {
            return
        }

        // Counts-only notifications (Mail/Messages/Slack) must go through the same
        // upsert/baseline logic as the built-in integrations. This allows an external
        // Dock agent to push counts without re-alerting after the user opens the app.
        if let key = n.dedupeKey, !key.isEmpty, (key == "mail_unread" || key == "messages_unread" || key == "slack_updates") {
            externalCountsUpdateAtByKey[key] = Date().timeIntervalSince1970
            let count = firstInt(in: n.body) ?? firstInt(in: n.title) ?? 0
            let bundleId: String = {
                if let s = n.actionURL, let u = URL(string: s),
                   let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems,
                   let bid = items.first(where: { $0.name == "bundle_id" })?.value,
                   !bid.isEmpty {
                    return bid
                }
                if n.source == "Mail" { return "com.apple.mail" }
                if n.source == "Messages" { return "com.apple.MobileSMS" }
                if n.source == "Slack" { return "com.tinyspeck.slackmacgap" }
                return ""
            }()

            if !bundleId.isEmpty {
                upsertCountsOnlyNotification(source: n.source, bundleId: bundleId, count: count, dedupeKey: key)
                return
            }
        }

        // Treat inbound notifications as a client "presence" signal so satellites show up even
        // before apps implement explicit heartbeat writes.
        touchClientPresence(from: n)

        guard shouldRetainHubNotification(n) else {
            return
        }

        let shouldOpenMainForPairing = Self.shouldPromotePendingPairingNotification(n)

        // Dedupe/update on dedupeKey when provided.
        if let key = n.dedupeKey, !key.isEmpty {
            if let idx = notifications.firstIndex(where: { $0.dedupeKey == key }) {
                var merged = n
                merged.id = notifications[idx].id
                notifications[idx] = merged
                sort()
                updateSummary()
                schedulePersistNotifications()
                return
            }
        }
        notifications.append(n)
        sort()
        updateSummary()
        schedulePersistNotifications()
        if shouldOpenMainForPairing {
            NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
        }
    }

    static func shouldPromotePendingPairingNotification(_ notification: HubNotification) -> Bool {
        guard notification.source == "Hub" else { return false }
        let key = (notification.dedupeKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return key.hasPrefix("pairing_request:")
    }

    private func touchClientPresence(from n: HubNotification) {
        let source = n.source.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty || source == "Hub" { return }

        let now = Date().timeIntervalSince1970

        let appId = normalizedClientId(source)
        if appId.isEmpty { return }

        // Throttle disk writes to keep the hub ultra-light.
        if let last = lastClientTouchById[appId], (now - last) < 5.0 {
            return
        }
        lastClientTouchById[appId] = now

        let dir = ClientStorage.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent("\(appId).json")
        var hb: HubClientHeartbeat

        if let data = try? Data(contentsOf: path),
           let existing = try? JSONDecoder().decode(HubClientHeartbeat.self, from: data) {
            hb = existing
            hb.appName = existing.appName.isEmpty ? source : existing.appName
            hb.activity = .active
            hb.updatedAt = now
        } else {
            hb = HubClientHeartbeat(appId: appId, appName: source, activity: .active, aiEnabled: false, updatedAt: now)
        }

        if let data = try? JSONEncoder().encode(hb) {
            // `.atomic` keeps the file read-safe for the ClientStore polling loop.
            try? data.write(to: path, options: .atomic)
        }

        // Pull immediately so the floating orb can reflect the new satellite quickly.
        clients.refresh()
    }

    private func normalizedClientId(_ s: String) -> String {
        let canonical = HubNetworkPolicyStorage.canonicalAppId(s)
        if canonical == "x_terminal" {
            return canonical
        }

        let lower = s.lowercased()
        var out = ""
        out.reserveCapacity(lower.count)
        for ch in lower.unicodeScalars {
            let v = ch.value
            if (v >= 48 && v <= 57) || (v >= 97 && v <= 122) {
                out.unicodeScalars.append(ch)
            } else if v == 95 || v == 45 || v == 32 {
                if out.last != "_" { out.append("_") }
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    func snooze(_ id: String, minutes: Int = 10) {
        let m = max(1, min(24 * 60, minutes))
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].snoozedUntil = Date().addingTimeInterval(Double(m) * 60.0).timeIntervalSince1970
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func snoozeLaterToday(_ id: String) {
        // "Later Today" heuristic: if before 17:00 -> 17:00, else -> tomorrow 09:00.
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        var target: Date
        if hour < 17 {
            target = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(60 * 60)
        } else {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(24 * 60 * 60)
            target = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
        snoozeUntil(id, until: target)
    }

    private func snoozeUntil(_ id: String, until: Date) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].snoozedUntil = until.timeIntervalSince1970
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func unsnooze(_ id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].snoozedUntil = nil
            updateSummary()
            sort()
            schedulePersistNotifications()
        }
    }

    func markRead(_ id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].unread = false
            updateSummary()
            schedulePersistNotifications()
        }
    }

    func presentNotificationInspector(_ notification: HubNotification) {
        notificationInspectorTarget = notification
        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
    }

    func dismissNotificationInspector() {
        notificationInspectorTarget = nil
    }

    func openPairedDevicesSettings(deviceID: String? = nil, capabilityKey: String? = nil) {
        let normalizedDeviceID = deviceID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCapabilityKey = hubNormalizedPairedDeviceCapabilityFocusKey(capabilityKey)
        settingsNavigationTarget = .pairedDevices(
            deviceID: normalizedDeviceID?.isEmpty == true ? nil : normalizedDeviceID,
            capabilityKey: normalizedCapabilityKey
        )
        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
    }

    func consumeSettingsNavigationTarget(_ target: HubSettingsNavigationTarget) {
        if settingsNavigationTarget == target {
            settingsNavigationTarget = nil
        }
    }

    func openNotificationAction(_ n: HubNotification) {
        guard let s = n.actionURL, !s.isEmpty, let url = URL(string: s) else {
            return
        }

        if (url.scheme ?? "").lowercased() == "xterminal" {
            NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
            return
        }

        // Counts-only integrations: opening the target app counts as "seen".
        if let key = n.dedupeKey, let c = (firstInt(in: n.body) ?? firstInt(in: n.title)) {
            if key == "mail_unread" || key == "messages_unread" || key == "slack_updates" {
                setLastSeenCount(c, dedupeKey: key)
            }
        }

        // Custom local actions handled by the Hub.
        if handleLocalActionURL(url) {
            return
        }

        // Default: let macOS route the URL.
        NSWorkspace.shared.open(url)
    }

    func openFATrackerForRadars(_ radarIds: [Int], projectId: Int? = nil, fallbackURL: String? = nil) {
        openInFATracker(radarIds: radarIds, projectId: projectId, fallbackURL: fallbackURL)
    }

    func setFATrackerLauncher(url: URL) {
        faTrackerLauncherPath = url.path
        // Persist a security-scoped bookmark so sandboxed builds can open it later.
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: faTrackerLauncherBookmarkKey)
        } catch {
            // Keep path only; opening may still work if it is inside an allowed location.
            UserDefaults.standard.removeObject(forKey: faTrackerLauncherBookmarkKey)
        }
    }

    func clearFATrackerLauncher() {
        faTrackerLauncherPath = ""
        UserDefaults.standard.removeObject(forKey: faTrackerLauncherBookmarkKey)
    }

    func testOpenFATrackerLauncher() {
        _ = openFATracker()
    }

    func openFATracker() -> Bool {
        if openFATrackerByBundleIdIfConfigured() {
            return true
        }
        return openFATrackerLauncherIfConfigured()
    }

    private static func pairedDevicesSettingsActionURL(
        deviceID: String? = nil,
        capabilityKey: String? = nil
    ) -> String {
        var components = URLComponents()
        components.scheme = "relflowhub"
        components.host = "settings"
        components.path = "/paired-devices"
        let normalizedDeviceID = deviceID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCapabilityKey = hubNormalizedPairedDeviceCapabilityFocusKey(capabilityKey)
        var queryItems: [URLQueryItem] = []
        if let normalizedDeviceID, !normalizedDeviceID.isEmpty {
            queryItems.append(URLQueryItem(name: "device_id", value: normalizedDeviceID))
        }
        if let normalizedCapabilityKey {
            queryItems.append(URLQueryItem(name: "capability", value: normalizedCapabilityKey))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.string ?? "relflowhub://settings/paired-devices"
    }

    private func handleLocalActionURL(_ url: URL) -> Bool {
        // relflowhub://handoff/fatracker?radars=123,456&fallback=rdar://123
        let scheme = (url.scheme ?? "").lowercased()
        if scheme != "relflowhub" {
            return false
        }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()

        // relflowhub://openapp?bundle_id=com.apple.mail
        if host == "openapp" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let bid = (items.first(where: { $0.name == "bundle_id" })?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !bid.isEmpty, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                _ = NSWorkspace.shared.open(appURL)
                return true
            }
            return true // handled (even if we couldn't resolve)
        }

        if host == "handoff" && path == "/fatracker" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let radarsRaw = items.first(where: { $0.name == "radars" })?.value ?? ""
            let fallback = items.first(where: { $0.name == "fallback" })?.value
            let projectId = Int(items.first(where: { $0.name == "project_id" })?.value ?? "")
            let ids = radarsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            openInFATracker(radarIds: ids, projectId: projectId, fallbackURL: fallback)
            return true
        }

        if host == "settings" && (path == "/paired-devices" || path == "/paired_devices" || path == "/devices") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let deviceID = items.first(where: { $0.name == "device_id" })?.value
            let capabilityKey = items.first(where: { $0.name == "capability" })?.value
            openPairedDevicesSettings(deviceID: deviceID, capabilityKey: capabilityKey)
            return true
        }
        return false
    }

    private func openInFATracker(radarIds: [Int], projectId: Int?, fallbackURL: String?) {
        // 1) Write a handoff file so FA Tracker can locate the intended radars.
        if !radarIds.isEmpty {
            writeFATrackerHandoff(radarIds: radarIds, projectId: projectId)
        }

        // 2) Attempt to launch FA Tracker (preferred).
        if openFATracker() {
            return
        }

        // 3) Fallback: open the first rdar:// link (or explicit fallback URL).
        if let s = fallbackURL, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
            return
        }
        if let first = radarIds.first, let u = URL(string: "rdar://\(first)") {
            NSWorkspace.shared.open(u)
        }
    }

    private func openFATrackerByBundleIdIfConfigured() -> Bool {
        let bid = faTrackerBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        if bid.isEmpty { return false }

        // Resolve to an app URL via LaunchServices (does not require direct file access).
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.open(url)
        }

        return false
    }

    private func openFATrackerLauncherIfConfigured() -> Bool {
        // Prefer the security-scoped bookmark if available.
        if let data = UserDefaults.standard.data(forKey: faTrackerLauncherBookmarkKey) {
            var stale = false
            do {
                let u = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                let ok = u.startAccessingSecurityScopedResource()
                defer {
                    if ok { u.stopAccessingSecurityScopedResource() }
                }
                if FileManager.default.fileExists(atPath: u.path) {
                    return NSWorkspace.shared.open(u)
                }
            } catch {
                // Fall back to path.
            }
        }

        let p = faTrackerLauncherPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return false }
        let u = URL(fileURLWithPath: normalizeUserPath(p))
        // Do not preflight existence here: sandboxed builds may be unable to stat the file even
        // though LaunchServices can open it.
        return NSWorkspace.shared.open(u)
    }

    func installFATrackerLauncherWrapper(targetPath: String) -> Bool {
        let target = normalizeUserPath(targetPath)
        if target.isEmpty { return false }

        // Put the wrapper under ~/RELFlowHub (allowed by our sandbox exception).
        let base = SharedPaths.ensureHubDirectory()
        let out = base.appendingPathComponent("launch_fatracker.command")

        let esc = target.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
#!/bin/bash
set -euo pipefail

TARGET=\"\(esc)\"

if [ -d \"$TARGET\" ] && [[ \"$TARGET\" == *.app ]]; then
  /usr/bin/open \"$TARGET\"
  exit 0
fi

if [ -f \"$TARGET\" ]; then
  /bin/bash \"$TARGET\"
  exit 0
fi

echo \"FA Tracker launcher target not found: $TARGET\" >&2
exit 1
"""

        do {
            try script.data(using: .utf8)?.write(to: out, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: out.path)
            faTrackerLauncherPath = out.path
            // Wrapper is inside allowed path; bookmark isn't necessary.
            UserDefaults.standard.removeObject(forKey: faTrackerLauncherBookmarkKey)
            return true
        } catch {
            return false
        }
    }

    private func normalizeUserPath(_ s: String) -> String {
        // Users often paste shell-escaped paths (e.g. "Andrew\ projects").
        // Convert common escapes back to a normal filesystem path.
        var p = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if (p.hasPrefix("\"") && p.hasSuffix("\"")) || (p.hasPrefix("'") && p.hasSuffix("'")) {
            p = String(p.dropFirst().dropLast())
        }
        p = p.replacingOccurrences(of: "\\ ", with: " ")
        return (p as NSString).expandingTildeInPath
    }

    private func writeFATrackerHandoff(radarIds: [Int], projectId: Int?) {
        var obj: [String: Any] = [
            "type": "fatracker_open",
            "createdAt": Date().timeIntervalSince1970,
            "radarIds": radarIds,
        ]
        if let pid = projectId, pid > 0 {
            obj["projectId"] = pid
        }

        // Write into the Hub directory (sandbox-safe). FA Tracker also watches this location.
        // This avoids App Group TCC prompt spam on ad-hoc signed dev builds.
        let base = SharedPaths.ensureHubDirectory()

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            return
        }

        let dir = base.appendingPathComponent("handoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("fatracker_open.json")
        try? data.write(to: path, options: .atomic)

        // Note: we intentionally do not touch App Group storage here to avoid repeated prompts.
    }

    func dismiss(_ id: String) {
        removeNotification(dedupeKey: nil, id: id)
    }

    func dismissAll() {
        notifications.removeAll()
        updateSummary()
        schedulePersistNotifications()
    }

    private func sort() {
        notifications.sort { a, b in
            let now = Date().timeIntervalSince1970
            let asn = (a.snoozedUntil ?? 0) > now
            let bsn = (b.snoozedUntil ?? 0) > now
            if asn != bsn {
                return !asn && bsn
            }
            if a.unread != b.unread {
                return a.unread && !b.unread
            }
            return a.createdAt > b.createdAt
        }
    }

    private func updateSummary() {
        // MVP: Today-new count is the number of unread FAtracker "radar" notifications.
        let now = Date().timeIntervalSince1970
        let n = notifications.filter { $0.unread && ($0.snoozedUntil ?? 0) <= now && isFATrackerRadarNotification($0) }.count
        let nextText = nextMeetingText()
        SummaryStorage.save(
            SummaryState(
                todayNewUnseenCount: n,
                nextMeetingText: nextText,
                updatedAt: Date().timeIntervalSince1970
            )
        )
    }

    func isFATrackerRadarNotification(_ n: HubNotification) -> Bool {
        if n.source != "FAtracker" { return false }

        // Agent notifications use a stable title format.
        if HubUIStrings.Notifications.FATracker.parsePrefixes.contains(where: { n.title.hasPrefix($0) }) { return true }

        // Or a relflowhub local handoff action.
        if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
            return (u.host ?? "").lowercased() == "handoff" && u.path.lowercased() == "/fatracker"
        }

        return false
    }

    private func nextMeetingText() -> String {
        let now = Date().timeIntervalSince1970
        if let m = meetings.first(where: { $0.isMeeting && !$0.id.isEmpty && !isMeetingDismissed($0, now: now) }) {
            let f = DateFormatter()
            f.dateFormat = HubUIStrings.Formatting.timeOnly
            if now >= m.startAt && now < m.endAt {
                return HubUIStrings.MainPanel.Meeting.inProgressSummary(m.title)
            }
            return HubUIStrings.MainPanel.Meeting.nextSummary(time: f.string(from: m.startDate), title: m.title)
        }
        // Keep default consistent with widget template.
        return HubUIStrings.MainPanel.Meeting.noScheduleToday
    }

    private func refreshCalendarStatusOnly() {
        disableHubCalendarIntegration()
    }

    private func disableHubCalendarIntegration() {
        meetings = []
        specialDaysToday = []
        calendarStatus = HubUIStrings.Menu.calendarMigrated
        updateSummary()
    }

    private func setupNotificationsAuthorizationState() {
        // No-op for now; kept as a hook for future UI.
    }
}
