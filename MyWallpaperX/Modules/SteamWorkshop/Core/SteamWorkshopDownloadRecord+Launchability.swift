import Foundation

extension SteamWorkshopDownloadRecord {
    var isPlayableOrLaunchable: Bool {
        isPlayable || isSceneLaunchable || isWebPlayableOrLaunchable
    }
}
