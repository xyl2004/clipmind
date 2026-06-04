import AppKit
import SwiftUI

@main
struct AgentWalletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appStore: AppStore

    init() {
        AgentWalletDiagnostics.runIfRequested()
        _appStore = StateObject(wrappedValue: AppStore())
    }

    var body: some Scene {
        WindowGroup("AgentWallet", id: "main") {
            ContentView(store: appStore)
                .frame(minWidth: 1080, minHeight: 720)
                .onAppear {
                    appStore.configureGlobalHotKey()
                }
        }
        .commands {
            AgentWalletCommands(store: appStore)
        }

        MenuBarExtra("AgentWallet", systemImage: "wallet.pass") {
            Button("打开 AgentWallet") {
                NSApp.activate(ignoringOtherApps: true)
                appStore.showMainWindow()
            }

            Button("查询剪贴板") {
                appStore.captureClipboard()
                Task {
                    await appStore.runResearch()
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("读取选中文字") {
                appStore.captureSelectedText()
                appStore.showFloatingChatPanel()
            }

            Divider()

            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AgentWalletCommands: Commands {
    @ObservedObject var store: AppStore

    var body: some Commands {
        CommandMenu("AgentWallet") {
            Button("查询剪贴板") {
                store.captureClipboard()
                Task {
                    await store.runResearch()
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("读取选中文字") {
                store.captureSelectedText()
                store.showFloatingChatPanel()
            }

            Button("开始查询") {
                Task {
                    await store.runResearch()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }
}
