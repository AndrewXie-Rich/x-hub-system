import Foundation

struct GitPatchPlan: Codable, Equatable {
    var schemaVersion: String = "xt.git_patch_plan.v1"
    var changedFiles: [String]
    var addedFiles: [String]
    var deletedFiles: [String]
    var modifiedFiles: [String]
    var renamedFiles: [String]
    var binaryFiles: [String]
    var hasBinaryPatch: Bool
    var hasFullIndexLines: Bool
    var canUseThreeWay: Bool
    var hunkCount: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case changedFiles = "changed_files"
        case addedFiles = "added_files"
        case deletedFiles = "deleted_files"
        case modifiedFiles = "modified_files"
        case renamedFiles = "renamed_files"
        case binaryFiles = "binary_files"
        case hasBinaryPatch = "has_binary_patch"
        case hasFullIndexLines = "has_full_index_lines"
        case canUseThreeWay = "can_use_three_way"
        case hunkCount = "hunk_count"
    }
}

enum GitApplier {
    static func planPatch(_ patch: String) -> GitPatchPlan {
        var changed = OrderedStringSet()
        var added = OrderedStringSet()
        var deleted = OrderedStringSet()
        var renamed = OrderedStringSet()
        var renamedPaths = OrderedStringSet()
        var binary = OrderedStringSet()
        var currentFile = ""
        var renameFrom = ""
        var hasFullIndex = false
        var hunkCount = 0

        for rawLine in patch.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .newlines)
            if line.hasPrefix("diff --git ") {
                let files = parseDiffGitFiles(line)
                currentFile = files.newPath ?? files.oldPath ?? ""
                if let oldPath = files.oldPath {
                    changed.insert(oldPath)
                }
                if let newPath = files.newPath {
                    changed.insert(newPath)
                }
                renameFrom = ""
                continue
            }

            if line.hasPrefix("@@") {
                hunkCount += 1
                continue
            }

            if line.hasPrefix("index ") {
                let rest = String(line.dropFirst("index ".count))
                let firstToken = rest.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                if firstToken.contains("..") {
                    let sides = firstToken.split(separator: ".", omittingEmptySubsequences: true)
                    if sides.count >= 2,
                       sides[0].count >= 7,
                       sides[1].count >= 7 {
                        hasFullIndex = true
                    }
                }
                continue
            }

            if line.hasPrefix("new file mode") {
                if !currentFile.isEmpty {
                    added.insert(currentFile)
                }
                continue
            }

            if line.hasPrefix("deleted file mode") {
                if !currentFile.isEmpty {
                    deleted.insert(currentFile)
                }
                continue
            }

            if line.hasPrefix("rename from ") {
                renameFrom = stripGitPathPrefix(String(line.dropFirst("rename from ".count)))
                continue
            }

            if line.hasPrefix("rename to ") {
                let renameTo = stripGitPathPrefix(String(line.dropFirst("rename to ".count)))
                if !renameFrom.isEmpty || !renameTo.isEmpty {
                    renamed.insert("\(renameFrom) -> \(renameTo)")
                    if !renameFrom.isEmpty {
                        changed.insert(renameFrom)
                        renamedPaths.insert(renameFrom)
                    }
                    if !renameTo.isEmpty {
                        changed.insert(renameTo)
                        renamedPaths.insert(renameTo)
                    }
                    currentFile = renameTo
                }
                continue
            }

            if line == "GIT binary patch" {
                if !currentFile.isEmpty {
                    binary.insert(currentFile)
                }
                continue
            }

            if line.hasPrefix("Binary files ") {
                if !currentFile.isEmpty {
                    binary.insert(currentFile)
                }
                continue
            }

            if line.hasPrefix("--- ") {
                let path = stripPatchFileMarker(String(line.dropFirst(4)))
                if path != "/dev/null" {
                    changed.insert(path)
                }
                continue
            }

            if line.hasPrefix("+++ ") {
                let path = stripPatchFileMarker(String(line.dropFirst(4)))
                if path != "/dev/null" {
                    changed.insert(path)
                    currentFile = path
                }
                continue
            }
        }

        let changedFiles = changed.values
        let addedFiles = added.values
        let deletedFiles = deleted.values
        let renamedFilePaths = Set(renamedPaths.values)
        let modifiedFiles = changedFiles.filter { file in
            !addedFiles.contains(file)
                && !deletedFiles.contains(file)
                && !renamedFilePaths.contains(file)
        }
        return GitPatchPlan(
            changedFiles: changedFiles,
            addedFiles: addedFiles,
            deletedFiles: deletedFiles,
            modifiedFiles: modifiedFiles,
            renamedFiles: renamed.values,
            binaryFiles: binary.values,
            hasBinaryPatch: !binary.values.isEmpty,
            hasFullIndexLines: hasFullIndex,
            canUseThreeWay: hasFullIndex,
            hunkCount: hunkCount
        )
    }

    static func checkPatch(_ patch: String, cwd: URL, threeWay: Bool = false) throws -> (exit: Int32, output: String) {
        var args = ["apply"]
        if threeWay {
            args.append("--3way")
        }
        args.append(contentsOf: ["--check", "-"])
        let res = try ProcessCapture.run(
            "/usr/bin/git",
            args,
            cwd: cwd,
            stdin: patch.data(using: .utf8),
            timeoutSec: 20.0
        )
        return (res.exitCode, res.combined)
    }

    static func applyPatch(_ patch: String, cwd: URL, threeWay: Bool = false) throws -> (exit: Int32, output: String) {
        let plan = planPatch(patch)
        let precheck = try checkPatch(patch, cwd: cwd, threeWay: threeWay)
        if precheck.exit != 0 {
            let detail = precheck.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = [
                "precheck_failed",
                "mode=\(threeWay ? "three_way" : "standard")",
                "changed_files=\(plan.changedFiles.joined(separator: ","))",
                detail
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            return (precheck.exit, output)
        }

        var args = ["apply"]
        if threeWay {
            args.append("--3way")
        }
        args.append("-")
        let res = try ProcessCapture.run(
            "/usr/bin/git",
            args,
            cwd: cwd,
            stdin: patch.data(using: .utf8),
            timeoutSec: 20.0
        )
        return (res.exitCode, res.combined)
    }

    private static func parseDiffGitFiles(_ line: String) -> (oldPath: String?, newPath: String?) {
        let rest = String(line.dropFirst("diff --git ".count))
        if rest.hasPrefix("a/"), let separator = rest.range(of: " b/", options: .backwards) {
            let oldPath = String(rest[..<separator.lowerBound])
            let newPath = String(rest[separator.lowerBound...].dropFirst())
            return (
                stripGitPathPrefix(oldPath),
                stripGitPathPrefix(newPath)
            )
        }

        let parts = parseGitPathTokens(rest)
        guard parts.count == 2 else { return (nil, nil) }
        return (
            stripGitPathPrefix(parts[0]),
            stripGitPathPrefix(parts[1])
        )
    }

    private static func stripPatchFileMarker(_ raw: String) -> String {
        let token = raw
            .trimmingCharacters(in: .newlines)
        let path: String
        if let tab = token.firstIndex(of: "\t") {
            path = String(token[..<tab]).trimmingCharacters(in: .whitespaces)
        } else {
            path = token.trimmingCharacters(in: .whitespaces)
        }
        return stripGitPathPrefix(path)
    }

    private static func parseGitPathTokens(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in raw {
            if isEscaped {
                switch character {
                case "n":
                    current.append("\n")
                case "t":
                    current.append("\t")
                case "\"":
                    current.append("\"")
                case "\\":
                    current.append("\\")
                default:
                    current.append("\\")
                    current.append(character)
                }
                isEscaped = false
                continue
            }

            if isQuoted, character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" {
                isQuoted.toggle()
                continue
            }

            if !isQuoted, character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if isEscaped {
            current.append("\\")
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func stripGitPathPrefix(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("a/") || value.hasPrefix("b/") {
            value = String(value.dropFirst(2))
        }
        return value
    }
}

private struct OrderedStringSet {
    private(set) var values: [String] = []
    private var seen: Set<String> = []

    mutating func insert(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard seen.insert(value).inserted else { return }
        values.append(value)
    }
}
