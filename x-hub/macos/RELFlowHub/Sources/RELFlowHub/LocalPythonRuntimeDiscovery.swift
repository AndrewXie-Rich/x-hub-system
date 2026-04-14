import Foundation
import RELFlowHubCore

enum LocalPythonRuntimeDiscovery {
    static let builtinCandidates: [String] = [
        "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
        "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
    ]

    private static let homeRelativeCandidates: [String] = [
        "venv/bin/python3",
        ".venv/bin/python3",
        ".venv311/bin/python3",
        ".app-build/bin/python3",
        "venv/bin/python",
        ".venv/bin/python",
        ".venv311/bin/python",
        ".app-build/bin/python",
    ]

    private static let projectRelativeCandidates: [String] = [
        ".venv/bin/python3",
        "venv/bin/python3",
        ".venv311/bin/python3",
        ".app-build/bin/python3",
        ".venv/bin/python",
        "venv/bin/python",
        ".venv311/bin/python",
        ".app-build/bin/python",
        ".systemlogchecker/radar_venv/bin/python3",
        ".systemlogchecker/radar_venv/bin/python",
    ]

    private static let childSearchRootNames: [String] = [
        "Documents",
        "Desktop",
        "Downloads",
    ]

    private static let maxProjectSearchDepth = 3
    private static let maxVisitedDirectoriesPerRoot = 48
    private static let maxChildDirectoriesPerDirectory = 32
    private static let lmStudioVendorPathComponents = [".lmstudio", "extensions", "backends", "vendor"]
    private static let lmStudioPreferredAppPrefixes = [
        "app-mlx-generate",
        "app-harmony",
    ]
    private static let hubManagedRuntimeRelativeCandidates = [
        "ai_runtime/python3",
        "ai_runtime/python",
    ]

    static func candidatePaths(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default,
        builtinCandidates: [String] = LocalPythonRuntimeDiscovery.builtinCandidates,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        childSearchRootNames: [String] = LocalPythonRuntimeDiscovery.childSearchRootNames,
        hubBaseDirectories: [URL]? = nil
    ) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []

        func appendPath(_ rawPath: String) {
            let expanded = (rawPath as NSString).expandingTildeInPath
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            guard !normalized.isEmpty else { return }
            guard seen.insert(normalized).inserted else { return }
            guard fileManager.isExecutableFile(atPath: normalized) else { return }
            out.append(normalized)
        }

        hubManagedRuntimeCandidatePaths(
            baseDirectories: hubBaseDirectories ?? SharedPaths.hubDirectoryCandidates(),
            fileManager: fileManager
        ).forEach(appendPath)

        builtinCandidates.forEach(appendPath)

        for variable in ["VIRTUAL_ENV", "CONDA_PREFIX"] {
            let value = (environment[variable] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            appendPath(URL(fileURLWithPath: value, isDirectory: true).appendingPathComponent("bin/python3").path)
            appendPath(URL(fileURLWithPath: value, isDirectory: true).appendingPathComponent("bin/python").path)
        }

        var homeCandidates = [homeDirectory.standardizedFileURL]
        let shouldAddGuessedHome = homeDirectory.path.contains("/Library/Containers/")
            || SharedPaths.sandboxHomeDirectory().path.contains("/Library/Containers/")
        if shouldAddGuessedHome,
           let guessedHome = SharedPaths.guessedRealUserHomeDirectory()?.standardizedFileURL,
           !homeCandidates.contains(guessedHome) {
            homeCandidates.append(guessedHome)
        }

        for home in homeCandidates {
            for relativePath in homeRelativeCandidates {
                appendPath(home.appendingPathComponent(relativePath).path)
            }

            let roots = [home] + childSearchRootNames.map {
                home.appendingPathComponent($0, isDirectory: true)
            }
            for root in roots {
                appendProjectCandidates(in: root, fileManager: fileManager, appendPath: appendPath)
            }

            lmStudioVendorCandidatePaths(homeDirectory: home, fileManager: fileManager).forEach(appendPath)
        }

        return out
    }

    static func hubManagedRuntimeCandidatePaths(
        baseDirectories: [URL] = SharedPaths.hubDirectoryCandidates(),
        fileManager: FileManager = .default
    ) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []

        func appendPath(_ rawPath: String) {
            let expanded = (rawPath as NSString).expandingTildeInPath
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            guard !normalized.isEmpty else { return }
            guard seen.insert(normalized).inserted else { return }
            guard fileManager.isExecutableFile(atPath: normalized) else { return }
            out.append(normalized)
        }

        for baseDirectory in baseDirectories {
            let normalizedBase = baseDirectory.standardizedFileURL
            for relativePath in hubManagedRuntimeRelativeCandidates {
                appendPath(normalizedBase.appendingPathComponent(relativePath).path)
            }
        }
        return out
    }

    static func lmStudioVendorCandidatePaths(
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []

        func appendPath(_ rawPath: String) {
            let expanded = (rawPath as NSString).expandingTildeInPath
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            guard !normalized.isEmpty else { return }
            guard seen.insert(normalized).inserted else { return }
            guard fileManager.isExecutableFile(atPath: normalized) else { return }
            out.append(normalized)
        }

        appendLMStudioVendorCandidates(
            in: homeDirectory.standardizedFileURL,
            fileManager: fileManager,
            appendPath: appendPath
        )
        return out
    }

    static func supplementalPythonPathEntries(
        forPythonPath pythonPath: String,
        homeDirectory: URL = SharedPaths.realHomeDirectory(),
        fileManager: FileManager = .default
    ) -> [String] {
        let normalizedPythonPath = URL(
            fileURLWithPath: (pythonPath as NSString).expandingTildeInPath
        ).standardizedFileURL.path
        guard !normalizedPythonPath.isEmpty else { return [] }

        let vendorRoot = lmStudioVendorRoot(in: homeDirectory)
        let vendorRootPath = vendorRoot.standardizedFileURL.path
        guard normalizedPythonPath.hasPrefix(vendorRootPath + "/") else { return [] }

        let relative = String(normalizedPythonPath.dropFirst(vendorRootPath.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard let familyName = components.first, !familyName.isEmpty else { return [] }

        let familyRoot = vendorRoot.appendingPathComponent(familyName, isDirectory: true)
        guard directoryExists(fileManager, path: familyRoot.path) else { return [] }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: familyRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var out: [String] = []
        var seen: Set<String> = []

        func appendSitePackages(_ url: URL) {
            let normalized = url.standardizedFileURL.path
            guard !normalized.isEmpty else { return }
            guard seen.insert(normalized).inserted else { return }
            guard directoryExists(fileManager, path: normalized) else { return }
            out.append(normalized)
        }

        let sortedEntries = entries.sorted { lhs, rhs in
            let lhsRank = lmStudioAppPriority(lhs.lastPathComponent)
            let rhsRank = lmStudioAppPriority(rhs.lastPathComponent)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        for entry in sortedEntries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let name = entry.lastPathComponent
            guard name.hasPrefix("app-") else { continue }

            appendSitePackages(entry.appendingPathComponent("site-packages", isDirectory: true))

            let libRoot = entry.appendingPathComponent("lib", isDirectory: true)
            guard directoryExists(fileManager, path: libRoot.path),
                  let versionEntries = try? fileManager.contentsOfDirectory(
                    at: libRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }

            for versionEntry in versionEntries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let versionValues = try? versionEntry.resourceValues(forKeys: [.isDirectoryKey])
                guard versionValues?.isDirectory == true else { continue }
                appendSitePackages(versionEntry.appendingPathComponent("site-packages", isDirectory: true))
            }
        }

        return out
    }

    private static func appendProjectCandidates(
        in root: URL,
        fileManager: FileManager,
        appendPath: (String) -> Void
    ) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        var queue: [(directory: URL, depth: Int)] = [(root, 0)]
        var visited: Set<String> = []
        var visitedDirectories = 0

        while !queue.isEmpty, visitedDirectories < maxVisitedDirectoriesPerRoot {
            let current = queue.removeFirst()
            let normalizedDirectory = current.directory.standardizedFileURL.path
            guard visited.insert(normalizedDirectory).inserted else {
                continue
            }

            guard let entries = try? fileManager.contentsOfDirectory(
                at: current.directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }
            visitedDirectories += 1

            var childDirectories: [URL] = []
            for entry in entries.sorted(by: { $0.path < $1.path }) {
                let values = try? entry.resourceValues(forKeys: keys)
                guard values?.isDirectory == true else { continue }
                for relativePath in projectRelativeCandidates {
                    appendPath(entry.appendingPathComponent(relativePath).path)
                }
                if current.depth + 1 < maxProjectSearchDepth {
                    childDirectories.append(entry)
                }
            }

            if current.depth + 1 < maxProjectSearchDepth {
                for child in childDirectories.prefix(maxChildDirectoriesPerDirectory) {
                    queue.append((child, current.depth + 1))
                }
            }
        }
    }

    private static func appendLMStudioVendorCandidates(
        in homeDirectory: URL,
        fileManager: FileManager,
        appendPath: (String) -> Void
    ) {
        let vendorRoot = lmStudioVendorRoot(in: homeDirectory)
        guard directoryExists(fileManager, path: vendorRoot.path),
              let familyEntries = try? fileManager.contentsOfDirectory(
                at: vendorRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return
        }

        for familyEntry in familyEntries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let familyValues = try? familyEntry.resourceValues(forKeys: [.isDirectoryKey])
            guard familyValues?.isDirectory == true else { continue }
            guard let runtimeEntries = try? fileManager.contentsOfDirectory(
                at: familyEntry,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for runtimeEntry in runtimeEntries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let runtimeValues = try? runtimeEntry.resourceValues(forKeys: [.isDirectoryKey])
                guard runtimeValues?.isDirectory == true else { continue }
                appendPath(runtimeEntry.appendingPathComponent("bin/python3").path)
                appendPath(runtimeEntry.appendingPathComponent("bin/python").path)
            }
        }
    }

    private static func lmStudioVendorRoot(in homeDirectory: URL) -> URL {
        lmStudioVendorPathComponents.reduce(homeDirectory.standardizedFileURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    private static func directoryExists(_ fileManager: FileManager, path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func lmStudioAppPriority(_ name: String) -> Int {
        for (index, prefix) in lmStudioPreferredAppPrefixes.enumerated() where name.hasPrefix(prefix) {
            return index
        }
        return lmStudioPreferredAppPrefixes.count
    }
}
