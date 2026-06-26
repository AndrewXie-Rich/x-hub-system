import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    var networkingSection: some View {
        Section(HubUIStrings.Settings.Networking.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.Networking.bridgeStatus)
                Spacer()
                Text(store.bridge.bridgeStatusText)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Networking.restoreNetwork) {
                    store.bridge.restore(seconds: 30 * 60)
                }
                Button(HubUIStrings.Settings.Networking.refreshStatus) { store.bridge.refresh() }
                Spacer()
            }

            Text(HubUIStrings.Settings.Networking.defaultHint)
                .font(.caption2)
                .foregroundStyle(.secondary)

            DisclosureGroup(HubUIStrings.Settings.Networking.emergencyDisclosure) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(HubUIStrings.Settings.Networking.emergencyHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button(HubUIStrings.Settings.Networking.cutOffGlobal) {
                            store.bridge.disable()
                        }
                        .tint(.red)
                        Button(HubUIStrings.Settings.Networking.restoreGlobal) {
                            store.bridge.restore(seconds: 30 * 60)
                        }
                        Spacer()
                    }
                }
                .padding(.top, 4)
            }

            if store.pendingNetworkRequests.isEmpty {
                Text(HubUIStrings.Settings.Networking.noPendingRequests)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.pendingNetworkRequests) { req in
                    networkRequestCard(req)
                }
            }
        }
    }

    var networkPoliciesSection: some View {
        Section(HubUIStrings.Settings.NetworkPolicies.sectionTitle) {
            HStack {
                Text(HubUIStrings.Settings.NetworkPolicies.policy)
                Spacer()
                Button(HubUIStrings.Settings.NetworkPolicies.add) { showAddNetworkPolicy = true }
            }

            if networkPolicies.isEmpty {
                Text(HubUIStrings.Settings.NetworkPolicies.empty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(networkPolicies) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(HubUIStrings.Settings.NetworkPolicies.policyTitle(appID: p.appId, projectID: p.projectId))
                            .font(.callout.weight(.semibold))
                        Text(HubUIStrings.Settings.NetworkPolicies.summary(mode: policyModeText(p.mode), limit: policyLimitText(p.maxSeconds)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Menu(HubUIStrings.Settings.NetworkPolicies.modeMenu) {
                                Button(HubUIStrings.Settings.NetworkPolicies.manual) { updatePolicy(p, mode: .manual, maxSeconds: nil) }
                                Button(HubUIStrings.Settings.NetworkPolicies.autoApprove) { updatePolicy(p, mode: .autoApprove, maxSeconds: p.maxSeconds) }
                                Button(HubUIStrings.Settings.NetworkPolicies.alwaysAllow) { updatePolicy(p, mode: .alwaysOn, maxSeconds: p.maxSeconds) }
                                Button(HubUIStrings.Settings.NetworkPolicies.alwaysDeny) { updatePolicy(p, mode: .deny, maxSeconds: nil) }
                            }
                            Menu(HubUIStrings.Settings.NetworkPolicies.durationMenu) {
                                Button(HubUIStrings.Settings.NetworkPolicies.noLimit) { updatePolicy(p, mode: nil, maxSeconds: nil) }
                                Button(HubUIStrings.Settings.NetworkPolicies.fifteenMinutes) { updatePolicy(p, mode: nil, maxSeconds: 15 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.thirtyMinutes) { updatePolicy(p, mode: nil, maxSeconds: 30 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.sixtyMinutes) { updatePolicy(p, mode: nil, maxSeconds: 60 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.oneHundredTwentyMinutes) { updatePolicy(p, mode: nil, maxSeconds: 120 * 60) }
                                Button(HubUIStrings.Settings.NetworkPolicies.eightHours) { updatePolicy(p, mode: nil, maxSeconds: 8 * 60 * 60) }
                            }
                            Button(HubUIStrings.Settings.NetworkPolicies.remove) { removePolicy(p) }
                            Spacer()
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    var routingSection: some View {
        Section(HubUIStrings.Settings.Routing.sectionTitle) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.routingTaskTypes, id: \.self) { t in
                    HStack {
                        Text(routingTaskTypeLabel(t))
                            .font(.caption.weight(.medium))
                        Spacer()
                        TextField(HubUIStrings.Settings.Routing.modelIDPlaceholder, text: bindingRoutingModelId(t))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 320)
                    }
                }
                Text(HubUIStrings.Settings.Routing.truthHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var quitSection: some View {
        Section(HubUIStrings.Settings.Quit.sectionTitle) {
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Quit.quitApp) { quitApp() }
                Spacer()
            }
            let ver = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
            let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
            Text(HubUIStrings.Settings.Quit.version(ver, build))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func networkRequestCard(_ req: HubNetworkRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(HubUIStrings.Settings.Networking.requestSource(req.source ?? HubUIStrings.Settings.Networking.unknown))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let path = req.rootPath, !path.isEmpty {
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let reason = req.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(reason)
                    .font(.caption)
            }

            let seconds = req.requestedSeconds ?? 900
            HStack(spacing: 10) {
                Button(HubUIStrings.Settings.Networking.approveFiveMinutes) {
                    store.approveNetworkRequest(req, seconds: 5 * 60)
                }
                Button(HubUIStrings.Settings.Networking.approveThirtyMinutes) {
                    store.approveNetworkRequest(req, seconds: 30 * 60)
                }
                Button(HubUIStrings.Settings.Networking.approveSuggested(max(1, seconds / 60))) {
                    store.approveNetworkRequest(req, seconds: seconds)
                }
                Button(HubUIStrings.Settings.Networking.dismiss) {
                    store.dismissNetworkRequest(req)
                }
                Menu(HubUIStrings.Settings.Networking.policyMenu) {
                    Button(HubUIStrings.Settings.Networking.allowProjectAlways) {
                        store.setNetworkPolicy(for: req, mode: .alwaysOn, maxSeconds: nil)
                        let requested = max(10, req.requestedSeconds ?? 900)
                        let seconds = max(requested, 8 * 60 * 60)
                        store.approveNetworkRequest(req, seconds: seconds)
                    }
                    Button(HubUIStrings.Settings.Networking.autoApproveProject) {
                        let maxSeconds = max(10, req.requestedSeconds ?? 900)
                        store.setNetworkPolicy(for: req, mode: .autoApprove, maxSeconds: maxSeconds)
                        store.approveNetworkRequest(req, seconds: maxSeconds)
                    }
                    Button(HubUIStrings.Settings.Networking.denyProjectAlways) {
                        store.setNetworkPolicy(for: req, mode: .deny, maxSeconds: nil)
                        store.dismissNetworkRequest(req)
                    }
                }
                Spacer()
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
