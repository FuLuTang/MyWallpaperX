import Foundation

struct SceneResourceReferenceIndex {
    struct Match {
        let referencedPath: String
        let matchedPath: String?
        let isBuiltInReference: Bool

        nonisolated var isResolved: Bool {
            matchedPath != nil
        }

        nonisolated var isMissing: Bool {
            isResolved == false && isBuiltInReference == false
        }
    }

    let matches: [Match]

    nonisolated var resolvedCount: Int {
        matches.filter(\.isResolved).count
    }

    nonisolated var builtInReferenceCount: Int {
        matches.filter(\.isBuiltInReference).count
    }

    nonisolated var missingReferences: [String] {
        matches.compactMap { $0.isMissing ? $0.referencedPath : nil }
    }
}

struct SceneResourceReferenceIndexBuilder {
    nonisolated func build(
        document: SceneDocument,
        packageReport: ScenePkgExtractionReport?,
        resourceIndex: SceneResourceIndex
    ) -> SceneResourceReferenceIndex {
        let availablePaths = Set(
            (packageReport?.discoveredPaths ?? []) + resourceIndex.resources.map(\.relativePath)
        ).map(Self.normalizedPath)

        let matches = document.referencedResourcePaths.map { path in
            let normalized = Self.normalizedPath(path)
            return SceneResourceReferenceIndex.Match(
                referencedPath: path,
                matchedPath: Self.matchPath(normalized, in: availablePaths),
                isBuiltInReference: Self.isBuiltInReference(normalized)
            )
        }

        return SceneResourceReferenceIndex(matches: matches)
    }

    nonisolated private static func matchPath(_ path: String, in availablePaths: [String]) -> String? {
        if availablePaths.contains(path) {
            return path
        }

        let jsonPath = path + ".json"
        if availablePaths.contains(jsonPath) {
            return jsonPath
        }

        let materialPath = "materials/" + path + ".json"
        if availablePaths.contains(materialPath) {
            return materialPath
        }

        let texturePath = "materials/" + path + ".tex"
        if availablePaths.contains(texturePath) {
            return texturePath
        }

        let directTexturePath = path + ".tex"
        if availablePaths.contains(directTexturePath) {
            return directTexturePath
        }

        return nil
    }

    nonisolated private static func isBuiltInReference(_ path: String) -> Bool {
        path.hasPrefix("models/util/")
    }

    nonisolated private static func normalizedPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .localizedLowercase
    }
}
