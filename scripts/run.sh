#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
pkill -x Ensign || true
open build/DerivedData/Build/Products/Debug/Ensign.app
