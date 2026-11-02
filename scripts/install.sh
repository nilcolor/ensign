#!/usr/bin/env bash
# Launch at login registers the app at the path it runs from, so the everyday copy has to live at a
# stable path that rebuilds and `make clean` never touch. Replacing it in place keeps that registration.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/release.sh
app="$PWD/build/DerivedData/Build/Products/Release/Ensign.app"
target="/Applications/Ensign.app"

if pgrep -x Ensign >/dev/null; then
    osascript -e 'quit app id "com.nilcolor.Ensign"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Ensign >/dev/null || break; sleep 0.3; done
    pkill -x Ensign || true
fi
rm -rf "$target"
/usr/bin/ditto "$app" "$target"
open "$target"
echo
echo "Installed and launched: $target"
