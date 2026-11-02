#!/usr/bin/env bash
# Signature and entitlements are reported because they are what the App Store and notarization
# check; get-task-allow is a hard failure because both refuse a binary that carries it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/generate.sh
xcodebuild -project Ensign.xcodeproj -scheme Ensign -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData -quiet build
app="$PWD/build/DerivedData/Build/Products/Release/Ensign.app"
[ -x "$app/Contents/MacOS/Ensign" ] || { echo "FAIL: no Release binary in $app" >&2; exit 1; }

/usr/bin/codesign --verify --strict --verbose=2 "$app"
echo
signature="$(/usr/bin/codesign -dvvv "$app" 2>&1)"
echo "$signature" | grep -E "^(Identifier|Signature|TeamIdentifier)" | sed 's/^/  /'
entitlements="$(/usr/bin/codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - )"
echo "$entitlements" | grep '=>' | sed -E 's/^ *"([^"]+)".*/  entitlement \1/'
if echo "$entitlements" | grep -q "get-task-allow"; then
    echo "FAIL: get-task-allow is in the Release entitlements" >&2
    exit 1
fi
if ! echo "$entitlements" | grep -q "app-sandbox"; then
    echo "FAIL: Release app is not sandboxed" >&2
    exit 1
fi
# Reported, never enforced: there is no developer team yet, and this target has to keep passing.
if echo "$signature" | grep -q "Signature=adhoc"; then
    echo "  ad-hoc signature: fine locally; App Store/notarization needs a DEVELOPMENT_TEAM. Not a failure."
fi
echo
echo "Release app: $app ($(du -sh "$app" | cut -f1))"
