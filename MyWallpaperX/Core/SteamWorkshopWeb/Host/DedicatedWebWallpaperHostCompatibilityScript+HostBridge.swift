//
//  DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift
//  MyWallpaperX
//

let webCompatibilityScriptHostBridge = #"""
  window.__myWallpaperRegisterInteractiveRegions = function(payload) {
    try {
      const rawRegions = Array.isArray(payload && payload.regions) ? payload.regions : [];
      const safeRegions = rawRegions.map((region, index) => {
        const raw = region || {};
        const normalizeNumber = (value, fallback) => {
          const numeric = Number(value);
          if (!Number.isFinite(numeric)) return fallback;
          return Math.max(0, Math.min(1, numeric));
        };
        const width = normalizeNumber(raw.width, 0);
        const height = normalizeNumber(raw.height, 0);
        return {
          id: String(raw.id || `region-${index + 1}`),
          x: normalizeNumber(raw.x, 0),
          y: normalizeNumber(raw.y, 0),
          width,
          height,
          allowsClick: raw.allowsClick !== false,
          allowsDrag: raw.allowsDrag === true
        };
      }).filter((region) => region.width > 0 && region.height > 0);
      const messagePayload = {
        source: String((payload && payload.source) || 'page-script'),
        regions: safeRegions
      };
      try {
        window.webkit.messageHandlers.wallpaperHostInteractiveRegions.postMessage(messagePayload);
      } catch (error) {
        hostLogger.post('interactive-regions.post.error', error && error.message ? error.message : error);
      }
      try {
        window.dispatchEvent(new CustomEvent('wallpaper-interactive-regions-registered', { detail: messagePayload }));
      } catch (_) {}
      try {
        window.__myWallpaperInteractiveRegionState.lastSignature = safeRegions.map((region) => {
          return [region.id, region.x, region.y, region.width, region.height, region.allowsClick ? 1 : 0, region.allowsDrag ? 1 : 0].join(':');
        }).join('|');
        window.__myWallpaperInteractiveRegionState.lastAutoRegisterAt = Date.now();
      } catch (_) {}
    } catch (error) {
      hostLogger.post('interactive-regions.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperApplyProperties = function(properties) {
    const safeProperties = properties || {};
    window.__myWallpaperLastUserProperties = safeProperties;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.applyUserProperties === 'function') {
        window.wallpaperPropertyListener.applyUserProperties(safeProperties);
      }
      window.dispatchEvent(new CustomEvent('wallpaper-properties-applied', { detail: safeProperties }));
    } catch (error) {
      hostLogger.post('properties.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperApplyGeneralProperties = function(properties) {
    const safeProperties = properties || {};
    const normalizedProperties = {};
    try {
      for (const [key, rawValue] of Object.entries(safeProperties)) {
        if (rawValue && typeof rawValue === 'object' && Object.prototype.hasOwnProperty.call(rawValue, 'value')) {
          const boxedValue = Object.assign({}, rawValue);
          const scalarValue = rawValue.value;
          try {
            Object.defineProperty(boxedValue, 'valueOf', {
              configurable: true,
              enumerable: false,
              value() { return scalarValue; }
            });
          } catch (_) {}
          try {
            Object.defineProperty(boxedValue, 'toString', {
              configurable: true,
              enumerable: false,
              value() { return String(scalarValue); }
            });
          } catch (_) {}
          try {
            Object.defineProperty(boxedValue, Symbol.toPrimitive, {
              configurable: true,
              enumerable: false,
              value() { return scalarValue; }
            });
          } catch (_) {}
          normalizedProperties[key] = boxedValue;
        } else {
          normalizedProperties[key] = rawValue;
        }
      }
    } catch (_) {}
    window.__myWallpaperLastGeneralProperties = normalizedProperties;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.applyGeneralProperties === 'function') {
        window.wallpaperPropertyListener.applyGeneralProperties(normalizedProperties);
      }
      window.dispatchEvent(new CustomEvent('wallpaper-general-properties-applied', { detail: normalizedProperties }));
    } catch (error) {
      hostLogger.post('general-properties.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperNotifyDirectoryFilesChanged = function(propertyName, addedOrChangedFiles, removedFiles) {
    const safePropertyName = String(propertyName || '');
    const safeAddedOrChangedFiles = Array.isArray(addedOrChangedFiles) ? addedOrChangedFiles.map((value) => String(value || '')) : [];
    const safeRemovedFiles = Array.isArray(removedFiles) ? removedFiles.map((value) => String(value || '')) : [];
    try {
      const directoryState = window.__myWallpaperDirectoryState || {};
      const previousFiles = Array.isArray(directoryState[safePropertyName]) ? directoryState[safePropertyName] : [];
      const nextFiles = new Set(previousFiles.map((value) => String(value || '')));
      for (const path of safeAddedOrChangedFiles) {
        if (path) {
          nextFiles.add(path);
        }
      }
      for (const path of safeRemovedFiles) {
        nextFiles.delete(path);
      }
      directoryState[safePropertyName] = Array.from(nextFiles).sort();
      window.__myWallpaperDirectoryState = directoryState;
    } catch (_) {}
    try {
      if (
        safeAddedOrChangedFiles.length > 0 &&
        window.wallpaperPropertyListener &&
        typeof window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged === 'function'
      ) {
        window.wallpaperPropertyListener.userDirectoryFilesAddedOrChanged(
          safePropertyName,
          safeAddedOrChangedFiles
        );
      }
      if (
        safeRemovedFiles.length > 0 &&
        window.wallpaperPropertyListener &&
        typeof window.wallpaperPropertyListener.userDirectoryFilesRemoved === 'function'
      ) {
        window.wallpaperPropertyListener.userDirectoryFilesRemoved(
          safePropertyName,
          safeRemovedFiles
        );
      }
      window.dispatchEvent(new CustomEvent('wallpaper-directory-files-changed', {
        detail: {
          propertyName: safePropertyName,
          addedOrChangedFiles: safeAddedOrChangedFiles,
          removedFiles: safeRemovedFiles
        }
      }));
    } catch (error) {
      hostLogger.post('directory.notify.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperNotifyDirectoryAccessError = function(propertyName, errorMessage) {
    const safePropertyName = String(propertyName || '');
    const safeErrorMessage = String(errorMessage || '');
    try {
      if (safeErrorMessage) {
        const directoryState = window.__myWallpaperDirectoryState || {};
        if (Object.prototype.hasOwnProperty.call(directoryState, safePropertyName)) {
          delete directoryState[safePropertyName];
          window.__myWallpaperDirectoryState = directoryState;
        }
      }
      window.dispatchEvent(new CustomEvent('wallpaper-directory-access-error', {
        detail: {
          propertyName: safePropertyName,
          errorMessage: safeErrorMessage
        }
      }));
      hostLogger.post('directory.access', `${safePropertyName} ${safeErrorMessage || 'ok'}`.trim());
    } catch (error) {
      hostLogger.post('directory.access.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperPushAudioSpectrum = function(levels) {
    const safeLevels = Array.isArray(levels)
      ? levels.map((value) => {
          const numeric = Number(value);
          return Number.isFinite(numeric) ? numeric : 0;
        })
      : [];
    try {
      window.dispatchEvent(new CustomEvent('wallpaper-audio-spectrum', { detail: safeLevels }));
    } catch (_) {}
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
    try {
      window.dispatchEvent(new CustomEvent('wallpaper-volume-changed', { detail: volume }));
    } catch (_) {}
    for (const listener of volumeListeners) {
      try { listener(volume); } catch (_) {}
    }
  };
  window.__myWallpaperSetPaused = function(isPaused) {
    const paused = !!isPaused;
    window.wallpaperEngine_paused = paused;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPaused === 'function') {
        window.wallpaperPropertyListener.setPaused(paused);
      }
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.setPlaybackState === 'function') {
        window.wallpaperPropertyListener.setPlaybackState(paused ? 'paused' : 'playing');
      }
      window.dispatchEvent(new CustomEvent('wallpaper-pause-changed', { detail: paused }));
    } catch (error) {
      hostLogger.post('pause.error', error && error.message ? error.message : error);
    }
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
          const resolvedSource = String(node.currentSrc || node.src || '').trim();
          const normalizedSource = resolvedSource.toLowerCase();
          if (!resolvedSource || normalizedSource.endsWith('/null') || normalizedSource === 'null') {
            continue;
          }
          node.play().catch((error) => {
            hostLogger.post('media.play.error', error && error.message ? error.message : error);
          });
        }
      } catch (error) {
        hostLogger.post('media.control.error', error && error.message ? error.message : error);
      }
    }
    wallpaperDispatchMediaPlayback(wallpaperPreferredMediaNode(), paused);
  };
})();
"""#
