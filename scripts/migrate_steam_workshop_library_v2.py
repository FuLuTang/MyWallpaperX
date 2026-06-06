#!/usr/bin/env python3
"""One-time Steam Workshop library migration for MyWallpaperX.

Default mode is dry-run and does not modify files. Use --apply to move files and rewrite metadata.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


VIDEO_EXTENSIONS = {".mp4", ".webm", ".mov", ".m4v"}
RESERVED_DIRS = {"Video", "Web", "Scene", ".mywallpaperx-steam-metadata", ".migration"}
INVALID_FILENAME_CHARS = set('/\\:?%*|"<>')
APPLE_REFERENCE_EPOCH_UNIX_SECONDS = 978307200


@dataclass
class MigrationItem:
    item_id: str
    content_type: str
    source_path: str
    target_path: str
    old_metadata_path: str | None
    new_metadata_path: str | None
    sqlite_old_path: str | None = None
    sqlite_new_path: str | None = None
    cleanup_directory_path: str | None = None


def default_library_root() -> Path:
    return Path.home() / "Movies" / "MyWallpaperX" / "创意工坊"


def default_sqlite_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "MyWallpaperX" / "wallpaper_index.sqlite3"


def safe_filename(raw: str, fallback: str) -> str:
    cleaned = "".join(" " if ch in INVALID_FILENAME_CHARS else ch for ch in raw)
    cleaned = " ".join(cleaned.split()).strip()
    return (cleaned or fallback)[:120]


def unique_path(directory: Path, base_name: str, suffix: str, reserved: set[Path]) -> Path:
    index = 0
    while True:
        name = f"{base_name}{suffix}" if index == 0 else f"{base_name} ({index}){suffix}"
        candidate = directory / name
        metadata_candidate = directory.parent / ".mywallpaperx-steam-metadata" / f"{candidate.stem}.json"
        if not candidate.exists() and candidate not in reserved and not metadata_candidate.exists():
            reserved.add(candidate)
            return candidate
        index += 1


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        return payload if isinstance(payload, dict) else None
    except Exception:
        return None


def path_from_file_url(value: str) -> Path:
    parsed = urlparse(value)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path))
    return Path(value)


def swift_date_now() -> float:
    return datetime.now(timezone.utc).timestamp() - APPLE_REFERENCE_EPOCH_UNIX_SECONDS


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    temp.replace(path)


def load_metadata_entries(metadata_dir: Path) -> list[tuple[Path, dict[str, Any]]]:
    entries: list[tuple[Path, dict[str, Any]]] = []
    if not metadata_dir.exists():
        return entries
    for path in sorted(metadata_dir.glob("*.json")):
        payload = load_json(path)
        if payload is not None:
            entries.append((path, payload))
    return entries


def item_id_from_metadata(payload: dict[str, Any]) -> str | None:
    item = payload.get("item")
    if isinstance(item, dict):
        value = item.get("id")
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def metadata_title(payload: dict[str, Any] | None) -> str | None:
    if not payload:
        return None
    item = payload.get("item")
    if isinstance(item, dict):
        title = item.get("title")
        if isinstance(title, str) and title.strip():
            return title.strip()
    return None


def load_project(directory: Path) -> dict[str, Any] | None:
    return load_json(directory / "project.json")


def project_title(project: dict[str, Any] | None) -> str | None:
    if not project:
        return None
    title = project.get("title")
    return title.strip() if isinstance(title, str) and title.strip() else None


def project_file(project: dict[str, Any] | None) -> str | None:
    if not project:
        return None
    value = project.get("file")
    return value.replace("\\", "/").strip() if isinstance(value, str) and value.strip() else None


def video_candidates(directory: Path) -> list[Path]:
    candidates = [path for path in directory.rglob("*") if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS]
    return sorted(candidates, key=lambda path: path.relative_to(directory).as_posix().lower())


def primary_video(directory: Path, project: dict[str, Any] | None) -> Path | None:
    candidates = video_candidates(directory)
    if not candidates:
        return None
    preferred = project_file(project)
    if preferred:
        direct = directory / preferred
        if direct.exists() and direct.is_file() and direct.suffix.lower() in VIDEO_EXTENSIONS:
            return direct
        preferred_name = Path(preferred).name.lower()
        for candidate in candidates:
            if candidate.name.lower() == preferred_name:
                return candidate
    return max(candidates, key=lambda path: path.stat().st_size if path.exists() else 0)


def html_candidates(directory: Path) -> list[Path]:
    return [path for path in directory.rglob("*") if path.is_file() and path.suffix.lower() in {".html", ".htm"}]


def detect_type(directory: Path, project: dict[str, Any] | None, metadata: dict[str, Any] | None) -> str:
    project_type = project.get("type") if isinstance(project, dict) else None
    project_type = project_type.strip().lower() if isinstance(project_type, str) else ""
    item = metadata.get("item") if isinstance(metadata, dict) else None
    workshop_type = item.get("workshopTypeText") if isinstance(item, dict) else None
    workshop_type = workshop_type.strip().lower() if isinstance(workshop_type, str) else ""
    declared_file = project_file(project) or ""
    declared_ext = Path(declared_file).suffix.lower()

    if (directory / "scene.pkg").exists() or project_type == "scene" or workshop_type == "scene":
        return "scene"
    if project_type == "web" or declared_ext in {".html", ".htm"} or html_candidates(directory):
        return "web"
    if primary_video(directory, project) is not None:
        return "video"
    return "web"


def metadata_by_item(entries: list[tuple[Path, dict[str, Any]]]) -> dict[str, tuple[Path, dict[str, Any]]]:
    result: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path, payload in entries:
        item_id = item_id_from_metadata(payload)
        if item_id and item_id not in result:
            result[item_id] = (path, payload)
    return result


def update_video_metadata(payload: dict[str, Any], target_video: Path) -> dict[str, Any]:
    updated = dict(payload)
    updated["fetchedAt"] = swift_date_now()
    updated["sourceVideoRelativePath"] = None
    updated["previewRelativePath"] = None
    updated["exportedVideoURL"] = target_video.as_uri()
    updated["legacyFolderURL"] = None
    return updated


def update_project_metadata(payload: dict[str, Any], target_directory: Path) -> dict[str, Any]:
    updated = dict(payload)
    updated["fetchedAt"] = swift_date_now()
    updated["exportedVideoURL"] = None
    updated["legacyFolderURL"] = target_directory.as_uri()
    return updated


def plan_migration(root: Path) -> list[MigrationItem]:
    metadata_dir = root / ".mywallpaperx-steam-metadata"
    video_dir = root / "Video"
    web_dir = root / "Web"
    scene_dir = root / "Scene"
    entries = load_metadata_entries(metadata_dir)
    by_item = metadata_by_item(entries)
    reserved_video_targets: set[Path] = set()
    planned: list[MigrationItem] = []
    planned_sources: set[Path] = set()

    for child in sorted(root.iterdir() if root.exists() else []):
        if not child.is_dir():
            continue
        if child.name in RESERVED_DIRS:
            continue
        item_id = child.name
        old_metadata_path, metadata = by_item.get(item_id, (None, None))
        project = load_project(child)
        content_type = detect_type(child, project, metadata)
        if content_type == "video":
            source_video = None
            exported = metadata.get("exportedVideoURL") if isinstance(metadata, dict) else None
            if isinstance(exported, str):
                try:
                    exported_path = path_from_file_url(exported)
                    if exported_path.exists():
                        source_video = exported_path
                except Exception:
                    source_video = None
            source_video = source_video or primary_video(child, project)
            if source_video is None:
                continue
            title = metadata_title(metadata) or project_title(project) or item_id
            target = unique_path(video_dir, safe_filename(title, "Workshop"), source_video.suffix or ".mp4", reserved_video_targets)
            new_metadata = metadata_dir / f"{target.stem}.json"
            planned.append(MigrationItem(
                item_id=item_id,
                content_type="video",
                source_path=str(source_video),
                target_path=str(target),
                old_metadata_path=str(old_metadata_path) if old_metadata_path else None,
                new_metadata_path=str(new_metadata),
                sqlite_old_path=str(source_video),
                sqlite_new_path=str(target),
                cleanup_directory_path=str(child),
            ))
            planned_sources.add(source_video)
            continue

        target_dir = (scene_dir if content_type == "scene" else web_dir) / item_id
        planned.append(MigrationItem(
            item_id=item_id,
            content_type=content_type,
            source_path=str(child),
            target_path=str(target_dir),
            old_metadata_path=str(old_metadata_path) if old_metadata_path else None,
            new_metadata_path=str(metadata_dir / f"{item_id}.json") if metadata else None,
        ))
        planned_sources.add(child)

    for path, metadata in entries:
        item_id = item_id_from_metadata(metadata)
        exported = metadata.get("exportedVideoURL")
        if not item_id or not isinstance(exported, str):
            continue
        source_video = path_from_file_url(exported)
        if source_video in planned_sources:
            continue
        if source_video.parent != root or not source_video.exists() or source_video.suffix.lower() not in VIDEO_EXTENSIONS:
            continue
        title = metadata_title(metadata) or source_video.stem
        target = unique_path(video_dir, safe_filename(title, "Workshop"), source_video.suffix or ".mp4", reserved_video_targets)
        planned.append(MigrationItem(
            item_id=item_id,
            content_type="video",
            source_path=str(source_video),
            target_path=str(target),
            old_metadata_path=str(path),
            new_metadata_path=str(metadata_dir / f"{target.stem}.json"),
            sqlite_old_path=str(source_video),
            sqlite_new_path=str(target),
        ))
    return planned


def apply_migration(root: Path, items: list[MigrationItem], sqlite_path: Path) -> None:
    metadata_dir = root / ".mywallpaperx-steam-metadata"
    entries = load_metadata_entries(metadata_dir)
    by_item = metadata_by_item(entries)

    for item in items:
        source = Path(item.source_path)
        target = Path(item.target_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        old_metadata_payload = by_item.get(item.item_id, (None, None))[1]
        if item.content_type == "video":
            if target.exists():
                raise RuntimeError(f"target already exists: {target}")
            shutil.move(str(source), str(target))
            if old_metadata_payload and item.new_metadata_path:
                write_json(Path(item.new_metadata_path), update_video_metadata(old_metadata_payload, target))
            validate_migrated_item(item)
            if item.cleanup_directory_path:
                cleanup_directory = Path(item.cleanup_directory_path)
                if cleanup_directory.exists():
                    shutil.rmtree(cleanup_directory)
        else:
            if target.exists():
                raise RuntimeError(f"target already exists: {target}")
            shutil.move(str(source), str(target))
            if old_metadata_payload and item.new_metadata_path:
                write_json(Path(item.new_metadata_path), update_project_metadata(old_metadata_payload, target))
            validate_migrated_item(item)

        if item.old_metadata_path and item.new_metadata_path and item.old_metadata_path != item.new_metadata_path:
            old_metadata = Path(item.old_metadata_path)
            if old_metadata.exists():
                old_metadata.unlink()

    update_sqlite_paths(sqlite_path, items)


def validate_migrated_item(item: MigrationItem) -> None:
    target = Path(item.target_path)
    if item.content_type == "video":
        if not target.is_file():
            raise RuntimeError(f"migrated video is missing: {target}")
    else:
        if not target.is_dir():
            raise RuntimeError(f"migrated directory is missing: {target}")

    if not item.new_metadata_path:
        return
    metadata_path = Path(item.new_metadata_path)
    metadata = load_json(metadata_path)
    if metadata is None:
        raise RuntimeError(f"migrated metadata is missing or invalid: {metadata_path}")
    if item.content_type == "video":
        exported = metadata.get("exportedVideoURL")
        exported_path = path_from_file_url(exported) if isinstance(exported, str) else None
        if exported_path != target:
            raise RuntimeError(f"video metadata does not point to migrated file: {metadata_path}")
    else:
        legacy = metadata.get("legacyFolderURL")
        legacy_path = path_from_file_url(legacy) if isinstance(legacy, str) else None
        if legacy_path != target:
            raise RuntimeError(f"project metadata does not point to migrated directory: {metadata_path}")


def update_sqlite_paths(sqlite_path: Path, items: list[MigrationItem]) -> None:
    updates = [(item.sqlite_new_path, item.sqlite_old_path) for item in items if item.sqlite_old_path and item.sqlite_new_path]
    if not updates or not sqlite_path.exists():
        return
    connection = sqlite3.connect(sqlite_path)
    try:
        with connection:
            for new_path, old_path in updates:
                connection.execute(
                    "UPDATE wallpapers SET path = ?, thumbnail_path = NULL, static_frame_path = NULL WHERE path = ?",
                    (new_path, old_path),
                )
    finally:
        connection.close()


def write_manifest(root: Path, items: list[MigrationItem]) -> Path:
    manifest_dir = root / ".migration"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    manifest_path = manifest_dir / f"steam-workshop-library-v2-{timestamp}.json"
    payload = {
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "root": str(root),
        "items": [asdict(item) for item in items],
    }
    write_json(manifest_path, payload)
    return manifest_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Migrate MyWallpaperX Steam Workshop library to Video/Web/Scene layout.")
    parser.add_argument("--root", type=Path, default=default_library_root())
    parser.add_argument("--sqlite", type=Path, default=default_sqlite_path())
    parser.add_argument("--apply", action="store_true", help="Perform migration. Without this flag, only prints a dry-run plan.")
    parser.add_argument("--write-manifest", action="store_true", help="Write a manifest during dry-run. Apply mode always writes one.")
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    sqlite_path = args.sqlite.expanduser().resolve()
    items = plan_migration(root)
    manifest_path = write_manifest(root, items) if args.apply or args.write_manifest else None
    print(json.dumps({
        "mode": "apply" if args.apply else "dry-run",
        "root": str(root),
        "sqlite": str(sqlite_path),
        "manifest": str(manifest_path) if manifest_path else None,
        "count": len(items),
        "items": [asdict(item) for item in items],
    }, ensure_ascii=False, indent=2))
    if args.apply:
        apply_migration(root, items, sqlite_path)
        print("Migration applied.")
    else:
        print("Dry-run only. Re-run with --apply to migrate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
