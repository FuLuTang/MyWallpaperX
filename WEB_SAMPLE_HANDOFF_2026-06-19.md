# MyWallpaperX Web Sample Debug Handoff - 2026-06-19

This file is for resuming in a fresh Codex window with minimal context loss.

## Must-read first

1. `/Users/songziqiang/Documents/Development/MyWallpaperX/AGENTS.md`
2. `/Users/songziqiang/Documents/Development/MyWallpaperX/WEB_SAMPLE_DEBUG_SUMMARY_2026-06-19.md`
3. This handoff file.

Project root:

```text
/Users/songziqiang/Documents/Development/MyWallpaperX
```

Official Web samples path, do not edit:

```text
/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web
```

Build command:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

Debug app binary:

```text
/Users/songziqiang/Documents/Development/MyWallpaperX/.codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX
```

Run one sample:

```sh
APP="/Users/songziqiang/Documents/Development/MyWallpaperX/.codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX"
LOGDIR="/tmp/mwx-target-<name>-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"
"$APP" --mwx-debug-suppress-main-window --mwx-log-web-diagnostics --mwx-debug-play-workshop-id 3700131876 > "$LOGDIR/3700131876.log" 2>&1 &
pid=$!
sleep 10
screencapture -x "$LOGDIR/3700131876.png" || true
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
```

## What was fixed in the current workspace

### 1. Rain visual regression caused by full-bag fallback semantics

Regression source:

- Local unpushed commit `84099c0 Defer web property replay until runtime is ready` introduced per-property fallback after full `applyUserProperties` failure.
- For `3700131876` / `3700928191`, the sample has script bugs. Per-property fallback continued executing branches that Wallpaper Engine's one-shot callback would not reach, which distorted rain/fog visuals.

Fix:

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`
- Non-initialization script errors no longer fall through to per-property replay.
- The host preserves prefix side effects, records `properties.error`, marks the property signature handled, and stops.

### 2. Color payload semantics and cache invalidation

Issue:

- `4cc9ea1 Fix web color property payload compatibility` changed color runtime values to `[r,g,b]` arrays.
- Most WE-style Web samples expect color values to be string-like (`"r g b"`) and call `.split(" ")`.
- Rain samples use `mistcolor.value.push(1)`, which should fail with string-like color payloads and stop at the same point as pushed baseline.

Fix:

- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertyRuntimePayload.swift`
- Runtime color JSON values are now string form again.
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift`
- Runtime cache version bumped from `12` to `13` so cached `propertyPayloadJSON` is regenerated.

### 3. `.push` errors are sample script errors, not initialization timing

Issue:

- WebKit can report `f.push` failure as a message containing `is undefined`, which was caught by the broad initialization-error classifier.
- That caused retries and delayed/hidden the real sample error.

Fix:

- `HostBridge.swift`
- `.push` / `push is not a function` messages are explicitly classified as non-initialization script errors.

### 4. Detail-panel sliders were ineffective because live updates replayed full bags

Issue:

- Detail panel generated a single-property delta.
- `WallpaperEngine.updateCurrentWebWallpaperProperties` merged it into `currentWebPropertiesJSON` and dispatched the merged full property bag.
- For samples with unrelated broken property branches, a live slider change could hit those errors and fail to reach the sample's refresh logic.

Fix:

- `MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift`
- Keep `currentWebPropertiesJSON` merged internally, but dispatch only the live delta to the Web runtime.

### 5. Startup defaults needed renderer refresh after script error

Issue:

- `3700131876` showed panel blur default `1`, but startup visual looked like a heavier stale/default blur until the slider was touched.
- The sample mutates some options before throwing at `mistcolor`, but throws before its final `resizeCanvas(); raindropFx.resize(...)` refresh.

Fix:

- `HostBridge.swift`
- After non-initialization script error, dispatch a resize event after settled frames.
- Diagnostic: `properties.resize-after-script-failure` at info severity.
- This preserves official one-shot error semantics and only gives already-applied prefix side effects a chance to refresh renderer state.

## Representative validation already run

Latest representative validation:

```text
/tmp/mwx-target-resize-after-script-failure-20260619-074410
```

Results:

- Build succeeded.
- `3700131876`:
  - `properties.error=1`, expected `f.push is not a function`.
  - `properties.resize-after-script-failure=1`, info severity.
  - `properties.applied.partial=0`.
  - `properties.skipped=0`.
  - no `window.error` or `promise.rejection`.
  - `host.ready=1`, `navigation.finish=1`.
- `2997985023`:
  - `properties.deferred-side-effect=1`.
  - no `properties.error`, partial/skipped, window/promise errors.
  - `host.ready=1`, `navigation.finish=1`.

User manually confirmed after these fixes:

- `3700131876` startup now loads with default blur/透明度 value `1` correctly.
- The blur slider is effective while the wallpaper is running.

## Latest follow-up - 2026-06-21 slider drag commit persistence

Current workspace change:

- `MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSheet.swift`
- Web property sliders now use a small `WebPropertySlider` subclass to detect AppKit mouse tracking.
- Drag-time updates remain preview-only, so the detail panel avoids rebuilding on every slider tick.
- When AppKit finishes the slider `mouseDown` tracking loop, the final normalized value is committed once through `updateWebPropertyValue`.
- This targets the reported behavior where the running wallpaper changed visually but no persisted override was saved after dragging.

Validation run:

- Build succeeded outside the Codex sandbox:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Runtime smoke / regression logs:

```text
/tmp/mwx-target-slider-tracking-20260621-041904
```

Results:

- `3700131876`: expected `f.push is not a function` and `properties.resize-after-script-failure`; host/navigation ready; no partial/skipped in checked output.
- `3700928191`: same expected rain-sample behavior.
- `2997985023`: expected `properties.deferred-side-effect`; host/navigation ready.

Manual verification still needed:

1. Open `3700131876`.
2. Drag `backgroundblursteps` / `背景模糊` to a non-default value.
3. Switch to another wallpaper.
4. Switch back to `3700131876`.
5. Confirm the slider档位 and visual restore.
6. Repeat once for `3700928191` if the first check passes.

## Previous remaining issue

User asked to stop before fixing this.

Problem:

- Slider档位 is not remembered after switching wallpapers and switching back.
- Confirmed by user for both:
  - `3700131876`
  - `3700928191`

Repro:

1. Open `3700131876`.
2. Move the blur slider to a different档位.
3. Switch to another wallpaper.
4. Switch back to `3700131876`.
5. The last slider档位/visual is not restored.

Likely investigation path:

1. Check `SteamWorkshopItemDetailSheet.updateWebProperty`.
2. Check `SteamWorkshopService.updateWebPropertyValue` and where overrides are stored.
3. Verify whether setting a non-baseline value writes an override file and whether `objectWillChange`/cache invalidation fires.
4. Inspect `effectiveWebPropertyValues` and `effectiveWebPropertiesJSONString` when switching back.
5. Inspect `.mywallpaperx-web-runtime.json` for affected samples:
   - version should be `13`.
   - `propertyPayloadJSON` should reflect the overridden value.
6. Check `SteamWorkshopWebRuntimeCacheManifest.overridesSignature` and `webRuntimeCacheOverridesSignature` to ensure override changes invalidate runtime cache.

Keep verification narrow:

- Primary: `3700131876`.
- Related: `3700928191`.
- Regression guard: `2997985023`.

Avoid full sample runs unless a shared cache or property-persistence mechanism is changed in a way that justifies broader coverage.

## Important commands

Check status:

```sh
git status --short --branch
```

Inspect current diffs:

```sh
git diff --stat
git diff -- MyWallpaperX/Core/SteamWorkshopWeb/Engine/WallpaperEngine+WebWallpaper.swift \
  MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift \
  MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPropertyRuntimePayload.swift \
  MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebRuntimeCache.swift
```

Useful logs from this session:

```text
/tmp/mwx-target-delta-property-update-20260619-073122
/tmp/mwx-target-resize-after-script-failure-20260619-074410
/tmp/mwx-target-raindrop-push-classification-20260619-071809
/tmp/mwx-origin-single-3700131876-20260619-072125
```

## Notes / constraints

- Do not apply old stash blindly. There was a previous experimental rain stash in earlier context; it was not part of the final fix.
- Do not edit Steam sample files.
- Keep `WEB_SAMPLE_DEBUG_SUMMARY_2026-06-19.md` updated after future fixes.
- The user prefers targeted representative validation, not broad sample batches.
