//
//  DedicatedWebWallpaperHostCompatibilityScript+MediaState.swift
//  MyWallpaperX
//

let webCompatibilityScriptMediaState = #"""
  const wallpaperMediaPropertiesPayload = (node) => {
    const fallbackTitle = wallpaperDocumentTitle();
    const mediaSource = node ? (node.currentSrc || node.src || '') : '';
    const sourceTitle = wallpaperFileStem(mediaSource);
    const mediaSession = wallpaperMediaSessionMetadata();
    const title = (mediaSession && mediaSession.title) || sourceTitle || fallbackTitle || '';
    const artist = (mediaSession && mediaSession.artist) || wallpaperDocumentMetaContent('meta[name="author"]') || '';
    const albumTitle =
      (mediaSession && mediaSession.album) ||
      (fallbackTitle && fallbackTitle !== title ? fallbackTitle : '');
    const position = node && Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0;
    const duration = node && Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0;
    return { title, artist, albumTitle, position, duration };
  };
  const wallpaperMediaThumbnailPayload = (node) => {
    const thumbnail = wallpaperMediaThumbnailURL(node);
    const source = node ? String(node.currentSrc || node.src || '') : '';
    const title = wallpaperFileStem(source) || wallpaperDocumentTitle() || '';
    return {
      thumbnail,
      source,
      title,
      available: thumbnail ? 'true' : 'false'
    };
  };
  const wallpaperMediaTimelinePayload = (node) => {
    const mediaSessionPosition = wallpaperMediaSessionPositionState();
    const position =
      mediaSessionPosition && Number.isFinite(Number(mediaSessionPosition.position))
        ? Number(mediaSessionPosition.position)
        : (node && Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0);
    const duration =
      mediaSessionPosition && Number.isFinite(Number(mediaSessionPosition.duration))
        ? Number(mediaSessionPosition.duration)
        : (node && Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0);
    const playbackRate =
      mediaSessionPosition && Number.isFinite(Number(mediaSessionPosition.playbackRate))
        ? Number(mediaSessionPosition.playbackRate)
        : (node && Number.isFinite(Number(node.playbackRate)) ? Number(node.playbackRate) : 1);
    return {
      position,
      duration,
      playbackRate,
      progress:
        Number.isFinite(duration) && duration > 0
          ? Math.max(0, Math.min(1, position / duration))
          : 0,
      available: Number.isFinite(duration) && duration > 0 ? 'true' : 'false'
    };
  };
  const wallpaperMediaSessionActionHandlers = () => {
    try {
      return navigator.mediaSession && navigator.mediaSession.__mwxActionHandlers
        ? navigator.mediaSession.__mwxActionHandlers
        : {};
    } catch (_) {
      return {};
    }
  };
  const wallpaperMediaPlaybackPayload = (node, pausedOverride) => {
    const mediaSession = wallpaperMediaSessionMetadata();
    const actionHandlers = wallpaperMediaSessionActionHandlers();
    const paused = typeof pausedOverride === 'boolean' ? pausedOverride : (node ? !!node.paused : true);
    const ended = node ? !!node.ended : false;
    const muted = node ? !!node.muted : false;
    const position = node && Number.isFinite(Number(node.currentTime)) ? Number(node.currentTime) : 0;
    const duration = node && Number.isFinite(Number(node.duration)) ? Number(node.duration) : 0;
    const rate = node && Number.isFinite(Number(node.playbackRate)) ? Number(node.playbackRate) : 1;
    let state = mediaPlaybackConstants.PLAYBACK_STOPPED;
    if (ended) {
      state = mediaPlaybackConstants.PLAYBACK_STOPPED;
    } else if (mediaSession && mediaSession.playbackState === 'playing') {
      state = mediaPlaybackConstants.PLAYBACK_PLAYING;
    } else if (mediaSession && mediaSession.playbackState === 'paused') {
      state = mediaPlaybackConstants.PLAYBACK_PAUSED;
    } else if (paused) {
      state = mediaPlaybackConstants.PLAYBACK_PAUSED;
    } else if (node) {
      state = mediaPlaybackConstants.PLAYBACK_PLAYING;
    }
    return {
      state,
      position,
      duration,
      rate,
      muted: muted ? 'true' : 'false',
      available: node ? 'true' : 'false',
      canPlay: actionHandlers.play ? 'true' : 'false',
      canPause: actionHandlers.pause ? 'true' : 'false',
      canSeekForward: actionHandlers.seekforward ? 'true' : 'false',
      canSeekBackward: actionHandlers.seekbackward ? 'true' : 'false'
    };
  };
  const wallpaperMediaSessionPositionState = () => {
    try {
      if (!navigator.mediaSession || typeof navigator.mediaSession.setPositionState !== 'function') {
        return null;
      }
      return navigator.mediaSession.__mwxPositionState || null;
    } catch (_) {
      return null;
    }
  };
  const wallpaperMediaStatusPayload = (node) => {
    const available = !!node;
    const playback = window.__myWallpaperMediaState && window.__myWallpaperMediaState.playback
      ? window.__myWallpaperMediaState.playback
      : null;
    const state = playback && playback.state ? playback.state : mediaPlaybackConstants.PLAYBACK_STOPPED;
    return {
      enabled: available,
      available: available ? 'true' : 'false',
      state
    };
  };
  const wallpaperDispatchMediaProperties = (node) => {
    const payload = wallpaperMediaPropertiesPayload(node);
    window.__myWallpaperMediaState.properties = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaProperties === 'function') {
        window.wallpaperPropertyListener.updateMediaProperties(payload);
      }
    } catch (error) {
      hostLogger.post('media.properties.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaPropertiesListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaStatus = (node) => {
    const payload = wallpaperMediaStatusPayload(node);
    window.__myWallpaperMediaState.status = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaStatus === 'function') {
        window.wallpaperPropertyListener.updateMediaStatus(payload);
      }
    } catch (error) {
      hostLogger.post('media.status.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaStatusListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaThumbnail = (node) => {
    const payload = wallpaperMediaThumbnailPayload(node);
    const hadThumbnail = wallpaperHasMediaThumbnail(window.__myWallpaperMediaState.thumbnail);
    const hasThumbnail = wallpaperHasMediaThumbnail(payload);
    window.__myWallpaperMediaState.thumbnail = payload;
    if (!hasThumbnail && !hadThumbnail) return;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaThumbnail === 'function') {
        window.wallpaperPropertyListener.updateMediaThumbnail(payload);
      }
    } catch (error) {
      hostLogger.post('media.thumbnail.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaThumbnailListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaTimeline = (node) => {
    const payload = wallpaperMediaTimelinePayload(node);
    window.__myWallpaperMediaState.timeline = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaTimeline === 'function') {
        window.wallpaperPropertyListener.updateMediaTimeline(payload);
      }
    } catch (error) {
      hostLogger.post('media.timeline.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaTimelineListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperDispatchMediaPlayback = (node, pausedOverride) => {
    const payload = wallpaperMediaPlaybackPayload(node, pausedOverride);
    window.__myWallpaperMediaState.playback = payload;
    try {
      if (window.wallpaperPropertyListener && typeof window.wallpaperPropertyListener.updateMediaPlayback === 'function') {
        window.wallpaperPropertyListener.updateMediaPlayback(payload);
      }
    } catch (error) {
      hostLogger.post('media.playback.error', error && error.message ? error.message : error);
    }
    for (const listener of mediaPlaybackListeners) {
      try { listener(payload); } catch (_) {}
    }
  };
  const wallpaperNotifyFullMediaState = (preferredNode, pausedOverride) => {
    const node = preferredNode || wallpaperPreferredMediaNode();
    wallpaperDispatchMediaStatus(node);
    wallpaperDispatchMediaProperties(node);
    wallpaperDispatchMediaThumbnail(node);
    wallpaperDispatchMediaTimeline(node);
    wallpaperDispatchMediaPlayback(node, pausedOverride);
  };
  const wallpaperQueueMediaRefresh = (() => {
    let scheduled = false;
    let pendingNode = null;
    let pendingPausedOverride = undefined;
    return (preferredNode, pausedOverride) => {
      if (preferredNode) {
        pendingNode = preferredNode;
      }
      if (typeof pausedOverride === 'boolean') {
        pendingPausedOverride = pausedOverride;
      }
      if (scheduled) return;
      scheduled = true;
      const flush = () => {
        scheduled = false;
        const nextNode = pendingNode;
        const nextPausedOverride = pendingPausedOverride;
        pendingNode = null;
        pendingPausedOverride = undefined;
        wallpaperNotifyFullMediaState(nextNode, nextPausedOverride);
      };
      if (typeof window.requestAnimationFrame === 'function') {
        window.requestAnimationFrame(flush);
      } else {
        window.setTimeout(flush, 0);
      }
    };
  })();
  const wallpaperRefreshMediaState = (preferredNode, pausedOverride) => {
    wallpaperQueueMediaRefresh(preferredNode, pausedOverride);
  };
"""#
