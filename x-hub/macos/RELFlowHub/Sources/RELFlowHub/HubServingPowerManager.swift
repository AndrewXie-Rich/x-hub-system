import Foundation
import IOKit.pwr_mgt

struct HubServingPowerAssertionFailure: Error {
    let message: String
}

protocol HubServingCaffeinateDriving {
    var runningArguments: [String]? { get }
    func start(arguments: [String]) -> Result<Void, HubServingPowerAssertionFailure>
    func stop() -> String?
}

final class ProcessHubServingCaffeinateDriver: HubServingCaffeinateDriving {
    private var process: Process?
    private var launchedArguments: [String]?

    var runningArguments: [String]? {
        guard let process, process.isRunning else { return nil }
        return launchedArguments
    }

    func start(arguments: [String]) -> Result<Void, HubServingPowerAssertionFailure> {
        let desiredArguments = arguments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !desiredArguments.isEmpty else {
            return .failure(HubServingPowerAssertionFailure(message: "caffeinate_arguments_missing"))
        }

        if runningArguments == desiredArguments {
            return .success(())
        }

        _ = stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = desiredArguments + ["-w", String(getpid())]
        process.terminationHandler = { proc in
            HubDiagnostics.log("hub_power.caffeinate exited code=\(proc.terminationStatus)")
        }

        do {
            try process.run()
            self.process = process
            launchedArguments = desiredArguments
            return .success(())
        } catch {
            self.process = nil
            launchedArguments = nil
            return .failure(HubServingPowerAssertionFailure(message: "caffeinate_start_failed=\(error.localizedDescription)"))
        }
    }

    func stop() -> String? {
        defer {
            process = nil
            launchedArguments = nil
        }

        guard let process else { return nil }
        guard process.isRunning else { return nil }

        process.terminate()
        _ = ProcessWaitSupport.waitForExit(process, timeoutSec: 0.8)

        if process.isRunning {
            let pid = pid_t(process.processIdentifier)
            if pid > 1 {
                kill(pid, SIGKILL)
            }
            _ = ProcessWaitSupport.waitForExit(process, timeoutSec: 0.5)
        }

        if process.isRunning {
            return "caffeinate_stop_timed_out pid=\(process.processIdentifier)"
        }
        return nil
    }
}

protocol HubServingPowerAssertionDriving {
    func acquireSystemIdleSleep(reason: String) -> Result<UInt32, HubServingPowerAssertionFailure>
    func acquireDisplayIdleSleep(reason: String) -> Result<UInt32, HubServingPowerAssertionFailure>
    func releaseAssertion(id: UInt32) -> String?
}

struct IOKitHubServingPowerAssertionDriver: HubServingPowerAssertionDriving {
    func acquireSystemIdleSleep(reason: String) -> Result<UInt32, HubServingPowerAssertionFailure> {
        acquireAssertion(
            type: kIOPMAssertionTypePreventUserIdleSystemSleep as String,
            reason: reason
        )
    }

    func acquireDisplayIdleSleep(reason: String) -> Result<UInt32, HubServingPowerAssertionFailure> {
        acquireAssertion(
            type: kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
            reason: reason
        )
    }

    func releaseAssertion(id: UInt32) -> String? {
        let result = IOPMAssertionRelease(IOPMAssertionID(id))
        guard result != kIOReturnSuccess else { return nil }
        return "IOPMAssertionRelease=\(result)"
    }

    private func acquireAssertion(type: String, reason: String) -> Result<UInt32, HubServingPowerAssertionFailure> {
        var assertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            return .failure(HubServingPowerAssertionFailure(message: "IOPMAssertionCreateWithName=\(result)"))
        }
        return .success(UInt32(assertionID))
    }
}

@MainActor
final class HubServingPowerManager: ObservableObject {
    static let shared = HubServingPowerManager()

    static let keepSystemAwakeKey = "relflowhub_keep_system_awake_while_serving"
    static let keepDisplayAwakeKey = "relflowhub_keep_display_awake_while_serving"

    @Published var keepSystemAwakeWhileServing: Bool {
        didSet {
            defaults.set(keepSystemAwakeWhileServing, forKey: Self.keepSystemAwakeKey)
            applyAssertionState()
        }
    }

    @Published var keepDisplayAwakeWhileServing: Bool {
        didSet {
            defaults.set(keepDisplayAwakeWhileServing, forKey: Self.keepDisplayAwakeKey)
            applyAssertionState()
        }
    }

    @Published private(set) var statusText: String
    @Published private(set) var detailText: String
    @Published private(set) var lastError: String = ""

    private let driver: HubServingPowerAssertionDriving
    private let caffeinateDriver: HubServingCaffeinateDriving
    private let defaults: UserDefaults

    private var systemAssertionID: UInt32?
    private var displayAssertionID: UInt32?
    private var lastLoggedAssertionSnapshot: String = ""

    private var servingState: ServingState = .init(
        autoStartEnabled: false,
        serverRunning: false,
        externalHost: nil
    )

    private struct ServingState: Equatable {
        var autoStartEnabled: Bool
        var serverRunning: Bool
        var externalHost: String?
    }

    private var shouldProtectServingAvailability: Bool {
        servingState.autoStartEnabled || servingState.serverRunning
    }

    init(
        driver: HubServingPowerAssertionDriving = IOKitHubServingPowerAssertionDriver(),
        caffeinateDriver: HubServingCaffeinateDriving = ProcessHubServingCaffeinateDriver(),
        defaults: UserDefaults = .standard
    ) {
        self.driver = driver
        self.caffeinateDriver = caffeinateDriver
        self.defaults = defaults
        self.keepSystemAwakeWhileServing = defaults.object(forKey: Self.keepSystemAwakeKey) as? Bool ?? true
        self.keepDisplayAwakeWhileServing = defaults.object(forKey: Self.keepDisplayAwakeKey) as? Bool ?? false
        self.statusText = HubUIStrings.Settings.GRPC.ServingPower.statusStandby
        self.detailText = HubUIStrings.Settings.GRPC.ServingPower.standbyDetail
        updatePresentation()
    }

    func refreshServingState(autoStartEnabled: Bool, serverRunning: Bool, externalHost: String?) {
        let trimmedHost = externalHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = ServingState(
            autoStartEnabled: autoStartEnabled,
            serverRunning: serverRunning,
            externalHost: trimmedHost?.isEmpty == true ? nil : trimmedHost
        )
        guard servingState != next else {
            updatePresentation()
            return
        }
        servingState = next
        applyAssertionState()
    }

    func shutdown() {
        releaseCaffeinate()
        releaseDisplayAssertion()
        releaseSystemAssertion()
        updatePresentation()
    }

    private func applyAssertionState() {
        lastError = ""

        let wantsSystemAssertion = keepSystemAwakeWhileServing && shouldProtectServingAvailability
        let wantsDisplayAssertion = wantsSystemAssertion && keepDisplayAwakeWhileServing

        if wantsSystemAssertion {
            acquireSystemAssertionIfNeeded()
            applyCaffeinateIfNeeded(displayAwake: keepDisplayAwakeWhileServing)
        } else {
            releaseCaffeinate()
            releaseDisplayAssertion()
            releaseSystemAssertion()
        }

        if wantsDisplayAssertion, systemAssertionID != nil {
            acquireDisplayAssertionIfNeeded()
        } else {
            releaseDisplayAssertion()
        }

        logAssertionSnapshotIfNeeded()
        updatePresentation()
    }

    private func acquireSystemAssertionIfNeeded() {
        guard systemAssertionID == nil else { return }
        let reason = HubUIStrings.Settings.GRPC.ServingPower.systemAssertionReason
        switch driver.acquireSystemIdleSleep(reason: reason) {
        case .success(let id):
            systemAssertionID = id
            HubDiagnostics.log("hub_power.system_assertion acquired id=\(id)")
        case .failure(let error):
            lastError = HubUIStrings.Settings.GRPC.ServingPower.acquireFailed(error.message)
            HubDiagnostics.log("hub_power.system_assertion acquire_failed detail=\(error.message)")
        }
    }

    private func acquireDisplayAssertionIfNeeded() {
        guard displayAssertionID == nil else { return }
        let reason = HubUIStrings.Settings.GRPC.ServingPower.displayAssertionReason
        switch driver.acquireDisplayIdleSleep(reason: reason) {
        case .success(let id):
            displayAssertionID = id
            HubDiagnostics.log("hub_power.display_assertion acquired id=\(id)")
        case .failure(let error):
            lastError = HubUIStrings.Settings.GRPC.ServingPower.acquireFailed(error.message)
            HubDiagnostics.log("hub_power.display_assertion acquire_failed detail=\(error.message)")
        }
    }

    private func applyCaffeinateIfNeeded(displayAwake: Bool) {
        let desiredArguments = Self.caffeinateArguments(displayAwake: displayAwake)
        if caffeinateDriver.runningArguments == desiredArguments {
            return
        }

        if caffeinateDriver.runningArguments != nil {
            releaseCaffeinate()
        }

        switch caffeinateDriver.start(arguments: desiredArguments) {
        case .success:
            HubDiagnostics.log("hub_power.caffeinate acquired args=\(Self.caffeinateSignature(arguments: desiredArguments))")
        case .failure(let error):
            if systemAssertionID == nil {
                lastError = HubUIStrings.Settings.GRPC.ServingPower.acquireFailed(error.message)
            }
            HubDiagnostics.log("hub_power.caffeinate acquire_failed detail=\(error.message)")
        }
    }

    private func releaseCaffeinate() {
        guard let runningArguments = caffeinateDriver.runningArguments else { return }
        HubDiagnostics.log("hub_power.caffeinate released args=\(Self.caffeinateSignature(arguments: runningArguments))")
        if let errorText = caffeinateDriver.stop() {
            if systemAssertionID == nil {
                lastError = HubUIStrings.Settings.GRPC.ServingPower.releaseFailed(errorText)
            }
            HubDiagnostics.log("hub_power.caffeinate release_failed detail=\(errorText)")
        }
    }

    private func releaseSystemAssertion() {
        guard let id = systemAssertionID else { return }
        systemAssertionID = nil
        HubDiagnostics.log("hub_power.system_assertion released id=\(id)")
        if let errorText = driver.releaseAssertion(id: id) {
            lastError = HubUIStrings.Settings.GRPC.ServingPower.releaseFailed(errorText)
            HubDiagnostics.log("hub_power.system_assertion release_failed detail=\(errorText)")
        }
    }

    private func releaseDisplayAssertion() {
        guard let id = displayAssertionID else { return }
        displayAssertionID = nil
        HubDiagnostics.log("hub_power.display_assertion released id=\(id)")
        if let errorText = driver.releaseAssertion(id: id) {
            lastError = HubUIStrings.Settings.GRPC.ServingPower.releaseFailed(errorText)
            HubDiagnostics.log("hub_power.display_assertion release_failed detail=\(errorText)")
        }
    }

    private func logAssertionSnapshotIfNeeded() {
        let host = servingState.externalHost ?? ""
        let caffeinateArguments = caffeinateDriver.runningArguments ?? []
        let snapshot = [
            "auto_start=\(servingState.autoStartEnabled ? 1 : 0)",
            "server_running=\(servingState.serverRunning ? 1 : 0)",
            "keep_system_awake=\(keepSystemAwakeWhileServing ? 1 : 0)",
            "keep_display_awake=\(keepDisplayAwakeWhileServing ? 1 : 0)",
            "protect_availability=\(shouldProtectServingAvailability ? 1 : 0)",
            "system_assertion=\(systemAssertionID != nil ? 1 : 0)",
            "display_assertion=\(displayAssertionID != nil ? 1 : 0)",
            "caffeinate=\(caffeinateArguments.isEmpty ? 0 : 1)",
            "caffeinate_args=\(caffeinateArguments.isEmpty ? "-" : Self.caffeinateSignature(arguments: caffeinateArguments))",
            "host=\(host.isEmpty ? "-" : host)"
        ].joined(separator: " ")

        guard snapshot != lastLoggedAssertionSnapshot else { return }
        lastLoggedAssertionSnapshot = snapshot
        HubDiagnostics.log("hub_power.state \(snapshot)")
    }

    private func updatePresentation() {
        if !keepSystemAwakeWhileServing {
            statusText = HubUIStrings.Settings.GRPC.ServingPower.statusDisabled
            detailText = HubUIStrings.Settings.GRPC.ServingPower.disabledDetail
            return
        }

        guard shouldProtectServingAvailability else {
            statusText = HubUIStrings.Settings.GRPC.ServingPower.statusStandby
            detailText = HubUIStrings.Settings.GRPC.ServingPower.standbyDetail
            return
        }

        if keepDisplayAwakeWhileServing {
            statusText = HubUIStrings.Settings.GRPC.ServingPower.statusSystemAndDisplay
        } else {
            statusText = HubUIStrings.Settings.GRPC.ServingPower.statusSystemOnly
        }
        detailText = HubUIStrings.Settings.GRPC.ServingPower.activeDetail(
            running: servingState.serverRunning,
            externalHost: servingState.externalHost,
            displayAwake: keepDisplayAwakeWhileServing
        )
    }

    private static func caffeinateArguments(displayAwake: Bool) -> [String] {
        var arguments = ["-i", "-m", "-s"]
        if displayAwake {
            arguments.insert("-d", at: 0)
        }
        return arguments
    }

    private static func caffeinateSignature(arguments: [String]) -> String {
        let flags = arguments.map { arg in
            arg.replacingOccurrences(of: "-", with: "")
        }.joined()
        return flags.isEmpty ? "-" : flags
    }
}
