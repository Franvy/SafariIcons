import AppKit

enum SafariProcess {
    static let bundleID = "com.apple.Safari"

    static func restart() async {
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleID {
            app.terminate()
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
    }
}
