import Foundation

extension SteamWorkshopDownloadRecord {
    var scenePackageURL: URL? {
        let candidate = folderURL.appendingPathComponent("scene.pkg")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    var isSceneLaunchable: Bool {
        status == .ready && contentType == .scene && scenePackageURL != nil
    }
}
