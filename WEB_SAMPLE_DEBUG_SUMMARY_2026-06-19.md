# Web Sample Debug Summary - 2026-06-19

## Purpose

Keep enough task state in the repo root to continue after context compaction.

User request:

- Follow the top-level `AGENTS.md` process.
- Run Web samples one by one from `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web`.
- Fix runtime errors and warnings when they are caused by MyWallpaperX host/runtime logic.
- Keep this file updated after the full run and after each fix/verification step.

## Current Run

- Date/time started: 2026-06-19 around 03:20 Asia/Shanghai.
- Branch: `feature/scene`.
- Initial working tree: clean.
- Build command:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Build result: succeeded. Only the standard Xcode multiple-destinations warning was observed.
- App binary:

```text
/Users/songziqiang/Documents/Development/MyWallpaperX/.codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX
```

- Runtime command pattern:

```sh
MyWallpaperX --mwx-debug-suppress-main-window --mwx-log-web-diagnostics --mwx-debug-play-workshop-id <directory-id>
```

- Full-run log directory:

```text
/tmp/mwx-web-sample-run-20260619-032000
```

- Sample count detected: 55 directories.
- Run status when this file was first created: 42/55 completed.

## Early Findings To Verify After Full Run

1. Potential record/folder mismatch:
   - Some logs show a requested `record=<directory-id>` while resource diagnostics point to another sample folder.
   - Examples seen during the run:
     - `2021524859` logged missing resource under `Web/1081733658`.
     - `1835932397` logged resource paths associated with `Web/884307090`.
   - Follow-up: checked `project.json`; these are dependency-host samples. Current record ID stays on the child sample while the actual HTML/root can come from its declared `dependency`. This is expected, not a bug.

2. Host/runtime candidate:
   - `2997985023` produced `window.error`:
     - `TypeError: undefined is not an object (evaluating 'model.model.focus')`
     - Source paths in log: `assets/js/wallpaper.js:155` and `:178`.
   - Need inspect sample logic and determine whether this is host timing/property compatibility or sample resource/model initialization.

3. Likely sample/external dependency issues, not host bugs unless evidence changes:
   - `3639973107`: `http://127.0.0.1:5000/performance` fetch fails; sample expects external local service.
   - `3697499196`: Google Storage fetch failures.
   - Weather/API calls such as `i.tianqi.com` or `autodev.openspeech.cn` may fail independently of MyWallpaperX.
   - Several Spine-style samples request missing `background.png`; inspect whether this is optional/default placeholder before changing host logic.

## Next Required Steps

1. Full 55-sample run finished.
2. Generate and preserve a full log summary in this file.
3. Rebuild and verify the startup input-forwarding fix.
4. After each independent fix:
   - rebuild Debug App
   - rerun the affected sample(s)
   - rerun related samples based on impact area
   - update this file with commands, results, and remaining risk
   - commit only after verification passes

## Full Run Summary

Log directory:

```text
/tmp/mwx-web-sample-run-20260619-032000
```

Counts:

- Logs: 55
- Completed samples: 55
- `MWX DEBUG PLAY: launching`: 55/55
- `type=runtime.profile`: 55/55
- `type=host.ready`: 55/55
- `type=navigation.finish`: 53/55
- `type=properties.error` / `type=general-properties.error`: 0/55

Samples without `navigation.finish`:

- `3701476549`: page is a remote iframe wrapper for `https://artemis.cdnspace.ca/`; `dom.ready` and `host.ready` were present.
- `3701773311`: local page reached `dom.ready` and `host.ready`; it also logged missing `Placeholder.png` while the actual file is `Placeholder.jpg`.

Error/warning groups:

- Host/runtime candidate:
  - `2997985023`: `window.error` on `model.model.focus` at `assets/js/wallpaper.js:155` and `:178`, triggered immediately after forwarded `pointer.down` / `pointer.up`.
- External dependency or remote API:
  - `3639973107`: expects local service `http://127.0.0.1:5000/performance`.
  - `3697499196`: Google Storage fetch failed.
  - `1835932397`, `1849772671`, `884307090`: `http://i.tianqi.com/index.php?c=code&id=11` XHR failed.
  - `3700632372`, `3702454590`: `https://autodev.openspeech.cn/.../weather` XHR failed.
- Missing sample resources / optional assets:
  - Several Spine-style samples request `background.png` that does not exist.
  - `3701249553` and `3705960722` also request missing `image/logo_nikke.png`.
  - `3676193993` requests missing `bg_full.png`.
  - `1081733658` and dependent samples request missing `img/faces/face-5.jpg`.
  - `3639973107` requests optional `performance.layout.user.js`.

## Fix 1 - Startup Active Input Forwarding

Root-cause hypothesis:

- `2997985023` is a Live2D sample whose `pointerdown` / `pointerup` handlers assume `model.model` is initialized.
- MyWallpaperX starts global mouse forwarding as soon as the host reaches ready. In the debug run, a button event was forwarded during the sample startup window, before Live2D model initialization completed.
- This is host-side startup input pollution, not a property replay issue: there were no `properties.error` events in the full run.

Changed files:

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/WebWallpaperHostTypes.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwardingMonitors.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+InputForwarding.swift`

Implementation:

- Record when active input forwarding starts.
- For the first 3.5 seconds, drop active input events:
  - mouse down/up
  - drag
  - wheel
- Keep passive pointer move / hover polling active.

Validation status:

- Build passed:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Targeted rerun log directory:

```text
/tmp/mwx-target-active-input-warmup-20260619-033047
```

- `2997985023`:
  - `launching`: present
  - `runtime.profile`: present
  - `host.ready`: present
  - `navigation.finish`: present
  - `severity=error`: none
  - `severity=warning`: none
  - no `pointer.down` / `pointer.up` during startup window
- `1748506393`:
  - `launching`: present
  - `runtime.profile`: present
  - `host.ready`: present
  - `navigation.finish`: present
  - `severity=error`: none
  - `severity=warning`: none
  - `pointer.down` / `pointer.up` still forwarded after the warmup window

Fix 1 status: verified.

## Remaining Issues After Fix 1

No remaining `properties.error`, `general-properties.error`, or host navigation failure was found in the full run.

Remaining error logs are currently classified as sample/external dependencies:

- `3639973107`: missing local service `http://127.0.0.1:5000/performance`.
- `3697499196`: remote Google Storage fetch failed.
- `1835932397`, `1849772671`, `884307090`: remote `i.tianqi.com` weather XHR failed.
- `3700632372`, `3702454590`: remote `autodev.openspeech.cn` weather XHR failed.

Remaining warning logs need review before changing host behavior:

- Missing `background.png` in several Spine-style samples.
- Missing `image/logo_nikke.png` in `3701249553` and `3705960722`.
- Missing `Placeholder.png` in `3701773311` while `Placeholder.jpg` exists and is used by the script.
- Missing `img/faces/face-5.jpg` in `1081733658` and dependent samples.

Representative review:

- Spine-style samples such as `3566247256` directly reference `background.png` in `style.css`; no matching file exists in that sample directory.
- `3701249553` directly references `image/logo_nikke.png`; no matching file exists.
- `3701773311` references `Placeholder.png` from `main.css`, while `index.js` uses `Placeholder.jpg` and the directory contains `Placeholder.jpg`.

Decision:

- Do not blanket-hide these warnings in the host. They are real missing-resource references from sample code.
- Do not edit the external sample library as part of this repo fix unless explicitly requested; those files live under `/Users/songziqiang/Movies/...`, not the app source tree.

## Continuation - 2026-06-19 05:27 Asia/Shanghai

Reason for continuation:

- Continue from this document after Fix 1.
- Re-check every remaining runtime error/warning group against actual logs and sample source before deciding whether to change host/runtime code.
- Refresh the post-fix full-run baseline so future agents can resume from this file.

### Current working state before continuation

- Branch: `feature/scene`.
- `HEAD`: `8202411 Fix web startup input forwarding warmup`.
- Working tree before this documentation update: clean.
- App binary used for rerun:

```text
/Users/songziqiang/Documents/Development/MyWallpaperX/.codex/DerivedData/Build/Products/Debug/MyWallpaperX.app/Contents/MacOS/MyWallpaperX
```

### Post-Fix-1 full rerun

Command pattern:

```sh
MyWallpaperX --mwx-debug-suppress-main-window --mwx-log-web-diagnostics --mwx-debug-play-workshop-id <directory-id>
```

Log directory:

```text
/tmp/mwx-web-sample-rerun-20260619-052724
```

Validation scope rationale:

- Fix 1 changed the shared active input forwarding path.
- A full 55-sample rerun was used to verify no global startup/input regression and to refresh the remaining error/warning baseline.

Counts:

- Logs: 55
- Completed samples: 55
- `MWX DEBUG PLAY: launching`: 55/55
- `type=runtime.profile`: 55/55
- `type=host.ready`: 55/55
- `type=navigation.finish`: 54/55 in the 7-second full-run window
- `type=properties.error`: 0/55
- `type=general-properties.error`: 0/55

Fix 1 verification in full rerun:

- `2997985023`:
  - `window.error`: 0
  - `pointer.down`: 0 during startup capture
  - `pointer.up`: 0 during startup capture
  - Result: the previous `model.model.focus` crash did not recur.

Follow-up for sample without `navigation.finish` in 7-second run:

- `3701773311` was rerun separately for 15 seconds.
- Targeted log directory:

```text
/tmp/mwx-target-3701773311-20260619-053524
```

- Result:
  - `dom.ready`: present
  - `host.ready`: present
  - `navigation.finish`: present after a remote image failure
  - warning: missing local `Placeholder.png`
  - error: remote image `https://wallpaperengineapi.onrender.com/apod-images/2026-06-17.jpg` failed
- Decision: not a host navigation failure. The short full-run window ended before the page completed after remote image failure.

### Remaining diagnostic groups after post-fix rerun

#### 1. Arthesian / Smooth.js console warnings

Samples:

- `1081733658`
- `2021524859` (dependency-backed shell using `1081733658` entry/resources)
- `3702321748` (dependency-backed shell using `1081733658` entry/resources)

Messages:

- `The dependency 'Smooth.METHOD_CUBIC' was neither a loaded object nor function! Please check if the module was correctly loaded.`
- `'ARTHESIAN.Helper.Array' uses 'Smooth.js' library for enhanced Interpolation. Interpolation will still work, but only in 'lineair' mode.`

Source review:

- `1081733658/index.html` loads `Arthesian Library/External/Smooth.js` before `Arthesian Library/Helper/Array.js`.
- `Smooth.js` defines `Smooth.METHOD_CUBIC` as the string constant `'cubic'`.
- `Arthesian Library/Helper/Array.js` calls `ARTHESIAN.Helper.checkDependency(['Smooth', 'METHOD_CUBIC'])` and warns when the dependency helper does not consider the string constant a loaded object/function.
- `Array.js` still uses `Smooth(data, { method: Smooth.METHOD_CUBIC, scaleTo: newLength })` when `Smooth` exists.

Classification:

- Sample/library warning, not MyWallpaperX host/runtime bug.
- Do not patch host to hide the warning; it reflects sample library diagnostics.

#### 2. Missing `img/faces/face-5.jpg`

Samples:

- `1081733658`
- `2021524859` (dependency-backed shell)
- `3702321748` (dependency-backed shell)

Evidence:

- Logs resolve the request to:

```text
/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web/1081733658/img/faces/face-5.jpg
```

- The file does not exist in the sample tree.
- Dependency-backed shell records correctly use the dependency resource root; this is expected and not a record/folder mismatch.

Classification:

- Missing sample resource.
- No host change.

#### 3. Missing Spine-style `background.png`

Samples:

- `3566247256`
- `3601888127`
- `3602501948`
- `3603106230`
- `3620596895`
- `3689993041`
- `3690554020`
- `3701249553`
- `3705960722`

Source review:

- Each sample has `style.css` with:

```css
background: url(background.png) no-repeat left top fixed;
```

- Checked each sample for both `background.png` and compatibility fallback `image/bg.png`.
- Neither file exists for these samples.
- Many of these samples do contain `image/logo_nikke.png`; `3701249553` and `3705960722` do not.

Classification:

- Missing sample resource.
- Existing host compatibility fallback from `background.png` to `image/bg.png` cannot apply because `image/bg.png` is also absent.
- No host change.

#### 4. Missing `image/logo_nikke.png`

Samples:

- `3701249553`
- `3705960722`

Source review:

- `main.js` sets:

```js
document.body.style.backgroundImage = "url('image/logo_nikke.png')";
```

- `image/logo_nikke.png` is not present in either sample directory.

Classification:

- Missing sample resource.
- No host change.

#### 5. Missing `bg_full.png`

Sample:

- `3676193993`

Source review:

- `style.css` contains:

```css
background-image:url("bg_full.png"),url("bg_fuji.png"),
```

- `bg_fuji.png` exists.
- `bg_full.png` does not exist.

Classification:

- Missing first-layer optional/extra sample background resource.
- No host change.

#### 6. Missing `Placeholder.png` and remote APOD image failure

Sample:

- `3701773311`

Source review:

- `main.css` references `Placeholder.png`.
- The sample directory contains `Placeholder.jpg`, not `Placeholder.png`.
- `index.js` uses `Placeholder.jpg` directly.
- Separate 15-second run also logged:

```text
Image failed: https://wallpaperengineapi.onrender.com/apod-images/2026-06-17.jpg
```

Classification:

- Local warning: sample CSS references a missing `.png` while script uses existing `.jpg`.
- Remote error: external image/API dependency.
- No host change.

#### 7. `3639973107` local performance service and optional user layout file

Diagnostics:

- Missing `performance.layout.user.js`.
- `fetch.error` / `console.error`: `http://127.0.0.1:5000/performance Load failed`.

Source review:

- `index.html` checks whether `performance.layout.user.js` exists.
- `performance.layout.js` comment says that after editing it is recommended to duplicate/rename it to `performance.layout.user.js` so updates do not overwrite it.
- `index.html` has a commented default layout include:

```html
<!-- <script src="performance.layout.js"></script> -->
```

- `project.json` describes external data collection via psutil / GPUtil / HWiNFO-like setup.

Classification:

- Missing `performance.layout.user.js`: optional sample user override file.
- `127.0.0.1:5000/performance`: external local service expected by the sample.
- No host change.

#### 8. Remote weather/API failures

Samples:

- `1835932397`
- `1849772671`
- `884307090`
- `3700632372` (dependency-backed shell using `884307090` entry/resources)
- `3702454590` (dependency-backed shell using `884307090` entry/resources)

Diagnostics:

- `http://i.tianqi.com/index.php?c=code&id=11` XHR failed.
- `https://autodev.openspeech.cn/csp/api/v2.1/weather?...` XHR failed.

Source review:

- `884307090/js/time.js` contains the active openspeech weather request:

```js
$.get("https://autodev.openspeech.cn/csp/api/v2.1/weather?openId=aiuicus&clientType=android&sign=android&needMoreData=true&pageNo=1&pageSize=1&city=" + city, ...)
```

- `884307090/js/time.js` also contains legacy/commented `i.tianqi.com` iframe code; dependency and runtime logs show weather integrations are sample-side behavior.
- `3700632372` and `3702454590` have their own shell `project.json` values for `weather_CityText`, while their runtime metadata uses `propertySourceRecordID=884307090` / dependency-backed entry.

Classification:

- External remote API dependency.
- No host change.

#### 9. `3697499196` Google Storage failures

Sample:

- `3697499196`

Diagnostics:

- Multiple fetch failures for URLs under:

```text
https://storage.googleapis.com/download/storage/v1/b/p-2-cen1/o/October%2F1%2FOctober_*.txt?alt=media
```

Source review:

- `ArtemisII_Wallpaper.html` builds these URLs directly:

```js
const url = `https://storage.googleapis.com/download/storage/v1/b/p-2-cen1/o/${encodeURIComponent(path)}?alt=media`;
```

Classification:

- External remote storage dependency.
- No host change.

### Current conclusion after continuation

- No remaining `properties.error` or `general-properties.error`.
- No confirmed remaining MyWallpaperX host/runtime bug in the current 55-sample baseline.
- Fix 1 remains verified by both targeted and full rerun evidence.
- Remaining diagnostics are classified as sample-owned missing resources, optional sample user overrides, or external service/API failures.
- Do not hide these diagnostics in host/runtime code because they are real sample-side failures/warnings and useful during debugging.

### Recommended next action

- If the task scope is only MyWallpaperX host/runtime fixes: no further code change is needed for the current baseline.
- If the user wants a clean zero-warning sample corpus, that is a separate task requiring edits under `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web`, not this app source repo. Those edits should be planned separately because they modify external sample content.

## Scope Correction - 2026-06-19 user clarification

User clarified the target:

- The Web samples are downloaded from the official Steam Wallpaper Engine content library.
- Do **not** edit sample files under `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web`.
- A sample can be imperfect, but MyWallpaperX should maximize Wallpaper Engine host compatibility and playback fidelity.
- Runtime diagnostics should distinguish:
  - confirmed MyWallpaperX host/runtime bugs,
  - likely Wallpaper Engine compatibility gaps,
  - host diagnostic-classification gaps,
  - external service/network dependency failures,
  - sample-owned missing/optional resources.

Implication for the remaining diagnostics:

- Do not stop at “sample/external issue”. Re-check whether Wallpaper Engine would likely allow or tolerate the behavior.
- Prioritize host-side compatibility improvements where they can safely emulate WE behavior without modifying official samples.
- Especially re-evaluate remote XHR/fetch failures because WKWebView may enforce CORS / App Transport Security differently from Wallpaper Engine's Chromium-based runtime.

## Fix 2 - Local Companion `/performance` Compatibility and Optional User Layout Classification

Root-cause analysis:

- `3639973107` is a terminal/system-monitor style wallpaper.
- Its runtime logic loads `performance.layout.user.js` only as an optional user override:
  - It first probes it with `fetch("performance.layout.user.js", { method: "HEAD" })`.
  - On failure, it falls back to bundled `performance.layout.js`.
- It then polls `http://127.0.0.1:5000/performance` once per second and expects JSON shaped like:

```json
{ "hwinfo": [], "psutil": {} }
```

or populated equivalent metrics.

- MyWallpaperX already had a local companion compatibility shim for `127.0.0.1:5000` endpoints such as `/usage`, `/notes`, `/shortcuts`, and `/logs`, but did not implement `/performance`.
- Result before fix: the sample repeatedly logged `Error fetching performance data: Load failed` even though this is a host compatibility gap, not something that should be fixed by editing the official sample.
- The missing `performance.layout.user.js` was also diagnosed as a warning even though the sample explicitly treats it as an optional user override.

Changed files:

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeLogging.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Support/WebWallpaperLocalSchemeHandler.swift`

Implementation:

- Added a `/performance` response to the existing local companion `fetch` compatibility shim:

```json
{ "hwinfo": [], "psutil": {} }
```

- Classified missing `performance.layout.user.js` as `local-resource.optional-user-layout` with `severity=info` instead of `local-resource-deny` warning.

Impact range:

- Only affects requests to the local companion URL `http://127.0.0.1:5000/performance` and missing `performance.layout.user.js` resource probes.
- Does not modify official sample files.
- Does not mask arbitrary missing JavaScript files; classification is limited to the known optional user-layout filename.

Validation:

- Build passed:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Targeted validation sample: `3639973107` because the fix is specific to its local companion performance-monitor flow.
- Final targeted log directory:

```text
/tmp/mwx-target-performance-compat-optional-layout-20260619-054505
```

- Result:
  - `launching`: 1
  - `runtime.profile`: 1
  - `host.ready`: 1
  - `navigation.finish`: 1
  - `fetch.compat` for `/performance`: 6
  - `/performance Load failed`: 0
  - `Error fetching performance data`: 0
  - `severity=error`: 0
  - `severity=warning`: 0
  - `local-resource.optional-user-layout`: 1 info event
  - `fetch.ignored HEAD performance.layout.user.js optional`: 1 info event

Fix 2 status: verified.

Next diagnostic candidates after Fix 2:

- Re-evaluate remote `xhr.error` / `fetch.error` groups as possible CORS / ATS / Chromium-vs-WKWebView compatibility gaps before classifying them as purely external service failures.
- Keep missing image/CSS resources as diagnostics, but consider whether some are optional decorative fallbacks that should be `info` instead of `warning` only when the sample logic clearly treats them as optional or has a working fallback.

## Fix 3 - Remote GET/HEAD Network Compatibility Proxy

Root-cause analysis:

- Several official WE web samples issue remote XHR/fetch calls from a local wallpaper origin.
- In MyWallpaperX's WKWebView runtime these requests failed with `status=0` / `Load failed`, even when the same URL was reachable from the host process.
- This is a host compatibility gap compared with Wallpaper Engine's Chromium-based runtime, which is more permissive for web wallpaper network access.
- Affected observed groups:
  - `1835932397`, `1849772671`, `884307090`: weather calls to `http://i.tianqi.com/index.php?c=code&id=11` and/or openspeech weather API.
  - `3700632372`, `3702454590`: dependency-backed shells using `884307090` weather logic.
  - `3697499196`: fetches Google Storage text assets; native host request reaches the server and gets real HTTP `401`, while WKWebView reported generic `Load failed`.

Changed files:

- `MyWallpaperX/Info.plist`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+InteractionAndRuntimeLogging.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Surface.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+Lifecycle.swift`
- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostPlaceholderAdapter+RuntimeBridge.swift`

Implementation:

- Added a restricted host network bridge message handler: `wallpaperHostNetworkRequest`.
- Added JS-side remote network fallback:
  - `fetch`: still tries native `fetch` first; if it fails for remote `http/https` `GET`/`HEAD`, it falls back to the host bridge and returns a synthetic `Response`.
  - `XMLHttpRequest`: for remote `http/https` `GET`/`HEAD`, goes directly through the host bridge and synthesizes XHR `readyState`, `status`, `responseText`, `response`, and response header methods. This avoids calling the page's error handler before a proxy success arrives.
- Swift-side bridge restrictions:
  - Allows only `http` / `https` URLs.
  - Allows only `GET` / `HEAD`.
  - Does not forward request bodies.
  - Forwards only a small safe header allowlist: `Accept`, `Accept-Language`, `Content-Type`.
  - Uses a 10-second timeout and a 2 MiB response body limit.
  - Logs `network.proxy` / `network.proxy.error` diagnostics so replay remains auditable.
- Added ATS configuration for broader WE-style web wallpaper network access:
  - `NSAllowsArbitraryLoads=true`
  - `i.tianqi.com` HTTP exception for the legacy weather endpoint.

Validation:

- Build passed with no warnings:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Final targeted log directory:

```text
/tmp/mwx-target-network-proxy-direct-xhr-20260619-055836
```

Validated samples and results:

- `884307090`:
  - `network.proxy`: 2
  - `xhr.proxy`: 2
  - `severity=error`: 0
  - `severity=warning`: 0
  - Weather requests returned HTTP 200 through host proxy.
- `1835932397`:
  - `network.proxy`: 2
  - `xhr.proxy`: 2
  - `severity=error`: 0
  - `severity=warning`: 0
  - Weather requests returned HTTP 200 through host proxy.
- `3700632372`:
  - `network.proxy`: 1
  - `xhr.proxy`: 1
  - `severity=error`: 0
  - `severity=warning`: 0
  - Openspeech weather request returned HTTP 200 through host proxy.
- `3697499196`:
  - `network.proxy`: 8
  - `fetch.proxy`: 8
  - `severity=error`: 0
  - `severity=warning`: 0
  - Google Storage now returns real HTTP 401 responses through host proxy instead of WKWebView `Load failed`; this is now correctly diagnosable as a remote authorization/status issue, not a host network failure.

Fix 3 status: verified.

Remaining known diagnostics after Fix 3:

- Missing local sample resources such as `background.png`, `image/logo_nikke.png`, `bg_full.png`, `Placeholder.png`, and `img/faces/face-5.jpg` still need classification review.
- Do not edit official sample files; if these are optional/decorative or have working fallback assets, prefer improving host diagnostic severity/classification instead of hiding or patching the sample.

## Fix 4 - Avoid duplicate async property initialization replays for Live2D/Pixi wallpapers

User-visible problem:

- `2997985023` could start with multiple Live2D character instances visually overlapping.
- The issue appeared in recent local changes and was not fixed by only avoiding local loopback resource proxying.

Sample logic reviewed:

- Official sample files were inspected but not modified:
  - `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web/2997985023/project.json`
  - `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web/2997985023/assets/js/wallpaper.js`
  - `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web/2997985023/assets/js/model.js`
- The sample's `applyUserProperties` handles `modelName` by scheduling `model.loadModel(modelName)` with `setTimeout(...)`.
- The same callback then continues to call `model.onResize(...)`, `model.videoContext...pause()`, and `model.updateBg(...)` while the async model load has not completed yet.
- This can throw an initialization-time exception after a model-load side effect has already been scheduled.

Root cause:

- Host property replay previously treated this exception as an initialization failure and retried the whole `applyUserProperties` bag.
- Every retry re-entered the sample callback and scheduled another async `loadModel(...)`.
- When those async loads later completed, multiple Live2D/Pixi display objects could remain in the same stage, producing the observed overlapping characters.

Changed files:

- `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift`

Implementation:

- Wrapped page `applyUserProperties` invocation so the host can detect whether the callback scheduled async work through:
  - `setTimeout`
  - `setInterval`
  - `requestAnimationFrame`
- If the callback throws an initialization-style exception after scheduling async work, the host now treats the call as an async side-effecting initialization that should not be blindly replayed.
- The host records the property signature as applied and logs `properties.deferred-side-effect` for diagnostics instead of scheduling another full replay.
- This is intentionally narrower than a sample-specific workaround: it only applies when both conditions are true:
  1. the error matches the existing initialization-error classifier;
  2. the page callback already scheduled async work before throwing.

Validation:

- Build passed after the refined implementation:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Targeted 2997985023 validation before broad regression:

```text
/tmp/mwx-target-2997985023-overlap-fix-20260619-062018
```

Result:

- `properties.deferred-side-effect`: 1
- `properties.applied.partial`: 0
- `properties.skipped`: 0
- `network.proxy`: 0
- `assets/live2d`: 0
- `promise.rejection`: 0
- `window.error`: 0
- `severity=error`: 0
- `severity=warning`: 0
- Screenshot: `/tmp/mwx-target-2997985023-overlap-fix-20260619-062018/2997985023.png`
- Visual result: single Live2D character, no multi-character overlap.

Related-sample regression scope:

- Scope selection: samples with `wallpaperPropertyListener` / `wallpaperRegisterPropertyListener`, especially those whose property listeners or page logic use async APIs such as `setTimeout`, `setInterval`, `requestAnimationFrame`, Pixi, Live2D, or model-loading logic.
- This is the relevant impact surface for the host property replay change; a full 55-sample run was not needed for this isolated property replay fix.

Regression log directory:

```text
/tmp/mwx-target-property-async-regression-20260619-062328
```

Validated samples:

```text
1081733658 1396475780 1509243786 1648488669 1748506393 2997985023
3530909637 3566247256 3601888127 3602501948 3603106230 3620596895
3676193993 3689993041 3690554020 3696345105 3700131876 3700928191
3701249553 3701797805 3702378813 3702822549 3703626233 3705960722
884307090 921617616 923576681
```

Regression results:

- All 27 selected samples reached `host.ready` and `navigation.finish`.
- New `properties.deferred-side-effect` behavior triggered only in `2997985023` and only once.
- No selected sample logged `properties.error` or `general-properties.error`.
- No selected sample logged `window.error` or `promise.rejection`.
- No selected sample had new `severity=error` diagnostics.
- Existing warning/resource diagnostics remained limited to known missing/optional resources in some samples.
- `884307090` still used remote host proxy successfully (`network.proxy=2`, `xhr.proxy=2`), confirming the separate remote network bridge path still works.
- `3700131876` and `3700928191` still reported `properties.applied.partial` with 6 skipped properties each; this is the pre-existing raindrop property mapping problem and remains the next independent fix.
- `3702378813` still reported one skipped property; this was not caused by the new async side-effect replay path because `properties.deferred-side-effect=0` for that sample.

Fix 4 status: verified for 2997985023 and related property-listener/async sample set.

Next issue:

- Continue with `3700131876` / `3700928191` raindrop shader property mapping regression. Current evidence points to min/max property key mapping such as `spawnintervalmin/max` being applied to the wrong option path.

## Continuation - 2026-06-19 Rain regression comparison

User asked to compare pushed `origin/feature/scene` with the local unpushed commits because the raindrop/glass effect used to work and regressed in recent local work.

Confirmed comparison result:

- Local branch `feature/scene` is ahead of `origin/feature/scene` by 20 commits.
- The visual regression is tied to commit `84099c0 Defer web property replay until runtime is ready`.
- `4cc9ea1 Fix web color property payload compatibility` changed the first failing branch for `3700131876`/`3700928191` from `mistcolor` to `motionIntervalMax`, but it still preserved the official one-shot `applyUserProperties` interruption behavior.
- `84099c0` introduced fallback that runs each property separately after the full callback fails. That changes JavaScript execution semantics: branches after the first script error continue running and can mutate `raindropFx.options` values such as `spawnSize`, producing abnormal rain visuals.

Fix plan for this issue:

1. Keep the retry/defer behavior for likely initialization timing errors.
2. Keep the async side-effect guard used by `2997985023`.
3. For non-initialization script errors, preserve official Wallpaper Engine callback semantics:
   - keep side effects that already happened before the throw;
   - record `properties.error` once;
   - mark this property signature handled to avoid repeated replay;
   - do not run per-property fallback.
4. Validate `3700131876` and `3700928191` no longer produce `properties.applied.partial` or `properties.skipped` and instead stop at the `motionIntervalMax` diagnostic.
5. Re-run `2997985023` and at least one prior property-listener regression sample to confirm the initialization/async paths still work.

Implementation in progress:

- Changed `MyWallpaperX/Core/SteamWorkshopWeb/Host/DedicatedWebWallpaperHostCompatibilityScript+HostBridge.swift` so non-initialization `applyUserProperties` failures no longer enter `myWallpaperApplyPropertiesIndividually`.
- Build and targeted validation still pending at the time of this note.

### Rain visual follow-up after first fix

After disabling per-property fallback for non-initialization errors, `3700131876` rendered raindrops again, but user reported the visual was still worse than pushed `origin/feature/scene`: glass fog was too heavy and old drops appeared not to disappear while new drops kept accumulating.

Additional root-cause analysis:

- The first fix restored the execution behavior from commit `4cc9ea1`, but the pushed baseline predates `4cc9ea1`.
- Commit `4cc9ea1` changed color property runtime payloads from normalized strings to `[r, g, b]` arrays.
- Most official WE-style Web samples in this local library read colors with `value.split(" ")`, which indicates the official runtime payload is string-like.
- The rain samples `3700131876` and `3700928191` have a script bug in `mistcolor`: `var f = i.mistcolor.value; f.push(1)`. With official string-like color payload this throws at `f.push`, matching pushed-baseline logs and stopping before mist/motion branches. With array color payload it succeeds and the sample applies extra mist/motion options, causing the heavier fog/lifecycle visual regression.

Second fix in progress:

- Keep parsing/normalization support in the app, but restore runtime JSON color values to string form when sending properties to the Web wallpaper JS.
- This is a general WE compatibility correction, not a per-sample workaround.
- Expected rain diagnostics after rebuild:
  - `3700131876`/`3700928191` should report `f.push is not a function` again.
  - No `properties.applied.partial` / `properties.skipped` should appear.
  - Visual should be closer to pushed baseline because `misttime`, `motioninterval*`, `spawn*` branches are not reached.

Cache effectiveness check:

- First validation after restoring string color payload still reported `motionIntervalMax`, which meant the new payload code had not taken effect.
- Root cause: `.mywallpaperx-web-runtime.json` cache stores `propertyPayloadJSON`, and its version was unchanged.
- Updated `SteamWorkshopWebRuntimeCacheManifest.currentVersion` from 12 to 13 so runtime property payloads are regenerated after the color payload semantic change.

Additional retry-classification finding:

- After cache version 13, rain samples received string color payloads, but no `properties.error` appeared in the 10s run.
- Explanation: WebKit reports the string `.push` failure as a message containing `.push` / `is undefined`, and the broad initialization-error classifier treated it as a timing error and kept retrying instead of preserving official one-shot failure semantics.
- Updated `myWallpaperIsPropertyInitializationError` to classify `.push` / `push is not a function` as non-initialization script errors.

Representative validation after `.push` classification fix:

Log directory:

```text
/tmp/mwx-target-raindrop-push-classification-20260619-071809
```

Validation scope was intentionally narrowed after user feedback:

- `3700131876`: primary rain/glass sample.
- `3700928191`: closely related rain sample.
- `2997985023`: Live2D async side-effect regression guard.
- `3530909637`, `3566247256`, `884307090`, `923576681`: representative color/string-split samples and missing-resource baseline samples.
- `3702378813`: representative non-initialization script error sample.

Results:

- Build succeeded.
- `3700131876`: `properties.error=1`, message `f.push is not a function. (In 'f.push(1)', 'f.push' is undefined)`; `properties.applied.partial=0`; `properties.skipped=0`; `host.ready=1`; `navigation.finish=1`.
- `3700928191`: same `f.push` diagnostic; no partial/skipped.
- `2997985023`: `properties.deferred-side-effect=1`, no `window.error` or `promise.rejection`; the previously fixed overlapping model path remains guarded. One transient `audio.suspend.error: AudioDestinationNode is not initialized` appeared in this run and should be tracked separately only if reproducible.
- Representative color split samples `3530909637`, `884307090`, `923576681`: no `properties.error`, no partial/skipped, no window/promise errors.
- `3566247256`: only known missing `background.png` warnings.
- `3702378813`: still reports expected non-initialization `audio.volume` property error with no partial/skipped.

Current interpretation:

- The runtime now matches pushed-baseline error semantics for the rain samples again: color payload is string-like, `.push` is treated as a sample script error, and the host does not continue applying later branches after that error.
- If the visual is still not acceptable, the next step should be a single-sample visual comparison for `3700131876` against `origin/feature/scene`, not another broad sample run.

User feedback after representative validation:

- User still feels `3700131876` is too blurry compared with memory of the previous visual, and asked whether this may be the sample's correct default and whether transparency/clarity can be adjusted in the detail panel.
- Checked `project.json`: there is no direct `opacity` property, but the detail-panel Web properties expose multiple controls that can reduce fog/blur/density:
  - `mist` / `雾化开启` (bool, default project value false)
  - `backgroundblursteps` / `背景模糊` (slider, min 1, max 10, default 1)
  - `mistblurstep` / `雾化模糊步骤` (slider, min 1, max 10, default 4)
  - `misttime` / `雾化时间` (slider, 1-100, default 10)
  - `dropletsperseconds` / `每秒雨滴数` (slider, 1-1000, default 500)
  - `evaporate` / `逐渐消失` (slider, 1-10000, default 10)
  - `refractbase` / `折射线`, `refractscale` / `折射率`
  - rain/droplet size and lighting sliders.
- Important behavior note: changing a single safe property from the detail panel sends a delta property bag and can apply independently. Recommended representative adjustments for clarity should be tested manually on `3700131876` only, not by broad sample runs.

## Follow-up - 3700131876 detail-panel slider has no visible effect

User reported the blur slider in the detail panel has no effect, so the previous assumption that the heavy blur might simply be the correct default is likely wrong.

Root-cause hypothesis confirmed from code:

- Detail panel preview/update methods create a delta payload for the single changed property.
- `WallpaperEngine.updateCurrentWebWallpaperProperties` then merged that delta into `currentWebPropertiesJSON` and dispatched the merged full property bag to the running Web page.
- For `3700131876`, full-bag execution hits the sample's `mistcolor` script error before reaching the final `resizeCanvas(); raindropFx.resize(...)` refresh call.
- Therefore sliders such as `backgroundblursteps` can mutate `raindropFx.options.backgroundBlurSteps` but never trigger the sample's final resize/blur refresh path, making the blur appear fixed.

Fix in progress:

- Keep `currentWebPropertiesJSON` as merged state for future launches/persistence.
- Dispatch only the delta payload to the live Web runtime during a detail-panel property update.
- Initial wallpaper launch still uses the full property payload.
- This is a general Wallpaper Engine compatibility improvement: runtime property changes are incremental and should not replay unrelated broken sample branches.

Representative validation after delta-dispatch fix:

Log directory:

```text
/tmp/mwx-target-delta-property-update-20260619-073122
```

Scope was intentionally small per user request:

- `3700131876`: primary rain sample and startup property error baseline.
- `2997985023`: Live2D async side-effect regression guard.

Results:

- Build succeeded.
- `3700131876`: startup still matches pushed-baseline semantics: one `properties.error` at `f.push is not a function`, no `properties.applied.partial`, no `properties.skipped`, no window/promise errors, `host.ready=1`, `navigation.finish=1`.
- `2997985023`: one `properties.deferred-side-effect`, no window/promise errors, no partial/skipped, `host.ready=1`, `navigation.finish=1`.

Remaining validation needed:

- User should test the actual detail-panel blur slider in the app. The code path now dispatches only the single-property delta to the running Web page, so changing `backgroundblursteps` should avoid replaying unrelated `mistcolor` and should allow the sample's final resize/blur refresh path to run for that delta.
- If the slider still appears fixed, next step is single-sample interactive debugging for `3700131876` only.

## Follow-up - startup default value not refreshed / setting appears non-persistent

User confirmed the blur slider works after the delta-dispatch fix, but found two remaining issues:

1. The sample's panel shows default blur value `1`, but startup visual looks like a heavier stale/default blur until the slider is touched.
2. After switching away and back, the visual returns to the stale/heavy state and the user must touch the slider again.

Root-cause hypothesis:

- Initial launch intentionally sends the full property bag to match WE startup behavior.
- `3700131876` applies several early options, then throws at `mistcolor` (`f.push is not a function`) before reaching the script's final `resizeCanvas(); raindropFx.resize(...)` call.
- The early option mutation (for example `backgroundBlurSteps = 1`) can therefore fail to rebuild the blur textures, so the visual remains at the constructor/default rendering until a later delta slider change reaches the final resize path.
- Persisting a value equal to the baseline does not create an override, so re-launch still depends on initial full-bag application and hits the same stale refresh problem.

Implementation in progress:

- For non-initialization script errors after a full property callback, preserve official one-shot semantics (do not continue applying later properties), but schedule a resize event after settled frames.
- This gives samples that refresh rendering on resize a chance to rebuild textures from the prefix side effects already applied before the error.
- The diagnostic `properties.resize-after-error` is logged when this compensation fires.

Representative validation after resize-compensation diagnostic rename:

Log directory:

```text
/tmp/mwx-target-resize-after-script-failure-20260619-074410
```

Scope:

- `3700131876` only for rain startup script-error/refresh behavior.
- `2997985023` only for Live2D async side-effect regression guard.

Results:

- Build succeeded.
- `3700131876`: `properties.error=1` with the expected `f.push is not a function` sample script error; `properties.resize-after-script-failure=1` at info severity; no partial/skipped/window/promise errors; `host.ready=1`; `navigation.finish=1`.
- `2997985023`: `properties.deferred-side-effect=1`; no properties error, partial/skipped, window/promise errors; `host.ready=1`; `navigation.finish=1`.

Conclusion:

- Runtime property updates are now delta-dispatched, so detail-panel sliders can affect samples whose full property bag contains unrelated script errors.
- Startup full-bag script errors now trigger a resize compensation event, so prefix-applied options can refresh renderer state without continuing past the sample error.
- User should verify visually that switching away and back to `3700131876` now starts with the same blur state as after touching the blur slider.

## Stop Point - 2026-06-19 07:50 Asia/Shanghai

User requested to stop fixing and hand off current state.

Current confirmed status:

- `3700131876` startup now loads with the expected default low blur / value `1` visual after the resize-after-script-failure compensation.
- Detail-panel blur slider is now effective while the wallpaper is running, after live property updates were changed to dispatch delta payloads instead of replaying the merged full property bag.
- `2997985023` Live2D overlapping regression remains fixed in representative validation.

Remaining issue, not fixed yet:

- Slider value persistence / restoration is still broken.
- Repro reported by user:
  1. Open `3700131876`.
  2. Move blur slider to another档位.
  3. Switch to another wallpaper.
  4. Switch back to `3700131876`.
  5. The last selected档位 is not restored.
- User also confirmed `3700928191` has the same persistence/restoration issue.
- Do not assume this is rain-specific; likely affects Web property override persistence, runtime cache invalidation, or playback context regeneration for multiple samples.

Recommended next investigation:

1. Start from `SteamWorkshopItemDetailSheet.updateWebProperty` and `SteamWorkshopService.updateWebPropertyValue`.
2. Verify where overrides are written and whether setting a non-baseline value is persisted to disk.
3. Check whether switching wallpapers rebuilds `propertyPayloadJSON` from `effectiveWebPropertyValues` or reuses stale `.mywallpaperx-web-runtime.json` cache.
4. Inspect the runtime cache invalidation signature (`overridesSignature`) and whether it changes after a property override save.
5. Use only representative samples unless broader scope is justified:
   - `3700131876` primary repro.
   - `3700928191` related repro confirmation.
   - `2997985023` regression guard for async property side effects.

Do not modify official sample files under `/Users/songziqiang/Movies/MyWallpaperX/创意工坊/Web`.

## Follow-up - 2026-06-21 Slider drag commit persistence

Resumed from:

```text
/Users/songziqiang/Documents/Development/MyWallpaperX/WEB_SAMPLE_HANDOFF_2026-06-19.md
```

Remaining user-visible problem:

- Dragging a Web property slider changed the running wallpaper visually, but after switching away and back the selected档位 was not restored.
- Confirmed repro samples from user:
  - `3700131876`
  - `3700928191`

Root-cause hypothesis from code:

- `NSSlider` was configured as continuous.
- While dragging, `sliderChanged(_:)` sent preview updates only.
- It committed the value only when an action arrived with `sender.isHighlighted == false`.
- AppKit does not reliably send a final action after the highlight state has already cleared, so a drag could update the live wallpaper but never call `updateWebPropertyValue`.
- Result: no override was saved to `UserDefaults`, no runtime cache invalidation happened, and switching wallpapers relaunched with baseline values.

Changed file:

- `MyWallpaperX/Modules/SteamWorkshop/UI/SteamWorkshopItemDetailSheet.swift`

Implementation:

- Keep drag-time slider updates as preview-only, so the detail panel does not rebuild on every tick.
- Use a small `WebPropertySlider` subclass that records mouse tracking during `mouseDown`.
- While `mouseDown` tracking is active, `sliderChanged(_:)` only previews the normalized value.
- After AppKit finishes the slider tracking loop, `WebPropertySlider` commits the final normalized value once through the existing `updateWebPropertyValue` path.
- Non-drag changes still commit immediately.
- This avoids relying on a process-wide local `.leftMouseUp` monitor and keeps the commit tied to the slider control that initiated the drag.

Validation:

- Build succeeded outside the Codex sandbox:

```sh
/usr/bin/xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug -derivedDataPath .codex/DerivedData build
```

- Runtime smoke / regression logs:

```text
/tmp/mwx-target-slider-tracking-20260621-041904
```

Results:

- `3700131876`:
  - `host.ready=1`
  - `navigation.finish=1`
  - expected `properties.error=1` with `f.push is not a function`
  - `properties.resize-after-script-failure=1`
  - no partial/skipped diagnostics in the checked output
- `3700928191`:
  - same expected `f.push` / resize-compensation behavior
  - no partial/skipped diagnostics in the checked output
- `2997985023`:
  - `host.ready=1`
  - `navigation.finish=1`
  - expected `properties.deferred-side-effect=1`
  - no window/promise error in the checked output

Residual validation note:

- Code review confirms the commit path writes overrides to `UserDefaults`, invalidates the in-memory Web runtime cache, and changes the runtime cache manifest `overridesSignature` used when switching back.
- The runtime smoke verifies no regression in the affected samples.
- The exact user repro still needs one manual UI check: drag `backgroundblursteps`, switch away, switch back, and confirm the slider value and visual are restored.
