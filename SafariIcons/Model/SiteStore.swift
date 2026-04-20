import Foundation
import AppKit
import Observation
import os

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case needsPermission
    case failed(String)
}

struct TransientError: Identifiable {
    let id = UUID()
    let message: String
}

struct DiagnosticReport: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@Observable
@MainActor
final class SiteStore {
    private(set) var sites: [Site] = []
    private(set) var favoriteBookmarks: [FavoriteBookmark] = []
    private(set) var state: LoadState = .idle
    private(set) var bookmarksError: String?
    private(set) var bookmarksDiagnostics: BookmarksResult?
    private(set) var iconVersion: UUID = UUID()
    var transientError: TransientError?
    var diagnosticReport: DiagnosticReport?

    private var siteByHost: [String: Site] = [:]

    private static let log = Logger(subsystem: "com.safariicons.SafariIcons", category: "SiteStore")

    private let store: IconStore
    private var dbWatcher: DispatchSourceFileSystemObject?
    private var dbWatchedFD: Int32 = -1
    private var bookmarksWatcher: DispatchSourceFileSystemObject?
    private var bookmarksWatchedFD: Int32 = -1
    private var reloadDebounceTask: Task<Void, Never>?
    private var favoritesDebounceTask: Task<Void, Never>?
    private var iconRepairTask: Task<Void, Never>?
    private var diagnosticScopeBookmarks: [FavoriteBookmark] = []
    private var dbWatcherNeedsRestart = false
    private var bookmarksWatcherNeedsRestart = false

    func site(for bookmark: FavoriteBookmark) -> Site {
        let h = bookmark.host.lowercased()
        if let hit = siteByHost[h] { return hit }
        let alternate: String
        if h.hasPrefix("www.") {
            alternate = String(h.dropFirst(4))
        } else {
            alternate = "www." + h
        }
        if let hit = siteByHost[alternate] { return hit }
        Self.log.warning("no cache_settings row for bookmark host=\(bookmark.host, privacy: .public); falling back to glassSmall")
        return Site(host: bookmark.host, rawStyleValue: nil, paths: store.paths)
    }

    private func rebuildSiteIndex() {
        var index: [String: Site] = [:]
        index.reserveCapacity(sites.count)
        for site in sites {
            index[site.host.lowercased()] = site
        }
        siteByHost = index
    }

    init(store: IconStore = IconStore()) {
        self.store = store
    }

    func renameFavorite(_ bookmark: FavoriteBookmark, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != bookmark.title else { return }
        do {
            try BookmarksWriter.renameFavorite(bookmark, newTitle: trimmed, paths: store.paths)
            loadFavorites()
        } catch {
            reportTransient(error, context: "Rename favorite")
        }
    }

    func load() {
        if dbWatcherNeedsRestart {
            dbWatcherNeedsRestart = !restartDBWatcher()
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: store.paths.db.path) else {
            state = .needsPermission
            return
        }
        guard fm.isReadableFile(atPath: store.paths.db.path) else {
            state = .needsPermission
            return
        }

        if state != .loaded {
            state = .loading
        }
        do {
            sites = try store.listSites()
            rebuildSiteIndex()
            Self.log.info("loaded \(self.sites.count, privacy: .public) sites from cache_settings")
            for site in sites.prefix(10) {
                let rawStyleValue = site.rawStyleValue ?? -1
                Self.log.debug("site host=\(site.host, privacy: .public) rawStyle=\(rawStyleValue, privacy: .public) resolvedStyle=\(site.style.rawValue, privacy: .public)")
            }
            state = .loaded
        } catch {
            state = .failed(userMessage(from: error))
        }
    }

    func loadFavorites() {
        if bookmarksWatcherNeedsRestart {
            bookmarksWatcherNeedsRestart = !restartBookmarksWatcher()
        }

        do {
            let result = try BookmarksReader.loadFavorites(paths: store.paths)
            favoriteBookmarks = result.bookmarks
            bookmarksDiagnostics = result
            bookmarksError = nil
            scheduleFavoriteIconRepair(for: result.bookmarks)
        } catch {
            favoriteBookmarks = []
            bookmarksDiagnostics = nil
            bookmarksError = userMessage(from: error)
            iconRepairTask?.cancel()
            iconRepairTask = nil
        }
    }

    func requestAccess() {
        let panel = NSOpenPanel()
        panel.title = "Authorize Access to Safari Data"
        panel.message = "SafariIcons needs to read Bookmarks.plist (your favorites) and Touch Icons Cache (icons) inside ~/Library/Safari/. Select the Safari folder below and click Authorize."
        panel.prompt = "Authorize"
        panel.directoryURL = store.paths.safari
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        _ = panel.runModal()
        try? store.lockImages(false)
        load()
        loadFavorites()
        startWatching()
    }

    func startWatching() {
        stopWatching()
        dbWatcherNeedsRestart = false
        bookmarksWatcherNeedsRestart = false
        _ = startDBWatcher()
        _ = startBookmarksWatcher()
    }

    func stopWatching() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = nil
        favoritesDebounceTask?.cancel()
        favoritesDebounceTask = nil
        iconRepairTask?.cancel()
        iconRepairTask = nil
        dbWatcher?.cancel()
        dbWatcher = nil
        dbWatchedFD = -1
        bookmarksWatcher?.cancel()
        bookmarksWatcher = nil
        bookmarksWatchedFD = -1
        dbWatcherNeedsRestart = false
        bookmarksWatcherNeedsRestart = false
    }

    private func scheduleReload() {
        reloadDebounceTask?.cancel()
        reloadDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.load()
        }
    }

    private func scheduleFavoritesReload() {
        favoritesDebounceTask?.cancel()
        favoritesDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.loadFavorites()
        }
    }

    private func startDBWatcher() -> Bool {
        let dbPath = store.paths.db.path
        let fd = open(dbPath, O_EVTONLY)
        guard fd >= 0 else {
            return false
        }

        dbWatchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            self?.handleDBWatcherEvent(event)
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        dbWatcher = source
        return true
    }

    private func startBookmarksWatcher() -> Bool {
        let bookmarksPath = store.paths.safari.appendingPathComponent("Bookmarks.plist").path
        let fd = open(bookmarksPath, O_EVTONLY)
        guard fd >= 0 else {
            return false
        }

        bookmarksWatchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            self?.handleBookmarksWatcherEvent(event)
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        source.resume()
        bookmarksWatcher = source
        return true
    }

    private func restartDBWatcher() -> Bool {
        dbWatcher?.cancel()
        dbWatcher = nil
        dbWatchedFD = -1
        return startDBWatcher()
    }

    private func restartBookmarksWatcher() -> Bool {
        bookmarksWatcher?.cancel()
        bookmarksWatcher = nil
        bookmarksWatchedFD = -1
        return startBookmarksWatcher()
    }

    private func handleDBWatcherEvent(_ event: DispatchSource.FileSystemEvent) {
        if !event.intersection([.rename, .delete]).isEmpty {
            dbWatcherNeedsRestart = true
        }
        scheduleReload()
    }

    private func handleBookmarksWatcherEvent(_ event: DispatchSource.FileSystemEvent) {
        if !event.intersection([.rename, .delete]).isEmpty {
            bookmarksWatcherNeedsRestart = true
        }
        scheduleFavoritesReload()
    }

    private func scheduleFavoriteIconRepair(for bookmarks: [FavoriteBookmark]) {
        iconRepairTask?.cancel()

        let iconURLs = Array(Set(bookmarks.map(\.iconURL)))
        guard !iconURLs.isEmpty else {
            iconRepairTask = nil
            return
        }

        let iconStore = store
        iconRepairTask = Task { [iconStore] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            let repairedAny = await Task.detached(priority: .utility) {
                try? iconStore.repairStoredIconsIfNeeded(at: iconURLs)
            }.value ?? false

            guard !Task.isCancelled, repairedAny else { return }
            iconVersion = UUID()
        }
    }

    func setStyle(_ style: IconStyle, for site: Site) {
        do {
            try store.setStyle(host: site.host, style: style)
            if let idx = sites.firstIndex(where: { $0.host == site.host }) {
                sites[idx].style = style
                siteByHost[site.host.lowercased()] = sites[idx]
            }
        } catch {
            reportTransient(error, context: "Set icon style")
        }
    }

    func acceptDrop(url: URL, for site: Site) {
        do {
            try store.writeIcon(from: url, for: site)
            iconVersion = UUID()
        } catch {
            reportTransient(error, context: "Write icon")
        }
    }

    func acceptDrop(data: Data, for site: Site) {
        do {
            try store.writeIcon(data: data, for: site)
            iconVersion = UUID()
        } catch {
            reportTransient(error, context: "Write icon")
        }
    }

    func resetDefaults() {
        do {
            try store.resetDefaults()
            sites = []
            siteByHost = [:]
            iconVersion = UUID()
        } catch {
            reportTransient(error, context: "Reset default icons")
        }
    }

    func resetIcon(for bookmark: FavoriteBookmark) {
        let site = site(for: bookmark)
        do {
            try store.removeStoredIcon(for: site)
            iconVersion = UUID()
        } catch {
            reportTransient(error, context: "Reset icon")
        }
    }

    func setImagesLocked(_ locked: Bool) {
        do {
            try store.lockImages(locked)
        } catch {
            reportTransient(error, context: locked ? "Lock icons folder" : "Unlock icons folder")
        }
    }

    func updateDiagnosticScope(bookmarks: [FavoriteBookmark]) {
        diagnosticScopeBookmarks = bookmarks
    }

    func showIconStyleDiagnostics() {
        do {
            let bookmarks = diagnosticScopeBookmarks
            let total = bookmarks.count

            guard !bookmarks.isEmpty else {
                diagnosticReport = DiagnosticReport(
                    title: "Icon Style Code Diagnostics",
                    message: "The current list is empty; nothing to diagnose."
                )
                return
            }

            let exactHosts = bookmarks.map { $0.host.lowercased() }
            let alternateHosts = exactHosts.map { host in
                if host.hasPrefix("www.") {
                    return String(host.dropFirst(4))
                }
                return "www." + host
            }
            let rawValueByHost = try store.iconStyleRawValues(for: exactHosts + alternateHosts)

            var counts: [Int?: Int] = [:]
            for host in exactHosts {
                let rawValue = rawValueByHost[host] ?? rawValueByHost[alternateHost(for: host)]
                counts[rawValue, default: 0] += 1
            }

            let sortedKeys = counts.keys.sorted { lhs, rhs in
                switch (lhs, rhs) {
                case let (.some(a), .some(b)):
                    return a < b
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return false
                }
            }

            let lines = sortedKeys.compactMap { rawValue -> String? in
                guard let count = counts[rawValue] else { return nil }
                let rawValueText = rawValue.map(String.init) ?? "missing"
                let meaning: String
                if let rawValue, let style = IconStyle.interpreted(from: rawValue) {
                    meaning = "\(style.debugName) / \(style.localizedLabel)"
                } else if rawValue != nil {
                    meaning = "unknown"
                } else {
                    meaning = "no cache_settings row"
                }
                return "\(rawValueText) -> \(meaning)  \(count) items"
            }

            let unknownCount = counts
                .filter { rawValue, _ in
                    guard let rawValue else { return true }
                    return IconStyle.interpreted(from: rawValue) == nil
                }
                .reduce(0) { $0 + $1.value }

            var message = """
                Scope: Current visible list
                Source: cache_settings.transparency_analysis_result
                Total items: \(total)
                Distinct codes: \(sortedKeys.count)

                \(lines.joined(separator: "\n"))
                """

            if unknownCount > 0 {
                message += "\n\nFound unknown-code records: \(unknownCount)"
            } else {
                message += "\n\nNo unknown codes found in the current database."
            }

            diagnosticReport = DiagnosticReport(
                title: "Icon Style Code Diagnostics",
                message: message
            )
        } catch {
            reportTransient(error, context: "Read icon style code diagnostics")
        }
    }

    private func alternateHost(for host: String) -> String {
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return "www." + host
    }

    private func userMessage(from error: Error) -> String {
        if let localized = error as? LocalizedError, let desc = localized.errorDescription {
            return desc
        }
        return error.localizedDescription
    }

    private func reportTransient(_ error: Error, context: String) {
        let message = "\(context) failed: \(userMessage(from: error))"
        Self.log.error("\(message, privacy: .public)")
        transientError = TransientError(message: message)
    }
}
