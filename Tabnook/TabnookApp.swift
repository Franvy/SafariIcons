import Sparkle
import SwiftUI

@main
struct TabnookApp: App {
    @State private var store = SiteStore()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        Window("Tabnook", id: "main") {
            ContentView()
                .environment(store)
                .onAppear {
                    store.load()
                    store.loadFavorites()
                    store.startWatching()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuItem(updater: updaterController.updater)
            }

            CommandMenu("Icons") {
                Button("Restart Safari to Apply Changes") {
                    Task { await SafariProcess.restart() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Reset to Default Icons") {
                    store.resetDefaults()
                    Task { await SafariProcess.restart() }
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Button("Inspect Style Codes for Current List") {
                    store.showIconStyleDiagnostics()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("Lock Icons Folder") {
                    store.setImagesLocked(true)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Unlock Icons Folder") {
                    store.setImagesLocked(false)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Divider()

                Button("Reveal Backup Folder in Finder") {
                    store.revealBackupFolder()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }

        Settings {
            BackupSettingsView()
                .environment(store)
        }
    }
}
