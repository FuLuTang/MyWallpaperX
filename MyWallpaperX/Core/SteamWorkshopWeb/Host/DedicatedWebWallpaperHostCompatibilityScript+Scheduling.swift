let webCompatibilityScriptScheduling = #"""
  window.__myWallpaperRunAfterSettledFrames = function(callback) {
    if (typeof callback !== 'function') return;
    let completed = false;
    let fallbackTimer = null;
    const complete = () => {
      if (completed) return;
      completed = true;
      if (fallbackTimer !== null) {
        try { window.clearTimeout(fallbackTimer); } catch (_) {}
        fallbackTimer = null;
      }
      callback();
    };
    try {
      fallbackTimer = window.setTimeout(complete, 250);
      if (typeof window.requestAnimationFrame !== 'function') {
        window.setTimeout(complete, 0);
        return;
      }
      let framesRemaining = 2;
      const step = () => {
        if (framesRemaining <= 0) {
          window.setTimeout(complete, 0);
          return;
        }
        framesRemaining -= 1;
        window.requestAnimationFrame(step);
      };
      window.requestAnimationFrame(step);
    } catch (_) {
      complete();
    }
  };
"""#
