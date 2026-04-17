let webCompatibilityScriptInteractionAndRuntimePointer = #"""
  window.__myWallpaperState = window.__myWallpaperState || { captureTarget: null, captureButtons: 0, hoverTarget: null };
  window.__myWallpaperUpdateHoverTarget = function(nextTarget, mouseEventInit) {
    const wallpaperState = window.__myWallpaperState || (window.__myWallpaperState = { captureTarget: null, captureButtons: 0, hoverTarget: null });
    const previousTarget = wallpaperState.hoverTarget;
    if (previousTarget === nextTarget) {
      return;
    }
    if (previousTarget && typeof MouseEvent === 'function') {
      try {
        previousTarget.dispatchEvent(new MouseEvent('mouseout', { ...mouseEventInit, bubbles: true, cancelable: true, composed: true, relatedTarget: nextTarget || null }));
        previousTarget.dispatchEvent(new MouseEvent('mouseleave', { ...mouseEventInit, bubbles: false, cancelable: false, composed: true, relatedTarget: nextTarget || null }));
      } catch (_) {}
    }
    wallpaperState.hoverTarget = nextTarget || null;
    if (nextTarget && typeof MouseEvent === 'function') {
      try {
        nextTarget.dispatchEvent(new MouseEvent('mouseover', { ...mouseEventInit, bubbles: true, cancelable: true, composed: true, relatedTarget: previousTarget || null }));
        nextTarget.dispatchEvent(new MouseEvent('mouseenter', { ...mouseEventInit, bubbles: false, cancelable: false, composed: true, relatedTarget: previousTarget || null }));
      } catch (_) {}
    }
  };
  const mouseEventInitBase = function(clientX, clientY, buttonValue, buttonsValue) {
    return {
      bubbles: true,
      cancelable: true,
      composed: true,
      clientX,
      clientY,
      button: buttonValue,
      buttons: buttonsValue,
      view: window
    };
  };
  const enrichMouseLikeEvent = function(event, target, clientX, clientY) {
    if (!event || !target || typeof Object.defineProperty !== 'function') {
      return event;
    }
    try {
      const rect = typeof target.getBoundingClientRect === 'function'
        ? target.getBoundingClientRect()
        : { left: 0, top: 0 };
      const offsetX = clientX - Number(rect.left || 0);
      const offsetY = clientY - Number(rect.top || 0);
      const pageX = clientX + (window.scrollX || 0);
      const pageY = clientY + (window.scrollY || 0);
      const define = (name, value) => {
        try {
          Object.defineProperty(event, name, {
            configurable: true,
            enumerable: true,
            get() { return value; }
          });
        } catch (_) {}
      };
      define('offsetX', offsetX);
      define('offsetY', offsetY);
      define('pageX', pageX);
      define('pageY', pageY);
      define('x', clientX);
      define('y', clientY);
    } catch (_) {}
    return event;
  };
  window.__myWallpaperDispatchMouseEvent = function(type, normalizedX, normalizedY, button, buttons, pointerId) {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const safeX = Math.max(0, Math.min(1, Number(normalizedX || 0)));
      const safeY = Math.max(0, Math.min(1, Number(normalizedY || 0)));
      const clientX = safeX * width;
      const clientY = safeY * height;
      const buttonValue = Number(button || 0);
      const buttonsValue = Number(buttons || 0);
      const pointerIdValue = Math.max(1, Number(pointerId || 1));
      const wallpaperState = window.__myWallpaperState || (window.__myWallpaperState = { captureTarget: null, captureButtons: 0 });
      let target = wallpaperState.captureTarget || document.elementFromPoint(clientX, clientY) || document.body || document.documentElement;
      if (!target) return;
      window.__myWallpaperUpdateHoverTarget(target, mouseEventInitBase(clientX, clientY, buttonValue, buttonsValue));
      const pointerLikeTypes = new Set(['pointermove', 'pointerdown', 'pointerup', 'pointercancel']);
      const pointerToMouseType = { 'pointerdown': 'mousedown', 'pointerup': 'mouseup', 'pointermove': 'mousemove', 'pointercancel': 'mouseleave' };
      const mouseEventInit = mouseEventInitBase(clientX, clientY, buttonValue, buttonsValue);
      let pointerEvent = null;
      if (pointerLikeTypes.has(String(type)) && typeof PointerEvent === 'function') {
        pointerEvent = new PointerEvent(String(type), {
          ...mouseEventInit,
          pointerId: pointerIdValue,
          pointerType: 'mouse',
          isPrimary: true
        });
      } else if (typeof MouseEvent === 'function') {
        pointerEvent = new MouseEvent(String(type), mouseEventInit);
      }
      if (pointerEvent) {
        enrichMouseLikeEvent(pointerEvent, target, clientX, clientY);
        target.dispatchEvent(pointerEvent);
      }
      if (String(type) === 'pointerdown' && buttonsValue !== 0) {
        wallpaperState.captureTarget = target;
        wallpaperState.captureButtons = buttonsValue;
        if (target && typeof target.setPointerCapture === 'function' && pointerEvent && typeof pointerEvent.pointerId === 'number') {
          try { target.setPointerCapture(pointerEvent.pointerId); } catch (_) {}
        }
        if (target && typeof DragEvent === 'function') {
          try {
            const dragStartEvent = new DragEvent('dragstart', {
              bubbles: true,
              cancelable: true,
              composed: true,
              clientX,
              clientY
            });
            target.dispatchEvent(dragStartEvent);
          } catch (_) {}
        }
      }
      const mouseTypeName = pointerToMouseType[String(type)];
      if (String(type) === 'pointermove' && wallpaperState.captureTarget && typeof DragEvent === 'function') {
        try {
          const dragOverEvent = new DragEvent('dragover', {
            bubbles: true,
            cancelable: true,
            composed: true,
            clientX,
            clientY
          });
          wallpaperState.captureTarget.dispatchEvent(dragOverEvent);
          const dragEvent = new DragEvent('drag', {
            bubbles: true,
            cancelable: true,
            composed: true,
            clientX,
            clientY
          });
          wallpaperState.captureTarget.dispatchEvent(dragEvent);
        } catch (_) {}
      }
      if (mouseTypeName && typeof MouseEvent === 'function') {
        const mouseEvent = enrichMouseLikeEvent(new MouseEvent(mouseTypeName, mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(mouseEvent);
      }
      if (String(type) === 'pointerup' && buttonValue === 0 && typeof MouseEvent === 'function') {
        const clickEvent = enrichMouseLikeEvent(new MouseEvent('click', mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(clickEvent);
      }
      if ((String(type) === 'pointerup' || String(type) === 'pointercancel' || buttonsValue === 0) && wallpaperState.captureTarget && typeof DragEvent === 'function') {
        try {
          const dragEndEvent = new DragEvent('dragend', {
            bubbles: true,
            cancelable: true,
            composed: true,
            clientX,
            clientY
          });
          wallpaperState.captureTarget.dispatchEvent(dragEndEvent);
          if (String(type) === 'pointerup') {
            const dropEvent = new DragEvent('drop', {
              bubbles: true,
              cancelable: true,
              composed: true,
              clientX,
              clientY
            });
            wallpaperState.captureTarget.dispatchEvent(dropEvent);
          }
        } catch (_) {}
      }
      if (String(type) === 'pointerup' || String(type) === 'pointercancel' || buttonsValue === 0) {
        if (target && typeof target.releasePointerCapture === 'function' && pointerEvent && typeof pointerEvent.pointerId === 'number') {
          try { target.releasePointerCapture(pointerEvent.pointerId); } catch (_) {}
        }
        wallpaperState.captureTarget = null;
        wallpaperState.captureButtons = 0;
      }
      if (String(type) === 'pointerup' && buttonValue === 1 && typeof MouseEvent === 'function') {
        const auxClickEvent = enrichMouseLikeEvent(new MouseEvent('auxclick', mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(auxClickEvent);
      }
      if (String(type) === 'pointerup' && buttonValue === 2 && typeof MouseEvent === 'function') {
        const contextMenuEvent = enrichMouseLikeEvent(new MouseEvent('contextmenu', mouseEventInit), target, clientX, clientY);
        target.dispatchEvent(contextMenuEvent);
      }
    } catch (error) {
      hostLogger.post('pointer.dispatch.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperDispatchWheelEvent = function(normalizedX, normalizedY, deltaX, deltaY, buttons) {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const safeX = Math.max(0, Math.min(1, Number(normalizedX || 0)));
      const safeY = Math.max(0, Math.min(1, Number(normalizedY || 0)));
      const clientX = safeX * width;
      const clientY = safeY * height;
      const target = document.elementFromPoint(clientX, clientY) || document.body || document.documentElement;
      if (!target || typeof WheelEvent !== 'function') return;
      const wheelEvent = new WheelEvent('wheel', {
        bubbles: true,
        cancelable: true,
        composed: true,
        clientX,
        clientY,
        deltaX: Number(deltaX || 0),
        deltaY: Number(deltaY || 0),
        buttons: Number(buttons || 0),
        view: window
      });
      target.dispatchEvent(wheelEvent);
    } catch (error) {
      hostLogger.post('wheel.dispatch.error', error && error.message ? error.message : error);
    }
  };
  window.__myWallpaperSetPassiveMouseState = function(active, normalizedX, normalizedY, buttons) {
    try {
      const width = Math.max(window.innerWidth || 0, 1);
      const height = Math.max(window.innerHeight || 0, 1);
      const safeX = Math.max(0, Math.min(1, Number(normalizedX || 0)));
      const safeY = Math.max(0, Math.min(1, Number(normalizedY || 0)));
      const clientX = safeX * width;
      const clientY = safeY * height;
      window.wallpaperEngine_cursor = {
        x: clientX,
        y: clientY,
        normalizedX: safeX,
        normalizedY: safeY,
        buttons: Number(buttons || 0)
      };
      window.wallpaperEngine_mouseover = Boolean(active);
      if (!active) {
        window.__myWallpaperUpdateHoverTarget(null, mouseEventInitBase(clientX, clientY, 0, 0));
      }
    } catch (_) {}
  };
"""#

