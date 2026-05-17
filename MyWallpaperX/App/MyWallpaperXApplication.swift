//
//  MyWallpaperXApplication.swift
//  MyWallpaperX
//

import AppKit

@main
enum MyWallpaperXApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        MainWindowCoordinator.configure(with: WallpaperManager.shared)
        app.run()
    }
}
