//
//  DedicatedWebWallpaperHostCompatibilityScript+BootstrapFoundation.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrapFoundation = #"""
  const audioStreams = [];
  const audioListeners = [];
  const volumeListeners = [];
  const mediaStatusListeners = [];
  const mediaPropertiesListeners = [];
  const mediaThumbnailListeners = [];
  const mediaTimelineListeners = [];
  const mediaPlaybackListeners = [];
  const playbackStateListeners = [];
  const audioContextInstances = new Set();
  const randomFileRequestTimeoutMS = 8000;
  const mediaPlaybackConstants = {
    PLAYBACK_STOPPED: 0,
    PLAYBACK_PLAYING: 1,
    PLAYBACK_PAUSED: 2
  };
  window.__myWallpaperIsMediaPlayAbortError = function(error) {
    const name = String((error && error.name) || '');
    const message = String((error && error.message) || error || '').toLowerCase();
    return name === 'AbortError' ||
      message.includes('operation was aborted') ||
      message.includes('interrupted by a call to pause') ||
      message.includes('interrupted by a new load request');
  };
  window.__myWallpaperIsOptionalAudioPlayError = function(error, node) {
    try {
      const tagName = String((node && node.tagName) || '').toLowerCase();
      if (tagName !== 'audio') return false;
      const name = String((error && error.name) || '');
      const message = String((error && error.message) || error || '').toLowerCase();
      const code = node && node.error ? Number(node.error.code || 0) : 0;
      return name === 'NotSupportedError' ||
        code === 4 ||
        message.includes('operation is not supported') ||
        message.includes('not supported');
    } catch (_) {
      return false;
    }
  };
  window.__myWallpaperWrapMediaPlayPromise = function(playResult, node) {
    if (!playResult || typeof playResult.catch !== 'function') return playResult;
    return playResult.catch((error) => {
      if (window.__myWallpaperIsMediaPlayAbortError(error)) {
        try {
          const tagName = node && node.tagName ? String(node.tagName).toLowerCase() : 'media';
          const source = node ? String(node.currentSrc || node.src || '').trim() : '';
          hostLogger.post('media.play.aborted', `${tagName} ${source}`.trim());
        } catch (_) {}
        return;
      }
      if (window.__myWallpaperIsOptionalAudioPlayError(error, node)) {
        try {
          const source = node ? String(node.currentSrc || node.src || '').trim() : '';
          hostLogger.post('media.play.unsupported', `audio ${source}`.trim());
        } catch (_) {}
        return;
      }
      throw error;
    });
  };
  window.wallpaperMediaIntegration = Object.assign(
    {},
    window.wallpaperMediaIntegration || {},
    mediaPlaybackConstants
  );
  window.__myWallpaperMediaState = {
    status: {
      enabled: false,
      available: 'false',
      state: mediaPlaybackConstants.PLAYBACK_STOPPED
    },
    properties: {
      title: '',
      artist: '',
      albumTitle: '',
      position: 0,
      duration: 0
    },
    thumbnail: { thumbnail: '' },
    timeline: { position: 0, duration: 0 },
    playback: { state: mediaPlaybackConstants.PLAYBACK_STOPPED }
  };
  window.__myWallpaperDirectoryState = window.__myWallpaperDirectoryState || {};
  window.__myWallpaperLastUserProperties = window.__myWallpaperInitialUserProperties || window.__myWallpaperLastUserProperties || {};
  window.__myWallpaperLastGeneralProperties = window.__myWallpaperInitialGeneralProperties || window.__myWallpaperLastGeneralProperties || {};
  window.wallpaperEngine_paused = !!window.__myWallpaperInitialPaused;
  let wallpaperPropertyListenerValue = window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener === 'object'
    ? window.wallpaperPropertyListener
    : {};
  const resumeAudioContexts = () => {
    const constructors = [window.AudioContext, window.webkitAudioContext].filter(Boolean);
    for (const Ctor of constructors) {
      try {
        if (!Ctor || !Ctor.prototype || typeof Ctor.prototype.resume !== 'function') continue;
        const originalResume = Ctor.prototype.resume;
        if (Ctor.prototype.__mwxResumeWrapped) continue;
        Ctor.prototype.__mwxResumeWrapped = true;
        Ctor.prototype.resume = function(...args) {
          try { audioContextInstances.add(this); } catch (_) {}
          return originalResume.apply(this, args).catch((error) => {
            hostLogger.post('audio.resume.error', error && error.message ? error.message : error);
            throw error;
          });
        };
      } catch (_) {}
    }
  };
  const wrapAudioContextConstructor = (name) => {
    try {
      const OriginalCtor = window[name];
      if (!OriginalCtor || OriginalCtor.__mwxConstructorWrapped) return;
      const WrappedCtor = function(...args) {
        const instance = new OriginalCtor(...args);
        try { audioContextInstances.add(instance); } catch (_) {}
        return instance;
      };
      WrappedCtor.prototype = OriginalCtor.prototype;
      Object.setPrototypeOf(WrappedCtor, OriginalCtor);
      WrappedCtor.__mwxConstructorWrapped = true;
      window[name] = WrappedCtor;
    } catch (_) {}
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
    const lastLogTimes = new Map();
    const noisyTypeIntervals = {
      'console.warn': 2000,
      'console.error': 500,
      'window.error': 500,
      'promise.rejection': 500,
      'resource.error': 2000,
      'resource.ignored': 5000,
      'fetch.error': 5000,
      'fetch.ignored': 5000,
      'xhr.error': 5000,
      'xhr.status': 5000,
      'media.error': 2000,
      'media.waiting': 2000,
      'media.stalled': 2000,
      'media.suspend': 2000,
      'media.playing': 1000,
      'media.pause': 1000,
      'media.loadedmetadata': 1000,
      'media.loadeddata': 1000,
      'media.canplay': 1000,
      'media.canplaythrough': 1000,
      'media.initial': 1000,
      'media.play.unsupported': 5000,
      'loader.pending': 1000,
      'iframe.crossOriginAccess': 5000,
      'backstretch.noop': 1000,
      'pointer.defer': 1000,
      'runtime.randomFile': 1000,
      'directory.access': 2000
    };
    return {
      post(type, message) {
        if (!handler || typeof handler.postMessage !== 'function') return;
        try {
          const normalizedType = String(type || '');
          const normalizedMessage = String(message ?? '').slice(0, 600);
          const interval = noisyTypeIntervals[normalizedType];
          if (interval) {
            const key = `${normalizedType}|${normalizedMessage}`;
            const now = Date.now();
            const lastTime = lastLogTimes.get(key) || 0;
            if ((now - lastTime) < interval) {
              return;
            }
            lastLogTimes.set(key, now);
            if (lastLogTimes.size > 300) {
              const staleBefore = now - 60000;
              for (const [entryKey, entryTime] of lastLogTimes.entries()) {
                if (entryTime < staleBefore) {
                  lastLogTimes.delete(entryKey);
                }
              }
            }
          }
          handler.postMessage({ type: normalizedType, message: normalizedMessage });
        } catch (_) {}
      }
    };
  })();
  resumeAudioContexts();
  wrapAudioContextConstructor('AudioContext');
  wrapAudioContextConstructor('webkitAudioContext');
  window.wallpaperEngine_mouseover = false;
  window.wallpaperEngine_cursor = { x: 0, y: 0, normalizedX: 0, normalizedY: 0, buttons: 0 };
  if (typeof window.updateCircleSize !== 'function') {
    window.updateCircleSize = function() {};
  }
  window.__myWallpaperInteractiveRegionState = {
    lastSignature: '',
    lastAutoRegisterAt: 0
  };
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
      try {
        listener(window.__myWallpaperMediaState.status);
      } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaPropertiesListener = function(listener) {
    if (typeof listener === 'function') {
      mediaPropertiesListeners.push(listener);
      try { listener(window.__myWallpaperMediaState.properties); } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaThumbnailListener = function(listener) {
    if (typeof listener === 'function') {
      mediaThumbnailListeners.push(listener);
      try { listener(window.__myWallpaperMediaState.thumbnail); } catch (_) {}
    }
  };
  window.wallpaperRegisterMediaTimelineListener = function(listener) {
    if (typeof listener === 'function') {
      mediaTimelineListeners.push(listener);
      try { listener(window.__myWallpaperMediaState.timeline); } catch (_) {}
    }
  };
  const replayWallpaperPropertyListenerState = function(options) {
    const replayOptions = options || {};
    try {
      if (document.readyState !== 'complete') {
        if (window.__myWallpaperDeferredPropertyReplayScheduled !== true) {
          window.__myWallpaperDeferredPropertyReplayScheduled = true;
          window.addEventListener('load', () => {
            window.__myWallpaperDeferredPropertyReplayScheduled = false;
            replayWallpaperPropertyListenerState(replayOptions);
          }, { once: true });
        }
        return;
      }
    } catch (_) {}
    if (replayOptions.includeUserProperties === true) {
      try {
        if (typeof window.__myWallpaperApplyProperties === 'function') {
          window.__myWallpaperApplyProperties(window.__myWallpaperLastUserProperties || {});
        } else if (typeof window.wallpaperPropertyListener.applyUserProperties === 'function') {
          window.wallpaperPropertyListener.applyUserProperties(window.__myWallpaperLastUserProperties || {});
        }
      } catch (_) {}
    }
    try {
      if (typeof window.__myWallpaperApplyGeneralProperties === 'function') {
        window.__myWallpaperApplyGeneralProperties(window.__myWallpaperLastGeneralProperties || {});
      } else if (typeof window.wallpaperPropertyListener.applyGeneralProperties === 'function') {
        window.wallpaperPropertyListener.applyGeneralProperties(window.__myWallpaperLastGeneralProperties || {});
      }
    } catch (_) {}
    try {
      if (typeof window.__myWallpaperApplyInitialPausedState === 'function') {
        window.__myWallpaperApplyInitialPausedState(!!window.wallpaperEngine_paused);
      } else if (window.wallpaperEngine_paused === true) {
        if (typeof window.wallpaperPropertyListener.setPaused === 'function') {
          window.wallpaperPropertyListener.setPaused(true);
        }
        if (typeof window.wallpaperPropertyListener.setPlaybackState === 'function') {
          window.wallpaperPropertyListener.setPlaybackState('paused');
        }
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaStatus === 'function') {
        window.wallpaperPropertyListener.updateMediaStatus(window.__myWallpaperMediaState.status);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaProperties === 'function') {
        window.wallpaperPropertyListener.updateMediaProperties(window.__myWallpaperMediaState.properties);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaThumbnail === 'function') {
        window.wallpaperPropertyListener.updateMediaThumbnail(window.__myWallpaperMediaState.thumbnail);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaTimeline === 'function') {
        window.wallpaperPropertyListener.updateMediaTimeline(window.__myWallpaperMediaState.timeline);
      }
    } catch (_) {}
    try {
      if (typeof window.wallpaperPropertyListener.updateMediaPlayback === 'function') {
        window.wallpaperPropertyListener.updateMediaPlayback(window.__myWallpaperMediaState.playback);
      }
    } catch (_) {}
    try {
      const directoryState = window.__myWallpaperDirectoryState || {};
      if (typeof window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged === 'function') {
        for (const [propertyName, files] of Object.entries(directoryState)) {
          const safeFiles = Array.isArray(files) ? files.map((value) => String(value || '')) : [];
          if (safeFiles.length > 0) {
            window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged(propertyName, safeFiles);
          }
        }
      }
    } catch (_) {}
  };
  const scheduleWallpaperPropertyListenerReplay = function() {
    try {
      if (window.__myWallpaperPropertyReplayQueued === true) return;
      window.__myWallpaperPropertyReplayQueued = true;
      const replay = () => {
        window.__myWallpaperPropertyReplayQueued = false;
        replayWallpaperPropertyListenerState({ includeUserProperties: true });
      };
      if (typeof window.requestAnimationFrame === 'function') {
        window.requestAnimationFrame(() => window.setTimeout(replay, 0));
      } else {
        window.setTimeout(replay, 0);
      }
    } catch (_) {
      try { replayWallpaperPropertyListenerState(); } catch (_) {}
    }
  };
  try {
    Object.defineProperty(window, 'wallpaperPropertyListener', {
      configurable: true,
      enumerable: true,
      get() {
        return wallpaperPropertyListenerValue;
      },
      set(value) {
        if (!value || typeof value !== 'object') return;
        wallpaperPropertyListenerValue = value;
        scheduleWallpaperPropertyListenerReplay();
      }
    });
  } catch (_) {
    window.wallpaperPropertyListener = wallpaperPropertyListenerValue;
  }
  window.wallpaperRegisterPropertyListener = function(listener) {
    if (!listener || typeof listener !== 'object') return;
    window.wallpaperPropertyListener = listener;
    scheduleWallpaperPropertyListenerReplay();
  };
  window.wallpaperSetPlaybackStateListener = function(listener) {
    if (typeof listener === 'function') {
      playbackStateListeners.push(listener);
      try {
        listener(!!window.wallpaperEngine_paused);
      } catch (_) {}
    }
  };
  window.wallpaperRegisterPlaybackListener = window.wallpaperSetPlaybackStateListener;
  window.wallpaperRegisterMediaPlaybackListener = function(listener) {
    if (typeof listener === 'function') {
      mediaPlaybackListeners.push(listener);
      try { listener(window.__myWallpaperMediaState.playback); } catch (_) {}
    }
  };
"""#
