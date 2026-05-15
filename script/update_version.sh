#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

eval "$("$ROOT_DIR/script/resolve_version.sh" "${1:---next}")"

PROJECT_FILE="$ROOT_DIR/MyWallpaperX.xcodeproj/project.pbxproj"

sed -i '' -E "s/(MARKETING_VERSION = )[0-9]+(\\.[0-9]+){1,2};/\\1${MARKETING_VERSION};/g" "$PROJECT_FILE"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\\1${BUILD_VERSION};/g" "$PROJECT_FILE"

git add "$PROJECT_FILE"

echo "Updated app version to ${MARKETING_VERSION} (${BUILD_VERSION})"
