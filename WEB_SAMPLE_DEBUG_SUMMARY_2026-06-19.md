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
