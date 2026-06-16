import Foundation

extension SteamWorkshopService {
    func resolvedWebHostCapabilitySnapshot() -> ResolvedWebHostCapabilitySnapshot {
        ResolvedWebHostCapabilitySnapshot(
            userPropertiesLevel: .basic,
            generalProperties: .init(
                applyListenerLevel: .basic,
                fpsLevel: .basic
            ),
            directoryNotificationsLevel: .placeholder,
            audioListenerLevel: .basic,
            audioStreamLevel: .basic,
            media: .init(
                statusLevel: .basic,
                propertiesLevel: .basic,
                thumbnailLevel: .basic,
                timelineLevel: .basic,
                playbackLevel: .basic
            ),
            pluginBridgeLevel: .placeholder,
            rgbBridgeLevel: .placeholder,
            pauseBridgeLevel: .basic,
            volumeBridgeLevel: .basic
        )
    }

    func resolvedWebStaticContentSummary(
        for record: SteamWorkshopDownloadRecord,
        entryURL: URL,
        rootURL: URL
    ) -> ResolvedWebStaticContentSummary {
        let propertyDefinitions = webPropertyDefinitions(for: record)
        var scannedFiles = Set<URL>()
        var pendingFiles = [entryURL]
        var externalDependencyURLs = Set<String>()
        var usesWebMResource = false
        var usesHoverOnlyInteraction = false
        var usesApplyGeneralProperties = false
        var usesGeneralFPS = false
        var usesPluginBridge = false
        var usesPersistentBrowserStorage = false
        var usesServiceWorkerRegistration = false
        var usesESModuleDependency = false
        var usesDynamicImport = false
        var usesWASMResource = false
        var usesWASMStreaming = false
        var usesCustomSchemeSensitiveWebGL = false
        var usesIframeCrossFrameAccess = false
        let hasFetchAllDirectoryProperty = propertyDefinitions.contains {
            $0.kind == .directory && $0.directoryMode?.lowercased() == "fetchall"
        }
        let hasOnDemandDirectoryProperty = propertyDefinitions.contains {
            $0.kind == .directory && $0.directoryMode?.lowercased() == "ondemand"
        }

        while let fileURL = pendingFiles.first {
            pendingFiles.removeFirst()
            guard scannedFiles.insert(fileURL).inserted else { continue }
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            if Self.webContentUsesWebMResource(content) {
                usesWebMResource = true
            }
            if fileURL.pathExtension.localizedLowercase == "css",
               Self.webContentUsesHoverOnlyInteraction(content) {
                usesHoverOnlyInteraction = true
            }
            if Self.webContentUsesApplyGeneralProperties(content) {
                usesApplyGeneralProperties = true
            }
            if Self.webContentUsesGeneralFPS(content) {
                usesGeneralFPS = true
            }
            if Self.webContentUsesPluginBridge(content) {
                usesPluginBridge = true
            }
            if Self.webContentUsesPersistentBrowserStorage(content) {
                usesPersistentBrowserStorage = true
            }
            if Self.webContentUsesServiceWorkerRegistration(content) {
                usesServiceWorkerRegistration = true
            }
            if Self.webContentUsesESModuleDependency(content) {
                usesESModuleDependency = true
            }
            if Self.webContentUsesDynamicImport(content) {
                usesDynamicImport = true
            }
            if Self.webContentUsesWASMResource(content) {
                usesWASMResource = true
            }
            if Self.webContentUsesWASMStreaming(content) {
                usesWASMStreaming = true
            }
            if Self.webContentUsesCustomSchemeSensitiveWebGL(content) {
                usesCustomSchemeSensitiveWebGL = true
            }
            if Self.webContentUsesIframeCrossFrameAccess(content) {
                usesIframeCrossFrameAccess = true
            }

            for reference in Self.extractLocalWebResourceReferences(from: content, fileExtension: fileURL.pathExtension) {
                switch reference {
                case let .local(path):
                    guard let resolvedURL = Self.resolveWebResourceURL(path, relativeTo: fileURL, rootURL: rootURL) else {
                        continue
                    }
                    let ext = resolvedURL.pathExtension.localizedLowercase
                    if ext == "webm" {
                        usesWebMResource = true
                    }
                    if ext == "wasm" {
                        usesWASMResource = true
                    }
                    if ["html", "htm", "css", "js", "json"].contains(ext),
                       FileManager.default.fileExists(atPath: resolvedURL.path),
                       Self.shouldScanWebDependencyFile(named: resolvedURL.lastPathComponent) {
                        pendingFiles.append(resolvedURL)
                    }
                case let .external(urlString):
                    externalDependencyURLs.insert(urlString)
                }
            }
        }

        let parsedURLs = externalDependencyURLs.compactMap { URL(string: $0) }
        let hosts = Set(parsedURLs.compactMap { $0.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let localhostHosts = hosts.filter { $0 == "localhost" || $0 == "127.0.0.1" || $0 == "::1" }
        let remoteScriptHosts = Set(
            parsedURLs.compactMap { url -> String? in
                guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                    return nil
                }
                let path = url.path.lowercased()
                if path.hasSuffix(".js") || path.hasSuffix(".mjs") || path.hasSuffix(".css") {
                    return host
                }
                return nil
            }
        )

        return ResolvedWebStaticContentSummary(
            usesApplyGeneralProperties: usesApplyGeneralProperties,
            usesGeneralFPS: usesGeneralFPS,
            usesPluginBridge: usesPluginBridge,
            usesPersistentBrowserStorage: usesPersistentBrowserStorage,
            usesServiceWorkerRegistration: usesServiceWorkerRegistration,
            usesESModuleDependency: usesESModuleDependency,
            usesDynamicImport: usesDynamicImport,
            usesWASMResource: usesWASMResource,
            usesWASMStreaming: usesWASMStreaming,
            usesCustomSchemeSensitiveWebGL: usesCustomSchemeSensitiveWebGL,
            usesIframeCrossFrameAccess: usesIframeCrossFrameAccess,
            usesWebMResource: usesWebMResource,
            usesHoverOnlyInteraction: usesHoverOnlyInteraction,
            hasFetchAllDirectoryProperty: hasFetchAllDirectoryProperty,
            hasOnDemandDirectoryProperty: hasOnDemandDirectoryProperty,
            externalDependencyHosts: hosts.sorted(),
            localhostDependencyHosts: localhostHosts.sorted(),
            remoteScriptDependencyHosts: remoteScriptHosts.sorted()
        )
    }
}
