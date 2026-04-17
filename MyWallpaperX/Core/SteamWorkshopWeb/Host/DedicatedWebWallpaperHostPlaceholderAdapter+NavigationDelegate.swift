import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        installDefaultInteractiveRegionsIfNeeded()
        applyCompatibilityState(to: webView, deferDirectorySync: false)
        startSyntheticInputForwardingIfNeeded()
        guard let screenID = screenID(for: webView) else { return }
        readyScreenIDs.insert(screenID)
        if readyScreenIDs.count == surfaces.count {
            phase = .ready
            eventHandler?(.ready)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        phase = .failed
        teardownHostSurfaces()
        eventHandler?(.failed(message: "dedicated_web_host_webcontent_terminated"))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func handleNavigationFailure(_ error: Error) {
        phase = .failed
        teardownHostSurfaces()
        removeLifecycleObservers()
        eventHandler?(.failed(message: error.localizedDescription))
    }
}
