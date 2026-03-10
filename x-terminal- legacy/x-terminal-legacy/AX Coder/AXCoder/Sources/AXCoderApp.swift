import SwiftUI
import AppKit

@main
struct XTerminalApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        
        Window("Supervisor AI", id: "supervisor") {
            SupervisorView()
                .environmentObject(appModel)
        }
        
        Window("Supervisor 设置", id: "supervisor_settings") {
            SupervisorSettingsView()
                .environmentObject(appModel)
        }
        
        Window("AI 模型设置", id: "model_settings") {
            ModelSettingsView()
                .environmentObject(appModel)
        }

        Window("Hub Setup", id: "hub_setup") {
            HubSetupWizardView()
                .environmentObject(appModel)
        }
        
        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Project…") {
                    appModel.openProjectPicker()
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Project") {
                Button("Open .xterminal Folder") {
                    if let ctx = appModel.projectContext {
                        let fm = FileManager.default
                        let target = fm.fileExists(atPath: ctx.xterminalDir.path) ? ctx.xterminalDir : ctx.legacyAxcoderDir
                        NSWorkspace.shared.open(target)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open AX_MEMORY.md") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.memoryMarkdownURL)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open ax_memory.json") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.memoryJSONURL)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open config.json") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.configURL)
                    }
                }
                .disabled(appModel.projectContext == nil)

                Button("Open raw_log.jsonl") {
                    if let ctx = appModel.projectContext {
                        NSWorkspace.shared.open(ctx.rawLogURL)
                    }
                }
                .disabled(appModel.projectContext == nil)
            }

            CommandMenu("Hub") {
                Button(hubCommandTitle) {
                    Task { @MainActor in
                        await appModel.connectToHub(auto: false)
                    }
                }
                .keyboardShortcut("x", modifiers: [.command, .option])

                Divider()

                Button("Open Hub Setup Wizard") {
                    NotificationCenter.default.post(name: .xterminalOpenHubSetupWizard, object: nil)
                }

                Button("One-Click Pairing Setup") {
                    appModel.startHubOneClickSetup()
                }

                Button("Reconnect Remote Link") {
                    appModel.startHubReconnectOnly()
                }
            }
        }
    }

    private var hubCommandTitle: String {
        if appModel.hubConnected {
            return "Hub Connected"
        }
        if appModel.hubRemoteLinking {
            return "Hub Linking..."
        }
        if appModel.hubRemoteConnected {
            switch appModel.hubRemoteRoute {
            case .lan:
                return "Hub Relay (LAN)"
            case .internet:
                return "Hub Relay (Internet)"
            case .internetTunnel:
                return "Hub Relay (Tunnel)"
            case .none:
                return "Hub Relay"
            }
        }
        return "One-Click Connect to Hub"
    }
}
