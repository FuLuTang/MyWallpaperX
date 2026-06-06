import Foundation

extension SteamWorkshopService {
    func reloadInstalledItems() {
        let fileManager = FileManager.default
        let root = libraryRootURL
        let directories = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let metadataFiles = (try? fileManager.contentsOfDirectory(
            at: downloadMetadataIndexDirectoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        if directories.isEmpty && metadataFiles.isEmpty {
            downloads = downloads.filter {
                if case .queued = $0.status { return true }
                if case .downloading = $0.status { return true }
                if case .failed = $0.status { return true }
                return false
            }
            return
        }

        var records: [SteamWorkshopDownloadRecord] = []
        var seenIDs = Set<String>()
        for metadataFile in metadataFiles where metadataFile.pathExtension == "json" {
            let itemID = metadataFile.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: metadataFile),
                  let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
                  let record = buildInstalledRecord(
                    from: snapshot,
                    legacyDirectory: snapshot.legacyFolderURL,
                    fallbackProject: nil,
                    fallbackIdentifier: itemID
                  ) else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }
        for directory in directories where directory.hasDirectoryPath {
            guard let record = buildInstalledRecord(at: directory),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }

        let transient = downloads.filter { record in
            switch record.status {
            case .queued, .downloading, .failed:
                return !records.contains(where: { $0.id == record.id })
            case .ready:
                return false
            }
        }

        downloads = (records + transient).sorted { $0.updatedAt > $1.updatedAt }
        preloadWebRuntimeCaches(for: records)
        let nextPrimaryID: String? = {
            if let selectedDownloadID,
               downloads.contains(where: { $0.id == selectedDownloadID }) {
                return selectedDownloadID
            }
            return nil
        }()
        let nextSelectedIDs = selectedDownloadIDs.filter { id in
            downloads.contains(where: { $0.id == id })
        }
        publishDownloadSelectionState(
            primaryID: nextPrimaryID,
            selectedIDs: nextSelectedIDs,
            deferPublishing: true
        )
    }

    func syncDownloadedItemToLibrary(id: String) throws {
        let fileManager = FileManager.default
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        let targetURL = libraryRootURL.appendingPathComponent(id, isDirectory: true)
        appendSteamAuthDebugLog("DOWNLOAD SYNC: source=\(sourceURL.path)")
        appendSteamAuthDebugLog("DOWNLOAD SYNC: target=\(targetURL.path)")
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            appendSteamAuthDebugLog("DOWNLOAD SYNC FAILED: staged source directory missing for id=\(id)")
            throw NSError(domain: "SteamWorkshop", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "SteamCMD 已完成下载，但没有找到下载结果目录。"
            ])
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            appendSteamAuthDebugLog("DOWNLOAD SYNC: removing existing target directory \(targetURL.path)")
            try? fileManager.removeItem(at: targetURL)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            appendSteamAuthDebugLog("DOWNLOAD SYNC FAILED: copyItem error=\(sanitizeSteamOutput(error.localizedDescription))")
            throw error
        }
        persistDownloadMetadataIfPossible(for: id, targetURL: targetURL)
    }

    func persistDownloadMetadataIfPossible(for id: String, targetURL: URL) {
        guard let item = browserItemForDownload(id: id) else { return }
        persistDownloadMetadata(item: item, id: id, targetURL: targetURL)
    }

    func persistDownloadMetadata(item: SteamWorkshopBrowserItem, id: String, targetURL: URL) {
        let existingSnapshot = loadExistingDownloadMetadataSnapshot(at: targetURL)
        let project = Self.loadWorkshopProject(from: targetURL.appendingPathComponent("project.json"))
        try? FileManager.default.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        let sourceVideoURL = resolveVideoURL(in: targetURL, preferredFileName: project?.file)
        let previewRelativePath = resolvePreviewRelativePath(in: targetURL)
        let exportedVideoURL = sourceVideoURL.flatMap {
            exportPrimaryVideoIfPossible(
                for: id,
                title: item.title,
                sourceVideoURL: $0,
                previousExportedVideoURL: existingSnapshot?.exportedVideoURL
            )
        }
        let sourceVideoRelativePath = sourceVideoURL.map { url in
            let basePath = targetURL.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path
            if filePath.hasPrefix(basePath + "/") {
                return String(filePath.dropFirst(basePath.count + 1))
            }
            return url.lastPathComponent
        }
        let snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: Date(),
            item: item,
            sourceVideoRelativePath: sourceVideoRelativePath,
            previewRelativePath: previewRelativePath,
            exportedVideoURL: exportedVideoURL,
            legacyFolderURL: targetURL
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: downloadMetadataFileURL(for: id), options: Data.WritingOptions.atomic)
    }

    func loadExistingDownloadMetadataSnapshot(at directory: URL) -> SteamWorkshopDownloadMetadataSnapshot? {
        let identifier = directory.lastPathComponent
        let indexedURL = downloadMetadataFileURL(for: identifier)
        if let data = try? Data(contentsOf: indexedURL),
           let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) {
            return snapshot
        }
        let legacyURL = Self.legacyDownloadMetadataFileURL(for: directory)
        guard let data = try? Data(contentsOf: legacyURL),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    func stagedDownloadDirectoryContainsContent(id: String) -> Bool {
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceURL.path),
              let items = try? FileManager.default.contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return false
        }
        return !items.isEmpty
    }

    private func resolvePreviewRelativePath(in directory: URL) -> String? {
        let projectURL = directory.appendingPathComponent("project.json")
        let project = Self.loadWorkshopProject(from: projectURL)
        let projectRoot = Self.loadWorkshopProjectRoot(from: projectURL)
        return Self.preferredPreviewRelativePath(
            in: directory,
            project: project,
            projectRoot: projectRoot
        )
    }

    private func exportPrimaryVideoIfPossible(
        for id: String,
        title: String,
        sourceVideoURL: URL,
        previousExportedVideoURL: URL?
    ) -> URL? {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: exportedVideosRootURL, withIntermediateDirectories: true)

        let sanitizedBaseName = sanitizedExportFileName(from: title).isEmpty
            ? "Workshop-\(id)"
            : sanitizedExportFileName(from: title)
        let destinationURL = uniqueExportURL(
            baseName: sanitizedBaseName,
            pathExtension: sourceVideoURL.pathExtension,
            preferredExistingURL: previousExportedVideoURL
        )

        let shouldReplaceExisting = previousExportedVideoURL == destinationURL
            || destinationURL == previousExportedVideoURL
        if let previousExportedVideoURL,
           previousExportedVideoURL != destinationURL,
           fileManager.fileExists(atPath: previousExportedVideoURL.path) {
            try? fileManager.removeItem(at: previousExportedVideoURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path), shouldReplaceExisting {
            try? fileManager.removeItem(at: destinationURL)
        }

        if !fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.copyItem(at: sourceVideoURL, to: destinationURL)
            } catch {
                appendSteamAuthDebugLog("DOWNLOAD EXPORT FAILED: id=\(id), error=\(sanitizeSteamOutput(error.localizedDescription))")
                return previousExportedVideoURL.flatMap { fileManager.fileExists(atPath: $0.path) ? $0 : nil }
            }
        }
        return destinationURL
    }

    private func uniqueExportURL(
        baseName: String,
        pathExtension: String,
        preferredExistingURL: URL?
    ) -> URL {
        let fileManager = FileManager.default
        if let preferredExistingURL,
           preferredExistingURL.deletingLastPathComponent() == exportedVideosRootURL {
            return preferredExistingURL
        }

        let normalizedExtension = pathExtension.isEmpty ? "mp4" : pathExtension
        var index = 0
        while true {
            let candidateName = index == 0
                ? "\(baseName).\(normalizedExtension)"
                : "\(baseName) (\(index)).\(normalizedExtension)"
            let candidateURL = exportedVideosRootURL.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func sanitizedExportFileName(from title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let collapsed = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(120))
    }
}
