#!/bin/sh
# Builds and opens the Debug app for testing.
set -e
cd "$(dirname "$0")/.."
./scripts/build-dev.sh >/dev/null
pkill -x Wakeful 2>/dev/null || true
while pgrep -x Wakeful >/dev/null; do sleep 0.2; done
open build/Build/Products/Debug/Wakeful.app
echo "Wakeful is running: look for the coffee cup in the menu bar."
