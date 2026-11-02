#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/generate.sh
xcodebuild -project Ensign.xcodeproj -scheme Ensign -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -quiet build
