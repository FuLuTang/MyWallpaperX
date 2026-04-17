import Foundation
import WebKit

extension WallpaperDaemon {
    static let webCompatibilityScript = #"""
    (() => {
      const audioStreams = [];
      const audioListeners = [];
      const volumeListeners = [];
      const mediaStatusListeners = [];
      const mediaPropertiesListeners = [];
      const playbackStateListeners = [];
      const resumeAudioContexts = () => {
        const constructors = [window.AudioContext, window.webkitAudioContext].filter(Boolean);
        for (const Ctor of constructors) {
          try {
            if (!Ctor || !Ctor.prototype || typeof Ctor.prototype.resume !== 'function') continue;
            const originalResume = Ctor.prototype.resume;
            if (Ctor.prototype.__mwxResumeWrapped) continue;
            Ctor.prototype.__mwxResumeWrapped = true;
            Ctor.prototype.resume = function(...args) {
              return originalResume.apply(this, args).catch((error) => {
                hostLogger.post('audio.resume.error', error && error.message ? error.message : error);
                throw error;
              });
            };
          } catch (_) {}
        }
      };
      const defineVisibilityProperty = (target, name, getter) => {
        if (!target) return false;
        try {
          Object.defineProperty(target, name, {
            configurable: true,
            enumerable: true,
            get: getter
          });
          return true;
        } catch (_) {
          return false;
        }
      };
      const hostLogger = (() => {
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallpaperHostLog;
        return {
          post(type, message) {
            if (!handler || typeof handler.postMessage !== 'function') return;
            try {
              handler.postMessage({ type, message: String(message ?? '') });
            } catch (_) {}
          }
        };
      })();
      resumeAudioContexts();
      const visibilityOverrideResults = [
        defineVisibilityProperty(document, 'hidden', () => false),
        defineVisibilityProperty(Document.prototype, 'hidden', () => false),
        defineVisibilityProperty(document, 'visibilityState', () => 'visible'),
        defineVisibilityProperty(Document.prototype, 'visibilityState', () => 'visible'),
        defineVisibilityProperty(document, 'webkitVisibilityState', () => 'visible'),
        defineVisibilityProperty(Document.prototype, 'webkitVisibilityState', () => 'visible')
      ];
      const visibilityOverrideApplied = visibilityOverrideResults.some(Boolean);
      hostLogger.post('visibility.override', visibilityOverrideApplied ? 'applied' : 'unavailable');
      const wrapConsole = (name) => {
        const original = console[name];
        console[name] = function(...args) {
          try {
            hostLogger.post(`console.${name}`, args.map(arg => {
              if (typeof arg === 'string') return arg;
              try { return JSON.stringify(arg); } catch (_) { return String(arg); }
            }).join(' '));
          } catch (_) {}
          if (typeof original === 'function') {
            return original.apply(this, args);
          }
        };
      };
      ['log', 'warn', 'error'].forEach(wrapConsole);
      window.addEventListener('error', (event) => {
        const target = event.target;
        if (target && target !== window) {
          const tagName = target.tagName || 'resource';
          const source = target.currentSrc || target.src || target.href || '';
          hostLogger.post('resource.error', `${tagName} ${source}`.trim());
          return;
        }
        hostLogger.post('window.error', `${event.message || 'unknown'} @ ${event.filename || 'inline'}:${event.lineno || 0}:${event.colno || 0}`);
      }, true);
      window.addEventListener('unhandledrejection', (event) => {
        const reason = event.reason && event.reason.stack ? event.reason.stack : event.reason;
        hostLogger.post('promise.rejection', reason || 'unknown');
      });
      document.addEventListener('DOMContentLoaded', () => {
        hostLogger.post('dom.ready', document.location.href);
        const mediaStateSummary = (node) => {
          const source = node.currentSrc || node.src || 'inline-media';
          const parts = [source];
          try { parts.push(`tag=${(node.tagName || 'media').toLowerCase()}`); } catch (_) {}
          try { parts.push(`readyState=${Number(node.readyState || 0)}`); } catch (_) {}
          try { parts.push(`networkState=${Number(node.networkState || 0)}`); } catch (_) {}
          try { parts.push(`paused=${node.paused ? 'true' : 'false'}`); } catch (_) {}
          try { parts.push(`ended=${node.ended ? 'true' : 'false'}`); } catch (_) {}
          try { parts.push(`muted=${node.muted ? 'true' : 'false'}`); } catch (_) {}
          try { parts.push(`currentTime=${Number(node.currentTime || 0).toFixed(3)}`); } catch (_) {}
          try { parts.push(`duration=${Number(node.duration || 0).toFixed(3)}`); } catch (_) {}
          try {
            if (typeof node.videoWidth === 'number' && typeof node.videoHeight === 'number') {
              parts.push(`videoSize=${node.videoWidth}x${node.videoHeight}`);
            }
          } catch (_) {}
          try {
            const rect = node.getBoundingClientRect();
            parts.push(`rect=${Math.round(rect.width)}x${Math.round(rect.height)}`);
          } catch (_) {}
          try { parts.push(`visibility=${document.visibilityState || 'unknown'}`); } catch (_) {}
          return parts.join(' ');
        };
        const postMediaState = (type, node) => hostLogger.post(type, mediaStateSummary(node));
        const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
        for (const node of mediaNodes) {
          postMediaState('media.initial', node);
          node.addEventListener('error', () => {
            const error = node.error;
            const details = error ? `code=${error.code}` : 'unknown';
            hostLogger.post('media.error', `${mediaStateSummary(node)} ${details}`.trim());
          });
          node.addEventListener('stalled', () => postMediaState('media.stalled', node));
          node.addEventListener('suspend', () => postMediaState('media.suspend', node));
          node.addEventListener('waiting', () => postMediaState('media.waiting', node));
          node.addEventListener('playing', () => postMediaState('media.playing', node));
          node.addEventListener('pause', () => postMediaState('media.pause', node));
          node.addEventListener('loadedmetadata', () => postMediaState('media.loadedmetadata', node));
          node.addEventListener('loadeddata', () => postMediaState('media.loadeddata', node));
          node.addEventListener('canplay', () => postMediaState('media.canplay', node));
          node.addEventListener('canplaythrough', () => postMediaState('media.canplaythrough', node));
          node.addEventListener('ended', () => postMediaState('media.ended', node));
          node.addEventListener('emptied', () => postMediaState('media.emptied', node));
          node.addEventListener('timeupdate', () => {
            try {
              if (!Number.isFinite(node.currentTime)) return;
              const bucket = Math.floor(node.currentTime * 2) / 2;
              if (node.__myWallpaperLastLoggedTimeBucket === bucket) return;
              node.__myWallpaperLastLoggedTimeBucket = bucket;
            } catch (_) {}
            postMediaState('media.timeupdate', node);
          });
        }
        hostLogger.post('dom.visibility', `${document.visibilityState || 'unknown'} hidden=${document.hidden ? 'true' : 'false'} mediaCount=${mediaNodes.length}`);
        document.addEventListener('visibilitychange', () => {
          hostLogger.post('dom.visibility', `${document.visibilityState || 'unknown'} hidden=${document.hidden ? 'true' : 'false'} mediaCount=${mediaNodes.length}`);
        });
      });
      window.wallpaperEngine_paused = false;
      window.wallpaperRegisterAudioStream = function(audio) {
        if (audio) {
          audioStreams.push(audio);
        }
      };
      window.wallpaperRegisterAudio = window.wallpaperRegisterAudioStream;
      window.wallpaperRegisterAudioListener = function(listener) {
        if (typeof listener === 'function') {
          audioListeners.push(listener);
        }
      };
      window.wallpaperRegisterVolumeListener = function(listener) {
        if (typeof listener === 'function') {
          volumeListeners.push(listener);
        }
      };
      window.wallpaperRegisterMediaStatusListener = function(listener) {
        if (typeof listener === 'function') {
          mediaStatusListeners.push(listener);
        }
      };
      window.wallpaperRegisterMediaPropertiesListener = function(listener) {
        if (typeof listener === 'function') {
          mediaPropertiesListeners.push(listener);
        }
      };
      window.wallpaperRegisterPropertyListener = window.wallpaperRegisterMediaStatusListener;
      window.wallpaperSetPlaybackStateListener = function(listener) {
        if (typeof listener === 'function') {
          playbackStateListeners.push(listener);
        }
      };
      window.wallpaperRegisterPlaybackListener = window.wallpaperSetPlaybackStateListener;
      window.wallpaperPropertyListener = window.wallpaperPropertyListener || {
        applyUserProperties() {},
        setPaused() {},
        setPlaybackState() {},
        updateMediaProperties() {}
      };
      window.__myWallpaperApplyProperties = function(properties) {
        const safeProperties = properties || {};
        try {
          if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.applyUserProperties === 'function') {
            window.wallpaperPropertyListener.applyUserProperties(safeProperties);
          }
          if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaProperties === 'function') {
            window.wallpaperPropertyListener.updateMediaProperties(safeProperties);
          }
        } catch (_) {}
        for (const listener of mediaStatusListeners) {
          try { listener(safeProperties); } catch (_) {}
        }
        for (const listener of mediaPropertiesListeners) {
          try { listener(safeProperties); } catch (_) {}
        }
      };
      window.__myWallpaperPushAudioSpectrum = function(levels) {
        const safeLevels = Array.isArray(levels)
          ? levels.map((value) => {
              const numeric = Number(value);
              return Number.isFinite(numeric) ? numeric : 0;
            })
          : [];
        for (const listener of audioListeners) {
          try { listener(safeLevels); } catch (_) {}
        }
      };
      window.__myWallpaperSetGlobalVolume = function(value) {
        const volume = Math.max(0, Math.min(1, Number(value) || 0));
        const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
        for (const node of mediaNodes.concat(audioStreams)) {
          if (!node) continue;
          try { node.volume = volume; } catch (_) {}
        }
        for (const listener of volumeListeners) {
          try { listener(volume); } catch (_) {}
        }
      };
      window.__myWallpaperSetPaused = function(isPaused) {
        const paused = !!isPaused;
        window.wallpaperEngine_paused = paused;
        hostLogger.post('runtime.pause', paused ? 'true' : 'false');
        try {
          if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPaused === 'function') {
            window.wallpaperPropertyListener.setPaused(paused);
          }
          if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPlaybackState === 'function') {
            window.wallpaperPropertyListener.setPlaybackState(paused ? 'paused' : 'playing');
          }
        } catch (_) {}
        for (const listener of playbackStateListeners) {
          try { listener(paused); } catch (_) {}
        }
        const mediaNodes = Array.from(document.querySelectorAll('audio,video'));
        for (const node of mediaNodes.concat(audioStreams)) {
          if (!node) continue;
          try {
            if (paused) {
              node.pause();
            } else if (typeof node.play === 'function') {
              node.play().catch((error) => {
                hostLogger.post('media.play.error', error && error.message ? error.message : error);
              });
            }
          } catch (_) {}
        }
      };
    })();
    """#
}
