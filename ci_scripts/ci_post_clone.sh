#!/bin/zsh

# Xcode Cloud: prepare a Flutter iOS build.
#
# Xcode Cloud runners have Xcode and CocoaPods but no Flutter, and they run
# xcodebuild directly — never `flutter build`. So everything Flutter would
# normally do ahead of the Xcode phase has to happen here:
#   1. install a pinned Flutter SDK
#   2. resolve packages
#   3. `--config-only` build, which writes ios/Flutter/Generated.xcconfig
#      (the dart-defines and Flutter paths xcodebuild reads)
#   4. pod install
#
# Fails loudly: a silent failure here produces an archive with no Flutter
# engine, which is worse than a red build.
set -euo pipefail

# CocoaPods aborts on a non-UTF-8 locale.
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

FLUTTER_VERSION="3.35.6"
REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "▸ repo: $REPO"
cd "$REPO"

echo "▸ installing Flutter $FLUTTER_VERSION"
git clone --depth 1 --branch "$FLUTTER_VERSION" \
  https://github.com/flutter/flutter.git "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

# git 2.35+ refuses to operate on a directory owned by another uid.
git config --global --add safe.directory "$HOME/flutter"

flutter --version
flutter precache --ios
flutter pub get

# The scanner authenticates to the API with a shared key that must not live in
# source control. Supplied as a secret environment variable on the workflow.
# Absent key still produces a usable internal-testing build: staff sign in
# with Microsoft 365, which is the primary auth path. Only the
# "Continue without signing in" fallback needs the shared key, so warn
# loudly rather than failing the build.
if [[ -z "${INSESSION_API_KEY:-}" ]]; then
  echo "⚠️  INSESSION_API_KEY is not set on this workflow."
  echo "⚠️  Testers must sign in with Microsoft 365; the"
  echo "⚠️  'Continue without signing in' path will not reach the backend."
  echo "⚠️  Add it under App Store Connect ▸ Xcode Cloud ▸ (workflow) ▸"
  echo "⚠️  Environment ▸ Environment Variables, marked Secret."
fi

# Xcode Cloud assigns its own build number; feed it to Flutter so the archive
# carries a unique CFBundleVersion and TestFlight accepts the upload.
BUILD_NUMBER="${CI_BUILD_NUMBER:-}"
BUILD_ARGS=(--release --config-only)
if [[ -n "${INSESSION_API_KEY:-}" ]]; then
  BUILD_ARGS+=("--dart-define=INSESSION_API_KEY=$INSESSION_API_KEY")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  echo "▸ build number from Xcode Cloud: $BUILD_NUMBER"
  BUILD_ARGS+=("--build-number=$BUILD_NUMBER")
fi

echo "▸ generating iOS build configuration"
flutter build ios "${BUILD_ARGS[@]}"

echo "▸ pod install"
cd "$REPO/ios"
pod install

echo "✓ ready for xcodebuild"
