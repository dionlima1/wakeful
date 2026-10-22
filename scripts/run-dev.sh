#!/bin/sh
# Builds and opens the Debug app with Wakeful Pro unlocked, for testing every feature.
#   scripts/run-dev.sh          Pro unlocked
#   scripts/run-dev.sh --free   free version (shows the upgrade screen)
set -e
cd "$(dirname "$0")/.."
./scripts/build-dev.sh >/dev/null
pkill -x Wakeful 2>/dev/null || true
while pgrep -x Wakeful >/dev/null; do sleep 0.2; done
if [ "$1" = "--free" ]; then
  open build/Build/Products/Debug/Wakeful.app
else
  open build/Build/Products/Debug/Wakeful.app --args -debugUnlockPro YES
fi
echo "Wakeful is running: look for the coffee cup in the menu bar."
