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
