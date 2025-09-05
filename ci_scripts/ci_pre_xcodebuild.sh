#!/bin/sh

# ci_pre_xcodebuild.sh
# Xcode Cloud script to build Flutter app before Xcode build

set -e

echo "🔥 Starting ci_pre_xcodebuild.sh..."

# Set Flutter path
export PATH="$PATH:$HOME/flutter/bin"

# Verify Flutter installation
echo "📱 Verifying Flutter installation..."
flutter doctor -v

# Build Flutter iOS app
echo "📱 Building Flutter iOS app..."
flutter build ios --release --no-codesign

echo "✅ ci_pre_xcodebuild.sh completed successfully!"