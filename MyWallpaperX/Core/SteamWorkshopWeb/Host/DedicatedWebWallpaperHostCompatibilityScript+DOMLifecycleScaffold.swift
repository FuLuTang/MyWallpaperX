let webCompatibilityScriptDOMLifecycleScaffold = #"""
    const wallpaperEnsureHostScaffold = (() => {
      const generatedMarker = 'data-mwx-host-generated';
      const ensureWindowTopBarForElement = (element) => {
        if (!element || !element.classList || !element.classList.contains('wrapper')) return;
        if (element.querySelector(':scope > .windowTopBar')) return;
        const topBar = document.createElement('div');
        topBar.className = 'windowTopBar';
        topBar.setAttribute(generatedMarker, 'windowTopBar');
        topBar.style.display = 'none';
        topBar.style.pointerEvents = 'none';
        topBar.style.userSelect = 'none';
        topBar.style.webkitUserSelect = 'none';

        const buttons = document.createElement('div');
        buttons.className = 'windowTopBarButtons';
        buttons.setAttribute(generatedMarker, 'windowTopBarButtons');

        for (let index = 0; index < 3; index += 1) {
          const button = document.createElement('span');
          button.className = 'windowTopBarButton';
          button.setAttribute(generatedMarker, `windowTopBarButton-${index + 1}`);
          buttons.appendChild(button);
        }

        topBar.appendChild(buttons);
        element.insertBefore(topBar, element.firstChild || null);
        const spacer = document.createElement('br');
        spacer.className = 'windowTopBarBR';
        spacer.setAttribute(generatedMarker, 'windowTopBarBR');
        spacer.style.display = 'none';
        element.insertBefore(spacer, topBar.nextSibling || element.firstChild || null);
      };
      const install = (root) => {
        const scope = root && typeof root.querySelectorAll === 'function' ? root : document;
        try {
          if (scope === document && document.body && document.body.classList && document.body.classList.contains('wrapper')) {
            ensureWindowTopBarForElement(document.body);
          }
          Array.from(scope.querySelectorAll('.wrapper')).forEach(ensureWindowTopBarForElement);
        } catch (_) {}
      };
      return { install };
    })();
    const wallpaperEnsureOptionalSliderControls = (() => {
      const generatedMarker = 'data-mwx-host-generated';
      const makeButton = (className) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = className;
        button.hidden = true;
        button.setAttribute(generatedMarker, className);
        button.style.display = 'none';
        button.style.pointerEvents = 'none';
        return button;
      };
      const ensureContainer = (container) => {
        if (!container || typeof container.querySelector !== 'function') return;
        if (!container.querySelector('.slider')) return;
        if (!container.querySelector('.prev-button')) {
          container.appendChild(makeButton('prev-button'));
        }
        if (!container.querySelector('.next-button')) {
          container.appendChild(makeButton('next-button'));
        }
      };
      const install = (root) => {
        const scope = root && typeof root.querySelectorAll === 'function' ? root : document;
        try {
          Array.from(scope.querySelectorAll('.slider-container')).forEach(ensureContainer);
        } catch (_) {}
      };
      return { install };
    })();
    try {
      const originalQuerySelector = Element.prototype.querySelector;
      if (typeof originalQuerySelector === 'function' && Element.prototype.__mwxSliderQueryGuardPatched !== true) {
        Element.prototype.querySelector = function(selector) {
          const result = originalQuerySelector.call(this, selector);
          if (
            result == null &&
            (selector === '.prev-button' || selector === '.next-button') &&
            this &&
            this.classList &&
            this.classList.contains('slider-container') &&
            originalQuerySelector.call(this, '.slider')
          ) {
            const className = selector.slice(1);
            const button = document.createElement('button');
            button.type = 'button';
            button.className = className;
            button.hidden = true;
            button.setAttribute('data-mwx-host-generated', className);
            button.style.display = 'none';
            button.style.pointerEvents = 'none';
            this.appendChild(button);
            return button;
          }
          return result;
        };
        Element.prototype.__mwxSliderQueryGuardPatched = true;
      }
    } catch (_) {}
    try {
      const originalAddEventListener = EventTarget.prototype.addEventListener;
      if (typeof originalAddEventListener === 'function' && EventTarget.prototype.__mwxDOMReadyGuardPatched !== true) {
        EventTarget.prototype.addEventListener = function(type, listener, options) {
          if (
            String(type || '') === 'DOMContentLoaded' &&
            typeof listener === 'function' &&
            (this === document || this === window)
          ) {
            const wrappedListener = function(event) {
              try { wallpaperEnsureOptionalSliderControls.install(document); } catch (_) {}
              return listener.call(this, event);
            };
            try { Object.defineProperty(wrappedListener, 'name', { value: listener.name || 'mwxDOMContentLoadedListener' }); } catch (_) {}
            return originalAddEventListener.call(this, type, wrappedListener, options);
          }
          return originalAddEventListener.call(this, type, listener, options);
        };
        EventTarget.prototype.__mwxDOMReadyGuardPatched = true;
      }
    } catch (_) {}
    try {
      document.addEventListener('DOMContentLoaded', () => {
        wallpaperEnsureOptionalSliderControls.install(document);
      }, { once: true, capture: true });
    } catch (_) {}
    const wallpaperScheduleDeferredDOMBootstrap = (() => {
      let scheduled = false;
      return () => {
        if (scheduled) return;
        scheduled = true;
        const bootstrap = () => {
          const installFrameBindings = (element) => {
            if (!element || !element.tagName || String(element.tagName).toLowerCase() !== 'iframe') return;
            try {
              const frameWindow = element.contentWindow;
              if (frameWindow && frameWindow.__mwxLoadListenerInstalled !== true) {
                frameWindow.__mwxLoadListenerInstalled = true;
                frameWindow.addEventListener('load', () => {
                  try {
                    const nextFrameDocument = element.contentDocument;
                    if (nextFrameDocument) {
                      attachWallpaperMediaNodesFromRoot(nextFrameDocument);
                      wallpaperScheduleLifecycleRefresh();
                      wallpaperScheduleInteractiveRegionRefresh();
                    }
                  } catch (_) {}
                });
              }
            } catch (_) {}
          };
          const installShadowObserversFromDocument = () => {
            try {
              Array.from(document.querySelectorAll('audio,video,iframe,[data-wallpaper],canvas')).forEach((element) => {
                if (element && element.shadowRoot) {
                  installWallpaperShadowObserver(element.shadowRoot);
                }
                installFrameBindings(element);
              });
            } catch (_) {}
          };
          installShadowObserversFromDocument();
          wallpaperEnsureHostScaffold.install(document);
          wallpaperEnsureOptionalSliderControls.install(document);
          wallpaperRefreshMediaState();
          wallpaperScheduleInteractiveRegionRefresh();
        };
        if (typeof window.requestIdleCallback === 'function') {
          window.requestIdleCallback(bootstrap, { timeout: 1500 });
        } else {
          window.setTimeout(bootstrap, 1200);
        }
      };
    })();
"""#
