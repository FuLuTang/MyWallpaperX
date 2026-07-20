import Foundation
import WebKit

extension DedicatedWebWallpaperHostPlaceholderAdapter {
    #if DEBUG
    func collectDebugDOMEvidence(
        from webView: WKWebView,
        screenID: CGDirectDisplayID,
        reason: String
    ) {
        let script = #"""
        const elements = Array.from(document.querySelectorAll('body *')).slice(0, 10000);
        const isVisible = (element) => {
          const style = getComputedStyle(element);
          if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity || 1) === 0) return false;
          const rect = element.getBoundingClientRect();
          return rect.width > 1 && rect.height > 1 && rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
        };
        const visible = elements.filter(isVisible);
        const images = Array.from(document.images);
        const canvases = Array.from(document.querySelectorAll('canvas'));
        const media = Array.from(document.querySelectorAll('video, audio'));
        const propertyListener = window.wallpaperPropertyListener;
        const propertyReplayState = window.__myWallpaperPropertyReplayState || null;
        const lastUserProperties = window.__myWallpaperLastUserProperties;
        const pendingProperties = propertyReplayState ? propertyReplayState.pendingProperties : null;
        const propertyDescriptor = Object.getOwnPropertyDescriptor(window, 'wallpaperPropertyListener');
        const userPropertyCallback = propertyListener && typeof propertyListener.applyUserProperties === 'function'
          ? propertyListener.applyUserProperties
          : null;
        const keyCount = (value) => {
          try { return value && typeof value === 'object' ? Object.keys(value).length : 0; }
          catch (_) { return 0; }
        };
        const backgroundCount = visible.filter((element) => {
          const value = getComputedStyle(element).backgroundImage;
          return value && value !== 'none';
        }).length;
        let serviceWorkerRegistrations = [];
        let serviceWorkerError = null;
        if ('serviceWorker' in navigator) {
          try {
            serviceWorkerRegistrations = await navigator.serviceWorker.getRegistrations();
          } catch (error) {
            serviceWorkerError = String(error);
          }
        }
        return {
          evidencePhase: String(reason || ''),
          readyState: document.readyState,
          titleLength: String(document.title || '').length,
          bodyChildCount: document.body ? document.body.children.length : 0,
          visibleElementCount: visible.length,
          textLength: document.body ? String(document.body.innerText || '').trim().length : 0,
          imageCount: images.length,
          loadedImageCount: images.filter((image) => image.complete && image.naturalWidth > 0).length,
          canvasCount: canvases.length,
          drawableCanvasCount: canvases.filter((canvas) => canvas.width > 1 && canvas.height > 1).length,
          mediaCount: media.length,
          iframeCount: document.querySelectorAll('iframe').length,
          backgroundCount,
          bodyBackgroundImageSet: Boolean(document.body && getComputedStyle(document.body).backgroundImage !== 'none'),
          documentBackgroundImageSet: getComputedStyle(document.documentElement).backgroundImage !== 'none',
          userPropertyCount: keyCount(lastUserProperties),
          pendingPropertyCount: keyCount(pendingProperties),
          propertyListenerAvailable: Boolean(userPropertyCallback),
          propertyBridgeAvailable: typeof window.__myWallpaperApplyProperties === 'function',
          propertyInterceptorInstalled: Boolean(propertyDescriptor && typeof propertyDescriptor.set === 'function'),
          propertyListenerReplayQueued: window.__myWallpaperPropertyReplayQueued === true,
          propertyDeferredReplayScheduled: window.__myWallpaperDeferredPropertyReplayScheduled === true,
          propertyReplayPending: Boolean(propertyReplayState && (
            propertyReplayState.pendingProperties !== null || propertyReplayState.pendingSignature
          )),
          propertyReplayAttempt: Number(propertyReplayState && propertyReplayState.attempt || 0),
          propertyReplayTimerActive: Boolean(propertyReplayState && propertyReplayState.timer !== null),
          propertyPendingSignaturePresent: Boolean(propertyReplayState && propertyReplayState.pendingSignature),
          propertyAppliedSignaturePresent: Boolean(window.__myWallpaperLastAppliedUserPropertySignature),
          propertyAppliedToCurrentListener: Boolean(
            userPropertyCallback && userPropertyCallback === window.__myWallpaperLastAppliedUserPropertyCallback
          ),
          propertyAppliedToCurrentPayload: Boolean(
            userPropertyCallback && typeof window.__myWallpaperStablePropertySignature === 'function' &&
            window.__myWallpaperStablePropertySignature(lastUserProperties || {}) ===
              window.__myWallpaperLastAppliedUserPropertySignature
          ),
          serviceWorkerSupported: 'serviceWorker' in navigator,
          serviceWorkerRegistrationCount: serviceWorkerRegistrations.length,
          serviceWorkerControlled: Boolean(navigator.serviceWorker && navigator.serviceWorker.controller),
          serviceWorkerScopes: serviceWorkerRegistrations.map((registration) => registration.scope),
          serviceWorkerError,
          viewport: `${innerWidth}x${innerHeight}`,
          scrollSize: `${document.documentElement.scrollWidth}x${document.documentElement.scrollHeight}`
        };
        """#
        webView.callAsyncJavaScript(
            script,
            arguments: ["reason": reason],
            in: nil,
            in: .page
        ) { [weak self, weak webView] result in
            guard let self, let webView else { return }
            switch result {
            case let .success(value):
                let payload = value as? [String: Any] ?? [:]
                let message = Self.debugDOMPayloadString(payload)
                self.recordDiagnostic(
                    type: "evidence.dom",
                    severity: .info,
                    message: message,
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
                let registrationCount = (payload["serviceWorkerRegistrationCount"] as? NSNumber)?.intValue ?? 0
                guard registrationCount > 0 else { return }
                let controlled = (payload["serviceWorkerControlled"] as? NSNumber)?.boolValue ?? false
                self.recordDiagnostic(
                    type: "evidence.serviceWorker",
                    severity: .info,
                    message: "registrations=\(registrationCount) controlled=\(controlled)",
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
            case let .failure(error):
                self.recordDiagnostic(
                    type: "evidence.dom.error",
                    severity: .error,
                    message: error.localizedDescription,
                    screenID: screenID,
                    url: webView.url?.absoluteString
                )
            }
        }
    }

    private static func debugDOMPayloadString(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }
    #endif
}
