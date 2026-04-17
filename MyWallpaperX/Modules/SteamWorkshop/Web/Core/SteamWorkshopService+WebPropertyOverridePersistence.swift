import Foundation

extension SteamWorkshopService {
    private enum WebPropertyOverrideStore {
        static let defaultsPrefix = "SteamWorkshop.webPropertyOverrides."
        static let bookmarkPrefix = "SteamWorkshop.webPropertyBookmarks."
    }

    func webPropertyOverrides(for record: SteamWorkshopDownloadRecord) -> [String: SteamWorkshopWebPropertyValue] {
        guard let data = defaults.data(forKey: WebPropertyOverrideStore.defaultsPrefix + record.id),
              let payload = try? JSONDecoder().decode([String: SteamWorkshopWebPropertyValue].self, from: data) else {
            return [:]
        }
        return payload
    }

    func saveWebPropertyOverrides(_ overrides: [String: SteamWorkshopWebPropertyValue], for record: SteamWorkshopDownloadRecord) {
        let key = WebPropertyOverrideStore.defaultsPrefix + record.id
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: key)
    }

    func updateWebPropertyBookmark(
        for definition: SteamWorkshopWebPropertyDefinition,
        value: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord
    ) {
        guard definition.kind == .file || definition.kind == .directory else { return }
        let key = WebPropertyOverrideStore.bookmarkPrefix + record.id + "." + definition.key
        guard let resolvedURL = resolvedWebRuntimeAssetURL(forKey: definition.key, definition: definition, rawValue: value, record: record),
              let bookmark = try? resolvedURL.bookmarkData() else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(bookmark, forKey: key)
    }

    func clearWebPropertyBookmarks(for record: SteamWorkshopDownloadRecord) {
        let prefix = WebPropertyOverrideStore.bookmarkPrefix + record.id + "."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    func resolvedBookmarkedWebPropertyURL(forKey key: String, record: SteamWorkshopDownloadRecord) -> URL? {
        let bookmarkKey = WebPropertyOverrideStore.bookmarkPrefix + record.id + "." + key
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).resolvingSymlinksInPath().standardizedFileURL else {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }

        if isStale, let refreshedBookmark = try? resolvedURL.bookmarkData() {
            defaults.set(refreshedBookmark, forKey: bookmarkKey)
        }
        return resolvedURL
    }
}
