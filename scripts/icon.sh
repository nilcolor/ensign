#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || { echo "needs rsvg-convert: brew install librsvg" >&2; exit 1; }

src=design/AppIcon.svg
out=App/Assets.xcassets/AppIcon.appiconset
mkdir -p "$out"

images=()
for pt in 16 32 128 256 512; do
  for scale in 1 2; do
    file="icon_${pt}x${pt}@${scale}x.png"
    rsvg-convert -w $((pt * scale)) -h $((pt * scale)) "$src" -o "$out/$file"
    images+=("{\"idiom\":\"mac\",\"size\":\"${pt}x${pt}\",\"scale\":\"${scale}x\",\"filename\":\"$file\"}")
  done
done

jq -n --argjson images "[$(IFS=,; echo "${images[*]}")]" \
  '{images: $images, info: {author: "xcode", version: 1}}' > "$out/Contents.json"
jq -n '{info: {author: "xcode", version: 1}}' > App/Assets.xcassets/Contents.json
