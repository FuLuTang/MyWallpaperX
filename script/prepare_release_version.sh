#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <marketing-version>" >&2
  exit 64
fi

MARKETING_VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before preparing a release version." >&2
  exit 1
fi

if git remote get-url origin >/dev/null 2>&1; then
  git fetch --force --tags origin
fi

if git rev-parse -q --verify "refs/tags/build-${MARKETING_VERSION}" >/dev/null; then
  echo "Release tag build-${MARKETING_VERSION} already exists; choose a newer version." >&2
  exit 1
fi

BUILD_VERSION="$(( $(git rev-list --count HEAD) + 1 ))"

script/update_project_version.sh "$MARKETING_VERSION" "$BUILD_VERSION"
git add MyWallpaperX.xcodeproj/project.pbxproj

if git diff --cached --quiet; then
  echo "Project version already matches ${MARKETING_VERSION} (${BUILD_VERSION})."
  exit 0
fi

git commit -m "Bump version to ${MARKETING_VERSION} (${BUILD_VERSION})"
