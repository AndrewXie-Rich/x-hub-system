import Foundation

enum AXChatAttachmentAppInspectionSupport {
    private static let maxDirectoryItems = 18
    private static let maxResourceFiles = 80
    private static let maxStrings = 28
    private static let maxReadBytes = 512_000

    static func macOSAppBundleReport(for attachment: AXChatAttachment) -> String? {
        let appURL = PathGuard.resolve(URL(fileURLWithPath: attachment.path, isDirectory: true))
        guard isMacOSAppBundle(attachment, resolvedURL: appURL) else { return nil }

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: appURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plist = loadPlist(at: infoPlistURL)
        let executableName = plistString("CFBundleExecutable", in: plist)
        let bundleName = firstNonEmpty([
            plistString("CFBundleDisplayName", in: plist),
            plistString("CFBundleName", in: plist),
            appURL.deletingPathExtension().lastPathComponent,
        ])
        let executableItems = shallowDirectoryItems(at: macOSURL, limit: maxDirectoryItems)
        let resourceItems = shallowDirectoryItems(at: resourcesURL, limit: maxDirectoryItems)
        let resourceFiles = resourceFileCandidates(in: resourcesURL, limit: maxResourceFiles)
        let stringSignals = selectedStringSignals(
            plist: plist,
            executableURL: executableName.map { macOSURL.appendingPathComponent($0) },
            resourceFiles: resourceFiles
        )
        let capabilityHints = inferredCapabilityHints(
            bundleName: bundleName,
            plist: plist,
            executableItems: executableItems,
            resourceItems: resourceItems,
            stringSignals: stringSignals
        )

        var lines: [String] = [
            "我按只读方式静态检查了附件 `\(attachment.displayName)`，没有运行这个 app。",
            "",
            "可确认的 macOS app 包信息：",
        ]

        if let bundleName {
            lines.append("- 应用名线索：\(bundleName)")
        }
        if let bundleID = plistString("CFBundleIdentifier", in: plist) {
            lines.append("- Bundle ID：\(bundleID)")
        }
        if let executableName {
            lines.append("- 入口程序：Contents/MacOS/\(executableName)")
        }
        if let packageType = plistString("CFBundlePackageType", in: plist) {
            lines.append("- 包类型：\(packageType)")
        }
        if let isAgent = plistBool("LSUIElement", in: plist) {
            lines.append("- UI 类型：\(isAgent ? "菜单栏/后台 agent 线索（LSUIElement=true）" : "常规前台 app 线索")")
        }
        let usageDescriptions = usageDescriptionLines(in: plist)
        if !usageDescriptions.isEmpty {
            lines.append("- 权限声明：\(usageDescriptions.prefix(4).joined(separator: "；"))")
        }
        let documentTypes = documentTypeLines(in: plist)
        if !documentTypes.isEmpty {
            lines.append("- 文件类型声明：\(documentTypes.prefix(4).joined(separator: "；"))")
        }
        if lines.last == "可确认的 macOS app 包信息：" {
            lines.append("- 未能读取到有效的 Contents/Info.plist。")
        }

        lines.append("")
        lines.append("包结构线索：")
        lines.append("- Contents/MacOS：\(executableItems.isEmpty ? "(empty or unavailable)" : executableItems.joined(separator: ", "))")
        lines.append("- Contents/Resources：\(resourceItems.isEmpty ? "(empty or unavailable)" : resourceItems.joined(separator: ", "))")

        if !stringSignals.isEmpty {
            lines.append("")
            lines.append("资源/字符串线索（节选）：")
            for signal in stringSignals.prefix(maxStrings) {
                lines.append("- \(signal)")
            }
        }

        lines.append("")
        lines.append("基于这些线索可谨慎判断：")
        if capabilityHints.isEmpty {
            lines.append("- 目前只能确认它是一个 macOS `.app` 包；功能需要继续读取资源或运行界面后才能确认。")
        } else {
            for hint in capabilityHints {
                lines.append("- \(hint)")
            }
        }
        lines.append("- 这不是运行后 UI 观测，也不是反编译结果；菜单、按钮、完整工作流只能从 Info.plist、资源文件名和可读字符串做静态推断。")

        return lines.joined(separator: "\n")
    }

    static func isMacOSAppBundle(_ attachment: AXChatAttachment) -> Bool {
        isMacOSAppBundle(
            attachment,
            resolvedURL: PathGuard.resolve(URL(fileURLWithPath: attachment.path, isDirectory: true))
        )
    }

    private static func isMacOSAppBundle(
        _ attachment: AXChatAttachment,
        resolvedURL: URL
    ) -> Bool {
        attachment.kind == .directory && resolvedURL.pathExtension.lowercased() == "app"
    }

    private static func loadPlist(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func plistString(_ key: String, in plist: [String: Any]) -> String? {
        guard let value = plist[key] else { return nil }
        if let string = value as? String {
            return nonEmpty(string)
        }
        if let number = value as? NSNumber {
            return nonEmpty(number.stringValue)
        }
        return nil
    }

    private static func plistBool(_ key: String, in plist: [String: Any]) -> Bool? {
        if let bool = plist[key] as? Bool {
            return bool
        }
        if let number = plist[key] as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let normalized = nonEmpty(value) {
                return normalized
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shallowDirectoryItems(at url: URL, limit: Int) -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(limit)
            .map { item in
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let suffix = values?.isDirectory == true ? "/" : ""
                return item.lastPathComponent + suffix
            }
    }

    private static func resourceFileCandidates(in root: URL, limit: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if shouldSkipDirectory(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            files.append(url)
            if files.count >= limit {
                break
            }
        }
        return files
    }

    private static func shouldSkipDirectory(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "_codesignature" || lowered == "__macosx" || lowered == "frameworks"
    }

    private static func selectedStringSignals(
        plist: [String: Any],
        executableURL: URL?,
        resourceFiles: [URL]
    ) -> [String] {
        var candidates: [String] = []
        candidates.append(contentsOf: plist.values.compactMap { value in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        })

        if let executableURL {
            candidates.append(contentsOf: extractStrings(from: executableURL, maxBytes: maxReadBytes))
        }

        for file in prioritizedResourceFiles(resourceFiles) {
            candidates.append(contentsOf: extractStrings(from: file, maxBytes: maxReadBytes))
            if candidates.count >= maxStrings * 4 {
                break
            }
        }

        let unique = orderedUnique(candidates.compactMap(cleanStringSignal))
        let interesting = unique.filter(isInterestingStringSignal)
        return orderedUnique(interesting + unique).prefix(maxStrings).map { $0 }
    }

    private static func prioritizedResourceFiles(_ files: [URL]) -> [URL] {
        let priorityExtensions: Set<String> = [
            "strings", "txt", "json", "plist", "xml", "html", "htm", "js", "py", "tcl", "tk", "ini", "cfg", "yaml", "yml", "csv"
        ]
        return files.sorted { lhs, rhs in
            let lhsPriority = priorityExtensions.contains(lhs.pathExtension.lowercased())
            let rhsPriority = priorityExtensions.contains(rhs.pathExtension.lowercased())
            if lhsPriority != rhsPriority { return lhsPriority }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }

    private static func extractStrings(from url: URL, maxBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else { return [] }

        var strings: [String] = []
        if let text = String(data: data, encoding: .utf8) {
            strings.append(contentsOf: text.components(separatedBy: .newlines))
        }
        strings.append(contentsOf: printableASCIIRuns(in: data))
        return strings
    }

    private static func printableASCIIRuns(in data: Data) -> [String] {
        var runs: [String] = []
        var scalars: [UnicodeScalar] = []

        func flush() {
            guard scalars.count >= 4 else {
                scalars.removeAll(keepingCapacity: true)
                return
            }
            runs.append(String(String.UnicodeScalarView(scalars)))
            scalars.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if byte >= 32 && byte <= 126, let scalar = UnicodeScalar(Int(byte)) {
                scalars.append(scalar)
                if scalars.count > 100 {
                    flush()
                }
            } else {
                flush()
            }
        }
        flush()
        return runs
    }

    private static func cleanStringSignal(_ raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;=,"))
        cleaned = cleaned.replacingOccurrences(of: "\\n", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "\\t", with: " ")
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        guard cleaned.count >= 3, cleaned.count <= 100 else { return nil }
        guard cleaned.unicodeScalars.contains(where: isHumanReadableScalar) else { return nil }
        let lowered = cleaned.lowercased()
        if lowered.hasPrefix("com.apple.") || lowered.hasPrefix("public.") {
            return cleaned
        }
        if lowered.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) {
            return nil
        }
        return cleaned
    }

    private static func isHumanReadableScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.letters.contains(scalar) || scalar.value >= 0x2E80
    }

    private static func isInterestingStringSignal(_ signal: String) -> Bool {
        let lowered = signal.lowercased()
        let keywords = [
            "open", "load", "save", "export", "import", "plot", "chart", "graph", "acoustic", "audio", "sound",
            "frequency", "spectrum", "fft", "db", "csv", "wav", "tkinter", "tk_", "button", "menu", "file",
            "打开", "读取", "导入", "保存", "导出", "绘图", "曲线", "声学", "音频", "频谱", "频率", "按钮", "菜单", "文件"
        ]
        return keywords.contains { lowered.contains($0) }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for value in values {
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(value)
        }
        return ordered
    }

    private static func usageDescriptionLines(in plist: [String: Any]) -> [String] {
        plist.keys
            .filter { $0.hasSuffix("UsageDescription") }
            .sorted()
            .compactMap { key in
                guard let value = plistString(key, in: plist) else { return nil }
                return "\(key)=\(value)"
            }
    }

    private static func documentTypeLines(in plist: [String: Any]) -> [String] {
        guard let types = plist["CFBundleDocumentTypes"] as? [[String: Any]] else { return [] }
        return types.compactMap { type in
            let name = type["CFBundleTypeName"] as? String
            let extensions = type["CFBundleTypeExtensions"] as? [String]
            let contentTypes = type["LSItemContentTypes"] as? [String]
            let joined = (extensions ?? contentTypes ?? []).prefix(4).joined(separator: ",")
            if let name = nonEmpty(name), !joined.isEmpty {
                return "\(name)(\(joined))"
            }
            return nonEmpty(joined)
        }
    }

    private static func inferredCapabilityHints(
        bundleName: String?,
        plist: [String: Any],
        executableItems: [String],
        resourceItems: [String],
        stringSignals: [String]
    ) -> [String] {
        let haystack = (
            [bundleName ?? ""] +
            plist.keys +
            plist.values.compactMap { $0 as? String } +
            executableItems +
            resourceItems +
            stringSignals
        )
        .joined(separator: "\n")
        .lowercased()

        var hints: [String] = []
        if containsAny(haystack, ["tkinter", "tcl", "tk_", " tk", "tk_"]) {
            hints.append("包含 Tk/Tkinter/Tcl 相关线索，界面大概率是轻量桌面 GUI。")
        }
        if containsAny(haystack, ["plot", "graph", "chart", "matplotlib", "绘图", "曲线"]) {
            hints.append("包含 plot/graph/chart/绘图线索，核心能力很可能包括曲线或图表展示。")
        }
        if containsAny(haystack, ["acoustic", "audio", "sound", "frequency", "spectrum", "fft", "db", "声学", "音频", "频谱", "频率"]) {
            hints.append("包含声学、音频、频谱或频率相关线索，处理对象很可能是声学/音频/测量数据。")
        }
        if containsAny(haystack, ["open", "load", "import", "csv", "txt", "wav", "打开", "读取", "导入"]) {
            hints.append("包含 open/load/import 或常见数据格式线索，可能支持导入或读取外部数据文件。")
        }
        if containsAny(haystack, ["save", "export", "png", "pdf", "保存", "导出"]) {
            hints.append("包含 save/export 或图片文档格式线索，可能支持保存或导出图像/结果。")
        }
        if containsAny(haystack, ["button", "menu", "toolbar", "按钮", "菜单"]) {
            hints.append("可读字符串里有按钮/菜单类 UI 线索，可继续按这些字符串梳理具体控件。")
        }
        return orderedUnique(hints)
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
