import Foundation
import CryptoKit
import os

struct FavoriteBookmark: Identifiable, Hashable, Sendable {
    let id: String
    let urlString: String
    let host: String
    let title: String
    let md5: String
    let iconURL: URL
}

struct BookmarksResult: Sendable {
    var bookmarks: [FavoriteBookmark]
    var foundBookmarksBar: Bool
    var topLevelChildCount: Int
    var subfolderCount: Int
}

enum BookmarksReaderError: LocalizedError {
    case permissionDenied(path: String, underlying: Error)
    case malformed

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let path, let underlying):
            return "Unable to read \(path) (permission denied). Please authorize access to the ~/Library/Safari/ folder. Underlying error: \(underlying.localizedDescription)"
        case .malformed:
            return "Bookmarks.plist parse failed or structure was unexpected."
        }
    }
}

struct BookmarksReader {
    private static let log = Logger(subsystem: "com.safariicons.SafariIcons", category: "BookmarksReader")

    static func loadFavorites(paths: SafariPaths = .default) throws -> BookmarksResult {
        let url = paths.safari.appendingPathComponent("Bookmarks.plist")

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error("Failed to read Bookmarks.plist: \(error.localizedDescription, privacy: .public)")
            throw BookmarksReaderError.permissionDenied(path: url.path, underlying: error)
        }

        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw BookmarksReaderError.malformed
        }

        guard let root = plist as? [String: Any] else {
            throw BookmarksReaderError.malformed
        }

        guard let bar = findFolder(named: "BookmarksBar", in: root) else {
            log.info("BookmarksBar folder not found in plist")
            return BookmarksResult(bookmarks: [], foundBookmarksBar: false, topLevelChildCount: 0, subfolderCount: 0)
        }

        let children = (bar["Children"] as? [[String: Any]]) ?? []
        var bookmarks: [FavoriteBookmark] = []
        var subfolderCount = 0

        for child in children {
            let type = child["WebBookmarkType"] as? String
            if type == "WebBookmarkTypeList" {
                subfolderCount += 1
                continue
            }
            guard type == "WebBookmarkTypeLeaf",
                  let urlString = child["URLString"] as? String,
                  let parsed = URL(string: urlString),
                  let rawHost = parsed.host, !rawHost.isEmpty
            else { continue }

            let host = rawHost
            let title = extractTitle(from: child) ?? fallbackTitle(for: host)
            let md5 = md5Hex(host)
            let stableID = "\(urlString)#\(bookmarks.count)"
            bookmarks.append(FavoriteBookmark(
                id: stableID,
                urlString: urlString,
                host: host,
                title: title,
                md5: md5,
                iconURL: paths.iconURL(forMD5: md5)
            ))
        }

        log.info("BookmarksBar: topLevelChildren=\(children.count, privacy: .public) leafs=\(bookmarks.count, privacy: .public) subfolders=\(subfolderCount, privacy: .public)")
        if !bookmarks.isEmpty {
            let sample = bookmarks.prefix(5).map { "\($0.title)<\($0.host)>" }.joined(separator: ", ")
            log.info("first 5: \(sample, privacy: .public)")
        }

        return BookmarksResult(
            bookmarks: bookmarks,
            foundBookmarksBar: true,
            topLevelChildCount: children.count,
            subfolderCount: subfolderCount
        )
    }

    private static func findFolder(named name: String, in node: [String: Any]) -> [String: Any]? {
        if (node["Title"] as? String) == name { return node }
        if let children = node["Children"] as? [[String: Any]] {
            for child in children {
                if let found = findFolder(named: name, in: child) { return found }
            }
        }
        return nil
    }

    private static func extractTitle(from node: [String: Any]) -> String? {
        if let uri = node["URIDictionary"] as? [String: Any],
           let title = uri["title"] as? String,
           !title.isEmpty {
            return title
        }
        if let title = node["Title"] as? String, !title.isEmpty {
            return title
        }
        return nil
    }

    private static func fallbackTitle(for host: String) -> String {
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let parts = stripped.split(separator: ".")
        guard parts.count >= 2 else { return stripped }
        return String(parts[parts.count - 2]).capitalized
    }

    private static func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02hhX", $0) }.joined()
    }
}
