import Foundation
import Darwin

struct XHubLocalRuntimeHostMetricsSnapshot: Codable, Equatable, Sendable {
    var sampledAtMs: Int64
    var sampleWindowMs: Int?
    var cpuUsagePercent: Double?
    var cpuCoreCount: Int
    var loadAverage1m: Double
    var loadAverage5m: Double
    var loadAverage15m: Double
    var normalizedLoadAverage1m: Double
    var memoryPressure: String
    var memoryUsedBytes: Int64?
    var memoryAvailableBytes: Int64?
    var memoryCompressedBytes: Int64?
    var thermalState: String
    var severity: String
    var summary: String
    var detailLines: [String]

    enum CodingKeys: String, CodingKey {
        case sampledAtMs = "sampled_at_ms"
        case sampleWindowMs = "sample_window_ms"
        case cpuUsagePercent = "cpu_usage_percent"
        case cpuCoreCount = "cpu_core_count"
        case loadAverage1m = "load_average_1m"
        case loadAverage5m = "load_average_5m"
        case loadAverage15m = "load_average_15m"
        case normalizedLoadAverage1m = "normalized_load_average_1m"
        case memoryPressure = "memory_pressure"
        case memoryUsedBytes = "memory_used_bytes"
        case memoryAvailableBytes = "memory_available_bytes"
        case memoryCompressedBytes = "memory_compressed_bytes"
        case thermalState = "thermal_state"
        case severity
        case summary
        case detailLines = "detail_lines"
    }
}

private struct XHubLocalRuntimeHostCPUSample {
    var totalTicks: UInt64
    var idleTicks: UInt64
    var sampledAtMs: Int64
}

private struct XHubLocalRuntimeHostCPUUsageMetrics {
    var usagePercent: Double?
    var sampleWindowMs: Int?
}

private final class XHubLocalRuntimeHostCPUSampleHistory: @unchecked Sendable {
    let lock = NSLock()
    var previous: XHubLocalRuntimeHostCPUSample?
}

private struct XHubLocalRuntimeHostMemoryMetrics {
    var pressure: String
    var usedBytes: Int64?
    var availableBytes: Int64?
    var compressedBytes: Int64?
}

enum XHubLocalRuntimeHostMetricsSampler {
    private static let cpuSampleHistory = XHubLocalRuntimeHostCPUSampleHistory()

    static func capture(
        now: Date = Date(),
        processInfo: ProcessInfo = .processInfo
    ) -> XHubLocalRuntimeHostMetricsSnapshot? {
        let sampledAtMs = Int64(now.timeIntervalSince1970 * 1000.0)
        let cpuCoreCount = max(1, processInfo.activeProcessorCount)
        let loadAverages = currentLoadAverages()
        let normalizedLoadAverage1m = cpuCoreCount > 0
            ? loadAverages.0 / Double(cpuCoreCount)
            : loadAverages.0
        let cpuMetrics = currentCPUUsageMetrics(sampledAtMs: sampledAtMs)
        let memoryMetrics = currentMemoryMetrics(processInfo: processInfo)
        let thermalState = thermalStateLabel(processInfo.thermalState)
        let severity = severityLabel(
            cpuUsagePercent: cpuMetrics.usagePercent,
            normalizedLoadAverage1m: normalizedLoadAverage1m,
            memoryPressure: memoryMetrics.pressure,
            thermalState: thermalState
        )
        let summary = summaryLine(
            severity: severity,
            cpuUsagePercent: cpuMetrics.usagePercent,
            loadAverages: loadAverages,
            normalizedLoadAverage1m: normalizedLoadAverage1m,
            memoryPressure: memoryMetrics.pressure,
            thermalState: thermalState
        )
        let detailLines = detailLines(
            summary: summary,
            cpuCoreCount: cpuCoreCount,
            sampleWindowMs: cpuMetrics.sampleWindowMs,
            usedBytes: memoryMetrics.usedBytes,
            availableBytes: memoryMetrics.availableBytes,
            compressedBytes: memoryMetrics.compressedBytes
        )

        return XHubLocalRuntimeHostMetricsSnapshot(
            sampledAtMs: sampledAtMs,
            sampleWindowMs: cpuMetrics.sampleWindowMs,
            cpuUsagePercent: cpuMetrics.usagePercent,
            cpuCoreCount: cpuCoreCount,
            loadAverage1m: loadAverages.0,
            loadAverage5m: loadAverages.1,
            loadAverage15m: loadAverages.2,
            normalizedLoadAverage1m: normalizedLoadAverage1m,
            memoryPressure: memoryMetrics.pressure,
            memoryUsedBytes: memoryMetrics.usedBytes,
            memoryAvailableBytes: memoryMetrics.availableBytes,
            memoryCompressedBytes: memoryMetrics.compressedBytes,
            thermalState: thermalState,
            severity: severity,
            summary: summary,
            detailLines: detailLines
        )
    }

    private static func currentLoadAverages() -> (Double, Double, Double) {
        var samples = [Double](repeating: 0, count: 3)
        let result = samples.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        guard result > 0 else { return (0, 0, 0) }
        let one = result >= 1 ? samples[0] : 0
        let five = result >= 2 ? samples[1] : 0
        let fifteen = result >= 3 ? samples[2] : 0
        return (one, five, fifteen)
    }

    private static func currentCPUUsageMetrics(sampledAtMs: Int64) -> XHubLocalRuntimeHostCPUUsageMetrics {
        guard let current = currentCPUSample(sampledAtMs: sampledAtMs) else {
            return XHubLocalRuntimeHostCPUUsageMetrics(usagePercent: nil, sampleWindowMs: nil)
        }

        cpuSampleHistory.lock.lock()
        let previous = cpuSampleHistory.previous
        cpuSampleHistory.previous = current
        cpuSampleHistory.lock.unlock()

        guard let previous else {
            return XHubLocalRuntimeHostCPUUsageMetrics(usagePercent: nil, sampleWindowMs: nil)
        }

        let totalDelta = current.totalTicks > previous.totalTicks
            ? current.totalTicks - previous.totalTicks
            : 0
        let idleDelta = current.idleTicks > previous.idleTicks
            ? current.idleTicks - previous.idleTicks
            : 0
        let sampleWindowMs = max(1, Int(current.sampledAtMs - previous.sampledAtMs))
        guard totalDelta > 0 else {
            return XHubLocalRuntimeHostCPUUsageMetrics(usagePercent: nil, sampleWindowMs: sampleWindowMs)
        }

        let busyDelta = totalDelta > idleDelta ? totalDelta - idleDelta : 0
        let usagePercent = min(100.0, max(0.0, (Double(busyDelta) / Double(totalDelta)) * 100.0))
        return XHubLocalRuntimeHostCPUUsageMetrics(
            usagePercent: usagePercent,
            sampleWindowMs: sampleWindowMs
        )
    }

    private static func currentCPUSample(sampledAtMs: Int64) -> XHubLocalRuntimeHostCPUSample? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard kr == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let byteCount = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            let address = vm_address_t(UInt(bitPattern: cpuInfo))
            _ = vm_deallocate(mach_task_self_, address, byteCount)
        }

        let buffer = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        var totalTicks: UInt64 = 0
        var idleTicks: UInt64 = 0
        for cpuIndex in 0 ..< max(0, Int(cpuCount)) {
            let offset = cpuIndex * Int(CPU_STATE_MAX)
            guard offset + Int(CPU_STATE_IDLE) < buffer.count else { break }
            let user = max(0, Int64(buffer[offset + Int(CPU_STATE_USER)]))
            let system = max(0, Int64(buffer[offset + Int(CPU_STATE_SYSTEM)]))
            let idle = max(0, Int64(buffer[offset + Int(CPU_STATE_IDLE)]))
            let nice = max(0, Int64(buffer[offset + Int(CPU_STATE_NICE)]))
            totalTicks += UInt64(user + system + idle + nice)
            idleTicks += UInt64(idle)
        }

        guard totalTicks > 0 else { return nil }
        return XHubLocalRuntimeHostCPUSample(
            totalTicks: totalTicks,
            idleTicks: idleTicks,
            sampledAtMs: sampledAtMs
        )
    }

    private static func currentMemoryMetrics(
        processInfo: ProcessInfo
    ) -> XHubLocalRuntimeHostMemoryMetrics {
        var pageSize: vm_size_t = 0
        if host_page_size(mach_host_self(), &pageSize) != KERN_SUCCESS || pageSize == 0 {
            pageSize = 4096
        }

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &vmStats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(
                    mach_host_self(),
                    host_flavor_t(HOST_VM_INFO64),
                    rebound,
                    &count
                )
            }
        }

        guard kr == KERN_SUCCESS else {
            return XHubLocalRuntimeHostMemoryMetrics(
                pressure: "unknown",
                usedBytes: nil,
                availableBytes: nil,
                compressedBytes: nil
            )
        }

        let freePages = UInt64(vmStats.free_count)
        let inactivePages = UInt64(vmStats.inactive_count)
        let speculativePages = UInt64(vmStats.speculative_count)
        let compressedPages = UInt64(vmStats.compressor_page_count)
        let availablePages = freePages + inactivePages + speculativePages
        let availableBytes64 = availablePages * UInt64(pageSize)
        let compressedBytes64 = compressedPages * UInt64(pageSize)
        let physicalMemory = processInfo.physicalMemory
        let usedBytes64 = physicalMemory > availableBytes64
            ? physicalMemory - availableBytes64
            : 0

        let availableRatio = physicalMemory > 0
            ? Double(availableBytes64) / Double(physicalMemory)
            : 0
        let compressedRatio = physicalMemory > 0
            ? Double(compressedBytes64) / Double(physicalMemory)
            : 0

        let pressure: String
        if availableRatio <= 0.03 || compressedRatio >= 0.30 {
            pressure = "critical"
        } else if availableRatio <= 0.08 || compressedRatio >= 0.20 {
            pressure = "high"
        } else if availableRatio <= 0.15 || compressedRatio >= 0.10 {
            pressure = "moderate"
        } else {
            pressure = "normal"
        }

        return XHubLocalRuntimeHostMemoryMetrics(
            pressure: pressure,
            usedBytes: Int64(clamping: usedBytes64),
            availableBytes: Int64(clamping: availableBytes64),
            compressedBytes: Int64(clamping: compressedBytes64)
        )
    }

    private static func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private static func severityLabel(
        cpuUsagePercent: Double?,
        normalizedLoadAverage1m: Double,
        memoryPressure: String,
        thermalState: String
    ) -> String {
        if thermalState == "critical"
            || memoryPressure == "critical"
            || (cpuUsagePercent ?? 0) >= 95
            || normalizedLoadAverage1m >= 1.5 {
            return "critical"
        }
        if thermalState == "serious"
            || memoryPressure == "high"
            || (cpuUsagePercent ?? 0) >= 85
            || normalizedLoadAverage1m >= 1.0 {
            return "high"
        }
        if thermalState == "fair"
            || memoryPressure == "moderate"
            || (cpuUsagePercent ?? 0) >= 70
            || normalizedLoadAverage1m >= 0.75 {
            return "elevated"
        }
        return "normal"
    }

    private static func summaryLine(
        severity: String,
        cpuUsagePercent: Double?,
        loadAverages: (Double, Double, Double),
        normalizedLoadAverage1m: Double,
        memoryPressure: String,
        thermalState: String
    ) -> String {
        let cpuText = cpuUsagePercent.map { String(format: "%.1f", $0) } ?? "unknown"
        return [
            "host_load_severity=\(severity)",
            "cpu_percent=\(cpuText)",
            String(
                format: "load_avg=%.2f/%.2f/%.2f",
                loadAverages.0,
                loadAverages.1,
                loadAverages.2
            ),
            String(format: "normalized_1m=%.2f", normalizedLoadAverage1m),
            "memory_pressure=\(memoryPressure)",
            "thermal_state=\(thermalState)"
        ].joined(separator: " ")
    }

    private static func detailLines(
        summary: String,
        cpuCoreCount: Int,
        sampleWindowMs: Int?,
        usedBytes: Int64?,
        availableBytes: Int64?,
        compressedBytes: Int64?
    ) -> [String] {
        let memoryLine = [
            "host_memory_bytes",
            "used=\(usedBytes.map(String.init) ?? "unknown")",
            "available=\(availableBytes.map(String.init) ?? "unknown")",
            "compressed=\(compressedBytes.map(String.init) ?? "unknown")"
        ].joined(separator: " ")
        let sampleLine = [
            "host_cpu_context",
            "cpu_cores=\(max(1, cpuCoreCount))",
            "sample_window_ms=\(sampleWindowMs.map(String.init) ?? "unknown")"
        ].joined(separator: " ")
        return [summary, memoryLine, sampleLine]
    }
}
