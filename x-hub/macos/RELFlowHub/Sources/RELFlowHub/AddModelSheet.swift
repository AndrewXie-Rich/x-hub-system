import AppKit
import SwiftUI
import RELFlowHubCore

@MainActor
struct AddModelSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var modelPath: String = ""
    @State private var modelId: String = ""
    @State private var modelName: String = ""
    @State private var quant: String = ""
    @State private var ctx: Int = 8192
    @State private var paramsBText: String = ""
    @State private var role: String = "general"
    @State private var extraRolesText: String = ""
    @State private var showAdvanced: Bool = false
    @State private var errorText: String = ""
    @State private var isAdding: Bool = false
    @State private var progressText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Model")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("Select Folder…") {
                        pickFolder()
                    }

                    Text(modelPath.isEmpty ? "No folder selected" : modelPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    TextField("Model ID", text: $modelId)
                    TextField("Name", text: $modelName)
                }

                HStack(spacing: 10) {
                    Text("Detected: \(quantText()) · ctx \(ctx) · \(paramsText())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(showAdvanced ? "Hide Advanced" : "Advanced...") {
                        showAdvanced.toggle()
                    }
                    .buttonStyle(.link)
                }

                if showAdvanced {
                    HStack {
                        TextField("Quant (e.g. int4/bf16)", text: $quant)
                        Stepper("ctx \(ctx)", value: $ctx, in: 512...131072, step: 512)
                    }

                    TextField("ParamsB (e.g. 8.0)", text: $paramsBText)
                }

                HStack(alignment: .top, spacing: 12) {
                    // Use a menu-style picker so it doesn't look like an editable text field.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Role")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Role", selection: $role) {
                            Text("General").tag("general")
                            Text("Translate").tag("translate")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 160, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra Roles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("comma-separated", text: $extraRolesText)
                    }
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isAdding {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressText.isEmpty ? "Working..." : progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    Task { @MainActor in
                        await addModelAsync()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isAdding || modelPath.isEmpty || modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 520)
    }

    private func pickFolder() {
        if isAdding {
            return
        }
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Select"
        if p.runModal() == .OK, let url = p.url {
            modelPath = url.path

            // Best-effort defaults.
            let folder = url.lastPathComponent
            if modelName.isEmpty { modelName = folder }
            if modelId.isEmpty { modelId = sanitizeId(folder) }

            // Auto-detect metadata from config.json and/or filenames.
            detectMetadata(for: url)
        }
    }

    private func detectMetadata(for url: URL) {
        let folder = url.lastPathComponent

        let config = readConfigJSON(dir: url)

        // ctx
        if let c = detectContextLength(config: config), c > 0 {
            ctx = c
        } else {
            ctx = 8192
        }

        // quant
        if quant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quant = detectQuant(folder: folder, config: config)
        }

        // paramsB
        if paramsBText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let pb = detectParamsB(folder: folder, dir: url, quant: quant), pb > 0 {
                paramsBText = String(format: "%.1f", pb)
            }
        }
    }

    private func readConfigJSON(dir: URL) -> [String: Any]? {
        let p = dir.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj as? [String: Any]
    }

    private func detectContextLength(config: [String: Any]?) -> Int? {
        guard let c = config else { return nil }
        let keys = [
            "max_position_embeddings",
            "model_max_length",
            "n_positions",
            "seq_length",
            "max_seq_len",
        ]
        for k in keys {
            if let v = c[k] as? Int { return v }
            if let v = c[k] as? Double { return Int(v) }
            if let v = c[k] as? String, let i = Int(v) { return i }
        }
        return nil
    }

    private func detectQuant(folder: String, config: [String: Any]?) -> String {
        // Config sometimes encodes dtype (bf16/fp16) but not int4.
        if let c = config {
            if let td = c["torch_dtype"] as? String {
                let s = td.lowercased()
                if s.contains("bfloat16") { return "bf16" }
                if s.contains("float16") { return "fp16" }
                if s.contains("float32") { return "fp32" }
            }
        }
        return inferQuant(folder)
    }

    private func detectParamsB(folder: String, dir: URL, quant: String) -> Double? {
        // 1) Folder-name heuristic: "8B", "1.8B", "14b".
        do {
            let s = folder
            let r = try NSRegularExpression(pattern: "(?i)(\\d+(?:\\.\\d+)?)\\s*b")
            if let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let rr = Range(m.range(at: 1), in: s) {
                return Double(String(s[rr]))
            }
        } catch {
            // ignore
        }

        // 2) Size-based heuristic from weights files.
        let bpp: Double
        let q = quant.lowercased()
        if q.contains("int4") || q == "4" {
            bpp = 0.5
        } else if q.contains("int8") || q == "8" {
            bpp = 1.0
        } else if q.contains("bf16") || q.contains("fp16") {
            bpp = 2.0
        } else {
            bpp = 2.0
        }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey]
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return nil
        }
        var total: Int64 = 0
        for u in files {
            let ext = u.pathExtension.lowercased()
            if ext == "safetensors" || (ext == "npz" && u.lastPathComponent == "weights.npz") {
                if let sz = try? u.resourceValues(forKeys: keys).fileSize {
                    total += Int64(sz)
                }
            }
        }
        if total <= 0 { return nil }
        let params = Double(total) / max(0.1, bpp)
        return params / 1_000_000_000.0
    }

    private func inferQuant(_ name: String) -> String {
        let s = name.lowercased()
        if s.contains("int4") || s.contains("4bit") || s.contains("_4") { return "int4" }
        if s.contains("int8") || s.contains("8bit") || s.contains("_8") { return "int8" }
        if s.contains("bf16") { return "bf16" }
        if s.contains("fp16") { return "fp16" }
        return "int4"
    }

    private func quantText() -> String {
        let q = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "(quant unknown)" : q
    }

    private func paramsText() -> String {
        let s = paramsBText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Double(s), v > 0 {
            return String(format: "%.1fB", v)
        }
        return "paramsB unknown"
    }

    private func sanitizeId(_ s: String) -> String {
        let ok = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".map { $0 })
        let low = s.lowercased()
        var out = ""
        for ch in low {
            if ok.contains(ch) {
                out.append(ch)
            } else if ch == " " {
                out.append("_")
            }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }

    private func validateAndBuildEntry() -> ModelCatalogEntry? {
        errorText = ""
        let id = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            errorText = "Model ID is required."
            return nil
        }
        if modelPath.isEmpty {
            errorText = "Please select a model folder."
            return nil
        }
        // MLX-LM expects a HuggingFace-style folder with config.json.
        let cfg = URL(fileURLWithPath: modelPath, isDirectory: true).appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: cfg.path) {
            errorText = "Selected folder is not a valid MLX model folder (missing config.json). Please pick the folder that contains config.json."
            return nil
        }

        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = quant.trimmingCharacters(in: .whitespacesAndNewlines)
        let pb = Double(paramsBText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        var roles: [String] = []
        let baseRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseRole.isEmpty {
            roles.append(baseRole)
        }
        let extra = extraRolesText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        roles.append(contentsOf: extra)
        // De-dup while preserving order.
        var uniq: [String] = []
        var seen: Set<String> = []
        for r in roles {
            if seen.contains(r) { continue }
            seen.insert(r)
            uniq.append(r)
        }
        roles = uniq

        return ModelCatalogEntry(
            id: id,
            name: name.isEmpty ? id : name,
            backend: "mlx",
            quant: q.isEmpty ? "int4" : q,
            contextLength: max(512, ctx),
            paramsB: max(0.0, pb),
            modelPath: modelPath,
            roles: roles,
            note: "catalog"
        )
    }

    private func addModelAsync() async {
        if isAdding { return }
        isAdding = true
        progressText = "Preparing..."
        defer {
            isAdding = false
            progressText = ""
        }

        guard var entry = validateAndBuildEntry() else {
            return
        }

        // Sandbox builds: copy the model folder into Hub-managed storage so the runtime can read it.
        if SharedPaths.isSandboxedProcess() {
            progressText = "Importing model into Hub storage..."
            let base = SharedPaths.ensureHubDirectory()
            let dst = base.appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(entry.id, isDirectory: true)
            let src = URL(fileURLWithPath: entry.modelPath, isDirectory: true)

            var accessed = false
            if src.startAccessingSecurityScopedResource() {
                accessed = true
            }
            defer {
                if accessed {
                    src.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dst.path) {
                        try fm.removeItem(at: dst)
                    }
                    try fm.copyItem(at: src, to: dst)
                }.value
                entry.modelPath = dst.path
                entry.note = "managed_copy"
            } catch {
                errorText = "Model import failed (sandbox).\n\n\(error.localizedDescription)"
                return
            }
        }

        progressText = "Saving..."
        var cat = ModelCatalogStorage.load()
        if let idx = cat.models.firstIndex(where: { $0.id == entry.id }) {
            cat.models[idx] = entry
        } else {
            cat.models.append(entry)
        }
        ModelCatalogStorage.save(cat)
        ModelStore.shared.upsertCatalogModel(entry)

        dismiss()
    }
}
