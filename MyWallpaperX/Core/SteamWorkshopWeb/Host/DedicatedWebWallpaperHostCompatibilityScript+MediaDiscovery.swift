//
//  DedicatedWebWallpaperHostCompatibilityScript+MediaDiscovery.swift
//  MyWallpaperX
//

let webCompatibilityScriptMediaDiscovery = #"""
  const decodeWallpaperURLComponent = (value) => {
    try {
      return decodeURIComponent(String(value || ''));
    } catch (_) {
      return String(value || '');
    }
  };
  const wallpaperFileStem = (value) => {
    const raw = decodeWallpaperURLComponent(String(value || ''));
    const fileName = raw.split('/').pop() || '';
    const withoutSuffix = fileName.split('?')[0].split('#')[0];
    const lastDot = withoutSuffix.lastIndexOf('.');
    return lastDot > 0 ? withoutSuffix.slice(0, lastDot) : withoutSuffix;
  };
  const wallpaperMediaNodes = () => {
    const result = [];
    const visitedRoots = new WeakSet();
    const collectFromRoot = (root) => {
      if (!root || visitedRoots.has(root)) return;
      visitedRoots.add(root);
      try {
        if (root.querySelectorAll) {
          root.querySelectorAll('audio,video').forEach((node) => result.push(node));
          root.querySelectorAll('*').forEach((element) => {
            if (element && element.shadowRoot) {
              collectFromRoot(element.shadowRoot);
            }
            if (element && element.tagName && String(element.tagName).toLowerCase() === 'iframe') {
              try {
                const frameDocument = element.contentDocument;
                if (frameDocument) {
                  collectFromRoot(frameDocument);
                }
              } catch (_) {}
            }
          });
        }
      } catch (_) {}
    };
    collectFromRoot(document);
    return result;
  };
  const wallpaperImmediateMediaNodes = () => {
    try {
      return Array.from(document.querySelectorAll('audio,video'));
    } catch (_) {
      return [];
    }
  };
  const wallpaperMediaNodeScore = (node) => {
    if (!node) return -1;
    let score = 0;
    try {
      if (!node.paused && !node.ended) score += 1000;
    } catch (_) {}
    try {
      if (node.__myWallpaperPreferredCandidate) score += 800;
    } catch (_) {}
    try {
      if (document.activeElement === node) score += 250;
    } catch (_) {}
    try {
      if (Number.isFinite(Number(node.currentTime)) && Number(node.currentTime) > 0) score += 300;
    } catch (_) {}
    try {
      if (Number.isFinite(Number(node.duration)) && Number(node.duration) > 0) score += 250;
    } catch (_) {}
    try {
      if (typeof node.readyState === 'number') score += Math.max(0, Number(node.readyState)) * 25;
    } catch (_) {}
    try {
      if (typeof node.networkState === 'number' && Number(node.networkState) === 1) score += 40;
    } catch (_) {}
    try {
      if (node.currentSrc || node.src) score += 120;
    } catch (_) {}
    try {
      if (node.poster) score += 40;
    } catch (_) {}
    try {
      if (node.muted === false) score += 15;
    } catch (_) {}
    try {
      if ((node.tagName || '').toLowerCase() === 'video') score += 20;
    } catch (_) {}
    return score;
  };
  const wallpaperMarkPreferredMediaNode = (node) => {
    wallpaperMediaNodes().forEach((candidate) => {
      try {
        candidate.__myWallpaperPreferredCandidate = candidate === node;
      } catch (_) {}
    });
  };
  const wallpaperPreferredMediaNode = () => {
    const nodes = wallpaperMediaNodes();
    if (nodes.length === 0) return null;
    let bestNode = nodes[0];
    let bestScore = wallpaperMediaNodeScore(bestNode);
    for (const node of nodes.slice(1)) {
      const score = wallpaperMediaNodeScore(node);
      if (score > bestScore) {
        bestNode = node;
        bestScore = score;
      }
    }
    wallpaperMarkPreferredMediaNode(bestNode);
    return bestNode;
  };
  const wallpaperFrameDocuments = () => {
    const result = [];
    try {
      document.querySelectorAll('iframe').forEach((frame) => {
        try {
          const frameDocument = frame.contentDocument;
          if (frameDocument) {
            result.push(frameDocument);
          }
        } catch (_) {}
      });
    } catch (_) {}
    return result;
  };
  const wallpaperDocumentTitle = () => {
    const titles = [];
    try {
      if (document.title) titles.push(String(document.title).trim());
    } catch (_) {}
    wallpaperFrameDocuments().forEach((frameDocument) => {
      try {
        if (frameDocument.title) titles.push(String(frameDocument.title).trim());
      } catch (_) {}
    });
    return titles.find((value) => value) || '';
  };
  const wallpaperDocumentMetaContent = (selector) => {
    const values = [];
    const readFromDocument = (targetDocument) => {
      try {
        const node = targetDocument.querySelector(selector);
        const content = node && node.getAttribute ? node.getAttribute('content') : '';
        const normalized = String(content || '').trim();
        if (normalized) values.push(normalized);
      } catch (_) {}
    };
    readFromDocument(document);
    wallpaperFrameDocuments().forEach(readFromDocument);
    return values.find((value) => value) || '';
  };
  const wallpaperMediaSessionMetadata = () => {
    try {
      const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
      const playbackState = navigator.mediaSession && typeof navigator.mediaSession.playbackState === 'string'
        ? String(navigator.mediaSession.playbackState).trim()
        : '';
      if (!metadata) {
        return playbackState ? { title: '', artist: '', album: '', artwork: [], playbackState } : null;
      }
      const artwork = Array.isArray(metadata.artwork) ? metadata.artwork : [];
      return {
        title: String(metadata.title || '').trim(),
        artist: String(metadata.artist || '').trim(),
        album: String(metadata.album || '').trim(),
        artwork: artwork
          .map((item) => (item && item.src ? String(item.src).trim() : ''))
          .filter(Boolean),
        playbackState
      };
    } catch (_) {
      return null;
    }
  };
  const wallpaperMediaThumbnailURL = (node) => {
    const mediaSession = wallpaperMediaSessionMetadata();
    if (mediaSession && mediaSession.artwork.length > 0) {
      return mediaSession.artwork[0];
    }
    if (!node) return '';
    try {
      if (typeof node.poster === 'string' && node.poster.trim()) return node.poster.trim();
    } catch (_) {}
    try {
      const attributePoster = node.getAttribute && node.getAttribute('poster');
      if (attributePoster && String(attributePoster).trim()) return String(attributePoster).trim();
    } catch (_) {}
    try {
      const dataThumbnail = node.getAttribute && node.getAttribute('data-thumbnail');
      if (dataThumbnail && String(dataThumbnail).trim()) return String(dataThumbnail).trim();
    } catch (_) {}
    const metaThumbnail =
      wallpaperDocumentMetaContent('meta[property="og:image"]') ||
      wallpaperDocumentMetaContent('meta[name="twitter:image"]') ||
      wallpaperDocumentMetaContent('meta[name="thumbnail"]');
    if (metaThumbnail) return metaThumbnail;
    return '';
  };
"""#
