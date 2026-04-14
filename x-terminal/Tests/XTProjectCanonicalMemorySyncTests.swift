import Foundation
import Testing
@testable import XTerminal

struct XTProjectCanonicalMemorySyncTests {
    @Test
    func itemsExposeStableProjectCanonicalSections() throws {
        let memory = AXMemory(
            schemaVersion: AXMemory.currentSchemaVersion,
            projectName: "X-Hub System",
            projectRoot: "/tmp/x-hub-system",
            goal: "Make Hub memory the default governed source for X-Terminal.",
            requirements: ["Default to Hub memory", "Allow per-project local-only override"],
            currentState: ["Conversation turns already mirror to Hub project thread"],
            decisions: ["Hub constitution remains the safety boundary"],
            nextSteps: ["Write canonical project memory back to Hub"],
            openQuestions: ["Do we need local IPC writeback parity?"],
            risks: ["Remote sync can fail when Hub pairing is unavailable"],
            recommendations: ["Add remote cache TTL after canonical writeback lands"],
            updatedAt: 1_772_200_000.125
        )

        let items = XTProjectCanonicalMemorySync.items(memory: memory)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        #expect(lookup["xterminal.project.memory.schema_version"] == XTProjectCanonicalMemorySync.schemaVersion)
        #expect(lookup["xterminal.project.memory.project_name"] == "X-Hub System")
        #expect(lookup["xterminal.project.memory.project_root"] == "/tmp/x-hub-system")
        #expect(
            lookup["xterminal.project.memory.updated_at"]
                == formatter.string(from: Date(timeIntervalSince1970: memory.updatedAt))
        )
        #expect(lookup["xterminal.project.memory.goal"] == "Make Hub memory the default governed source for X-Terminal.")
        #expect(
            lookup["xterminal.project.memory.requirements"]
                == "1. Default to Hub memory\n2. Allow per-project local-only override"
        )
        #expect(
            lookup["xterminal.project.memory.next_steps"]
                == "1. Write canonical project memory back to Hub"
        )

        let summary = try #require(lookup["xterminal.project.memory.summary_json"])
        let summaryData = try #require(summary.data(using: .utf8))
        let summaryObject = try #require(
            JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
        )
        #expect(summaryObject["schema_version"] as? String == XTProjectCanonicalMemorySync.schemaVersion)
        #expect(summaryObject["goal"] as? String == memory.goal)
        #expect((summaryObject["next_steps"] as? [String]) == memory.nextSteps)
        #expect((summaryObject["risks"] as? [String]) == memory.risks)
    }

    @Test
    func itemsTrimScalarsAndSkipEmptyOptionalSections() {
        let longRisk = String(repeating: "r", count: 420)
        let memory = AXMemory(
            schemaVersion: AXMemory.currentSchemaVersion,
            projectName: "  Demo  ",
            projectRoot: "/tmp/demo",
            goal: "  Ship governed A-Tiers  ",
            requirements: ["  first requirement  ", ""],
            currentState: [],
            decisions: [],
            nextSteps: [],
            openQuestions: [],
            risks: [longRisk],
            recommendations: [],
            updatedAt: 1
        )

        let items = XTProjectCanonicalMemorySync.items(memory: memory)
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(lookup["xterminal.project.memory.project_name"] == "Demo")
        #expect(lookup["xterminal.project.memory.goal"] == "Ship governed A-Tiers")
        #expect(lookup["xterminal.project.memory.requirements"] == "1. first requirement")
        #expect(lookup["xterminal.project.memory.recommendations"] == nil)

        let risks = lookup["xterminal.project.memory.risks"] ?? ""
        #expect(risks.hasPrefix("1. \(String(repeating: "r", count: 400))"))
        #expect(risks.hasSuffix("..."))
    }

    @Test
    func preferredProjectNameOverridesMemoryProjectNameInScalarAndSummaryJSON() throws {
        let memory = AXMemory(
            schemaVersion: AXMemory.currentSchemaVersion,
            projectName: "project-snapshot-friendly-name",
            projectRoot: "/tmp/project-snapshot-friendly-name",
            goal: "Keep Hub-facing project identity stable.",
            requirements: [],
            currentState: [],
            decisions: [],
            nextSteps: [],
            openQuestions: [],
            risks: [],
            recommendations: [],
            updatedAt: 1_772_200_111.0
        )

        let items = XTProjectCanonicalMemorySync.items(
            memory: memory,
            preferredProjectName: "Supervisor 耳机项目"
        )
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.key, $0.value) })

        #expect(lookup["xterminal.project.memory.project_name"] == "Supervisor 耳机项目")

        let summary = try #require(lookup["xterminal.project.memory.summary_json"])
        let summaryData = try #require(summary.data(using: .utf8))
        let summaryObject = try #require(
            JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
        )
        #expect(summaryObject["project_name"] as? String == "Supervisor 耳机项目")
    }
}
