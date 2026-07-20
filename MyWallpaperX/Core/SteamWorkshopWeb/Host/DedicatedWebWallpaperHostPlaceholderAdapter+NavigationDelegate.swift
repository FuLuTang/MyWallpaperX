import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private var ignoredNavigationFailureCodes: Set<Int> {
        [NSURLErrorCancelled]
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let screenID = screenID(for: webView) else { return }
        setAudioSpectrumDemand(false, for: screenID)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        installDefaultInteractiveRegionsIfNeeded()
        applyCompatibilityState(to: webView, deferDirectorySync: false)
        startSyntheticInputForwardingIfNeeded()
        guard let screenID = screenID(for: webView) else { return }
        finishWebContentRecovery(for: screenID, webView: webView)
        recordDiagnostic(type: "navigation.finish", severity: .info, message: "ready", screenID: screenID, url: webView.url?.absoluteString)
        markScreenReady(screenID)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        handleWebContentTermination(for: webView)
    }

    func handleWebContentTermination(for webView: WKWebView) {
        guard let screenID = screenID(for: webView),
              let surface = surfaces[screenID],
              surface.webView === webView,
              currentRequest != nil else {
            return
        }
        setAudioSpectrumDemand(false, for: screenID)

        recordDiagnostic(
            type: "webcontent.terminated",
            severity: .warning,
            message: "WKWebView content process terminated",
            screenID: screenID,
            url: webView.url?.absoluteString
        )

        if recoveringWebContentScreenIDs.contains(screenID) {
            guard webContentRecoveryReloadStartedScreenIDs.contains(screenID) else {
                return
            }
            failWebContentRecovery(for: screenID, message: "WKWebView content process terminated again after recovery reload")
            return
        }

        guard webContentRecoveryAttemptsByScreen[screenID, default: 0] == 0 else {
            failWebContentRecovery(for: screenID, message: "WKWebView content process recovery attempts exhausted")
            return
        }

        webContentRecoveryAttemptsByScreen[screenID] = 1
        recoveringWebContentScreenIDs.insert(screenID)
        readyScreenIDs.remove(screenID)
        resetInteractionState(for: screenID)
        recordDiagnostic(
            type: "webcontent.recovery",
            severity: .warning,
            message: "Reloading the terminated display once",
            screenID: screenID,
            url: webView.url?.absoluteString
        )

        webContentRecoveryWorkItems[screenID]?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak webView] in
            guard let self,
                  let webView,
                  self.currentRequest != nil,
                  self.recoveringWebContentScreenIDs.contains(screenID),
                  let currentSurface = self.surfaces[screenID],
                  currentSurface.webView === webView else {
                return
            }
            self.webContentRecoveryWorkItems.removeValue(forKey: screenID)
            self.webContentRecoveryReloadStartedScreenIDs.insert(screenID)
            webView.reload()
        }
        webContentRecoveryWorkItems[screenID] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func finishWebContentRecovery(for screenID: CGDirectDisplayID, webView: WKWebView) {
        guard recoveringWebContentScreenIDs.contains(screenID),
              surfaces[screenID]?.webView === webView else {
            return
        }
        webContentRecoveryWorkItems.removeValue(forKey: screenID)?.cancel()
        recoveringWebContentScreenIDs.remove(screenID)
        webContentRecoveryReloadStartedScreenIDs.remove(screenID)
        recordDiagnostic(
            type: "webcontent.recovery.succeeded",
            severity: .info,
            message: "Reloaded terminated display",
            screenID: screenID,
            url: webView.url?.absoluteString
        )
    }

    func failWebContentRecovery(for screenID: CGDirectDisplayID, message: String) {
        recordDiagnostic(
            type: "webcontent.recovery.exhausted",
            severity: .error,
            message: message,
            screenID: screenID,
            url: surfaces[screenID]?.webView.url?.absoluteString
        )
        failCurrentLaunch(message: "dedicated_web_host_webcontent_terminated")
    }

    func resetWebContentRecoveryState(for screenID: CGDirectDisplayID? = nil) {
        if let screenID {
            webContentRecoveryWorkItems.removeValue(forKey: screenID)?.cancel()
            webContentRecoveryAttemptsByScreen.removeValue(forKey: screenID)
            recoveringWebContentScreenIDs.remove(screenID)
            webContentRecoveryReloadStartedScreenIDs.remove(screenID)
            return
        }
        for workItem in webContentRecoveryWorkItems.values {
            workItem.cancel()
        }
        webContentRecoveryWorkItems.removeAll()
        webContentRecoveryAttemptsByScreen.removeAll()
        recoveringWebContentScreenIDs.removeAll()
        webContentRecoveryReloadStartedScreenIDs.removeAll()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, webView: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error, webView: webView)
    }

    func handleNavigationFailure(_ error: Error, webView: WKWebView) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           ignoredNavigationFailureCodes.contains(nsError.code) {
            return
        }
        if nsError.domain == WKError.errorDomain,
           ignoredNavigationFailureCodes.contains(nsError.code) {
            return
        }
        if nsError.domain == WKError.errorDomain,
           nsError.code == WKError.Code.webContentProcessTerminated.rawValue {
            handleWebContentTermination(for: webView)
            return
        }
        if let screenID = screenID(for: webView),
           recoveringWebContentScreenIDs.contains(screenID) {
            recordDiagnostic(
                type: "webcontent.recovery.failed",
                severity: .error,
                message: error.localizedDescription,
                screenID: screenID,
                url: webView.url?.absoluteString
            )
        }
        recordDiagnostic(
            type: "navigation.fail",
            severity: .error,
            message: error.localizedDescription,
            screenID: screenID(for: webView),
            url: webView.url?.absoluteString
        )
        failCurrentLaunch(message: error.localizedDescription)
    }
}
