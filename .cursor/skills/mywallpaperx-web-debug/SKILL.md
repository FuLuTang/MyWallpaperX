---
name: mywallpaperx-web-debug
description: Build, launch, and smoke-test MyWallpaperX Web wallpaper runtime from this repository. Use when debugging MyWallpaperX app startup, Web host runtime behavior, wallpaper daemon logs, or when the user asks for automated local testing of the app.
---

# MyWallpaperX Web Debug

Use this project skill when you need to automate local testing of `MyWallpaperX`, especially the Web wallpaper host path.

## Entry script

Primary automation script:
- `scripts/mywallpaperx_web_debug.py`

## What it can do

- Locate an existing `MyWallpaperX.app`
- Build `MyWallpaperX` with a repo-local `DerivedData` path
- Launch the app
- Read recent runtime logs relevant to:
  - `MyWallpaperX`
  - `MyWallpaperXWallpaperDaemon`
  - `WallpaperEngine:`
- Run a smoke test that launches the app and writes a JSON report

## Default workflow

When the user asks for automated local testing:

1. Try locating an existing app first:

```bash
python3 scripts/mywallpaperx_web_debug.py locate-app
```

2. If needed, run smoke test using existing build:

```bash
python3 scripts/mywallpaperx_web_debug.py smoke
```

3. If no app exists or the user wants a rebuild:

```bash
python3 scripts/mywallpaperx_web_debug.py smoke --build
```

4. If only logs are needed:

```bash
python3 scripts/mywallpaperx_web_debug.py logs --last-minutes 5
```

## Important operating notes

- Prefer existing build artifacts before rebuilding.
- Keep Web runtime debugging isolated from the video wallpaper chain.
- If build fails due environment permissions, report that clearly as an environment blocker rather than a code blocker.
- If logs are empty, say so explicitly and request the minimum user assistance needed.

## When to ask the user for help

Ask for user assistance only when one of these blocks automation:

- macOS permission prompts need manual approval
- the app must be brought to foreground manually
- a specific wallpaper sample must be selected in UI
- system log access or build paths are blocked by local permissions

## Expected outputs

For each automated run, summarize:

- whether app launch succeeded
- whether matching processes were found
- whether runtime logs were captured
- the most likely current blocker
- the next best debugging action
