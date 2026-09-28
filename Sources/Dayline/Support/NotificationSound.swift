import AppKit
import Foundation

@MainActor
enum NotificationSoundPreferences {
    static let enabledKey = "soundNotifications"
    static let bookmarkKey = "customNotificationSoundBookmark"
    static let nameKey = "customNotificationSoundName"

    static var selectedName: String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    static func select(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
    }

    static func useSystemSound() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    static func makeSound() -> NSSound? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return NSSound(named: NSSound.Name("Glass"))
                ?? NSSound(named: NSSound.Name("Ping"))
        }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        if stale, let refreshed = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return NSSound(contentsOf: url, byReference: false)
    }
}
