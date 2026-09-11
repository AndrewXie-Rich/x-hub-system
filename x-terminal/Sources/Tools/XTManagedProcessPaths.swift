import Foundation

struct XTManagedProcessPaths {
    let root: URL

    var managedProcessesDir: URL {
        root.appendingPathComponent(".xterminal/managed_processes", isDirectory: true)
    }

    var managedProcessesLogsDir: URL {
        managedProcessesDir.appendingPathComponent("logs", isDirectory: true)
    }

    var managedProcessesSnapshotURL: URL {
        managedProcessesDir.appendingPathComponent("processes.json")
    }

    func managedProcessLogURL(processId: String) -> URL {
        let base = processId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let safe = base.isEmpty ? UUID().uuidString.lowercased() : base
        return managedProcessesLogsDir.appendingPathComponent("\(safe).log")
    }
}
