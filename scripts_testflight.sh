#!/bin/zsh
# Archives the iOS app and uploads it to TestFlight.
#
# Requires an App Store Connect API key. Xcode uses it both to create the
# distribution certificate / App Store profile (-allowProvisioningUpdates) and
# to upload the build, so no interactive Apple ID sign-in is needed.
#
# Usage: ISSUER_ID=<uuid> ./scripts_testflight.sh
set -e

KEY_ID="${KEY_ID:-Q25J59WJQS}"
KEY_PATH="${KEY_PATH:-$HOME/Downloads/AuthKey_${KEY_ID}.p8}"
TEAM_ID="${TEAM_ID:-4BVW4KZPSA}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/ios/archive/Runner.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-build/ios/ipa}"

if [ -z "$ISSUER_ID" ]; then
  echo "ISSUER_ID is required (App Store Connect > Users and Access > Integrations)." >&2
  exit 1
fi
if [ ! -f "$KEY_PATH" ]; then
  echo "API key not found at $KEY_PATH" >&2
  exit 1
fi

AUTH_ARGS=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$KEY_ID"
  -authenticationKeyIssuerID "$ISSUER_ID"
)

# The backend rejects unauthenticated requests, so the key is compiled in here.
if [ -z "$INSESSION_API_KEY" ]; then
  echo "INSESSION_API_KEY is required (matches the APP_API_KEY app setting)." >&2
  exit 1
fi

echo "==> Building Flutter release bundle"
flutter build ios --release --no-codesign \
  --dart-define=INSESSION_API_KEY="$INSESSION_API_KEY"

echo "==> Archiving"
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  "${AUTH_ARGS[@]}"

echo "==> Exporting signed IPA"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ios/ExportOptions.plist \
  "${AUTH_ARGS[@]}"

IPA=$(ls "$EXPORT_PATH"/*.ipa | head -1)
echo "==> Built $IPA"

echo "==> Validating with App Store Connect"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

echo "==> Uploading to TestFlight"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

echo "==> Uploaded. Processing usually takes 5-15 minutes before the build"
echo "    appears in the Event Scanning Group."
