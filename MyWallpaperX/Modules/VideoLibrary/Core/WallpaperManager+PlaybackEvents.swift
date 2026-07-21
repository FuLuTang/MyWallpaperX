//
//  WallpaperManager+PlaybackEvents.swift
//  MyWallpaperX
//

import Combine
import Foundation

extension WallpaperManager {
    func observePlaybackEvents(storeIn cancellables: inout Set<AnyCancellable>) {
        NotificationCenter.default.publisher(for: WallpaperEngine.playbackFailedNotification)
            .sink { [weak self] notification in
                self?.handleEnginePlaybackFailure(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: WallpaperEngine.playbackEndedNotification)
            .sink { [weak self] notification in
                guard let videoPath = notification.userInfo?["videoPath"] as? String else { return }
                self?.handlePlaybackEnded(forPath: videoPath)
            }
            .store(in: &cancellables)
    }

    private func handleEnginePlaybackFailure(_ notification: Notification) {
        if notification.userInfo?["contentKind"] as? String == "web" {
            guard activeWallpaperRuntime == .web else { return }
            isPlaying = WallpaperEngine.shared.isPlaying()
            stopAutoSwitchTimer()
            return
        }
        guard let videoPath = notification.userInfo?["videoPath"] as? String else { return }
        handlePlaybackFailure(forPath: videoPath)
    }
}
