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
