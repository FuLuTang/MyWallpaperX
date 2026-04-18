import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    private var ignoredNavigationFailureCodes: Set<Int> {
        [NSURLErrorCancelled]
    }

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
        failCurrentLaunch(message: "dedicated_web_host_webcontent_terminated")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func handleNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           ignoredNavigationFailureCodes.contains(nsError.code) {
            return
        }
        if nsError.domain == WKError.errorDomain,
           ignoredNavigationFailureCodes.contains(nsError.code) {
            return
        }
        failCurrentLaunch(message: error.localizedDescription)
    }
}
