#!/usr/bin/env bash
#
# xcodegen.sh — generate Tiefstand.xcodeproj with the version from version.sh.
#
# project.yml references ${VERSION} and ${BUILD_NUMBER}; XcodeGen substitutes
# them from the environment, so the Xcode build can no longer drift away from
# what the releases ship. DEVELOPMENT_TEAM still comes from your environment.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
. Scripts/version.sh

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    echo "DEVELOPMENT_TEAM is not set." >&2
    echo "Find it with: security find-identity -v -p codesigning" >&2
    echo "then: export DEVELOPMENT_TEAM=XXXXXXXXXX" >&2
    exit 1
fi

echo "▸ Generating Tiefstand.xcodeproj — v$VERSION (build $BUILD_NUMBER)"
xcodegen generate
echo "✓ Open Tiefstand.xcodeproj and Run (⌘R) once to register the widget."
