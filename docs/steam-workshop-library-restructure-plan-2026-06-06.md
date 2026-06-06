# Steam Workshop Library Restructure Plan

Date: 2026-06-06

This document is the handoff source of truth for the Steam Workshop downloaded-library restructure. If Codex context is compacted, read this file before continuing the implementation.

## Goal

Remove duplicate storage for video Workshop wallpapers and make the user-visible download library layout clear.

Current problem:

- SteamCMD downloads full Workshop content into a staging folder.
- The app copies the whole staged folder into `~/Movies/MyWallpaperX/创意工坊/<itemID>/`.
- For video wallpapers, the app also copies the primary video again with a title-based filename.
- Result: video downloads can leave two copies of the same video content.

Target:

- Video wallpapers keep exactly one user-visible video file.
- Web and Scene wallpapers keep full project directories because their runtime depends on project structure.
- The app must actively discover samples in the normalized directories, not rely only on metadata files.
- A one-time migration script handles old local data. The app should not keep long-term old-structure compatibility code.

## Target Directory Layout

```text
~/Movies/MyWallpaperX/创意工坊/
  Video/
    Title.mp4
    Title (1).mp4

  Web/
    <itemID>/
      project.json
      ...

  Scene/
    <itemID>/
      project.json
      scene.pkg
      ...

  .mywallpaperx-steam-metadata/
    Title.json          # video metadata, basename matches video file
    Title (1).json      # video metadata conflict variant
    <itemID>.json       # web / scene metadata
```

Video filenames must not include the Steam item ID. Filename conflicts use Finder-style suffixes: `Title.ext`, `Title (1).ext`, `Title (2).ext`.

Metadata rules:

- Video metadata filename uses the final video basename, e.g. `Title.mp4` -> `.mywallpaperx-steam-metadata/Title.json`.
- Web and Scene metadata filenames stay `<itemID>.json`.
- Metadata content must still preserve the real Steam `item.id`.
- Metadata is an enhancement source, not the only discovery source.

## App Discovery Rules

`SteamWorkshopService.reloadInstalledItems()` should rebuild downloaded records from normalized directories:

1. Scan `Video/`
   - Include supported video extensions.
   - Resolve metadata by video basename.
   - If metadata exists, use `snapshot.item.id`, title, author, detail URL, preview data, and final video path.
   - If metadata is missing, still display the sample as a degraded local video download record. Use a stable synthetic ID such as `video:<filename-hash>` or `video:<basename>`.
   - Record `exportedVideoURL` or equivalent final video URL as the single playable path.

2. Scan `Web/`
   - Each direct child directory is `<itemID>`.
   - Metadata is `.mywallpaperx-steam-metadata/<itemID>.json`.
   - If metadata is missing, read `project.json` and resolve HTML entry enough to display the item.

3. Scan `Scene/`
   - Each direct child directory is `<itemID>`.
   - Metadata is `.mywallpaperx-steam-metadata/<itemID>.json`.
   - If metadata is missing, read `project.json` / `scene.pkg` enough to display the item.

4. Metadata-only records
   - Do not use metadata alone to claim a download exists.
   - If metadata points to a missing file/directory, ignore it or mark it unavailable only if the UI has a deliberate missing-state design.

## Download Sync Rules

After SteamCMD download succeeds:

1. Inspect staged directory `<runtime>/steamapps/workshop/content/<appID>/<itemID>/`.
2. Parse `project.json` when available.
3. Determine content type.
4. Video:
   - Resolve primary video via `project.file` first, then current fallback candidate rules.
   - Copy or move exactly one primary video to `~/Movies/MyWallpaperX/创意工坊/Video/<safeTitle>.<ext>`.
   - Do not copy the whole staged `<itemID>` directory into the user library.
   - Persist metadata as `.mywallpaperx-steam-metadata/<videoBasename>.json`.
   - Metadata should contain the final video path and real Steam item ID.
5. Web:
   - Copy full staged directory to `~/Movies/MyWallpaperX/创意工坊/Web/<itemID>/`.
   - Persist metadata as `.mywallpaperx-steam-metadata/<itemID>.json`.
6. Scene:
   - Copy full staged directory to `~/Movies/MyWallpaperX/创意工坊/Scene/<itemID>/`.
   - Persist metadata as `.mywallpaperx-steam-metadata/<itemID>.json`.
7. Use temporary destination paths and replace only after copy succeeds where practical.

## One-Time Migration Script

Add a local script, proposed path:

```text
scripts/migrate_steam_workshop_library_v2.py
```

Behavior:

- Default mode is `--dry-run`.
- `--apply` performs changes.
- Input root defaults to `~/Movies/MyWallpaperX/创意工坊`.
- It migrates old data into the normalized structure.
- It writes a JSON manifest before apply, e.g. under `~/Movies/MyWallpaperX/创意工坊/.migration/`.
- It validates that migrated samples will be discoverable by the new app rules.

Old data cases:

1. Old video with exported title file already present in root
   - Move root video file to `Video/<Title>.ext`.
   - Rewrite metadata from old `<itemID>.json` to `<Title>.json`.
   - Remove old `<itemID>/` full directory only after new file and metadata validate.

2. Old video with only `<itemID>/` directory
   - Find primary video from `project.json.file` or video candidate fallback.
   - Move/copy primary video to `Video/<Title>.ext`.
   - Write `<Title>.json`.
   - Remove old `<itemID>/` full directory only after validation.

3. Old Web
   - Move `<itemID>/` to `Web/<itemID>/`.
   - Keep metadata filename `<itemID>.json`.

4. Old Scene
   - Move `<itemID>/` to `Scene/<itemID>/`.
   - Keep metadata filename `<itemID>.json`.

5. Video library index path update
   - If a migrated Steam video was previously imported into the Video Library, the video library index may point to the old exported video path.
   - The script must update the video library storage path if feasible, or produce an explicit report of paths requiring app-side repair.
   - Current code uses `WallpaperIndexStore` SQLite for video library persistence, with legacy UserDefaults fallback. Inspect current on-disk store path before implementing the update.

Safety:

- Do not delete old data before new data and metadata are written and validated.
- Preserve old files on partial failure.
- Filename conflicts use Finder-style suffixes.

## Code Hotspots

Primary files:

- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+Paths.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadLibrarySync.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+LibraryRecords.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopService+DownloadSelection.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Core/SteamWorkshopAPIModels.swift`
- `MyWallpaperX/Modules/SteamWorkshop/Web/Core/SteamWorkshopService+WebPlayback.swift`
- `MyWallpaperX/App/MainWindowCoordinator.swift`
- `MyWallpaperX/Modules/VideoLibrary/Core/WallpaperManager+ImportProcessing.swift`
- `MyWallpaperX/Modules/VideoLibrary/Core/WallpaperIndexStore.swift`

Important current behavior:

- `SteamWorkshopDownloadRecord.videoURL` currently prefers `exportedVideoURL`, then `sourceVideoURL`.
- `setAsWallpaper(_:)` posts `.steamWorkshopVideoReadyToPlay` with `record.videoURL`.
- `MainWindowCoordinator` receives that notification and calls `wallpaperManager.processImportedVideos(..., context: .steamPlayback)`.
- Video Library imports by path and does not copy the source video.
- Deleting a Steam download currently removes `record.exportedVideoURL`; this can break Video Library entries if they point to the same file.

## Implementation Steps

1. Write this plan document. Status: done.
2. Refactor path helpers:
   - Add `videoLibraryRootURL`, `webLibraryRootURL`, `sceneLibraryRootURL`.
   - Keep `libraryRootURL` as base `创意工坊`.
   - Add metadata lookup that supports video metadata by basename and Web/Scene by item ID.
   - Status: implemented in `SteamWorkshopService+Paths.swift` and `SteamWorkshopService+DownloadLibrarySync.swift`.
3. Refactor metadata model if needed:
   - Existing `SteamWorkshopDownloadMetadataSnapshot` has `exportedVideoURL` and `legacyFolderURL`.
   - Use these fields if sufficient; avoid schema churn unless necessary.
   - Status: no schema change; video uses `exportedVideoURL`, Web/Scene use `legacyFolderURL`.
4. Refactor download sync:
   - Determine type before copying.
   - Video writes one file into `Video/`.
   - Web/Scene copy full directory into their type folder.
   - Persist correct metadata filename.
   - Status: implemented.
5. Refactor record rebuilding:
   - `reloadInstalledItems()` scans `Video/`, `Web/`, `Scene/`.
   - Build records even without metadata where possible.
   - Status: implemented. Video without metadata is shown as a degraded local video record.
6. Refactor delete behavior:
   - Video deletes the single video file and matching metadata only when deleting the Steam download.
   - Avoid accidentally breaking Video Library references; either detect references or leave a follow-up if index access is too risky.
   - Status: implemented for new Steam download records. Migration script updates Video Library SQLite paths for moved videos.
7. Add migration script:
   - dry-run first
   - apply mode
   - manifest
   - validation
   - Status: implemented at `scripts/migrate_steam_workshop_library_v2.py`. Dry-run does not modify files unless `--write-manifest` is passed; `--apply` writes a manifest and migrates.
8. Verification:
   - `git status --short`
   - static search for old assumptions
   - `xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug build`
   - run migration script in dry-run mode if local sample directory exists
   - Status: Debug build passed once after implementation. Script syntax check passed. A temporary old video sample migrated successfully under `/tmp`.

## Open Decisions Already Resolved

- Video filenames must not include item ID.
- Video metadata filename matches video basename.
- Web/Scene metadata filename remains item ID.
- App must actively discover samples in normalized directories.
- No long-term old-structure compatibility code in App; old data is handled by the one-time script.

## Implementation Update

Status as of 2026-06-06 20:48 Asia/Shanghai:

- App code now creates and uses `Video/`, `Web/`, and `Scene/` under `~/Movies/MyWallpaperX/创意工坊/`.
- New Steam video downloads copy only the primary video into `Video/<safe title>.<ext>` and write metadata as `.mywallpaperx-steam-metadata/<video basename>.json`.
- New Web downloads copy the full staged folder into `Web/<itemID>/` and keep metadata as `<itemID>.json`.
- New Scene downloads copy the full staged folder into `Scene/<itemID>/` and keep metadata as `<itemID>.json`.
- `reloadInstalledItems()` now discovers direct video files in `Video/`, direct Web directories in `Web/`, and direct Scene directories in `Scene/`. Video files without metadata still produce degraded local ready records.
- Metadata refresh from the download inspector now preserves video metadata naming by video basename instead of writing `<itemID>.json`.
- Delete behavior now removes the normalized video file plus matching video metadata for video records, and removes only normalized `Web/<itemID>` or `Scene/<itemID>` directories for project records.
- The migration script exists at `scripts/migrate_steam_workshop_library_v2.py`.
  - Default mode is dry-run and does not write a manifest.
  - `--apply` writes `.migration/steam-workshop-library-v2-<timestamp>.json` and performs the migration.
  - Video migration validates the new video file and metadata before deleting the old `<itemID>` directory.
  - Web/Scene migration validates the new directory and metadata when metadata exists.
  - SQLite video library paths are updated from old video paths to new normalized video paths when matching rows exist.

Verification completed:

- `python3 -m py_compile scripts/migrate_steam_workshop_library_v2.py` passed.
- `git diff --check` passed.
- Temporary migration test passed for one video, one Web, and one Scene sample. The video result had exactly one file in `Video/` and metadata named by video basename while preserving item ID in JSON.
- Real default library dry-run for `~/Movies/MyWallpaperX/创意工坊` planned 76 items without modifying files: 55 Web, 13 Video, 8 Scene.
- `xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug build` passed.

## Follow-Up Fixes

Status as of 2026-06-06 21:02 Asia/Shanghai:

- Successful SteamCMD downloads now call `cleanupStagedDownload(id:)` after `syncDownloadedItemToLibrary(_:)`, so the runtime staging copy is removed after the normalized library copy succeeds.
- Existing staging leftovers under `~/Library/Application Support/MyWallpaperX/SteamWorkshopRuntime/steamapps/workshop/content/downloads/temp` were cleaned. Before cleanup, `content` held about 596 MB; after cleanup, `content`, `downloads`, and `temp` were all 0B.
- Removed unused old video export and old metadata helper code:
  - `exportPrimaryVideoIfPossible`
  - `loadExistingDownloadMetadataSnapshot`
  - `persistDownloadMetadataIfPossible`
- Queued/downloading placeholder records no longer point at the old `创意工坊/<itemID>` path; their placeholder `folderURL` uses the library root instead.

Follow-up verification:

- Static search found no remaining references to `loadExistingDownloadMetadataSnapshot`, `exportPrimaryVideoIfPossible`, `persistDownloadMetadataIfPossible`, or `libraryRootURL.appendingPathComponent(id, isDirectory: true)`.
- Migration dry-run against `~/Movies/MyWallpaperX/创意工坊` returned `count: 0`.
- `python3 -m py_compile scripts/migrate_steam_workshop_library_v2.py` passed.
- `git diff --check` passed.
- `xcodebuild -project MyWallpaperX.xcodeproj -scheme MyWallpaperX -configuration Debug build` passed.
