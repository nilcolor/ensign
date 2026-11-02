#!/usr/bin/env bash
# --dirty so a build with uncommitted changes can never be named after a clean tag; "dev" until the
# repo has its first commit. ditto rather than zip, which drops the extended attributes and symlinks
# the app's signature depends on.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(git describe --tags --dirty --always 2>/dev/null || echo dev)"
./scripts/release.sh
app="$PWD/build/DerivedData/Build/Products/Release/Ensign.app"
archive="$HOME/Downloads/Ensign-$version.zip"
rm -f "$archive"
/usr/bin/ditto -c -k --keepParent "$app" "$archive"
echo
echo "Shared: $archive ($(du -h "$archive" | cut -f1))"
