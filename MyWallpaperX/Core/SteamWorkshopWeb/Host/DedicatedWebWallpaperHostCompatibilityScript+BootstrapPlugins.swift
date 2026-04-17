//
//  DedicatedWebWallpaperHostCompatibilityScript+BootstrapPlugins.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrapPlugins = #"""
  const loadedPluginNames = new Set();
  const pluginListeners = [];
  const wallpaperPluginStub = {
    supported: false,
    version: '0',
    isAvailable: () => false
  };
  const wallpaperCueStub = {
    supported: false,
    version: '0',
    isAvailable: () => false,
    getDeviceCount(callback) {
      try { if (typeof callback === 'function') callback(0); } catch (_) {}
      return 0;
    },
    getDeviceInfo(deviceIndex, callback) {
      const payload = {
        id: Number(deviceIndex || 0),
        index: Number(deviceIndex || 0),
        type: 'stub',
        model: 'unsupported',
        serial: '',
        ledCount: 0,
        leds: []
      };
      try {
        if (typeof callback === 'function') {
          callback(payload);
        }
      } catch (_) {}
      return payload;
    },
    getLedPositionsByDeviceIndex(deviceIndex, callback) {
      try { if (typeof callback === 'function') callback([]); } catch (_) {}
      return [];
    },
    getLedPositions(callback) {
      try { if (typeof callback === 'function') callback([]); } catch (_) {}
      return [];
    },
    setLedColorsByImageData() { return false; },
    setLedColorsByDeviceIndex() { return false; },
    setAllLedsColorsAsync() { return false; },
    setSync() { return false; }
  };
  window.cue = Object.assign({}, wallpaperCueStub, window.cue || {});
  window.wpPlugins = Object.assign(
    {},
    window.wpPlugins || {},
    {
      led: Object.assign({}, wallpaperPluginStub, window.wpPlugins && window.wpPlugins.led ? window.wpPlugins.led : {}),
      rgb: Object.assign({}, wallpaperPluginStub, window.wpPlugins && window.wpPlugins.rgb ? window.wpPlugins.rgb : {}),
      cue: Object.assign({}, wallpaperPluginStub, window.wpPlugins && window.wpPlugins.cue ? window.wpPlugins.cue : {})
    }
  );
  window.wallpaperPluginListener = window.wallpaperPluginListener || {
    onPluginLoaded() {}
  };
  window.wallpaperRegisterPluginListener = function(listener) {
    if (!listener || typeof listener.onPluginLoaded !== 'function') return;
    pluginListeners.push(listener);
    window.wallpaperPluginListener = listener;
    for (const pluginName of loadedPluginNames) {
      try { listener.onPluginLoaded(pluginName, '1'); } catch (_) {}
    }
  };
  window.__myWallpaperNotifyPluginLoaded = function(pluginName) {
    const safePluginName = String(pluginName || '').trim();
    if (!safePluginName) return;
    const notifyNames = new Set([safePluginName]);
    if (safePluginName === 'led' || safePluginName === 'rgb') {
      notifyNames.add('cue');
    }
    for (const loadedName of notifyNames) {
      loadedPluginNames.add(loadedName);
      if (loadedName === 'cue' || loadedName === 'led' || loadedName === 'rgb') {
        window.wpPlugins[loadedName] = Object.assign({}, wallpaperPluginStub, window.wpPlugins[loadedName] || {}, {
          supported: true,
          version: '1',
          isAvailable: () => true
        });
      }
    }
    const previousCue = window.cue || {};
    const previousCueIsAvailable = typeof previousCue.isAvailable === 'function' ? previousCue.isAvailable.bind(previousCue) : null;
    window.cue = Object.assign({}, wallpaperCueStub, previousCue, {
      supported: notifyNames.has('cue'),
      version: notifyNames.has('cue') ? '1' : String(previousCue.version || '0'),
      isAvailable: () => notifyNames.has('cue') || (previousCueIsAvailable ? previousCueIsAvailable() : false)
    });
    try {
      const allListeners = [];
      if (window.wallpaperPluginListener && typeof window.wallpaperPluginListener.onPluginLoaded === 'function') {
        allListeners.push(window.wallpaperPluginListener);
      }
      for (const listener of pluginListeners) {
        if (listener && typeof listener.onPluginLoaded === 'function' && allListeners.includes(listener) === false) {
          allListeners.push(listener);
        }
      }
      for (const loadedName of notifyNames) {
        for (const listener of allListeners) {
          try { listener.onPluginLoaded(loadedName, '1'); } catch (_) {}
        }
        window.dispatchEvent(new CustomEvent('wallpaper-plugin-loaded', { detail: loadedName }));
      }
    } catch (error) {
      hostLogger.post('plugin.listener.error', error && error.message ? error.message : error);
    }
  };
  window.wallpaperPropertyListener = window.wallpaperPropertyListener || {
    applyUserProperties() {},
    applyGeneralProperties() {},
    userDirectoryFilesAddedOrChanged() {},
    userDirectoryFilesRemoved() {},
    setPaused() {},
    setPlaybackState() {},
    updateMediaStatus() {},
    updateMediaProperties() {},
    updateMediaThumbnail() {},
    updateMediaTimeline() {},
    updateMediaPlayback() {}
  };
  window.wallpaperApplyUserProperties = function(properties) {
    window.__myWallpaperApplyProperties(properties || {});
  };
  window.wallpaperSetPaused = function(isPaused) {
    window.__myWallpaperSetPaused(!!isPaused);
  };
  window.wallpaperSetVolume = function(value) {
    window.__myWallpaperSetGlobalVolume(value);
  };
"""#
