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
      try {
        const sourceURL = source ? new URL(String(source), document.location.href) : null;
        const rawSource =
          target.getAttribute && tagName === 'IMG'
            ? String(target.getAttribute('src') || '').trim()
            : '';
        if (tagName === 'IMG' && (!rawSource || (sourceURL && sourceURL.href === document.location.href))) {
          hostLogger.post('resource.ignored', `${tagName} empty-src`);
          return;
        }
      } catch (_) {}
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
    const localCompanionResponse = (resource) => {
      try {
        const rawURL = resource && typeof resource === 'object' && 'url' in resource ? resource.url : resource;
        const url = new URL(String(rawURL || ''), document.location.href);
        const isLocalCompanion =
          (url.hostname === '127.0.0.1' || url.hostname === 'localhost') &&
          url.port === '5000';
        if (!isLocalCompanion) return null;
        const path = url.pathname.replace(/\/+$/, '') || '/';
        if (path === '/usage') {
          return new Response(JSON.stringify([0, 0, -1, 0, 0, 0]), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        if (path === '/notes' || path === '/shortcuts') {
          return new Response(JSON.stringify([]), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
          });
        }
        if (path === '/logs') {
          return new Response('', {
            status: 200,
            headers: { 'Content-Type': 'text/plain' }
          });
        }
      } catch (_) {}
      return null;
    };
    window.fetch = function(resource, init) {
      const method = String((init && init.method) || (resource && resource.method) || 'GET').toUpperCase();
      const rawURL = resource && typeof resource === 'object' && 'url' in resource ? resource.url : resource;
      const companionResponse = localCompanionResponse(resource);
      if (companionResponse) {
        hostLogger.post('fetch.compat', String(rawURL));
        return Promise.resolve(companionResponse);
      }
      return originalFetch(resource, init).catch(error => {
        try {
          const url = new URL(String(rawURL || ''), document.location.href);
          const localPath = url.pathname.replace(/^\/+/, '');
          if (method === 'HEAD' && localPath === 'performance.layout.user.js') {
            hostLogger.post('fetch.ignored', `${method} ${localPath} optional`);
            throw error;
          }
        } catch (urlError) {
          if (urlError !== error) {
            // Fall through to regular error logging when URL normalization fails.
          } else {
            throw error;
          }
        }
        hostLogger.post('fetch.error', `${String(rawURL)} ${error && error.message ? error.message : error}`);
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
