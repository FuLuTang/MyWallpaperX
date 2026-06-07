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

MARKETING_VERSION="$PROJECT_MARKETING_VERSION"
PREVIOUS_TAG="$(git tag --list 'build-*' --sort=-version:refname | head -n 1)"

if [[ "$MODE" != "--release" && "$MODE" != "release" && "$MODE" != "development" ]]; then
  echo "Usage: $0 [--release]" >&2
  exit 64
fi

BUILD_VERSION="$(git rev-list --count HEAD)"

cat <<EOF
MARKETING_VERSION=${MARKETING_VERSION}
BUILD_VERSION=${BUILD_VERSION}
PREVIOUS_TAG=${PREVIOUS_TAG}
EOF
