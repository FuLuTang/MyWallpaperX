#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-development}"

PROJECT_MARKETING_VERSION="$(python3 - <<'PY'
from pathlib import Path
import re

project_file = Path("MyWallpaperX.xcodeproj/project.pbxproj")
text = project_file.read_text()
versions = re.findall(r"MARKETING_VERSION = ([^;]+);", text)
if not versions:
    raise SystemExit("MARKETING_VERSION not found in project.pbxproj")

first = versions[0].strip().strip('"')
if any(version.strip().strip('"') != first for version in versions):
    raise SystemExit(f"Conflicting MARKETING_VERSION values: {versions}")

print(first)
PY
)"

version_ge() {
  local left="$1"
  local right="$2"
  python3 - "$left" "$right" <<'PY'
import sys

def parts(version):
    values = [int(part) for part in version.split(".")]
    return values + [0] * (3 - len(values))

sys.exit(0 if parts(sys.argv[1]) >= parts(sys.argv[2]) else 1)
PY
}

next_patch_version() {
  python3 - "$1" <<'PY'
import sys

parts = [int(part) for part in sys.argv[1].split(".")]
parts = parts + [0] * (3 - len(parts))
parts[2] += 1
print(".".join(str(part) for part in parts[:3]))
PY
}

latest_tag_for_major_minor() {
  local major_minor="$1"
  git tag --list "build-${major_minor}.*" --sort=-version:refname | head -n 1
}

MARKETING_VERSION="$PROJECT_MARKETING_VERSION"
PREVIOUS_TAG="$(git tag --list 'build-*' --sort=-version:refname | head -n 1)"

if [[ "$MODE" == "--release" || "$MODE" == "release" ]]; then
  IFS='.' read -r PROJECT_MAJOR PROJECT_MINOR _ <<< "$PROJECT_MARKETING_VERSION"
  LATEST_SERIES_TAG="$(latest_tag_for_major_minor "${PROJECT_MAJOR}.${PROJECT_MINOR}")"

  if [[ -n "$LATEST_SERIES_TAG" ]]; then
    NEXT_TAG_VERSION="$(next_patch_version "${LATEST_SERIES_TAG#build-}")"
    if version_ge "$NEXT_TAG_VERSION" "$PROJECT_MARKETING_VERSION"; then
      MARKETING_VERSION="$NEXT_TAG_VERSION"
    fi
  fi
elif [[ "$MODE" != "development" ]]; then
  echo "Usage: $0 [--release]" >&2
  exit 64
fi

BUILD_VERSION="$(git rev-list --count HEAD)"

cat <<EOF
MARKETING_VERSION=${MARKETING_VERSION}
BUILD_VERSION=${BUILD_VERSION}
PREVIOUS_TAG=${PREVIOUS_TAG}
EOF
