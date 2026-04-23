import Foundation
import os

enum BackupPaths {
    static let bookmarkDefaultsKey = "TabnookBackupDirectoryBookmark"
    static let folderName = "Backup"
    static let iconsSubfolder = "Icons"
    static let manifestFilename = "manifest.json"

    private static let log = Logger(subsystem: "com.franvy.Tabnook", category: "BackupPaths")

    static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tabnook", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    static func resolveRootURL() -> (url: URL, isSecurityScoped: Bool) {
        if let bookmarkURL = resolveBookmark() {
            return (bookmarkURL, true)
        }
        return (defaultRootURL(), false)
    }

    static func storeBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
    }

    static func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkDefaultsKey)
    }

    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
            return nil
        }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                if let refreshed = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: bookmarkDefaultsKey)
                }
            }
            return url
        } catch {
            log.error("Failed to resolve backup bookmark: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
