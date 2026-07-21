//
//  DedicatedWebWallpaperHostPlaceholderAdapter+NavigationIdentity.swift
//  MyWallpaperX
//

import Foundation
import AppKit
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    @discardableResult
    func createAndLoadSurface(
        for screen: NSScreen,
        request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL
    ) -> Bool {
        guard let screenID = Self.screenID(for: screen) else { return false }
        let surface = makeSurface(for: screen, screenID: screenID)
        surfaces[screenID] = surface
        setTransientMouseCaptureEnabled(false, for: surface)
        surface.window.orderFrontRegardless()
        surface.window.level = Self.webWindowLevel
        guard loadTrackedNavigation(
            on: surface,
            request: request,
            localEntryURL: localEntryURL,
            stopCurrent: false
        ) else {
            removeSurface(for: screenID)
            return false
        }
        return true
    }

    func reloadTrackedSurfaces(
        for request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL
    ) -> Bool {
        for surface in Array(surfaces.values) {
            setTransientMouseCaptureEnabled(false, for: surface)
            surface.schemeHandler.updateAdditionalReadableRoots(accessibleResourceURLs(from: request.propertiesJSON))
            surface.window.orderFrontRegardless()
            surface.window.level = Self.webWindowLevel
            guard loadTrackedNavigation(
                on: surface,
                request: request,
                localEntryURL: localEntryURL,
                stopCurrent: true
            ) else {
                return false
            }
        }
        return true
    }

    @discardableResult
    func loadTrackedNavigation(
        on surface: HostSurface,
        request: WallpaperEngine.WebWallpaperLaunchRequest,
        localEntryURL: URL,
        stopCurrent: Bool
    ) -> Bool {
        navigationOwnershipByScreen.removeValue(forKey: surface.screenID)
        if stopCurrent {
            surface.webView.stopLoading()
        }
        guard let navigation = surface.webView.load(
            URLRequest(url: runtimeEntryURL(for: request, localEntryURL: localEntryURL, surface: surface))
        ) else {
            return false
        }
        guard currentRequest?.id == request.id,
              surfaces[surface.screenID]?.webView === surface.webView else {
            return false
        }
        navigationOwnershipByScreen[surface.screenID] = NavigationOwnership(
            requestID: request.id,
            navigation: navigation
        )
        return true
    }

    func reloadTrackedNavigation(on surface: HostSurface, requestID: UUID) -> Bool {
        navigationOwnershipByScreen.removeValue(forKey: surface.screenID)
        guard let navigation = surface.webView.reload() else { return false }
        guard currentRequest?.id == requestID,
              surfaces[surface.screenID]?.webView === surface.webView else {
            return false
        }
        navigationOwnershipByScreen[surface.screenID] = NavigationOwnership(
            requestID: requestID,
            navigation: navigation
        )
        return true
    }

    func screenIDForCurrentNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? {
        guard let requestID = currentRequest?.id,
              let navigation,
              let screenID = screenID(for: webView),
              surfaces[screenID]?.webView === webView,
              let tracked = navigationOwnershipByScreen[screenID],
              tracked.requestID == requestID,
              tracked.navigation === navigation else {
            return nil
        }
        return screenID
    }

    func screenIDForStartedNavigation(_ navigation: WKNavigation?, webView: WKWebView) -> CGDirectDisplayID? {
        guard let requestID = currentRequest?.id,
              let navigation,
              let screenID = screenID(for: webView),
              surfaces[screenID]?.webView === webView else {
            return nil
        }
        if let ownership = navigationOwnershipByScreen[screenID],
           ownership.requestID == requestID,
           ownership.navigation === navigation {
            return screenID
        }
        guard !recoveringWebContentScreenIDs.contains(screenID),
              readyScreenIDs.contains(screenID) else {
            return nil
        }
        navigationOwnershipByScreen[screenID] = NavigationOwnership(
            requestID: requestID,
            navigation: navigation
        )
        readyScreenIDs.remove(screenID)
        phase = .launching
        return screenID
    }
}
