import Foundation
import Testing
@testable import XTerminal

struct GitApplierTests {
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
        let current = try String(contentsOf: fixture.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(current == "old\n")
    }

    private func seedGitRepo(at root: URL, readme: String) throws {
        let initResult = try ProcessCapture.run(
            "/usr/bin/git",
            ["init", "-q"],
            cwd: root
        )
        #expect(initResult.exitCode == 0)
        try readme.write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
