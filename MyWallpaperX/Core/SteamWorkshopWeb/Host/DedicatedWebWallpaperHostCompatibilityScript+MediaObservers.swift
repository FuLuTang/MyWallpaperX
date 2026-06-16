//
//  DedicatedWebWallpaperHostCompatibilityScript+MediaObservers.swift
//  MyWallpaperX
//

let webCompatibilityScriptMediaObservers = #"""
  document.addEventListener('DOMContentLoaded', () => {
    hostLogger.post('dom.ready', document.location.href);
    try {
      document.documentElement.style.width = '100%';
      document.documentElement.style.height = '100%';
      document.body && (document.body.style.width = '100%');
      document.body && (document.body.style.height = '100%');
    } catch (_) {}
    const registeredMediaNodes = new WeakSet();
    let loggedFirstMediaNode = false;
    let loggedFirstVideoCanPlay = false;
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
    Array.from(document.querySelectorAll('source')).forEach((sourceNode) => {
      const src = (sourceNode.getAttribute('src') || '').trim();
      if (!src) {
        hostLogger.post('resource.sanitized', `empty-source ${sourceNode.outerHTML}`);
        sourceNode.remove();
      }
    });
    if (typeof HTMLMediaElement !== 'undefined' && typeof HTMLMediaElement.prototype.play === 'function') {
      const _originalPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        const isInvalidMediaSource =
          typeof window.__myWallpaperIsInvalidMediaSourceValue === 'function'
            ? window.__myWallpaperIsInvalidMediaSourceValue
            : (value) => !String(value || '').trim();
        const mediaSrc = this.currentSrc || (this.getAttribute && this.getAttribute('src')) || this.src || '';
        let hasSrc = !!mediaSrc && !isInvalidMediaSource(mediaSrc);
        if (!hasSrc && typeof this.querySelectorAll === 'function') {
          try {
            hasSrc = Array.from(this.querySelectorAll('source')).some((sourceNode) => {
              const sourceValue = sourceNode.currentSrc || (sourceNode.getAttribute && sourceNode.getAttribute('src')) || sourceNode.src || '';
              return !!sourceValue && !isInvalidMediaSource(sourceValue);
            });
          } catch (_) {}
        }
        if (!hasSrc) {
          hostLogger.post('resource.sanitized', 'play() skipped: no src on media node');
          return Promise.resolve();
        }
        return _originalPlay.apply(this, arguments);
      };
    }
    const attachWallpaperMediaNode = (node) => {
      if (!node || registeredMediaNodes.has(node)) return;
      registeredMediaNodes.add(node);
      if (!loggedFirstMediaNode) {
        loggedFirstMediaNode = true;
        hostLogger.post('first-media-node-found', mediaStateSummary(node));
      }
      postMediaState('media.initial', node);
      node.addEventListener('error', () => {
        const error = node.error;
        const details = error ? `code=${error.code}` : 'unknown';
        hostLogger.post('media.error', `${mediaStateSummary(node)} ${details}`.trim());
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('stalled', () => {
        postMediaState('media.stalled', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('suspend', () => {
        postMediaState('media.suspend', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('waiting', () => {
        postMediaState('media.waiting', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('playing', () => {
        postMediaState('media.playing', node);
        wallpaperRefreshMediaState(node, false);
      });
      node.addEventListener('pause', () => {
        postMediaState('media.pause', node);
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('loadedmetadata', () => {
        postMediaState('media.loadedmetadata', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('loadeddata', () => {
        postMediaState('media.loadeddata', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('canplay', () => {
        if (!loggedFirstVideoCanPlay && String(node.tagName || '').toLowerCase() === 'video') {
          loggedFirstVideoCanPlay = true;
          hostLogger.post('first-video-canplay', mediaStateSummary(node));
        }
        postMediaState('media.canplay', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('canplaythrough', () => {
        postMediaState('media.canplaythrough', node);
        wallpaperRefreshMediaState(node);
      });
      node.addEventListener('ended', () => {
        postMediaState('media.ended', node);
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('emptied', () => {
        postMediaState('media.emptied', node);
        wallpaperRefreshMediaState(node, true);
      });
      node.addEventListener('durationchange', () => wallpaperRefreshMediaState(node));
      node.addEventListener('timeupdate', () => wallpaperDispatchMediaTimeline(node));
      node.addEventListener('play', () => {
        wallpaperMarkPreferredMediaNode(node);
        wallpaperDispatchMediaPlayback(node, false);
      });
      node.addEventListener('playing', () => {
        wallpaperMarkPreferredMediaNode(node);
        wallpaperDispatchMediaPlayback(node, false);
      });
      node.addEventListener('pause', () => wallpaperDispatchMediaPlayback(node, true));
      node.addEventListener('ended', () => wallpaperDispatchMediaPlayback(node, true));
      node.addEventListener('emptied', () => wallpaperRefreshMediaState(node, true));
      node.addEventListener('volumechange', () => wallpaperRefreshMediaState(node));
      node.addEventListener('ratechange', () => wallpaperRefreshMediaState(node));
      node.addEventListener('seeking', () => wallpaperRefreshMediaState(node));
      node.addEventListener('seeked', () => wallpaperRefreshMediaState(node));
      node.addEventListener('progress', () => wallpaperRefreshMediaState(node));
      node.addEventListener('loadstart', () => wallpaperRefreshMediaState(node));
    };
    const attachWallpaperMediaNodesFromRoot = (rootNode) => {
      if (!rootNode) return;
      const rootType = rootNode.nodeType;
      if (rootType === Node.DOCUMENT_FRAGMENT_NODE || rootType === Node.DOCUMENT_NODE) {
        if (rootNode.querySelectorAll) {
          rootNode.querySelectorAll('audio,video').forEach(attachWallpaperMediaNode);
          rootNode.querySelectorAll('iframe').forEach((element) => {
            try {
              const frameDocument = element.contentDocument;
              if (frameDocument) {
                attachWallpaperMediaNodesFromRoot(frameDocument);
              }
            } catch (_) {}
          });
        }
        return;
      }
      if (rootType !== Node.ELEMENT_NODE) return;
      if (rootNode.matches && rootNode.matches('audio,video')) {
        attachWallpaperMediaNode(rootNode);
      }
      if (rootNode.shadowRoot) {
        attachWallpaperMediaNodesFromRoot(rootNode.shadowRoot);
      }
      if (rootNode.tagName && String(rootNode.tagName).toLowerCase() === 'iframe') {
        try {
          const frameDocument = rootNode.contentDocument;
          if (frameDocument) {
            attachWallpaperMediaNodesFromRoot(frameDocument);
          }
        } catch (_) {}
      }
      if (rootNode.querySelectorAll) {
        rootNode.querySelectorAll('audio,video').forEach(attachWallpaperMediaNode);
        rootNode.querySelectorAll('iframe').forEach((element) => {
          try {
            const frameDocument = element.contentDocument;
            if (frameDocument) {
              attachWallpaperMediaNodesFromRoot(frameDocument);
            }
          } catch (_) {}
        });
      }
    };
"""#
