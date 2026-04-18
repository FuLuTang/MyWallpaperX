//
//  DedicatedWebWallpaperHostCompatibilityScript+BootstrapResourceRewriting.swift
//  MyWallpaperX
//

let webCompatibilityScriptBootstrapResourceRewriting = #"""
  window.__myWallpaperRewriteLocalFileURL = function(rawValue) {
    const value = String(rawValue || '').trim();
    const normalizedValue = value.toLowerCase();
    if (
      !value ||
      normalizedValue === 'null' ||
      normalizedValue === 'undefined' ||
      normalizedValue === '(null)' ||
      normalizedValue === 'about:blank'
    ) {
      return '';
    }
    if (value.startsWith('mwx-local://')) return value;
    if (!normalizedValue.startsWith('file:///')) return value;
    try {
      const parsed = new URL(value);
      const decodedPath = decodeURIComponent(parsed.pathname || '');
      const normalizedPath = decodedPath.startsWith('/') ? decodedPath : `/${decodedPath}`;
      const segments = normalizedPath
        .split('/')
        .filter(Boolean)
        .map((segment) => encodeURIComponent(segment));
      return `mwx-local://wallpaper/__absolute__/${segments.join('/')}`;
    } catch (_) {
      return value;
    }
  };
  const rewriteStyleValue = (value) => {
    const normalized = String(value || '');
    if (!normalized || normalized.toLowerCase().includes('file:///') === false) {
      return normalized;
    }
    return normalized.replace(/file:\/\/\/[^"')\s]+/gi, (match) => window.__myWallpaperRewriteLocalFileURL(match));
  };
  const patchURLBackedProperty = (prototype, propertyName) => {
    if (!prototype) return;
    try {
      const descriptor = Object.getOwnPropertyDescriptor(prototype, propertyName);
      if (!descriptor || typeof descriptor.set !== 'function' || prototype[`__mwxPatched_${propertyName}`]) return;
      Object.defineProperty(prototype, propertyName, {
        configurable: true,
        enumerable: descriptor.enumerable === true,
        get: descriptor.get ? function() { return descriptor.get.call(this); } : undefined,
        set: function(value) {
          descriptor.set.call(this, window.__myWallpaperRewriteLocalFileURL(value));
        }
      });
      prototype[`__mwxPatched_${propertyName}`] = true;
    } catch (_) {}
  };
  const patchStyleProperty = (propertyName) => {
    try {
      const prototype = window.CSSStyleDeclaration && window.CSSStyleDeclaration.prototype;
      if (!prototype) return;
      const descriptor = Object.getOwnPropertyDescriptor(prototype, propertyName);
      if (!descriptor || typeof descriptor.set !== 'function' || prototype[`__mwxPatched_${propertyName}`]) return;
      Object.defineProperty(prototype, propertyName, {
        configurable: true,
        enumerable: descriptor.enumerable === true,
        get: descriptor.get ? function() { return descriptor.get.call(this); } : undefined,
        set: function(value) {
          descriptor.set.call(this, rewriteStyleValue(value));
        }
      });
      prototype[`__mwxPatched_${propertyName}`] = true;
    } catch (_) {}
  };
  patchURLBackedProperty(window.HTMLImageElement && window.HTMLImageElement.prototype, 'src');
  patchURLBackedProperty(window.HTMLMediaElement && window.HTMLMediaElement.prototype, 'src');
  patchURLBackedProperty(window.HTMLSourceElement && window.HTMLSourceElement.prototype, 'src');
  patchURLBackedProperty(window.HTMLAnchorElement && window.HTMLAnchorElement.prototype, 'href');
  patchURLBackedProperty(window.HTMLLinkElement && window.HTMLLinkElement.prototype, 'href');
  patchURLBackedProperty(window.HTMLVideoElement && window.HTMLVideoElement.prototype, 'poster');
  patchStyleProperty('background');
  patchStyleProperty('backgroundImage');
  try {
    const originalSetAttribute = Element.prototype.setAttribute;
    if (typeof originalSetAttribute === 'function' && Element.prototype.__mwxSetAttributePatched !== true) {
      Element.prototype.setAttribute = function(name, value) {
        const normalizedName = String(name || '').toLowerCase();
        if (['src', 'href', 'poster'].includes(normalizedName)) {
          return originalSetAttribute.call(this, name, window.__myWallpaperRewriteLocalFileURL(value));
        }
        if (normalizedName === 'style') {
          return originalSetAttribute.call(this, name, rewriteStyleValue(value));
        }
        return originalSetAttribute.call(this, name, value);
      };
      Element.prototype.__mwxSetAttributePatched = true;
    }
  } catch (_) {}
  try {
    const sanitizePlaceholderMediaSources = () => {
      const nodes = Array.from(document.querySelectorAll('audio,video,source,link'));
      nodes.forEach((node) => {
        try {
          const attributesToNormalize = [];
          if (typeof node.getAttribute === 'function') {
            if (node.hasAttribute && node.hasAttribute('src')) {
              attributesToNormalize.push('src');
            }
            if (node.hasAttribute && node.hasAttribute('poster')) {
              attributesToNormalize.push('poster');
            }
          }
          attributesToNormalize.forEach((attributeName) => {
            const current = node.getAttribute(attributeName);
            if (current == null) return;
            const rewritten = window.__myWallpaperRewriteLocalFileURL(current);
            if (rewritten === current) return;
            if (!rewritten) {
              node.removeAttribute(attributeName);
              if (attributeName in node) {
                try { node[attributeName] = ''; } catch (_) {}
              }
              return;
            }
            if (typeof node.setAttribute === 'function') {
              node.setAttribute(attributeName, rewritten);
            }
          });
        } catch (_) {}
      });
    };
    sanitizePlaceholderMediaSources();
    document.addEventListener('DOMContentLoaded', sanitizePlaceholderMediaSources, { once: true });
  } catch (_) {}
  try {
    const prototype = window.CSSStyleDeclaration && window.CSSStyleDeclaration.prototype;
    const originalSetProperty = prototype && prototype.setProperty;
    if (typeof originalSetProperty === 'function' && prototype.__mwxSetPropertyPatched !== true) {
      prototype.setProperty = function(name, value, priority) {
        return originalSetProperty.call(this, name, rewriteStyleValue(value), priority);
      };
      prototype.__mwxSetPropertyPatched = true;
    }
  } catch (_) {}
  const normalizeLegacyBodyBackgrounds = () => {
    try {
      if (!document.body || !document.body.style) return;
      const currentBackground = String(document.body.style.background || '');
      const currentBackgroundImage = String(document.body.style.backgroundImage || '');
      const normalizedBackground = rewriteStyleValue(currentBackground);
      const normalizedBackgroundImage = rewriteStyleValue(currentBackgroundImage);
      if (normalizedBackground !== currentBackground) {
        document.body.style.background = normalizedBackground;
      }
      if (normalizedBackgroundImage !== currentBackgroundImage) {
        document.body.style.backgroundImage = normalizedBackgroundImage;
      }
    } catch (_) {}
  };
  const installLegacyBackgroundFunctionWrappers = () => {
    try {
      const wrapNamedFunction = (name) => {
        const original = window[name];
        if (typeof original !== 'function' || original.__mwxBackgroundWrapped) {
          return;
        }
        const wrapped = function(...args) {
          const result = original.apply(this, args);
          normalizeLegacyBodyBackgrounds();
          return result;
        };
        wrapped.__mwxBackgroundWrapped = true;
        window[name] = wrapped;
      };
      wrapNamedFunction('shouldShow');
      wrapNamedFunction('changeBackground');
      wrapNamedFunction('TransitionSwith');
    } catch (_) {}
  };
  installLegacyBackgroundFunctionWrappers();
  try { window.addEventListener('DOMContentLoaded', installLegacyBackgroundFunctionWrappers, { once: true }); } catch (_) {}
  try { window.addEventListener('load', installLegacyBackgroundFunctionWrappers, { once: true }); } catch (_) {}
  try { setTimeout(installLegacyBackgroundFunctionWrappers, 0); } catch (_) {}
  try { setTimeout(installLegacyBackgroundFunctionWrappers, 250); } catch (_) {}
  const randomFileCallbacks = new Map();
  const randomFileTimeouts = new Map();
  window.__myWallpaperResolveRandomFile = function(requestID, value) {
    try {
      const normalizedRequestID = String(requestID);
      const callback = randomFileCallbacks.get(normalizedRequestID);
      const timeoutID = randomFileTimeouts.get(normalizedRequestID);
      if (timeoutID) {
        try { window.clearTimeout(timeoutID); } catch (_) {}
        randomFileTimeouts.delete(normalizedRequestID);
      }
      if (typeof callback === 'function') {
        callback(String(value || ''));
      }
      randomFileCallbacks.delete(normalizedRequestID);
    } catch (_) {}
  };
  window.wallpaperRequestRandomFileForProperty = function(propertyName, callback) {
    let requestID = '';
    try {
      requestID = `req_${Date.now()}_${Math.random().toString(36).slice(2)}`;
      if (typeof callback === 'function') {
        randomFileCallbacks.set(requestID, callback);
        const timeoutID = window.setTimeout(() => {
          const pendingCallback = randomFileCallbacks.get(requestID);
          randomFileCallbacks.delete(requestID);
          randomFileTimeouts.delete(requestID);
          if (typeof pendingCallback === 'function') {
            try { pendingCallback(''); } catch (_) {}
          }
        }, randomFileRequestTimeoutMS);
        randomFileTimeouts.set(requestID, timeoutID);
      }
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallpaperHostRandomFile;
      if (handler && typeof handler.postMessage === 'function') {
        handler.postMessage({
          requestID,
          propertyName: String(propertyName || '')
        });
      } else if (typeof callback === 'function') {
        randomFileCallbacks.delete(requestID);
        const timeoutID = randomFileTimeouts.get(requestID);
        if (timeoutID) {
          try { window.clearTimeout(timeoutID); } catch (_) {}
          randomFileTimeouts.delete(requestID);
        }
        callback('');
      }
      hostLogger.post('runtime.randomFile', String(propertyName || 'unknown'));
    } catch (_) {
      if (requestID) {
        randomFileCallbacks.delete(requestID);
        const timeoutID = randomFileTimeouts.get(requestID);
        if (timeoutID) {
          try { window.clearTimeout(timeoutID); } catch (_) {}
          randomFileTimeouts.delete(requestID);
        }
      }
      if (typeof callback === 'function') {
        callback('');
      }
    }
  };
  const updateCursorState = (event) => {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const x = Number(event && typeof event.clientX === 'number' ? event.clientX : 0);
      const y = Number(event && typeof event.clientY === 'number' ? event.clientY : 0);
      window.wallpaperEngine_cursor = {
        x,
        y,
        normalizedX: x / width,
        normalizedY: y / height,
        buttons: Number(event && typeof event.buttons === 'number' ? event.buttons : 0)
      };
      window.wallpaperEngine_mouseover = true;
    } catch (_) {}
  };
"""#
