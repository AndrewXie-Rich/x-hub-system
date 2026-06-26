import AppKit
import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    func reloadSkillsSnapshots() {
        skillsIndex = HubSkillsStoreStorage.loadSkillsIndex()
        skillsPins = HubSkillsStoreStorage.loadSkillPins()
        skillsSources = HubSkillsStoreStorage.loadSkillSources()
    }

    var skillsSection: some View {
        Section(HubUIStrings.Settings.Skills.sectionTitle) {
            let storeDir = HubSkillsStoreStorage.skillsStoreDir()

            HStack {
                Text(HubUIStrings.Settings.Skills.store)
                Spacer()
                Button(HubUIStrings.Settings.Skills.showInFinder) {
                    try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([storeDir])
                }
                Button(HubUIStrings.Settings.Skills.reload) {
                    reloadSkillsSnapshots()
                }
            }

            Text(storeDir.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack {
                Text(HubUIStrings.Settings.Skills.installedPackages)
                Spacer()
                Text(HubUIStrings.Settings.countBadge(skillsIndex.skills.count))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(HubUIStrings.Settings.Skills.pins)
                Spacer()
                Text(HubUIStrings.Settings.Skills.pinsSummary(
                    memoryCore: skillsPins.memoryCorePins.count,
                    global: skillsPins.globalPins.count,
                    project: skillsPins.projectPins.count
                ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !skillsLastErrorText.isEmpty {
                Text(skillsLastErrorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !skillsLastActionText.isEmpty {
                Text(skillsLastActionText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Skills.storageHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HubUIStrings.Settings.Skills.userIDLabel)
                        .font(.caption.monospaced())
                    Spacer()
                    TextField(HubUIStrings.Settings.Skills.userIDPlaceholder, text: $skillsResolveUserId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 320)
                }

                HStack {
                    Text(HubUIStrings.Settings.Skills.projectIDLabel)
                        .font(.caption.monospaced())
                    Spacer()
                    TextField(HubUIStrings.Settings.Skills.projectIDPlaceholder, text: $skillsResolveProjectId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 320)
                }

                Text(HubUIStrings.Settings.Skills.priorityHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(HubUIStrings.Settings.Skills.resolvedResults) {
                let resolved = HubSkillsStoreStorage.resolvedSkills(
                    index: skillsIndex,
                    pins: skillsPins,
                    userId: skillsResolveUserId,
                    projectId: skillsResolveProjectId
                )

                HStack(spacing: 10) {
                    Button(HubUIStrings.Settings.Skills.copyResolvedResults) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(renderResolvedSkills(resolved), forType: .string)
                    }
                    Button(HubUIStrings.Settings.Skills.openPinsFile) {
                        let url = HubSkillsStoreStorage.skillsPinsURL()
                        let fm = FileManager.default
                        if !fm.fileExists(atPath: url.path) {
                            let empty = HubSkillsStoreStorage.SkillPinsSnapshot(
                                schemaVersion: "skills_pins.v1",
                                updatedAtMs: 0,
                                memoryCorePins: [],
                                globalPins: [],
                                projectPins: []
                            )
                            try? HubSkillsStoreStorage.saveSkillPins(empty)
                        }
                        if fm.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        } else {
                            NSWorkspace.shared.open(url.deletingLastPathComponent())
                        }
                    }
                    Spacer()
                }
                .font(.caption)

                if resolved.isEmpty {
                    Text(HubUIStrings.Settings.Skills.emptyResolvedResults)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resolved) { r in
                        skillResolvedRow(r)
                            .padding(.vertical, 3)
                    }
                }
            }

            DisclosureGroup(HubUIStrings.Settings.Skills.pins) {
                Text(HubUIStrings.Settings.Skills.memoryCorePins)
                    .font(.caption.weight(.semibold))
                if skillsPins.memoryCorePins.isEmpty {
                    Text(HubUIStrings.Settings.Skills.empty)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedPins(skillsPins.memoryCorePins)) { p in
                        skillPinRow(p, scope: .memoryCore)
                            .padding(.vertical, 3)
                    }
                }

                Divider()

                Text(HubUIStrings.Settings.Skills.globalPins)
                    .font(.caption.weight(.semibold))
                let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                let globals = uid.isEmpty ? sortedPins(skillsPins.globalPins) : sortedPins(skillsPins.globalPins.filter { ($0.userId ?? "") == uid })
                if globals.isEmpty {
                    Text(HubUIStrings.Settings.Skills.emptyGlobalPins(needsUserID: uid.isEmpty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(globals) { p in
                        skillPinRow(p, scope: .global)
                            .padding(.vertical, 3)
                    }
                }

                Divider()

                Text(HubUIStrings.Settings.Skills.projectPins)
                    .font(.caption.weight(.semibold))
                let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)
                let projects = (!uid.isEmpty && !pid.isEmpty)
                    ? sortedPins(skillsPins.projectPins.filter { ($0.userId ?? "") == uid && ($0.projectId ?? "") == pid })
                    : sortedPins(skillsPins.projectPins)
                if projects.isEmpty {
                    Text(HubUIStrings.Settings.Skills.emptyProjectPins(needsProjectFilter: uid.isEmpty || pid.isEmpty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { p in
                        skillPinRow(p, scope: .project)
                            .padding(.vertical, 3)
                    }
                }
            }

            DisclosureGroup(HubUIStrings.Settings.Skills.search) {
                TextField(HubUIStrings.Settings.Skills.searchPlaceholder, text: $skillsSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                let results = HubSkillsStoreStorage.searchSkills(index: skillsIndex, sources: skillsSources, query: skillsSearchQuery, limit: 30)
                if results.isEmpty {
                    Text(
                        skillsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? HubUIStrings.Settings.Skills.emptySkills
                            : HubUIStrings.Settings.Skills.noMatchingResults
                    )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { meta in
                        skillMetaRow(meta)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func shortSha(_ sha: String) -> String {
        let s = sha.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count <= 12 { return s }
        return "\(s.prefix(8))…\(s.suffix(4))"
    }

    private func renderResolvedSkills(_ resolved: [HubSkillsStoreStorage.ResolvedSkill]) -> String {
        let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append(HubUIStrings.Settings.Skills.resolvedUserID(uid.isEmpty ? HubUIStrings.Settings.Skills.resolvedEmptyValue : uid))
        lines.append(HubUIStrings.Settings.Skills.resolvedProjectID(pid.isEmpty ? HubUIStrings.Settings.Skills.resolvedEmptyValue : pid))
        lines.append(HubUIStrings.Settings.Skills.resolvedPrecedence)
        lines.append("")

        for r in resolved {
            let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
            let sha = r.pin.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ver = r.meta?.version.trimmingCharacters(in: .whitespacesAndNewlines) ?? HubUIStrings.Settings.Diagnostics.missingField
            let src = r.meta?.sourceId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lines.append(
                HubUIStrings.Settings.Skills.resolvedSkillLine(
                    scopeLabel: r.scope.shortLabel,
                    skillID: sid,
                    version: ver,
                    packageSHA256: sha,
                    sourceID: src
                )
            )
        }

        return HubDiagnosticsBundleExporter.redactTextForSharing(lines.joined(separator: "\n"))
    }

    private func openSkillManifest(packageSha256: String) {
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sha.isEmpty else { return }
        let url = HubSkillsStoreStorage.skillManifestURL(packageSha256: sha)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func revealSkillPackage(packageSha256: String) {
        let sha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !sha.isEmpty else { return }
        let url = HubSkillsStoreStorage.skillPackageURL(packageSha256: sha)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func updateSkillPin(
        scope: HubSkillsStoreStorage.PinScope,
        skillId: String,
        packageSha256: String,
        userIdOverride: String? = nil,
        projectIdOverride: String? = nil
    ) {
        skillsLastActionText = ""
        skillsLastErrorText = ""

        let uid = (userIdOverride ?? skillsResolveUserId).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (projectIdOverride ?? skillsResolveProjectId).trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let userForScope: String? = {
                if scope == .memoryCore { return nil }
                return uid.isEmpty ? nil : uid
            }()
            let projectForScope: String? = {
                if scope != .project { return nil }
                return pid.isEmpty ? nil : pid
            }()

            let res = try HubSkillsStoreStorage.setPin(
                scope: scope,
                userId: userForScope,
                projectId: projectForScope,
                skillId: skillId,
                packageSha256: packageSha256,
                note: nil
            )
            skillsPins = HubSkillsStoreStorage.loadSkillPins()

            let newSha = packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if newSha.isEmpty {
                skillsLastActionText = HubUIStrings.Settings.Skills.pinActionUnpinned(
                    skillID: skillId,
                    scopeLabel: scope.displayLabel
                )
            } else {
                let prev = res.previousSha.trimmingCharacters(in: .whitespacesAndNewlines)
                skillsLastActionText = HubUIStrings.Settings.Skills.pinActionPinned(
                    skillID: skillId,
                    scopeLabel: scope.displayLabel,
                    shortSHA: shortSha(newSha),
                    previousShortSHA: prev.isEmpty ? nil : shortSha(prev)
                )
            }
        } catch {
            skillsLastErrorText = error.localizedDescription
        }
    }

    private func sortedPins(_ pins: [HubSkillsStoreStorage.SkillPin]) -> [HubSkillsStoreStorage.SkillPin] {
        pins.sorted { a, b in
            let am = a.updatedAtMs ?? 0
            let bm = b.updatedAtMs ?? 0
            if am != bm { return am > bm }
            return a.skillId.localizedCaseInsensitiveCompare(b.skillId) == .orderedAscending
        }
    }

    @ViewBuilder
    private func skillResolvedRow(_ r: HubSkillsStoreStorage.ResolvedSkill) -> some View {
        let sid = r.pin.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = r.pin.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ver = (r.meta?.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (r.meta?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = HubUIStrings.Settings.Skills.skillTitle(skillID: sid, version: ver)

        VStack(alignment: .leading, spacing: 2) {
            Text(HubUIStrings.Settings.Skills.scopeAndTitle(scopeLabel: r.scope.displayLabel, title: title))
                .font(.callout.weight(.semibold))
            if !name.isEmpty, name != sid {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if r.meta == nil {
                Text(HubUIStrings.Settings.Skills.packageMissing(shortSha(sha)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                Text(HubUIStrings.Settings.Skills.packageSHA(shortSha(sha)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                if !sha.isEmpty {
                    Button(HubUIStrings.Settings.Skills.openManifest) { openSkillManifest(packageSha256: sha) }
                    Button(HubUIStrings.Settings.Skills.showPackageDirectory) { revealSkillPackage(packageSha256: sha) }
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func skillPinRow(_ p: HubSkillsStoreStorage.SkillPin, scope: HubSkillsStoreStorage.PinScope) -> some View {
        let sid = p.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = p.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uid = (p.userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = (p.projectId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeDetail = [
            uid.isEmpty ? nil : HubUIStrings.Settings.Skills.scopeUserID(uid),
            pid.isEmpty ? nil : HubUIStrings.Settings.Skills.scopeProjectID(pid),
        ]
            .compactMap { $0 }
        let scopeDetailText = HubUIStrings.Formatting.middleDotSeparated(scopeDetail)

        let meta = skillsIndex.skills.first(where: { $0.packageSha256.lowercased() == sha })?.toMeta()
        let ver = (meta?.version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = HubUIStrings.Settings.Skills.skillTitle(skillID: sid, version: ver)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            if !scopeDetailText.isEmpty {
                Text(scopeDetailText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Text(HubUIStrings.Settings.Skills.packageSHA(shortSha(sha)))
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                if !sha.isEmpty {
                    Button(HubUIStrings.Settings.Skills.openManifest) { openSkillManifest(packageSha256: sha) }
                    Button(HubUIStrings.Settings.Skills.showPackageDirectory) { revealSkillPackage(packageSha256: sha) }
                }
                Button(HubUIStrings.Settings.Skills.unpin) {
                    updateSkillPin(scope: scope, skillId: sid, packageSha256: "", userIdOverride: uid, projectIdOverride: pid)
                }
                Spacer()
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func skillMetaRow(_ meta: HubSkillsStoreStorage.SkillMeta) -> some View {
        let sid = meta.skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let ver = meta.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let sha = meta.packageSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let desc = meta.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let caps = meta.capabilitiesRequired
        let capsText = caps.isEmpty ? HubUIStrings.Settings.Skills.empty : caps.joined(separator: ", ")
        let hint = meta.installHint.trimmingCharacters(in: .whitespacesAndNewlines)

        let canPin = !sha.isEmpty
        let uid = skillsResolveUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = skillsResolveProjectId.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(HubUIStrings.Settings.Skills.skillTitle(skillID: sid, version: ver))
                    .font(.callout.weight(.semibold))
                Spacer()
                if sha.isEmpty {
                    Text(HubUIStrings.Settings.Skills.notInstalled)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(shortSha(sha))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if !desc.isEmpty {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(HubUIStrings.Settings.Skills.publisherSourceCapabilities(
                publisherID: meta.publisherId,
                sourceID: meta.sourceId,
                capabilities: capsText
            ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !hint.isEmpty {
                Text(HubUIStrings.Settings.Skills.installHint(hint))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Menu(HubUIStrings.Settings.Skills.pinTo) {
                    Button(HubUIStrings.Settings.Skills.pinMemoryCore) { updateSkillPin(scope: .memoryCore, skillId: sid, packageSha256: sha) }
                        .disabled(!canPin)
                    Button(HubUIStrings.Settings.Skills.pinGlobal) { updateSkillPin(scope: .global, skillId: sid, packageSha256: sha, userIdOverride: uid) }
                        .disabled(!canPin || uid.isEmpty)
                    Button(HubUIStrings.Settings.Skills.pinProject) {
                        updateSkillPin(scope: .project, skillId: sid, packageSha256: sha, userIdOverride: uid, projectIdOverride: pid)
                    }
                    .disabled(!canPin || uid.isEmpty || pid.isEmpty)

                    Divider()

                    Button(HubUIStrings.Settings.Skills.unpinMemoryCore()) { updateSkillPin(scope: .memoryCore, skillId: sid, packageSha256: "") }
                    Button(HubUIStrings.Settings.Skills.unpinGlobal()) { updateSkillPin(scope: .global, skillId: sid, packageSha256: "", userIdOverride: uid) }
                        .disabled(uid.isEmpty)
                    Button(HubUIStrings.Settings.Skills.unpinProject()) {
                        updateSkillPin(scope: .project, skillId: sid, packageSha256: "", userIdOverride: uid, projectIdOverride: pid)
                    }
                    .disabled(uid.isEmpty || pid.isEmpty)
                }

                if !sha.isEmpty {
                    Button(HubUIStrings.Settings.Skills.openManifest) { openSkillManifest(packageSha256: sha) }
                    Button(HubUIStrings.Settings.Skills.showPackageDirectory) { revealSkillPackage(packageSha256: sha) }
                }
                Spacer()
            }
            .font(.caption)
        }
    }
}
