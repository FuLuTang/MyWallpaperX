import Foundation

extension SteamWorkshopService {
    func reloadInstalledItems() {
        let videoFiles = directVideoFiles(in: videoLibraryRootURL)
        let webDirectories = directChildDirectories(in: webLibraryRootURL)
        let sceneDirectories = directChildDirectories(in: sceneLibraryRootURL)
        if videoFiles.isEmpty && webDirectories.isEmpty && sceneDirectories.isEmpty {
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
        for videoURL in videoFiles {
            let metadata = loadVideoDownloadMetadataSnapshot(for: videoURL)
            guard let record = buildInstalledVideoRecord(videoURL: videoURL, metadata: metadata),
                  seenIDs.contains(record.id) == false else { continue }
            records.append(record)
            seenIDs.insert(record.id)
        }
        for directory in webDirectories + sceneDirectories {
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
#if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--mwx-debug-run-web-workshop-id") {
            preloadWebRuntimeCaches(for: records)
        }
#else
        preloadWebRuntimeCaches(for: records)
#endif
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

    private func directChildDirectories(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter(\.hasDirectoryPath)
    }

    private func directVideoFiles(in root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { url in
            !url.hasDirectoryPath && isSupportedWorkshopVideoFile(url)
        }
    }

    func syncDownloadedItemToLibrary(_ request: SteamWorkshopPendingDownloadRequest) async throws {
        let id = request.id
        let fileManager = FileManager.default
        let sourceURL = stagingWorkshopContentRootURL.appendingPathComponent(id, isDirectory: true)
        appendSteamAuthDebugLog("DOWNLOAD SYNC: source=\(sourceURL.path)")
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            appendSteamAuthDebugLog("DOWNLOAD SYNC FAILED: staged source directory missing for id=\(id)")
            throw NSError(domain: "SteamWorkshop", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "SteamCMD 已完成下载，但没有找到下载结果目录。"
            ])
        }

        let item = await metadataItemForCompletedDownload(request)
        let project = Self.loadWorkshopProject(from: sourceURL.appendingPathComponent("project.json"))
        let sourceVideoURL = resolveVideoURL(in: sourceURL, preferredFileName: project?.file)
        let htmlURL = resolveHTMLURL(in: sourceURL, preferredFileName: project?.file)
        let dependencyID = project?.dependency?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentType = resolveContentType(
            project: project,
            directory: sourceURL,
            videoURL: sourceVideoURL,
            htmlURL: htmlURL,
            dependencyItemID: dependencyID?.isEmpty == false ? dependencyID : nil,
            browserItem: item
        )

        switch contentType {
        case .video:
            guard let sourceVideoURL else {
                throw NSError(domain: "SteamWorkshop", code: 14, userInfo: [
                    NSLocalizedDescriptionKey: "SteamCMD 已完成下载，但没有找到可保存的视频文件。"
                ])
            }
            try persistVideoDownload(
                item: item,
                id: id,
                sourceDirectoryURL: sourceURL,
                sourceVideoURL: sourceVideoURL
            )
        case .scene:
            let targetURL = sceneLibraryRootURL.appendingPathComponent(id, isDirectory: true)
            try copyDownloadedDirectory(from: sourceURL, to: targetURL)
            persistProjectDownloadMetadata(item: item, id: id, targetURL: targetURL)
        case .web, .unknown:
            let targetURL = webLibraryRootURL.appendingPathComponent(id, isDirectory: true)
            try copyDownloadedDirectory(from: sourceURL, to: targetURL)
            persistProjectDownloadMetadata(item: item, id: id, targetURL: targetURL)
        }
    }

    func persistDownloadMetadata(item: SteamWorkshopBrowserItem, id: String, targetURL: URL) {
        if let record = latestDownloadRecord(for: id),
           record.contentType == .video,
           let videoURL = record.exportedVideoURL ?? record.sourceVideoURL {
            persistVideoDownloadMetadata(item: item, videoURL: videoURL)
            return
        }
        persistProjectDownloadMetadata(item: item, id: id, targetURL: targetURL)
    }

    private func persistVideoDownload(
        item: SteamWorkshopBrowserItem?,
        id: String,
        sourceDirectoryURL: URL,
        sourceVideoURL: URL
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: videoLibraryRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)

        let resolvedItem = item ?? browserItemForDownload(id: id)
        let title = resolvedItem?.title ?? Self.loadWorkshopProject(from: sourceDirectoryURL.appendingPathComponent("project.json"))?.title ?? "Workshop-\(id)"
        let existingEntry = loadDownloadMetadataEntry(forItemID: id)
        let destinationURL = uniqueExportURL(
            baseName: sanitizedExportFileName(from: title).isEmpty ? "Workshop" : sanitizedExportFileName(from: title),
            pathExtension: sourceVideoURL.pathExtension,
            preferredExistingURL: existingEntry?.snapshot.exportedVideoURL
        )
        appendSteamAuthDebugLog("DOWNLOAD SYNC VIDEO: target=\(destinationURL.path)")

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        do {
            try fileManager.copyItem(at: sourceVideoURL, to: destinationURL)
        } catch {
            appendSteamAuthDebugLog("DOWNLOAD SYNC VIDEO FAILED: copyItem error=\(sanitizeSteamOutput(error.localizedDescription))")
            throw error
        }

        guard let metadataItem = resolvedItem else {
            return
        }
        let snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: Date(),
            item: metadataItem,
            sourceVideoRelativePath: nil,
            previewRelativePath: nil,
            exportedVideoURL: destinationURL,
            legacyFolderURL: nil
        )
        let metadataURL = downloadMetadataFileURL(forVideoURL: destinationURL)
        writeDownloadMetadataSnapshot(snapshot, to: metadataURL)
        if let existingURL = existingEntry?.url, existingURL != metadataURL {
            try? fileManager.removeItem(at: existingURL)
        }
    }

    private func persistVideoDownloadMetadata(item: SteamWorkshopBrowserItem, videoURL: URL) {
        try? FileManager.default.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        let snapshot = SteamWorkshopDownloadMetadataSnapshot(
            fetchedAt: Date(),
            item: item,
            sourceVideoRelativePath: nil,
            previewRelativePath: nil,
            exportedVideoURL: videoURL,
            legacyFolderURL: nil
        )
        writeDownloadMetadataSnapshot(snapshot, to: downloadMetadataFileURL(forVideoURL: videoURL))
    }

    private func persistProjectDownloadMetadata(item: SteamWorkshopBrowserItem?, id: String, targetURL: URL) {
        guard let item = item ?? browserItemForDownload(id: id) else { return }
        let project = Self.loadWorkshopProject(from: targetURL.appendingPathComponent("project.json"))
        try? FileManager.default.createDirectory(at: downloadMetadataIndexDirectoryURL(), withIntermediateDirectories: true)
        let sourceVideoURL = resolveVideoURL(in: targetURL, preferredFileName: project?.file)
        let previewRelativePath = resolvePreviewRelativePath(in: targetURL)
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
            exportedVideoURL: nil,
            legacyFolderURL: targetURL
        )
        writeDownloadMetadataSnapshot(snapshot, to: downloadMetadataFileURL(for: id))
    }

    private func copyDownloadedDirectory(from sourceURL: URL, to targetURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        appendSteamAuthDebugLog("DOWNLOAD SYNC DIRECTORY: target=\(targetURL.path)")
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            appendSteamAuthDebugLog("DOWNLOAD SYNC DIRECTORY FAILED: copyItem error=\(sanitizeSteamOutput(error.localizedDescription))")
            throw error
        }
    }

    private func writeDownloadMetadataSnapshot(_ snapshot: SteamWorkshopDownloadMetadataSnapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: Data.WritingOptions.atomic)
    }

    func metadataItemForCompletedDownload(_ request: SteamWorkshopPendingDownloadRequest) async -> SteamWorkshopBrowserItem? {
        if let item = request.item ?? browserItemForDownload(id: request.id),
           !SteamWorkshopDetailRefreshSupport.needsListRefresh(item) {
            return item
        }

        let fallback = request.item ?? browserItemForDownload(id: request.id)
        return await resolveCachedDownloadAuthorMetadata(
            itemID: request.id,
            fallback: fallback,
            title: request.pageTitle
        )
    }

    func loadDownloadMetadataEntry(forItemID itemID: String) -> (url: URL, snapshot: SteamWorkshopDownloadMetadataSnapshot)? {
        let directURL = downloadMetadataFileURL(for: itemID)
        if let data = try? Data(contentsOf: directURL),
           let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
           snapshot.item.id == itemID {
            return (directURL, snapshot)
        }

        let metadataFiles = (try? FileManager.default.contentsOfDirectory(
            at: downloadMetadataIndexDirectoryURL(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in metadataFiles where url.pathExtension == "json" && url != directURL {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data),
                  snapshot.item.id == itemID else { continue }
            return (url, snapshot)
        }
        return nil
    }

    func downloadMetadataFileURL(forVideoURL videoURL: URL) -> URL {
        downloadMetadataIndexDirectoryURL()
            .appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("json")
    }

    func downloadMetadataFileURL(for record: SteamWorkshopDownloadRecord) -> URL {
        if record.contentType == .video,
           let videoURL = record.exportedVideoURL ?? record.sourceVideoURL {
            return downloadMetadataFileURL(forVideoURL: videoURL)
        }
        return downloadMetadataFileURL(for: record.id)
    }

    private func loadVideoDownloadMetadataSnapshot(for videoURL: URL) -> SteamWorkshopDownloadMetadataSnapshot? {
        let metadataURL = downloadMetadataFileURL(forVideoURL: videoURL)
        guard let data = try? Data(contentsOf: metadataURL),
              let snapshot = try? JSONDecoder().decode(SteamWorkshopDownloadMetadataSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    private func buildInstalledVideoRecord(
        videoURL: URL,
        metadata: SteamWorkshopDownloadMetadataSnapshot?
    ) -> SteamWorkshopDownloadRecord? {
        guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }
        let identifier = metadata?.item.id ?? "video:\(videoURL.deletingPathExtension().lastPathComponent)"
        let browserItem = metadata?.item
        let title = browserItem?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = videoURL.deletingPathExtension().lastPathComponent
        let updatedAt = (try? videoURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return SteamWorkshopDownloadRecord(
            id: identifier,
            title: title?.isEmpty == false ? title! : fallbackTitle,
            description: browserItem?.descriptionText ?? "",
            tags: browserItem?.tags ?? [],
            folderURL: videoURL.deletingLastPathComponent(),
            projectFileURL: nil,
            ownEntryHTMLURL: nil,
            dependencyHostEntryHTMLURL: nil,
            dependencyHostFolderURL: nil,
            entryHTMLURL: nil,
            resolvedWebRootURL: nil,
            previewURL: browserItem?.previewImageURL,
            sourceVideoURL: nil,
            exportedVideoURL: videoURL,
            updatedAt: updatedAt,
            sizeText: fileSizeTextForURL(videoURL) ?? "未知大小",
            status: .ready,
            browserItem: browserItem,
            contentType: .video,
            dependencyItemID: nil,
            dependencyStatus: .none
        )
    }

    private func fileSizeTextForURL(_ url: URL) -> String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return nil
        }
        return Self.fileSizeText(forBytes: size)
    }

    private func isSupportedWorkshopVideoFile(_ url: URL) -> Bool {
        Set(["mp4", "webm", "mov", "m4v"]).contains(url.pathExtension.localizedLowercase)
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
            let metadataURL = downloadMetadataFileURL(forVideoURL: candidateURL)
            if !fileManager.fileExists(atPath: candidateURL.path),
               !fileManager.fileExists(atPath: metadataURL.path) {
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
