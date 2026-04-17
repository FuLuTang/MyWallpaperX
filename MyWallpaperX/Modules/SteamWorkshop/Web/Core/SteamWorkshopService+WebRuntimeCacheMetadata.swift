import Foundation

extension SteamWorkshopService {
    func webRuntimeCacheOverridesSignature(for record: SteamWorkshopDownloadRecord) -> Data? {
        let overrides = webPropertyOverrides(for: record)
        guard !overrides.isEmpty else { return nil }
        return try? JSONEncoder().encode(overrides)
    }

    func webRuntimeCacheProjectModifiedAt(for record: SteamWorkshopDownloadRecord) -> Date? {
        guard let projectFileURL = record.projectFileURL else { return nil }
        return (try? projectFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func webRuntimeCachePropertySourceProjectModifiedAt(for record: SteamWorkshopDownloadRecord) -> Date? {
        guard let sourceRecord = webPropertyDefinitionSourceRecord(for: record),
              let projectFileURL = sourceRecord.projectFileURL else { return nil }
        return (try? projectFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func webRuntimeCacheResolvedEntryModifiedAt(for record: SteamWorkshopDownloadRecord) -> Date? {
        guard let entryURL = record.webEntryURL else { return nil }
        return (try? entryURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
