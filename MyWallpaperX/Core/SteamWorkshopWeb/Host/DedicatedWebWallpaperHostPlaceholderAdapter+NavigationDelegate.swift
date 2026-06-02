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
        recordDiagnostic(type: "navigation.finish", severity: .info, message: "ready", screenID: screenID, url: webView.url?.absoluteString)
        readyScreenIDs.insert(screenID)
        if readyScreenIDs.count == surfaces.count {
            phase = .ready
            eventHandler?(.ready)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recordDiagnostic(
            type: "webcontent.terminated",
            severity: .error,
            message: "WKWebView content process terminated",
            screenID: screenID(for: webView),
            url: webView.url?.absoluteString
        )
        failCurrentLaunch(message: "dedicated_web_host_webcontent_terminated")
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
