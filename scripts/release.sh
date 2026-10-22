#!/bin/sh
# Archives Wakeful, uploads the build to App Store Connect and (optionally) submits it for review.
#
#   export ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.../AuthKey_XXXX.p8
#   export REVIEW_PHONE="+55 ..." REVIEW_EMAIL="..."   # App Review contact, kept out of the repo
#   scripts/release.sh            # archive + upload build + upload store page
#   scripts/release.sh --submit   # same, then submit for App Review
#
# The app record must already exist in App Store Connect (bundle id com.dionlima.wakeful).
# Signing is manual (store/ExportOptions.plist): the Mac App Store profiles "Wakeful Mac App Store" and
# "Wakeful Widgets Mac App Store" are fetched with the API key, so it doesn't need cloud-signing rights.
set -e
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}" "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
KEY_PATH=$(eval echo "\"$ASC_KEY_PATH\"")
# Paths like ".../OneDrive/DEV Apps/..." contain spaces, so the auth flags are passed quoted.
xcodebuild_auth() {
  xcodebuild "$@" -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
}

xcodegen generate --quiet
python3 scripts/store/asc.py install-profiles
rm -rf build/archive build/export
xcodebuild_auth archive -project Wakeful.xcodeproj -scheme Wakeful -configuration Release \
  -destination 'generic/platform=macOS' -archivePath build/archive/Wakeful.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=UL28GCBV3R | tail -1

# Same options as store/ExportOptions.plist, but uploading instead of exporting locally.
sed 's#<string>export</string>#<string>upload</string>#' store/ExportOptions.plist > build/ExportOptions-upload.plist
xcodebuild_auth -exportArchive -archivePath build/archive/Wakeful.xcarchive -exportPath build/export \
  -exportOptionsPlist build/ExportOptions-upload.plist | tail -3

python3 scripts/store/build_metadata.py
scripts/render-screenshots.sh

if [ "$1" = "--submit" ]; then
  echo "Waiting for App Store Connect to process the build can take 10–30 minutes; deliver retries until it is ready."
  fastlane mac submit
else
  fastlane mac metadata
fi
