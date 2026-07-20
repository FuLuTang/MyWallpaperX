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
        let key = webPropertyBookmarkKey(forKey: definition.key, record: record)
        guard let resolvedURL = resolvedWebResourceBinding(
            forKey: definition.key,
            definition: definition,
            rawValue: value,
            record: record,
            usesBookmarks: false
        )?.resolvedURL,
              let bookmark = makeWebPropertyBookmarkData(for: resolvedURL) else {
            defaults.removeObject(forKey: key)
            updateWebPropertySecurityScope(nil, forBookmarkKey: key)
            return
        }
        defaults.set(bookmark, forKey: key)
        updateWebPropertySecurityScope(resolvedURL, forBookmarkKey: key)
    }

    func clearWebPropertyBookmarks(for record: SteamWorkshopDownloadRecord) {
        let prefix = WebPropertyOverrideStore.bookmarkPrefix + record.id + "."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
            updateWebPropertySecurityScope(nil, forBookmarkKey: key)
        }
    }

    func hasWebPropertyBookmark(forKey key: String, record: SteamWorkshopDownloadRecord) -> Bool {
        defaults.data(forKey: webPropertyBookmarkKey(forKey: key, record: record)) != nil
    }

    func resolvedBookmarkedWebPropertyURL(forKey key: String, record: SteamWorkshopDownloadRecord) -> URL? {
        let bookmarkKey = webPropertyBookmarkKey(forKey: key, record: record)
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            updateWebPropertySecurityScope(nil, forBookmarkKey: bookmarkKey)
            return nil
        }

        var isStale = false
        guard let resolvedURL = resolveWebPropertyBookmarkData(bookmarkData, bookmarkDataIsStale: &isStale) else {
            defaults.removeObject(forKey: bookmarkKey)
            updateWebPropertySecurityScope(nil, forBookmarkKey: bookmarkKey)
            return nil
        }
        updateWebPropertySecurityScope(resolvedURL, forBookmarkKey: bookmarkKey)

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            defaults.removeObject(forKey: bookmarkKey)
            updateWebPropertySecurityScope(nil, forBookmarkKey: bookmarkKey)
            return nil
        }

        if isStale, let refreshedBookmark = makeWebPropertyBookmarkData(for: resolvedURL) {
            defaults.set(refreshedBookmark, forKey: bookmarkKey)
        }
        return resolvedURL
    }

    private func webPropertyBookmarkKey(forKey key: String, record: SteamWorkshopDownloadRecord) -> String {
        WebPropertyOverrideStore.bookmarkPrefix + record.id + "." + key
    }

    private func makeWebPropertyBookmarkData(for url: URL) -> Data? {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return bookmark
        }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func resolveWebPropertyBookmarkData(_ data: Data, bookmarkDataIsStale isStale: inout Bool) -> URL? {
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).resolvingSymlinksInPath().standardizedFileURL {
            return url
        }

        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).resolvingSymlinksInPath().standardizedFileURL
    }

    private func updateWebPropertySecurityScope(_ url: URL?, forBookmarkKey key: String) {
        let normalizedURL = url?.resolvingSymlinksInPath().standardizedFileURL
        if let existingURL = activeWebPropertySecurityScopedURLs[key] {
            if existingURL.path == normalizedURL?.path {
                return
            }
            existingURL.stopAccessingSecurityScopedResource()
            activeWebPropertySecurityScopedURLs.removeValue(forKey: key)
        }

        guard let normalizedURL else { return }
        if normalizedURL.startAccessingSecurityScopedResource() {
            activeWebPropertySecurityScopedURLs[key] = normalizedURL
        }
    }
}
