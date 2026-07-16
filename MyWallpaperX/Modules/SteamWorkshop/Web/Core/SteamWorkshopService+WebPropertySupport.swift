import Foundation

extension SteamWorkshopService {
    private func existingWebResourceURL(for candidateURL: URL) -> URL? {
        let standardizedCandidateURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedCandidateURL.path) {
            return standardizedCandidateURL
        }

        let parentURL = standardizedCandidateURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parentURL.path) else {
            return nil
        }

        let pathComponents = standardizedCandidateURL.pathComponents.filter { $0 != "/" }
        guard !pathComponents.isEmpty else {
            return nil
        }

        var resolvedURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in pathComponents {
            let exactURL = resolvedURL.appendingPathComponent(component, isDirectory: false)
            if FileManager.default.fileExists(atPath: exactURL.path) {
                resolvedURL = exactURL
                continue
            }

            guard let directoryContents = try? FileManager.default.contentsOfDirectory(
                at: resolvedURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            guard let matchedURL = directoryContents.first(where: {
                $0.lastPathComponent.compare(component, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else {
                return nil
            }
            resolvedURL = matchedURL
        }

        let standardizedResolvedURL = resolvedURL.resolvingSymlinksInPath().standardizedFileURL
        return FileManager.default.fileExists(atPath: standardizedResolvedURL.path) ? standardizedResolvedURL : nil
    }

    func effectiveWebPropertyValues(
        for record: SteamWorkshopDownloadRecord,
        descriptor: ResolvedWebProjectDescriptor
    ) -> [String: SteamWorkshopWebPropertyValue] {
        effectiveWebPropertyValues(for: record, definitions: descriptor.propertyDefinitions)
    }

    func effectiveWebPropertyValues(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> [String: SteamWorkshopWebPropertyValue] {
        var values = webPropertyBaselineValues(
            for: record,
            definitions: definitions,
            respectingUserOverrides: true
        )
        for (key, value) in webPropertyOverrides(for: record) {
            values[key] = value
        }
        return values
    }

    func webPropertyBaselineValues(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition]
    ) -> [String: SteamWorkshopWebPropertyValue] {
        webPropertyBaselineValues(
            for: record,
            definitions: definitions,
            respectingUserOverrides: false
        )
    }

    private func webPropertyBaselineValues(
        for record: SteamWorkshopDownloadRecord,
        definitions: [SteamWorkshopWebPropertyDefinition],
        respectingUserOverrides: Bool
    ) -> [String: SteamWorkshopWebPropertyValue] {
        var values = Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0.defaultValue) })
        for (key, value) in webPresetValues(for: record) {
            values[key] = value
        }
        applyBundledBackgroundVideoFallback(
            to: &values,
            definitions: definitions,
            record: record,
            respectingUserOverrides: respectingUserOverrides
        )
        return values
    }

    private func applyBundledBackgroundVideoFallback(
        to values: inout [String: SteamWorkshopWebPropertyValue],
        definitions: [SteamWorkshopWebPropertyDefinition],
        record: SteamWorkshopDownloadRecord,
        respectingUserOverrides: Bool
    ) {
        // A few WE projects ship a usable built-in video while their declared defaults select
        // neither that video nor an image. Only repair that exact untouched configuration.
        guard record.contentType == .web,
              !record.isDependencyBackedWeb else {
            return
        }

        var definitionsByNormalizedKey: [String: SteamWorkshopWebPropertyDefinition] = [:]
        for definition in definitions {
            let normalizedKey = definition.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            definitionsByNormalizedKey[normalizedKey] = definition
        }
        guard let videoToggle = definitionsByNormalizedKey["backgroundvideo"],
              videoToggle.kind == .toggle,
              values[videoToggle.key]?.boolValue == false,
              let videoSource = definitionsByNormalizedKey["backgroundvideonumber"],
              videoSource.kind == .combo,
              let backgroundImage = definitionsByNormalizedKey["backgroundimageb"],
              backgroundImage.kind == .file else {
            return
        }
        let backgroundImagePath = values[backgroundImage.key]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard backgroundImagePath.isEmpty else { return }

        let backgroundOpacity = definitionsByNormalizedKey["backgroundcoloropacity"]
        if respectingUserOverrides {
            var overridesByNormalizedKey: [String: SteamWorkshopWebPropertyValue] = [:]
            for (key, value) in webPropertyOverrides(for: record) {
                overridesByNormalizedKey[key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = value
            }
            let explicitVideoValue = overridesByNormalizedKey["backgroundvideo"]?.boolValue
            let explicitImagePath = overridesByNormalizedKey["backgroundimageb"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard explicitVideoValue != false,
                  explicitVideoValue == true || explicitImagePath.isEmpty else {
                return
            }
        }

        var sourceCandidates: [SteamWorkshopWebPropertyValue] = []
        if let currentSource = values[videoSource.key] {
            sourceCandidates.append(currentSource)
        }
        sourceCandidates.append(contentsOf: videoSource.options.map(\.value))

        guard let availableSource = sourceCandidates.first(where: { source in
            guard let fileName = bundledWebMFileName(for: source) else { return false }
            return existingWebResourceURL(
                for: record.folderURL.appendingPathComponent(fileName, isDirectory: false)
            ) != nil
        }) else {
            return
        }

        values[videoToggle.key] = .bool(true)
        values[videoSource.key] = availableSource
        if let backgroundOpacity,
           let opacity = values[backgroundOpacity.key]?.numberValue,
           opacity >= 99 {
            values[backgroundOpacity.key] = .number(0)
        }
    }

    private func bundledWebMFileName(for source: SteamWorkshopWebPropertyValue) -> String? {
        switch source {
        case let .number(value):
            guard value.isFinite,
                  value > 0,
                  value.rounded() == value else {
                return nil
            }
            return "\(Int(value)).webm"
        case let .string(rawValue):
            let fileName = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty,
                  !fileName.contains("/"),
                  !fileName.contains("\\") else {
                return nil
            }
            if URL(fileURLWithPath: fileName).pathExtension.isEmpty {
                return "\(fileName).webm"
            }
            return URL(fileURLWithPath: fileName).pathExtension.lowercased() == "webm" ? fileName : nil
        case .bool:
            return nil
        }
    }

    func resolvedWebResourceBinding(
        forKey key: String,
        definition: SteamWorkshopWebPropertyDefinition?,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord,
        usesBookmarks: Bool = true
    ) -> ResolvedWebResourceBinding? {
        guard let rawPath = rawValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }

        let normalized = rawPath.replacingOccurrences(of: "\\", with: "/")
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isDirectoryDefinition = definition?.kind == .directory
        let isFileDefinition = definition?.kind == .file
        let looksLikePathPreset = webShellResourcePathLikeKeys(for: record).contains(normalizedKey)
        let origin: ResolvedWebResourceBindingOrigin = definition == nil ? .presetFallback : .propertyDefinition
        let kind: ResolvedWebResourceBindingKind
        if isDirectoryDefinition {
            kind = .directory
        } else if isFileDefinition {
            kind = .file
        } else if looksLikePathPreset {
            kind = .pathlikePreset
        } else {
            return nil
        }

        let candidateRoots = webResourceCandidateRoots(for: record)

        if usesBookmarks,
           kind != .pathlikePreset,
           let bookmarkURL = resolvedBookmarkedWebPropertyURL(forKey: key, record: record) {
            return ResolvedWebResourceBinding(
                key: key,
                rawValue: rawPath,
                kind: kind,
                fileType: definition?.fileType,
                resolvedURL: bookmarkURL,
                source: .bookmarkedOverride,
                origin: origin
            )
        }

        if normalized.hasPrefix("/") {
            let candidateURL = URL(fileURLWithPath: normalized).resolvingSymlinksInPath().standardizedFileURL
            let resolvedCandidateURL = existingWebResourceURL(for: candidateURL)
            let bundledRoot = resolvedCandidateURL.flatMap { candidateURL in
                candidateRoots.first { isWebResource(candidateURL, containedIn: $0.1) }
            }
            return ResolvedWebResourceBinding(
                key: key,
                rawValue: rawPath,
                kind: kind,
                fileType: definition?.fileType,
                resolvedURL: bundledRoot == nil && usesBookmarks ? nil : resolvedCandidateURL,
                source: bundledRoot?.0 ?? (resolvedCandidateURL != nil && !usesBookmarks ? .absolutePath : .unresolved),
                origin: origin
            )
        }

        for (source, rootURL) in candidateRoots {
            let candidateURL = rootURL.appendingPathComponent(normalized).resolvingSymlinksInPath().standardizedFileURL
            guard isWebResource(candidateURL, containedIn: rootURL) else {
                continue
            }
            if let resolvedCandidateURL = existingWebResourceURL(for: candidateURL) {
                return ResolvedWebResourceBinding(
                    key: key,
                    rawValue: rawPath,
                    kind: kind,
                    fileType: definition?.fileType,
                    resolvedURL: resolvedCandidateURL,
                    source: source,
                    origin: origin
                )
            }
        }

        return ResolvedWebResourceBinding(
            key: key,
            rawValue: rawPath,
            kind: kind,
            fileType: definition?.fileType,
            resolvedURL: nil,
            source: .unresolved,
            origin: origin
        )
    }

    private func webResourceCandidateRoots(for record: SteamWorkshopDownloadRecord) -> [(ResolvedWebResourceBindingSource, URL)] {
        var candidateRoots: [(ResolvedWebResourceBindingSource, URL)] = []
        if record.isDependencyBackedWeb {
            // Dependency-backed presets commonly point at files owned by the shell sample,
            // while scripts and property definitions come from the dependency host.
            candidateRoots.append((.shellRoot, record.webShellRootURL))
        }
        if let rootURL = record.webHostRootURL ?? record.resolvedWebRootURL {
            let standardizedRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
            if candidateRoots.contains(where: { $0.1.path == standardizedRootURL.path }) == false {
                candidateRoots.append((.hostRoot, standardizedRootURL))
            }
        }
        let standardizedFolderURL = record.folderURL.resolvingSymlinksInPath().standardizedFileURL
        if candidateRoots.contains(where: { $0.1.path == standardizedFolderURL.path }) == false {
            candidateRoots.append((.recordFolder, standardizedFolderURL))
        }
        return candidateRoots
    }

    private func isWebResource(_ candidateURL: URL, containedIn rootURL: URL) -> Bool {
        let candidatePath = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    func resolvedWebRuntimeAssetURL(
        forKey key: String,
        definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord
    ) -> URL? {
        resolvedWebResourceBinding(forKey: key, definition: definition, rawValue: rawValue, record: record)?.resolvedURL
    }

    func resolvedWebRuntimeValue(
        forKey key: String,
        definition: SteamWorkshopWebPropertyDefinition,
        rawValue: SteamWorkshopWebPropertyValue,
        record: SteamWorkshopDownloadRecord
    ) -> SteamWorkshopWebPropertyValue {
        if definition.kind == .color,
           case let .string(rawString) = rawValue,
           let normalizedColor = Self.normalizedWebColorRuntimeString(from: rawString) {
            return .string(normalizedColor)
        }

        if let binding = resolvedWebResourceBinding(
            forKey: key,
            definition: definition,
            rawValue: rawValue,
            record: record
        ), let resolvedPath = binding.resolvedPath {
            return .string(resolvedPath)
        }

        guard definition.kind == .file || definition.kind == .directory else {
            return rawValue
        }
        return rawValue
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
