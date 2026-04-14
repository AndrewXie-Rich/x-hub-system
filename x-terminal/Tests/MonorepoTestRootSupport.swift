import Foundation

func monorepoTestRepoRoot(filePath: String = #filePath) -> URL {
    let fileURL = URL(fileURLWithPath: filePath)
    var current = fileURL.deletingLastPathComponent()
    let fileManager = FileManager.default

    while true {
        if looksLikeMonorepoRoot(current, fileManager: fileManager) {
            return current
        }

        let parent = current.deletingLastPathComponent()
        if parent.path == current.path {
            break
        }
        current = parent
    }

    return fileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func looksLikeMonorepoRoot(
    _ candidate: URL,
    fileManager: FileManager
) -> Bool {
    let requiredRefs = [
        "X_MEMORY.md",
        "docs/WORKING_INDEX.md",
        "x-terminal/README.md",
    ]

    return requiredRefs.allSatisfy { ref in
        fileManager.fileExists(atPath: candidate.appendingPathComponent(ref).path)
    }
}
