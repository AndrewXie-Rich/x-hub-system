import Foundation
import Testing
@testable import XTerminal

struct GitApplierTests {
    @Test
    func planPatchClassifiesFilesModesAndHunks() {
        let patch = """
        diff --git a/file name.txt b/file name.txt
        index 257cc56..5716ca5 100644
        --- a/file name.txt\t
        +++ b/file name.txt\t
        @@ -1 +1 @@
        -old
        +new
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..e69de29
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1 @@
        +new
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        index e69de29..0000000
        --- a/old.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -old
        diff --git a/old name.txt b/new name.txt
        similarity index 100%
        rename from old name.txt
        rename to new name.txt
        diff --git a/image.bin b/image.bin
        new file mode 100644
        index 0000000..1234567
        GIT binary patch
        literal 0
        HcmV?d00001
        """ + "\n"

        let plan = GitApplier.planPatch(patch)

        #expect(plan.changedFiles == [
            "file name.txt",
            "new.txt",
            "old.txt",
            "old name.txt",
            "new name.txt",
            "image.bin"
        ])
        #expect(plan.addedFiles == ["new.txt", "image.bin"])
        #expect(plan.deletedFiles == ["old.txt"])
        #expect(plan.modifiedFiles == ["file name.txt"])
        #expect(plan.renamedFiles == ["old name.txt -> new name.txt"])
        #expect(plan.binaryFiles == ["image.bin"])
        #expect(plan.hasBinaryPatch)
        #expect(plan.hasFullIndexLines)
        #expect(plan.canUseThreeWay)
        #expect(plan.hunkCount == 3)
    }

    @Test
    func applyPatchSucceedsAfterPrecheckPasses() throws {
        let fixture = ToolExecutorProjectFixture(name: "git-applier-valid-patch")
        defer { fixture.cleanup() }

        try seedGitRepo(at: fixture.root, readme: "old\n")

        let patch = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -old
        +new
        """ + "\n"

        let result = try GitApplier.applyPatch(patch, cwd: fixture.root)

        #expect(result.exit == 0)
        let updated = try String(contentsOf: fixture.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(updated == "new\n")
    }

    @Test
    func applyPatchFailsClosedWhenPrecheckFails() throws {
        let fixture = ToolExecutorProjectFixture(name: "git-applier-invalid-patch")
        defer { fixture.cleanup() }

        try seedGitRepo(at: fixture.root, readme: "old\n")

        let patch = """
        diff --git a/README.md b/README.md
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -missing
        +new
        """ + "\n"

        let result = try GitApplier.applyPatch(patch, cwd: fixture.root)

        #expect(result.exit != 0)
        #expect(result.output.contains("precheck_failed"))
        #expect(result.output.contains("mode=standard"))
        #expect(result.output.contains("changed_files=README.md"))
        let current = try String(contentsOf: fixture.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(current == "old\n")
    }

    @Test
    func checkPatchSupportsThreeWayModeForValidGitDiff() throws {
        let fixture = ToolExecutorProjectFixture(name: "git-applier-three-way-check")
        defer { fixture.cleanup() }

        try seedCommittedGitRepo(at: fixture.root, readme: "old\n")
        let patch = try makeReadmePatch(at: fixture.root, replacement: "new\n")

        let standard = try GitApplier.checkPatch(patch, cwd: fixture.root)
        let threeWay = try GitApplier.checkPatch(patch, cwd: fixture.root, threeWay: true)

        #expect(standard.exit == 0)
        #expect(threeWay.exit == 0)
    }

    @Test
    func applyPatchCanUseThreeWayMode() throws {
        let fixture = ToolExecutorProjectFixture(name: "git-applier-three-way-apply")
        defer { fixture.cleanup() }

        try seedCommittedGitRepo(at: fixture.root, readme: "old\n")
        let patch = try makeReadmePatch(at: fixture.root, replacement: "new\n")

        let result = try GitApplier.applyPatch(patch, cwd: fixture.root, threeWay: true)

        #expect(result.exit == 0)
        let updated = try String(contentsOf: fixture.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(updated == "new\n")
    }

    private func seedGitRepo(at root: URL, readme: String) throws {
        try requireGitSuccess(try runGit(["init", "-q"], cwd: root), "git init")
        try readme.write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func seedCommittedGitRepo(at root: URL, readme: String) throws {
        try seedGitRepo(at: root, readme: readme)
        try requireGitSuccess(try runGit(["config", "user.email", "xt-tests@example.com"], cwd: root), "git config user.email")
        try requireGitSuccess(try runGit(["config", "user.name", "XT Tests"], cwd: root), "git config user.name")
        try requireGitSuccess(try runGit(["add", "README.md"], cwd: root), "git add")
        try requireGitSuccess(try runGit(["commit", "-q", "-m", "base"], cwd: root), "git commit")
    }

    private func makeReadmePatch(at root: URL, replacement: String) throws -> String {
        try replacement.write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let diff = try runGit(["diff", "--", "README.md"], cwd: root)
        try requireGitSuccess(diff, "git diff")
        try requireGitSuccess(try runGit(["checkout", "-q", "--", "README.md"], cwd: root), "git checkout")
        return diff.stdout
    }

    private func runGit(_ args: [String], cwd: URL) throws -> ProcessResult {
        try ProcessCapture.run("/usr/bin/git", args, cwd: cwd)
    }

    private func requireGitSuccess(_ result: ProcessResult, _ operation: String) throws {
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "GitApplierTests",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "\(operation) failed\n\(result.combined)"]
            )
        }
    }
}
