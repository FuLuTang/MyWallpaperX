import Foundation

extension SteamWorkshopService {
    func isWebAnalysisCacheManifestValid(
        _ manifest: SteamWorkshopWebAnalysisCacheManifest,
        for record: SteamWorkshopDownloadRecord
    ) -> Bool {
        if manifest.projectModifiedAt != webRuntimeCacheProjectModifiedAt(for: record) {
            return false
        }
        if manifest.propertySourceRecordID != webPropertyDefinitionSourceRecord(for: record)?.id {
            return false
        }
        if manifest.propertySourceProjectModifiedAt != webRuntimeCachePropertySourceProjectModifiedAt(for: record) {
            return false
        }
        if manifest.resolvedEntryModifiedAt != webRuntimeCacheResolvedEntryModifiedAt(for: record) {
            return false
        }
        let currentEntryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let cachedEntryPath = manifest.analysis.resolvedEntryPath
        if currentEntryPath != cachedEntryPath {
            return false
        }
        let currentRootPath: String = if let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL {
            effectiveWebRootURL(for: record, entryURL: entryURL).path
        } else {
            ""
        }
        let cachedRootPath = manifest.analysis.effectiveRootPath
        if currentRootPath != cachedRootPath {
            return false
        }
        return true
    }

    func isWebRuntimeCacheManifestValid(
        _ manifest: SteamWorkshopWebRuntimeCacheManifest,
        for record: SteamWorkshopDownloadRecord
    ) -> Bool {
        if manifest.projectModifiedAt != webRuntimeCacheProjectModifiedAt(for: record) {
            return false
        }
        if manifest.propertySourceRecordID != webPropertyDefinitionSourceRecord(for: record)?.id {
            return false
        }
        if manifest.propertySourceProjectModifiedAt != webRuntimeCachePropertySourceProjectModifiedAt(for: record) {
            return false
        }
        if manifest.resolvedEntryModifiedAt != webRuntimeCacheResolvedEntryModifiedAt(for: record) {
            return false
        }
        if manifest.overridesSignature != webRuntimeCacheOverridesSignature(for: record) {
            return false
        }
        let currentEntryPath = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL.path ?? ""
        let cachedEntryPath = manifest.execution.resolvedEntryPath
        if currentEntryPath != cachedEntryPath {
            return false
        }
        let currentRootPath: String = if let entryURL = record.webEntryURL?.resolvingSymlinksInPath().standardizedFileURL {
            effectiveWebRootURL(for: record, entryURL: entryURL).path
        } else {
            ""
        }
        let cachedRootPath = manifest.execution.effectiveRootPath
        if currentRootPath != cachedRootPath {
            return false
        }
        return true
    }
}
