import Foundation
import RELFlowHubCore

extension ModelStore {
    func pruneLegacyDemoModels() {
        var cur = ModelStateStorage.load()
        let before = cur.models.count
        cur.models.removeAll { m in
            (m.note ?? "") == "demo" && (m.modelPath == nil || (m.modelPath ?? "").isEmpty)
        }
        if cur.models.count != before {
            cur.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(cur)
            snapshot = cur
        }
    }

    func migrateLegacyHomeModelsIfNeeded() {
        // If we are using a sandbox container base dir, migrate any previously copied
        // ~/RELFlowHub/*.json into the container so the UI can see them.
        let base = SharedPaths.ensureHubDirectory()
        let legacy = SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true)
        if base.path == legacy.path {
            return
        }

        let fm = FileManager.default
        let names = ["models_state.json", "models_catalog.json"]
        for n in names {
            let src = legacy.appendingPathComponent(n)
            let dst = base.appendingPathComponent(n)
            if fm.fileExists(atPath: dst.path) {
                continue
            }
            if !fm.fileExists(atPath: src.path) {
                continue
            }
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
