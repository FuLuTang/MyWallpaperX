import Foundation

enum WallpaperRuntimeKind: String {
    case video
    case web
    case scene
    case systemStill
}

extension Notification.Name {
    static let wallpaperRuntimeWillSwitch = Notification.Name("WallpaperRuntimeWillSwitch")
}

@inline(__always)
func postWallpaperRuntimeWillSwitch(to kind: WallpaperRuntimeKind) {
    ImportedVideoAutoplayGate.shared.invalidate()
    NotificationCenter.default.post(
        name: .wallpaperRuntimeWillSwitch,
        object: nil,
        userInfo: ["kind": kind.rawValue]
    )
}
