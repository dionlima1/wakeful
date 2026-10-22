#!/bin/sh
# Local Debug build signed with the Apple Development certificate (no provisioning profile needed on macOS).
set -e
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Wakeful.xcodeproj -scheme Wakeful -configuration Debug -derivedDataPath build \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=UL28GCBV3R CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER= \
  build "$@"
