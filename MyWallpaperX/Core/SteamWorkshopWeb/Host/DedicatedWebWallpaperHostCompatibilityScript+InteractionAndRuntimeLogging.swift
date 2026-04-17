let webCompatibilityScriptInteractionAndRuntimeLogging = #"""
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
  ['warn', 'error'].forEach(wrapConsole);
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
  if (typeof window.fetch === 'function') {
    const originalFetch = window.fetch.bind(window);
    window.fetch = function(resource, init) {
      return originalFetch(resource, init).catch(error => {
        hostLogger.post('fetch.error', `${String(resource)} ${error && error.message ? error.message : error}`);
        throw error;
      });
    };
  }
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.__mwx_url = url;
    this.addEventListener('error', () => hostLogger.post('xhr.error', `${method} ${String(url)}`));
    this.addEventListener('loadend', () => {
      if (this.status >= 400 || this.status === 0) {
        hostLogger.post('xhr.status', `${method} ${String(url)} status=${this.status}`);
      }
    });
    return originalOpen.call(this, method, url, ...rest);
  };
"""#
