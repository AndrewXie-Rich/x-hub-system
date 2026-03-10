import Foundation
@testable import XTerminal

struct ToolExecutorProjectFixture {
    let root: URL

    init(name: String) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

func toolSummaryObject(_ output: String) -> [String: JSONValue]? {
    let parsed = ToolExecutor.parseStructuredToolOutput(output)
    guard case .object(let summary)? = parsed.summary else { return nil }
    return summary
}

func toolBody(_ output: String) -> String {
    ToolExecutor.parseStructuredToolOutput(output).body
}

func jsonString(_ value: JSONValue?) -> String? {
    guard case .string(let text)? = value else { return nil }
    return text
}

func jsonNumber(_ value: JSONValue?) -> Double? {
    guard case .number(let number)? = value else { return nil }
    return number
}

func jsonBool(_ value: JSONValue?) -> Bool? {
    guard case .bool(let flag)? = value else { return nil }
    return flag
}

func jsonObject(_ value: JSONValue?) -> [String: JSONValue]? {
    guard case .object(let object)? = value else { return nil }
    return object
}

func jsonArray(_ value: JSONValue?) -> [JSONValue]? {
    guard case .array(let array)? = value else { return nil }
    return array
}
