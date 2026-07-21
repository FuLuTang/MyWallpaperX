//
//  DedicatedWebWallpaperHostPlaceholderAdapter+Failure.swift
//  MyWallpaperX
//

import Foundation

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func failCurrentLaunch(message: String) {
        guard let requestID = currentRequest?.id else { return }
        phase = .failed
        teardownHostSurfaces()
        removeLifecycleObservers()
        currentRequest = nil
        eventHandler?(.failed(message: message, requestID: requestID))
    }
}
