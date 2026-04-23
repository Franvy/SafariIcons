import SwiftUI
import AppKit

struct BackupSettingsView: View {
    @Environment(SiteStore.self) private var store
    @State private var currentPath: String = ""

    var body: some View {
        Form {
            Section("Backup Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(currentPath.isEmpty ? "Loading…" : currentPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack {
                        Button("Choose Folder…") { chooseFolder() }
                        Button("Reveal in Finder") { store.revealBackupFolder() }
                        Button("Reset to Default") { store.resetBackupRootToDefault() }
                    }
                }

                Text("Custom icons are mirrored here and auto-restored when Safari refreshes its cache. Point this at iCloud Drive / Dropbox to sync across Macs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 520, height: 260)
        .task(id: store.transientInfo?.id) {
            await refreshPath()
        }
        .task {
            await refreshPath()
        }
    }

    private func refreshPath() async {
        let url = await store.currentBackupRootURL()
        currentPath = url.path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Backup Folder"
        panel.message = "Pick a folder to store Tabnook's custom icon backups. iCloud Drive is recommended for multi-Mac sync."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            panel.directoryURL = iCloud
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.setBackupRoot(url, migrateExisting: true)
        }
    }
}
