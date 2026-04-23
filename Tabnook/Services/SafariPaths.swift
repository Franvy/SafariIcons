import Foundation

struct SafariPaths: Sendable {
    let safari: URL
    let touchIconCache: URL
    let images: URL
    let db: URL

    static let `default` = SafariPaths()

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        safari = library.appendingPathComponent("Safari", isDirectory: true)
        touchIconCache = safari.appendingPathComponent("Touch Icons Cache", isDirectory: true)
        images = touchIconCache.appendingPathComponent("Images", isDirectory: true)
        db = touchIconCache.appendingPathComponent("TouchIconCacheSettings.db")
    }

    func iconURL(forMD5 md5: String) -> URL {
        images.appendingPathComponent("\(md5).png")
    }
}
