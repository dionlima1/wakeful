#!/bin/sh
# Renders localized App Store screenshots (2880×1800) into fastlane/screenshots/<locale>/.
#   scripts/render-screenshots.sh            all App Store locales
#   scripts/render-screenshots.sh pt-BR,ja   only these
set -e
cd "$(dirname "$0")/.."
./scripts/build-dev.sh >/dev/null
APP=build/Build/Products/Debug/Wakeful.app
OUT=$("$APP/Contents/MacOS/Wakeful" --render-screenshots ${1:-} | tail -1)
mkdir -p fastlane/screenshots
for dir in "$OUT"/*/; do
  locale=$(basename "$dir")
  rm -rf "fastlane/screenshots/$locale"
  cp -R "$dir" "fastlane/screenshots/$locale"
done
echo "Screenshots in fastlane/screenshots ($(ls fastlane/screenshots | wc -l | tr -d ' ') locales)"
