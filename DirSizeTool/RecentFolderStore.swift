import Foundation
import Observation

/// A folder the user has picked before and can scan again.
struct RecentFolder: Identifiable, Hashable, Codable {
    /// Security-scoped bookmark; the sandbox only grants access after a restart through it.
    var bookmark: Data
    /// Last known name and path, shown even if the bookmark can't be resolved.
    var name: String
    var path: String

    /// Resolved folder URL, or `nil` if the folder isn't available (deleted, drive not connected).
    var url: URL?

    var isAvailable: Bool { url != nil }

    /// The folder URL, so it can be passed directly to `openWindow`.
    var id: URL { url ?? URL(filePath: path) }

    private enum CodingKeys: String, CodingKey {
        case bookmark, name, path
    }
}

/// The recent folders list, persisted in `UserDefaults` across app launches.
@Observable
final class RecentFolderStore {
    /// Maximum number of folders kept in the list.
    private static let maxCount = 10
    private static let defaultsKey = "recentFolders"

    private(set) var folders: [RecentFolder] = []

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let saved = try? JSONDecoder().decode([RecentFolder].self, from: data) else { return }

        var bookmarkRefreshed = false
        folders = saved.map { folder in
            var folder = folder
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: folder.bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                // Keep the entry so it works again once the folder or drive is back.
                return folder
            }

            // Keep access for the app's lifetime so scan windows can read the folder.
            _ = url.startAccessingSecurityScopedResource()
            folder.url = url
            folder.name = url.lastPathComponent
            folder.path = url.path(percentEncoded: false)

            if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
                folder.bookmark = fresh
                bookmarkRefreshed = true
            }
            return folder
        }

        if bookmarkRefreshed {
            save()
        }
    }

    /// Adds a folder picked by the user to the top of the list and returns its ID.
    @discardableResult
    func add(_ url: URL) -> RecentFolder.ID {
        // Keep access for the app's lifetime so scan windows can read the folder.
        _ = url.startAccessingSecurityScopedResource()

        let path = url.path(percentEncoded: false)
        folders.removeAll { $0.path == path }

        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            let folder = RecentFolder(bookmark: bookmark, name: url.lastPathComponent, path: path, url: url)
            folders.insert(folder, at: 0)
            folders = Array(folders.prefix(Self.maxCount))
            save()
        }
        return url
    }

    /// Moves an existing folder to the top of the list, keeping its bookmark.
    func moveToTop(_ id: RecentFolder.ID) {
        guard let index = folders.firstIndex(where: { $0.id == id }), index > 0 else { return }
        folders.insert(folders.remove(at: index), at: 0)
        save()
    }

    func clear() {
        folders.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
